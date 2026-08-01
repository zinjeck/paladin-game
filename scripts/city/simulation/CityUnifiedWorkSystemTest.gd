extends Node

const CityConstructionSystemScript = preload(
	"res://scripts/city/simulation/systems/CityConstructionSystem.gd"
)
const CityResourceMatcherScript = preload(
	"res://scripts/city/simulation/systems/CityResourceMatcher.gd"
)
const CityWorkSystemScript = preload(
	"res://scripts/city/simulation/systems/CityWorkSystem.gd"
)
const CitizenTaskSystemScript = preload(
	"res://scripts/citizens/simulation/systems/CitizenTaskSystem.gd"
)
const CitizenHaulingSystemScript = preload(
	"res://scripts/citizens/simulation/systems/CitizenHaulingSystem.gd"
)
const CitizenDecisionSystemScript = preload(
	"res://scripts/citizens/simulation/systems/CitizenDecisionSystem.gd"
)

const TEST_WORLD_SIZE := Vector2i(32, 24)
const TEST_WORLD_SEED: int = 27_041
const NORMAL_FOOD_TASK_PRIORITY: int = 85

var failure_count: int = 0


func _ready() -> void:
	_test_parent_orders_and_two_level_fairness()
	_test_unreachable_order_runtime_diagnostics()
	_test_survival_food_fallback_and_reservation_accounting()
	_test_unreachable_food_tier_does_not_hide_fallbacks()
	_test_food_path_limit_covers_full_city()
	_test_food_candidate_rotation_prevents_budget_starvation()
	_test_full_storage_construction_relocation_and_cancel_preview()
	_test_safe_boundary_and_cancellation_preserve_physical_cargo()
	_test_cargo_ready_demand_preempts_soft_claim()
	_test_resource_demand_priorities_are_adjustable()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"Unified work system tests failed: " + str(failure_count)
		)
		get_tree().quit(1)
		return

	print("Unified work system tests passed.")
	get_tree().quit(0)


func _test_unreachable_order_runtime_diagnostics() -> void:
	var city_world := _reset_fixture()
	var citizen := _add_citizen("Pathfinder", Vector2i(2, 4))
	var citizen_id := int(citizen.get("id", -1))

	# A full-height water barrier leaves the command physically valid but gives
	# the only eligible worker no route to the target or any neighboring work
	# tile.
	for y in range(city_world.height):
		var barrier_tile := city_world.get_tile(10, y)
		barrier_tile["terrain"] = WorldData.TERRAIN_WATER
		barrier_tile["biome"] = WorldData.BIOME_OCEAN
		barrier_tile["is_land"] = false
		barrier_tile.erase("surface_feature")

	var target_tile := Vector2i(18, 4)
	city_world.get_tile(target_tile.x, target_tile.y)["surface_feature"] = (
		WorldData.CITY_SURFACE_FEATURE_TREE
	)
	_expect(
		CityWorkSystem.add_city_player_command_targets(
			WorldData.CITY_PLAYER_COMMAND_TYPE_CHOP_TREE,
			[target_tile]
		) == 1,
		"The reachability fixture must create one valid command."
	)
	CityWorkSystemScript.synchronize_player_work_board()
	var orders := CityWorkSystem.get_city_work_order_snapshot()
	var blocked_order: Dictionary = orders[0] if orders.size() == 1 else {}
	var blocked_jobs: Array = blocked_order.get("jobs", [])
	var blocked_job: Dictionary = (
		blocked_jobs[0] if blocked_jobs.size() == 1 else {}
	)

	_expect(
		str(blocked_order.get("state", ""))
		== CityWorkSystemScript.ORDER_STATE_BLOCKED
		and str(blocked_order.get("blocked_reason", ""))
		== CityWorkSystemScript.BLOCKED_REASON_NO_REACHABLE_WORK_POSITION,
		"A parent with no reachable job must report BLOCKED/no reachable work position."
	)
	_expect(
		not bool(blocked_job.get("actionable", true))
		and str(blocked_job.get("state", ""))
		== CityWorkSystemScript.JOB_STATE_BLOCKED
		and blocked_job.get("active_citizen_ids", []).is_empty()
		and str(blocked_job.get("blocked_reason", ""))
		== CityWorkSystemScript.BLOCKED_REASON_NO_REACHABLE_WORK_POSITION,
		"An unreachable runtime job must not remain advertised as actionable."
	)
	_expect(
		CityWorkSystemScript.get_best_player_job_for_citizen(
			citizen_id
		).is_empty(),
		"Citizen-specific scheduling must also reject the unreachable job."
	)

	# Opening one deterministic gate must recover both diagnostics and the
	# unchanged citizen-specific scheduler on the next board synchronization.
	var gate_tile := city_world.get_tile(10, 4)
	gate_tile["terrain"] = WorldData.TERRAIN_LAND
	gate_tile["biome"] = WorldData.BIOME_PLAIN
	gate_tile["is_land"] = true
	CityWorkSystemScript.synchronize_player_work_board()
	var recovered_order: Dictionary = (
		CityWorkSystem.get_city_work_order_snapshot()[0]
	)
	var recovered_jobs: Array = recovered_order.get("jobs", [])
	var recovered_job: Dictionary = (
		recovered_jobs[0] if recovered_jobs.size() == 1 else {}
	)

	_expect(
		str(recovered_order.get("state", ""))
		== CityWorkSystemScript.ORDER_STATE_ACTIVE
		and bool(recovered_job.get("actionable", false))
		and str(recovered_job.get("state", ""))
		== CityWorkSystemScript.JOB_STATE_ACTIONABLE
		and str(recovered_job.get("blocked_reason", "")).is_empty(),
		"Opening a route must deterministically restore ACTIVE/actionable diagnostics."
	)
	_expect(
		not CityWorkSystemScript.get_best_player_job_for_citizen(
			citizen_id
		).is_empty(),
		"Opening a route must restore citizen-specific scheduling without changing it."
	)


func _test_parent_orders_and_two_level_fairness() -> void:
	var city_world := _reset_fixture()
	var citizen := _add_citizen("Scheduler", Vector2i(2, 4))
	var citizen_id := int(citizen.get("id", -1))
	var command_tiles: Array[Vector2i] = []

	for x in range(18, 28):
		var tile_position := Vector2i(x, 4)
		city_world.get_tile(x, 4)["surface_feature"] = (
			WorldData.CITY_SURFACE_FEATURE_TREE
		)
		command_tiles.append(tile_position)

	var designated_count := CityWorkSystem.add_city_player_command_targets(
		WorldData.CITY_PLAYER_COMMAND_TYPE_CHOP_TREE,
		command_tiles
	)
	_expect(
		designated_count == command_tiles.size(),
		"The large natural-work fixture must remain one complete command group."
	)

	var road_site := CityConstructionSystemScript.create_road_site(
		[Vector2i(4, 4)],
		"player",
		city_world
	)
	var site_id := int(road_site.get("id", -1))
	_expect(site_id > 0, "The fairness fixture must create a road site.")

	if site_id <= 0:
		return

	_expect(
		CityConstructionSystem.add_resource_to_city_construction_site(
			site_id,
			WorldData.RESOURCE_STONE,
			1
		) == 1,
		"The road site must accept its one physical stone."
	)
	CityConstructionSystemScript.refresh_city_construction_site(site_id)
	CityWorkSystemScript.synchronize_player_work_board()

	var orders := CityWorkSystem.get_city_work_order_snapshot()
	var group_order: Dictionary = {}
	var site_order: Dictionary = {}

	for raw_order in orders:
		if not raw_order is Dictionary:
			continue

		var order: Dictionary = raw_order

		match str(order.get("order_type", "")):
			CityWorkSystemScript.ORDER_TYPE_COMMAND_GROUP:
				_expect(
					group_order.is_empty(),
					"One natural-command group must create exactly one parent order."
				)
				group_order = order

			CityWorkSystemScript.ORDER_TYPE_CONSTRUCTION_SITE:
				if int(order.get("source_id", -1)) == site_id:
					_expect(
						site_order.is_empty(),
						"One construction site must create exactly one parent order."
					)
					site_order = order

	_expect(
		orders.size() == 2 and not group_order.is_empty()
		and not site_order.is_empty(),
		"The board must contain one group parent and one site parent, not one parent per tile."
	)

	var nearby_choice := (
		CityWorkSystemScript.get_best_player_job_for_citizen(citizen_id)
	)
	_expect(
		int(nearby_choice.get("work_order_id", -1))
		== int(site_order.get("id", -2)),
		"A nearby site must beat a far ten-tile group; child count must not multiply parent weight."
	)
	_expect(
		nearby_choice
		== CityWorkSystemScript.get_best_player_job_for_citizen(citizen_id),
		"Unchanged work state must produce a deterministic parent and job choice."
	)

	# Establish progress signatures, then make only the large group old and
	# neglected. Its bounded neglect bonus must eventually overcome locality.
	var group_order_id := int(group_order.get("id", -1))
	var neglected_order := CityWorkSystem.get_city_work_order_by_id(group_order_id)
	SimulationClock.absolute_world_minutes = 240
	neglected_order["created_world_minute"] = 0
	neglected_order["last_progress_world_minute"] = 0
	WorldData.city_work_orders[group_order_id] = neglected_order
	CityWorkSystemScript.synchronize_player_work_board()
	var debug_group_order: Dictionary = {}

	for raw_debug_order in CityWorkSystemScript.get_order_debug_snapshot():
		if (
			raw_debug_order is Dictionary
			and int(raw_debug_order.get("id", -1)) == group_order_id
		):
			debug_group_order = raw_debug_order
			break

	_expect(
		int(debug_group_order.get("minutes_since_progress", -1)) == 240,
		"The debug snapshot must expose deterministic minutes since parent progress."
	)

	var aged_choice := (
		CityWorkSystemScript.get_best_player_job_for_citizen(citizen_id)
	)
	_expect(
		int(aged_choice.get("work_order_id", -1)) == group_order_id,
		"A neglected parent must eventually receive attention despite being farther away."
	)


func _test_survival_food_fallback_and_reservation_accounting() -> void:
	var city_world := _reset_fixture()
	var first := _add_hungry_citizen("First", Vector2i(8, 9))
	var second := _add_hungry_citizen("Second", Vector2i(8, 10))
	var third := _add_hungry_citizen("Third", Vector2i(8, 11))
	var fishery_size := WorldData.get_city_object_size_for_type(
		WorldData.CITY_OBJECT_FISHING_GROUNDS
	)
	var fishery := WorldData.add_city_object({
		"object_type": WorldData.CITY_OBJECT_FISHING_GROUNDS,
		"top_left": Vector2i(10, 9),
		"size_tiles": fishery_size,
		"object_owner": "player",
		"city_world": city_world,
	})
	var fishery_id := int(fishery.get("id", -1))
	_expect(
		WorldData.add_resource_to_city_object_storage(
			fishery_id,
			WorldData.RESOURCE_FISH,
			1
		) == 1,
		"The fishery fixture must expose one unit of workplace output."
	)

	var pile_result := WorldData.add_resource_to_city_ground_piles_with_result({
		"tile_position": Vector2i(7, 12),
		"resource": WorldData.RESOURCE_FISH,
		"amount_delta": 2,
	})
	var pile_id := _first_ground_pile_id(pile_result)
	_expect(pile_id > 0, "The food fixture must create an ordinary fish pile.")

	var first_match := CityResourceMatcherScript.find_best_survival_food_source(
		first,
		100,
		10,
		32
	)
	_expect(
		str(first_match.get("source_kind", ""))
		== WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER
		and int(first_match.get("source_id", -1)) == fishery_id,
		"Survival food must prefer reachable workplace output over an ordinary ground pile."
	)
	_expect(
		_assign_food_match(int(first.get("id", -1)), first_match),
		"Assigning the first workplace-food request must reserve its unit."
	)

	var second_match := CityResourceMatcherScript.find_best_survival_food_source(
		second,
		100,
		10,
		32
	)
	_expect(
		str(second_match.get("source_kind", ""))
		== WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE
		and int(second_match.get("source_id", -1)) == pile_id,
		"A competing reservation must make survival food fall back from workplace output to ground food."
	)
	_expect(
		_assign_food_match(int(second.get("id", -1)), second_match),
		"Assigning the second food request must reserve the ordinary pile."
	)

	var third_match := CityResourceMatcherScript.find_best_survival_food_source(
		third,
		100,
		10,
		32
	)
	_expect(
		int(third_match.get("source_id", -1)) <= 0,
		"Fully reserved workplace and ground food must not be promised to a third citizen."
	)
	_expect(
		WorldData.get_city_food_endpoint_unreserved_amount(
			int(third.get("id", -1)),
			WorldData.make_city_ground_pile_haul_endpoint(pile_id),
			WorldData.RESOURCE_FISH
		) == 0,
		"Food endpoint availability must subtract competing task reservations."
	)


func _test_unreachable_food_tier_does_not_hide_fallbacks() -> void:
	var city_world := _reset_fixture()
	var citizen := _add_hungry_citizen("Fallback", Vector2i(20, 10))
	var stockpile_size := WorldData.get_city_object_size_for_type(
		WorldData.CITY_OBJECT_STOCKPILE
	)
	var stockpile_positions: Array[Vector2i] = [
		Vector2i(1, 2),
		Vector2i(4, 2),
		Vector2i(7, 2),
		Vector2i(10, 2),
		Vector2i(1, 7),
		Vector2i(4, 7),
		Vector2i(7, 7),
		Vector2i(10, 7),
	]

	for top_left in stockpile_positions:
		var stockpile := WorldData.add_city_object({
			"object_type": WorldData.CITY_OBJECT_STOCKPILE,
			"top_left": top_left,
			"size_tiles": stockpile_size,
			"object_owner": "player",
			"city_world": city_world,
		})
		_expect(
			WorldData.add_resource_to_city_object_storage(
				int(stockpile.get("id", -1)),
				WorldData.RESOURCE_FISH,
				1
			) == 1,
			"Every isolated stockpile must contain tempting but unreachable food."
		)

	var fishery_size := WorldData.get_city_object_size_for_type(
		WorldData.CITY_OBJECT_FISHING_GROUNDS
	)
	var fishery := WorldData.add_city_object({
		"object_type": WorldData.CITY_OBJECT_FISHING_GROUNDS,
		"top_left": Vector2i(23, 8),
		"size_tiles": fishery_size,
		"object_owner": "player",
		"city_world": city_world,
	})
	var fishery_id := int(fishery.get("id", -1))
	_expect(
		WorldData.add_resource_to_city_object_storage(
			fishery_id,
			WorldData.RESOURCE_FISH,
			1
		) == 1,
		"The reachable fallback workplace must contain fish."
	)

	var pile_result := WorldData.add_resource_to_city_ground_piles_with_result({
		"tile_position": Vector2i(20, 13),
		"resource": WorldData.RESOURCE_FISH,
		"amount_delta": 1,
	})
	var pile_id := _first_ground_pile_id(pile_result)
	_expect(pile_id > 0, "The reachable ground-food fallback must exist.")

	# A full-height mountain wall leaves every lower-ID stockpile accessible on
	# its own side but unreachable from the hungry citizen. The eight-request
	# decision budget must still reach later source tiers in this same call.
	for y in range(city_world.height):
		var wall_tile := city_world.get_tile(15, y)
		wall_tile["terrain"] = WorldData.TERRAIN_MOUNTAIN
		wall_tile["is_land"] = false

	city_world.mark_tile_data_changed()
	var survival_workplace_match := (
		CityResourceMatcherScript.find_best_survival_food_source(
			citizen,
			100,
			10,
			8
		)
	)
	_expect(
		int(survival_workplace_match.get("source_id", -1)) == fishery_id,
		"Eight unreachable stockpiles must not hide reachable workplace food."
	)
	_expect(
		int(survival_workplace_match.get("path_requests_used", 0)) == 2,
		"Survival matching must spend one exact path request per viable tier."
	)

	var household_workplace_match := (
		CityResourceMatcherScript.find_best_household_food_source(
			citizen,
			WorldData.RESOURCE_FISH,
			1,
			8
		)
	)
	_expect(
		int(
			household_workplace_match.get("endpoint", {}).get("id", -1)
		) == fishery_id,
		"Household matching must also reach workplace food past an unreachable tier."
	)

	_expect(
		WorldData.remove_resource_from_city_object_storage(
			fishery_id,
			WorldData.RESOURCE_FISH,
			1
		) == 1,
		"The fixture must empty workplace food before testing ground fallback."
	)
	var survival_ground_match := (
		CityResourceMatcherScript.find_best_survival_food_source(
			citizen,
			100,
			10,
			8
		)
	)
	_expect(
		str(survival_ground_match.get("source_kind", ""))
		== WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE
		and int(survival_ground_match.get("source_id", -1)) == pile_id,
		"Unreachable storage and empty workplaces must not hide reachable ground food."
	)

	var household_ground_match := (
		CityResourceMatcherScript.find_best_household_food_source(
			citizen,
			WorldData.RESOURCE_FISH,
			1,
			8
		)
	)
	_expect(
		str(household_ground_match.get("endpoint", {}).get("kind", ""))
		== WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE
		and int(
			household_ground_match.get("endpoint", {}).get("id", -1)
		) == pile_id,
		"Household matching must also reach ordinary ground food as final fallback."
	)


func _test_food_path_limit_covers_full_city() -> void:
	var large_city_world := WorldData.new()
	large_city_world.width = 101
	large_city_world.height = 101
	var expansion_limit := (
		CityResourceMatcherScript._get_city_wide_path_expansion_limit(
			large_city_world
		)
	)
	_expect(
		expansion_limit == 10_201 and expansion_limit > 10_000,
		"Exact food reachability must cover every city tile instead of stopping at 10,000 nodes."
	)


func _test_food_candidate_rotation_prevents_budget_starvation() -> void:
	var city_world := _reset_fixture()
	var first := _add_hungry_citizen("First scan", Vector2i(2, 15))
	var second := _add_hungry_citizen("Second scan", Vector2i(28, 15))
	var first_id := int(first.get("id", -1))
	var second_id := int(second.get("id", -1))
	var house := WorldData.add_city_object({
		"object_type": WorldData.CITY_OBJECT_HOUSE,
		"top_left": Vector2i(7, 2),
		"size_tiles": WorldData.get_city_object_size_for_type(WorldData.CITY_OBJECT_HOUSE),
		"object_owner": "player",
		"city_world": city_world,
	})
	var stockpile := WorldData.add_city_object({
		"object_type": WorldData.CITY_OBJECT_STOCKPILE,
		"top_left": Vector2i(11, 2),
		"size_tiles": WorldData.get_city_object_size_for_type(WorldData.CITY_OBJECT_STOCKPILE),
		"object_owner": "player",
		"city_world": city_world,
	})
	var keep := WorldData.add_city_object({
		"object_type": WorldData.CITY_OBJECT_CITY_CENTER,
		"top_left": Vector2i(15, 1),
		"size_tiles": WorldData.get_city_object_size_for_type(WorldData.CITY_OBJECT_CITY_CENTER),
		"object_owner": "player",
		"city_world": city_world,
	})
	var fishery := WorldData.add_city_object({
		"object_type": WorldData.CITY_OBJECT_FISHING_GROUNDS,
		"top_left": Vector2i(21, 2),
		"size_tiles": WorldData.get_city_object_size_for_type(
						WorldData.CITY_OBJECT_FISHING_GROUNDS
					),
		"object_owner": "player",
		"city_world": city_world,
	})

	_expect(
		WorldData.assign_city_citizen_home(
			first_id,
			int(house.get("id", -1))
		),
		"The first hungry citizen must own the isolated pantry tier."
	)
	_expect(
		WorldData.remove_city_citizen_home(second_id),
		"The later hungry citizen must have no private pantry tier."
	)

	for food_object in [house, stockpile, keep, fishery]:
		_expect(
			WorldData.add_resource_to_city_object_storage(
				int(food_object.get("id", -1)),
				WorldData.RESOURCE_FISH,
				1
			) == 1,
			"Every populated food tier must contain one physical fish."
		)

	var pile_result := WorldData.add_resource_to_city_ground_piles_with_result({
		"tile_position": Vector2i(27, 15),
		"resource": WorldData.RESOURCE_FISH,
		"amount_delta": 2,
	})
	var pile_id := _first_ground_pile_id(pile_result)
	_expect(pile_id > 0, "The later citizen needs a reachable final-tier pile.")

	# Citizen one is sealed west of x=5. Citizen two and the ground pile are
	# south-east, while every container tier is sealed north of y=10.
	for y in range(city_world.height):
		var vertical_wall_tile := city_world.get_tile(5, y)
		vertical_wall_tile["terrain"] = WorldData.TERRAIN_MOUNTAIN
		vertical_wall_tile["is_land"] = false

	for x in range(6, city_world.width):
		var horizontal_wall_tile := city_world.get_tile(x, 10)
		horizontal_wall_tile["terrain"] = WorldData.TERRAIN_MOUNTAIN
		horizontal_wall_tile["is_land"] = false

	city_world.mark_tile_data_changed()
	first = WorldData.get_city_citizen_by_id(first_id)
	second = WorldData.get_city_citizen_by_id(second_id)
	var first_probe := CityResourceMatcherScript.find_best_survival_food_source(
		first,
		100,
		10,
		8
	)
	var second_short_probe := (
		CityResourceMatcherScript.find_best_survival_food_source(
			second,
			100,
			10,
			3
		)
	)
	_expect(
		int(first_probe.get("source_id", -1)) <= 0
		and int(first_probe.get("path_requests_used", 0)) == 5,
		"The first citizen must exhaust all five populated unreachable tiers."
	)
	_expect(
		int(second_short_probe.get("source_id", -1)) <= 0
		and int(second_short_probe.get("path_requests_used", 0)) == 3,
		"Three remaining requests must stop just before the later citizen's ground tier."
	)

	CitizenDecisionSystemScript.reset_runtime_state()
	CitizenDecisionSystemScript._process_food_needs(true)
	_expect(
		str(WorldData.get_city_citizen_current_task(first_id).get("kind", ""))
		== WorldData.CITY_CITIZEN_TASK_KIND_NONE
		and str(
			WorldData.get_city_citizen_current_task(second_id).get("kind", "")
		) == WorldData.CITY_CITIZEN_TASK_KIND_NONE,
		"The first shared-budget pass must reproduce the later-citizen starvation boundary."
	)

	WorldData.set_city_citizen_hunger_state(first_id, 40, 0)
	WorldData.set_city_citizen_hunger_state(second_id, 40, 0)
	CitizenDecisionSystemScript._process_food_needs(false)
	_expect(
		str(WorldData.get_city_citizen_current_task(first_id).get("kind", ""))
		== WorldData.CITY_CITIZEN_TASK_KIND_NONE
		and str(
			WorldData.get_city_citizen_current_task(second_id).get("kind", "")
		) == WorldData.CITY_CITIZEN_TASK_KIND_NONE,
		"The normal-food cursor must start independently instead of borrowing the critical cursor."
	)

	WorldData.set_city_citizen_hunger_state(first_id, 20, 0)
	WorldData.set_city_citizen_hunger_state(second_id, 20, 0)
	CitizenDecisionSystemScript._process_food_needs(true)
	var second_task := WorldData.get_city_citizen_current_task(second_id)
	_expect(
		str(second_task.get("kind", ""))
		== WorldData.CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD
		and str(second_task.get("food_source_endpoint_kind", ""))
		== WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE
		and int(second_task.get("target_object_id", -1)) == pile_id,
		"The rotating critical-food start must let the later citizen search first on the next tick."
	)

	_expect(
		WorldData.clear_city_citizen_task(
			second_id,
			WorldData.CITY_CITIZEN_TASK_SOURCE_AUTONOMY
		),
		"The fixture must release the critical food reservation before the normal scan."
	)
	WorldData.set_city_citizen_hunger_state(first_id, 40, 0)
	WorldData.set_city_citizen_hunger_state(second_id, 40, 0)
	CitizenDecisionSystemScript._process_food_needs(false)
	second_task = WorldData.get_city_citizen_current_task(second_id)
	_expect(
		str(second_task.get("kind", ""))
		== WorldData.CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD
		and int(second_task.get("target_object_id", -1)) == pile_id,
		"The rotating normal-food start must independently reach the later citizen on its next pass."
	)


func _test_full_storage_construction_relocation_and_cancel_preview() -> void:
	var city_world := _reset_fixture()
	var citizen := _add_citizen("Relocator", Vector2i(13, 14))
	var citizen_id := int(citizen.get("id", -1))
	var stockpile_size := WorldData.get_city_object_size_for_type(
		WorldData.CITY_OBJECT_STOCKPILE
	)
	var stockpile := WorldData.add_city_object({
		"object_type": WorldData.CITY_OBJECT_STOCKPILE,
		"top_left": Vector2i(2, 2),
		"size_tiles": stockpile_size,
		"object_owner": "player",
		"city_world": city_world,
	})
	var stockpile_id := int(stockpile.get("id", -1))
	var stockpile_capacity := WorldData.get_city_object_storage_capacity(
		stockpile
	)
	_expect(
		WorldData.add_resource_to_city_object_storage(
			stockpile_id,
			WorldData.RESOURCE_COAL,
			stockpile_capacity
		) == stockpile_capacity,
		"The relocation fixture must make public storage genuinely full."
	)

	var house_size := WorldData.get_city_object_size_for_type(
		WorldData.CITY_OBJECT_HOUSE
	)
	var house_site := CityConstructionSystemScript.create_rectangular_site({
		"object_type": WorldData.CITY_OBJECT_HOUSE,
		"top_left": Vector2i(15, 14),
		"size_tiles": house_size,
		"object_owner": "player",
		"city_world": city_world,
	})
	var site_id := int(house_site.get("id", -1))
	_expect(site_id > 0, "The relocation fixture must create a House blueprint.")

	if site_id <= 0:
		return

	var footprint_tiles: Array = house_site.get("footprint_tiles", [])
	var pile_result := WorldData.add_resource_to_city_ground_piles_with_result({
		"tile_position": footprint_tiles[0],
		"resource": WorldData.RESOURCE_COAL,
		"amount_delta": 1,
	})
	var pile_id := _first_ground_pile_id(pile_result)
	CityConstructionSystemScript.refresh_city_construction_site(site_id)
	CityWorkSystemScript.synchronize_player_work_board()

	var site_order := _find_order(
		CityWorkSystemScript.ORDER_TYPE_CONSTRUCTION_SITE,
		site_id
	)
	var relocation_job: Dictionary = {}

	for raw_job in site_order.get("jobs", []):
		if (
			raw_job is Dictionary
			and str(raw_job.get("kind", ""))
			== CityWorkSystemScript.JOB_KIND_CLEARING_RELOCATION
		):
			relocation_job = raw_job
			break

	_expect(
		pile_id > 0 and not relocation_job.is_empty()
		and bool(relocation_job.get("actionable", false)),
		"A footprint pile must expose an actionable ground-relocation job when public storage is full."
	)
	_expect(
		CityConstructionSystemScript.can_relocate_ground_pile_outside_site(
			site_id,
			pile_id
		),
		"The cleanup fallback must find a legal ground tile outside the blueprint."
	)

	var relocation_candidate := (
		CityWorkSystemScript.get_best_player_job_for_citizen(citizen_id)
	)
	_expect(
		not relocation_candidate.is_empty()
		and int(relocation_candidate.get("work_order_id", -1))
		== int(site_order.get("id", -2))
		and CityWorkSystemScript.assign_player_job(
			citizen_id,
			relocation_candidate
		),
		"The relocation worker must claim the site-owned cleanup job."
	)
	CityWorkSystemScript.synchronize_player_work_board()
	site_order = _find_order(
		CityWorkSystemScript.ORDER_TYPE_CONSTRUCTION_SITE,
		site_id
	)
	relocation_job = {}

	for raw_job in site_order.get("jobs", []):
		if (
			raw_job is Dictionary
			and str(raw_job.get("kind", ""))
			== CityWorkSystemScript.JOB_KIND_CLEARING_RELOCATION
		):
			relocation_job = raw_job
			break

	_expect(
		str(site_order.get("state", ""))
		== CityWorkSystemScript.ORDER_STATE_ACTIVE
		and str(site_order.get("blocked_reason", "")).is_empty()
		and site_order.get("active_citizen_ids", []) == [citizen_id]
		and int(site_order.get("active_worker_count", 0)) == 1,
		"An in-progress cleanup must keep its parent ACTIVE with the actual worker ID."
	)
	_expect(
		str(relocation_job.get("state", ""))
		== CityWorkSystemScript.JOB_STATE_ACTIVE
		and str(relocation_job.get("blocked_reason", "")).is_empty()
		and relocation_job.get("active_citizen_ids", []) == [citizen_id]
		and int(relocation_job.get("claimed_citizen_id", -1)) == citizen_id
		and int(relocation_job.get("source_reserved_amount", 0)) == 1
		and int(relocation_job.get("destination_reserved_amount", 0)) == 1,
		"An active cleanup job must expose its claim and both reservation quantities."
	)

	var preview_tiles := CityWorkSystemScript.get_cancel_preview_tiles(
		[footprint_tiles.back()]
	)
	var expected_preview: Array[Vector2i] = []

	for raw_tile in footprint_tiles:
		if raw_tile is Vector2i:
			expected_preview.append(raw_tile)

	expected_preview.sort_custom(_sort_tiles_y_then_x)
	_expect(
		preview_tiles == expected_preview,
		"Hovering one blueprint tile in Cancel Task must expand to its full footprint."
	)


func _test_safe_boundary_and_cancellation_preserve_physical_cargo() -> void:
	var city_world := _reset_fixture()
	var citizen := _add_citizen("Carrier", Vector2i(7, 7))
	var citizen_id := int(citizen.get("id", -1))
	var road_site := CityConstructionSystemScript.create_road_site(
		[Vector2i(9, 7)],
		"player",
		city_world
	)
	var site_id := int(road_site.get("id", -1))
	_expect(site_id > 0, "The cancellation fixture must create a road site.")

	if site_id <= 0:
		return

	var source_result := WorldData.add_resource_to_city_ground_piles_with_result({
		"tile_position": Vector2i(7, 7),
		"resource": WorldData.RESOURCE_STONE,
		"amount_delta": 2,
	})
	var source_id := _first_ground_pile_id(source_result)
	var source := WorldData.make_city_ground_pile_haul_endpoint(source_id)
	var site_endpoint := WorldData.make_city_construction_site_haul_endpoint(
		site_id
	)
	_expect(
		WorldData.set_city_citizen_haul_cargo(
			citizen_id,
			WorldData.RESOURCE_STONE,
			2
		) == 2,
		"The cancellation fixture must put physical stone in transit."
	)
	var assigned := WorldData.assign_city_citizen_task(
		citizen_id,
		{
			"kind": WorldData.CITY_CITIZEN_TASK_KIND_HAUL,
			"source": WorldData.CITY_CITIZEN_TASK_SOURCE_PLAYER,
			"priority": WorldData.CITY_CONSTRUCTION_TASK_PRIORITY,
			"target_object_id": source_id,
			"haul": {
				"source": source,
				"destination": {},
				"requester": site_endpoint,
				"resource_type": WorldData.RESOURCE_STONE,
				"requested_amount": 2,
				"reason": (
					WorldData.CITY_CITIZEN_HAUL_REASON_CONSTRUCTION_DELIVERY
				),
				"source_access_purpose": (
					WorldData.CONTAINER_HAUL_PURPOSE_CONSTRUCTION
				),
				"destination_access_purpose": (
					WorldData.CONTAINER_HAUL_PURPOSE_CONSTRUCTION
				),
				"phase": WorldData.CITY_CITIZEN_HAUL_PHASE_RETARGETING,
				"source_tile": Vector2i(7, 7),
				"destination_tile": WorldData.INVALID_CITY_TILE_POSITION,
			},
		}
	)
	_expect(assigned, "The fixture must attach carried cargo to the site request.")

	var total_before := WorldData.get_total_physical_city_resource_amount(
		WorldData.RESOURCE_STONE
	)
	var task_before := WorldData.get_city_citizen_current_task(citizen_id)
	_expect(
		not CitizenTaskSystemScript
		.prepare_unemployed_citizen_for_priority_interrupt(citizen_id),
		"Normal player work must wait when an unemployed citizen already carries cargo."
	)
	_expect(
		WorldData.get_city_citizen_haul_cargo_resource_amount(
			citizen_id,
			WorldData.RESOURCE_STONE
		) == 2
		and WorldData.get_city_citizen_current_task(citizen_id) == task_before,
		"The normal safe-boundary check must preserve both cargo and its current delivery."
	)

	_expect(
		CityConstructionSystemScript.cancel_city_construction_site(site_id),
		"Cancel Task must cancel the blueprint referenced by in-flight cargo."
	)
	_expect(
		WorldData.get_city_citizen_haul_cargo_resource_amount(
			citizen_id,
			WorldData.RESOURCE_STONE
		) == 2,
		"Blueprint cancellation must preserve picked-up cargo instead of spilling or deleting it."
	)
	_expect(
		WorldData.get_total_physical_city_resource_amount(
			WorldData.RESOURCE_STONE
		) == total_before,
		"Blueprint cancellation must conserve the total amount of physical cargo and resources."
	)


func _test_cargo_ready_demand_preempts_soft_claim() -> void:
	var city_world := _reset_fixture()
	var carrier := _add_citizen("Ready carrier", Vector2i(6, 10))
	var claimant := _add_citizen("Soft claimant", Vector2i(24, 11))
	var carrier_id := int(carrier.get("id", -1))
	var claimant_id := int(claimant.get("id", -1))
	var keep_size := WorldData.get_city_object_size_for_type(
		WorldData.CITY_OBJECT_CITY_CENTER
	)
	var house_size := WorldData.get_city_object_size_for_type(
		WorldData.CITY_OBJECT_HOUSE
	)

	for tile_position in (
		WorldData.make_rectangle_city_object_footprint_tiles(
			Vector2i(2, 2),
			keep_size
		)
		+ WorldData.make_rectangle_city_object_footprint_tiles(
			Vector2i(12, 9),
			house_size
		)
		+ [Vector2i(24, 10)]
	):
		city_world.get_tile(
			tile_position.x,
			tile_position.y
		).erase("surface_feature")

	var keep := WorldData.add_city_object({
		"object_type": WorldData.CITY_OBJECT_CITY_CENTER,
		"top_left": Vector2i(2, 2),
		"size_tiles": keep_size,
		"object_owner": "player",
		"city_world": city_world,
	})
	var keep_id := int(keep.get("id", -1))
	var keep_endpoint := WorldData.make_city_citizen_haul_endpoint(
		keep_id
	)
	var house_site := CityConstructionSystemScript.create_rectangular_site({
		"object_type": WorldData.CITY_OBJECT_HOUSE,
		"top_left": Vector2i(12, 9),
		"size_tiles": house_size,
		"object_owner": "player",
		"city_world": city_world,
	})
	var site_id := int(house_site.get("id", -1))
	var site_endpoint := (
		WorldData.make_city_construction_site_haul_endpoint(site_id)
	)

	_expect(
		keep_id > 0
		and site_id > 0
		and str(house_site.get("phase", ""))
		== WorldData.CITY_CONSTRUCTION_PHASE_GATHERING,
		"The cargo-routing fixture must create reachable storage and a gathering site."
	)

	if keep_id <= 0 or site_id <= 0:
		return

	var source_result := WorldData.add_resource_to_city_ground_piles_with_result({
		"tile_position": Vector2i(24, 10),
		"resource": WorldData.RESOURCE_STONE,
		"amount_delta": 4,
	})
	var source_id := _first_ground_pile_id(source_result)
	var source_endpoint := WorldData.make_city_ground_pile_haul_endpoint(
		source_id
	)
	var soft_task_assigned := WorldData.assign_city_citizen_task(
		claimant_id,
		{
			"kind": WorldData.CITY_CITIZEN_TASK_KIND_HAUL,
			"source": WorldData.CITY_CITIZEN_TASK_SOURCE_PLAYER,
			"priority": WorldData.CITY_CONSTRUCTION_TASK_PRIORITY,
			"target_object_id": source_id,
			"haul": {
				"source": source_endpoint,
				"destination": site_endpoint,
				"requester": site_endpoint,
				"resource_type": WorldData.RESOURCE_STONE,
				"requested_amount": 4,
				"reason": (
					WorldData.CITY_CITIZEN_HAUL_REASON_CONSTRUCTION_DELIVERY
				),
				"source_access_purpose": (
					WorldData.CONTAINER_HAUL_PURPOSE_CONSTRUCTION
				),
				"destination_access_purpose": (
					WorldData.CONTAINER_HAUL_PURPOSE_CONSTRUCTION
				),
				"phase": WorldData.CITY_CITIZEN_HAUL_PHASE_PENDING_SOURCE,
				"source_tile": Vector2i(24, 10),
				"destination_tile": Vector2i(11, 10),
			},
		}
	)
	var soft_reservation_id := (
		WorldData.get_city_haul_reservation_id_for_citizen(
			claimant_id
		)
	)
	_expect(
		soft_task_assigned
		and WorldData.city_haul_reservation_is_soft(
			soft_reservation_id
		),
		"An unpicked construction assignment must remain a transferable soft reservation."
	)

	_expect(
		WorldData.set_city_citizen_haul_cargo(
			carrier_id,
			WorldData.RESOURCE_STONE,
			4
		) == 4,
		"The ready carrier must physically hold the site's complete stone deficit."
	)
	var carrier_task_assigned := WorldData.assign_city_citizen_task(
		carrier_id,
		{
			"kind": WorldData.CITY_CITIZEN_TASK_KIND_HAUL,
			"source": WorldData.CITY_CITIZEN_TASK_SOURCE_AUTONOMY,
			"priority": 90,
			"target_object_id": source_id,
			"haul": {
				"source": source_endpoint,
				"destination": keep_endpoint,
				"requester": keep_endpoint,
				"resource_type": WorldData.RESOURCE_STONE,
				"requested_amount": 4,
				"reason": (
					WorldData.CITY_CITIZEN_HAUL_REASON_GROUND_PILE_CLEANUP
				),
				"source_access_purpose": (
					WorldData.CONTAINER_HAUL_PURPOSE_GROUND_PILE_CLEANUP
				),
				"destination_access_purpose": (
					WorldData.CONTAINER_HAUL_PURPOSE_PUBLIC_STORAGE
				),
				"phase": (
					WorldData.CITY_CITIZEN_HAUL_PHASE_PENDING_DESTINATION
				),
				"source_tile": Vector2i(6, 10),
				"destination_tile": Vector2i(5, 4),
			},
		}
	)
	_expect(
		carrier_task_assigned,
		"The ready carrier must begin with an ordinary storage destination."
	)

	if not soft_task_assigned or not carrier_task_assigned:
		return

	carrier = WorldData.get_city_citizen_by_id(carrier_id)
	var carrier_task := WorldData.get_city_citizen_current_task(
		carrier_id
	)
	var carrier_haul := WorldData.get_city_citizen_current_haul(
		carrier_id
	)
	CitizenHaulingSystemScript._advance_pending_destination(
		city_world,
		{
			"citizen_id": carrier_id,
			"citizen": carrier,
			"current_task": carrier_task,
			"haul": carrier_haul,
			"path_requests_remaining": 8,
		}
	)
	var final_reservation := WorldData.get_city_haul_reservation(
		WorldData.get_city_haul_reservation_id_for_citizen(
			carrier_id
		)
	)

	_expect(
		WorldData.city_citizen_haul_endpoints_match(
			final_reservation.get("destination", {}),
			site_endpoint
		)
		and str(
			final_reservation.get(
				"destination_access_purpose",
				WorldData.CONTAINER_HAUL_PURPOSE_NONE
			)
		) == WorldData.CONTAINER_HAUL_PURPOSE_CONSTRUCTION,
		"Cargo already in hand must reroute from passive storage to the compatible player-command demand."
	)
	_expect(
		WorldData.get_city_haul_reservation(
			soft_reservation_id
		).is_empty()
		and str(
			WorldData.get_city_citizen_current_task(
				claimant_id
			).get("kind", "")
		) == WorldData.CITY_CITIZEN_TASK_KIND_NONE,
		"The ready carrier must displace the other citizen's unpicked claim without duplicating the delivery."
	)
	_expect(
		WorldData.get_city_citizen_haul_cargo_resource_amount(
			carrier_id,
			WorldData.RESOURCE_STONE
		) == 4,
		"Demand reassignment must preserve physical cargo until atomic deposit."
	)


func _test_resource_demand_priorities_are_adjustable() -> void:
	CityResourceMatcherScript.reset_resource_demand_category_priorities()
	var default_command_score := (
		CityResourceMatcherScript.score_resource_destination({
			"category": (
				CityResourceMatcherScript
				.RESOURCE_DEMAND_CATEGORY_PLAYER_COMMAND
			),
			"path_cost": 100_000,
			"fulfillment_amount": 4,
			"cargo_ready": true,
		})
	)
	var default_storage_score := (
		CityResourceMatcherScript.score_resource_destination({
			"category": (
				CityResourceMatcherScript
				.RESOURCE_DEMAND_CATEGORY_STORAGE
			),
			"path_cost": 10_000,
			"fulfillment_amount": 4,
			"cargo_ready": true,
		})
	)
	_expect(
		default_command_score > default_storage_score,
		"The default policy must strongly favor compatible player-command demand over passive storage."
	)
	_expect(
		CityResourceMatcherScript.set_resource_demand_category_priority(
			CityResourceMatcherScript.RESOURCE_DEMAND_CATEGORY_PLAYER_COMMAND,
			0
		)
		and CityResourceMatcherScript.set_resource_demand_category_priority(
			CityResourceMatcherScript.RESOURCE_DEMAND_CATEGORY_STORAGE,
			100
		),
		"Demand category priorities must expose bounded runtime adjustment hooks."
	)
	var adjusted_command_score := (
		CityResourceMatcherScript.score_resource_destination({
			"category": (
				CityResourceMatcherScript
				.RESOURCE_DEMAND_CATEGORY_PLAYER_COMMAND
			),
			"path_cost": 100_000,
			"fulfillment_amount": 4,
			"cargo_ready": true,
		})
	)
	var adjusted_storage_score := (
		CityResourceMatcherScript.score_resource_destination({
			"category": (
				CityResourceMatcherScript
				.RESOURCE_DEMAND_CATEGORY_STORAGE
			),
			"path_cost": 10_000,
			"fulfillment_amount": 4,
			"cargo_ready": true,
		})
	)
	_expect(
		adjusted_storage_score > adjusted_command_score,
		"Changing policy weights must alter destination selection without rewriting correctness rules."
	)
	CityResourceMatcherScript.reset_resource_demand_category_priorities()


func _reset_fixture() -> WorldData:
	WorldData.reset_runtime_session_state()
	CityResourceMatcherScript.reset_resource_demand_category_priorities()
	SimulationClock.start_new_game()
	var city_world := WorldData.new()
	city_world.setup(TEST_WORLD_SIZE.x, TEST_WORLD_SIZE.y, TEST_WORLD_SEED)

	for y in range(city_world.height):
		for x in range(city_world.width):
			var tile := city_world.get_tile(x, y)
			tile["terrain"] = WorldData.TERRAIN_LAND
			tile["biome"] = WorldData.BIOME_PLAIN
			tile["is_land"] = true
			tile["fertility"] = 50.0

	city_world.mark_tile_data_changed()
	WorldData.store_city_world_save(city_world, TEST_WORLD_SEED)
	return city_world


func _add_citizen(_display_name: String, tile_position: Vector2i) -> Dictionary:
	# An empty name requests the normal deterministic sex-specific pool entry.
	return WorldData.add_city_citizen(
		"",
		tile_position,
		WorldData.CITY_CITIZEN_SEX_FEMALE
	)


func _add_hungry_citizen(
	display_name: String,
	tile_position: Vector2i
) -> Dictionary:
	var citizen := _add_citizen(display_name, tile_position)
	WorldData.set_city_citizen_hunger_state(
		int(citizen.get("id", -1)),
		20,
		0
	)
	return WorldData.get_city_citizen_by_id(int(citizen.get("id", -1)))


func _assign_food_match(citizen_id: int, match_result: Dictionary) -> bool:
	return WorldData.assign_city_citizen_task(
		citizen_id,
		{
			"kind": WorldData.CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD,
			"source": WorldData.CITY_CITIZEN_TASK_SOURCE_AUTONOMY,
			"priority": NORMAL_FOOD_TASK_PRIORITY,
			"target_object_id": int(match_result.get("source_id", -1)),
			"target_tile": match_result.get(
				"target_tile",
				WorldData.INVALID_CITY_TILE_POSITION
			),
			"food_resource_type": str(
				match_result.get("resource_type", WorldData.RESOURCE_NONE)
			),
			"food_requested_amount": int(
				match_result.get("requested_amount", 0)
			),
			"food_source_endpoint_kind": str(
				match_result.get(
					"source_kind",
					WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
				)
			),
			"food_source_access_purpose": (
				WorldData.CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_PERSONAL_FOOD
			),
		}
	)


func _first_ground_pile_id(add_result: Dictionary) -> int:
	for raw_placement in add_result.get("placements", []):
		if raw_placement is Dictionary:
			return int(raw_placement.get("ground_pile_id", -1))

	return -1


func _find_order(order_type: String, source_id: int) -> Dictionary:
	for raw_order in CityWorkSystem.get_city_work_order_snapshot():
		if (
			raw_order is Dictionary
			and str(raw_order.get("order_type", "")) == order_type
			and int(raw_order.get("source_id", -1)) == source_id
		):
			return raw_order

	return {}


func _sort_tiles_y_then_x(a: Vector2i, b: Vector2i) -> bool:
	if a.y != b.y:
		return a.y < b.y

	return a.x < b.x


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error(message)
