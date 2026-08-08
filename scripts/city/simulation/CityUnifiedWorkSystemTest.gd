extends Node

const CityConstructionSystemScript = preload(
	"res://scripts/city/simulation/systems/CityConstructionSystem.gd"
)
const CityResourceMatcherScript = preload(
	"res://scripts/city/simulation/systems/CityResourceMatcher.gd"
)
const CityNavigationSystemScript = preload(
	"res://scripts/city/simulation/systems/CityNavigationSystem.gd"
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
const CitizenNeedsSystemScript = preload(
	"res://scripts/citizens/simulation/systems/CitizenNeedsSystem.gd"
)

const TEST_WORLD_SIZE := Vector2i(32, 24)
const TEST_WORLD_SEED: int = 27_041
const NORMAL_FOOD_TASK_PRIORITY: int = 85

var failure_count: int = 0
var test_culture_id: int = -1


func _ready() -> void:
	_test_roads_optimize_travel_time()
	_test_large_destination_heuristic_is_admissible()
	_test_independent_road_tiles_batch_scheduling()
	_test_parent_orders_and_two_level_fairness()
	_test_new_blueprint_rebalances_uncommitted_construction_travel()
	_test_blocked_construction_worker_uses_reachable_existing_alternative()
	_test_unreachable_blueprint_does_not_churn_construction_travel()
	_test_rebalance_preserves_active_construction_clearing()
	_test_unreachable_order_runtime_diagnostics()
	_test_food_replenishment_cycle_and_whole_item_consumption()
	_test_household_and_public_food_reserve_targets()
	_test_normal_home_food_preference_allowance()
	_test_survival_food_fallback_and_reservation_accounting()
	_test_unreachable_food_tier_does_not_hide_fallbacks()
	_test_food_path_limit_covers_full_city()
	_test_unified_food_search_avoids_budget_starvation()
	_test_full_storage_construction_relocation_and_cancel_preview()
	_test_construction_labor_balance()
	_test_safe_boundary_and_cancellation_preserve_physical_cargo()
	_test_cargo_ready_demand_preempts_soft_claim()
	_test_resource_demand_priorities_are_adjustable()
	_test_off_shift_homeless_idle_wander()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"Unified work system tests failed: " + str(failure_count)
		)
		get_tree().quit(1)
		return

	print("Unified work system tests passed.")
	get_tree().quit(0)


func _test_roads_optimize_travel_time() -> void:
	var city_world := _reset_fixture()
	var start_tile := Vector2i(2, 2)
	var destination_tile := Vector2i(10, 2)
	var road_tiles: Array[Vector2i] = []

	for x in range(2, 11):
		var road_tile := Vector2i(x, 3)
		road_tiles.append(road_tile)
		_expect(
			not WorldData.add_city_road_object(
				[road_tile],
				"player",
				city_world
			).is_empty(),
			"The travel-time fixture must create each completed road tile independently."
		)

	var result := CityNavigationSystemScript.find_path_to_any_city_tile({
		"city_world": city_world,
		"start_tile": start_tile,
		"destination_tiles": [destination_tile],
	})
	var path: Array = result.get("path", [])
	var used_road := false

	for raw_tile in path:
		if raw_tile is Vector2i and road_tiles.has(raw_tile):
			used_road = true
			break

	var direct_normal_cost := (
		(destination_tile.x - start_tile.x)
		* WorldData.CITY_CITIZEN_CARDINAL_MOVEMENT_COST
	)
	_expect(
		bool(result.get("success", false))
		and used_road
		and int(result.get("path_cost", direct_normal_cost))
		< direct_normal_cost,
		"Pathfinding must prefer a longer road route when its travel time is lower."
	)
	_expect(
		WorldData.get_city_citizen_movement_step_cost(
			start_tile,
			Vector2i(2, 3)
		) == WorldData.CITY_CITIZEN_ROAD_CARDINAL_MOVEMENT_COST,
		"Completed roads must halve cardinal movement cost."
	)


func _test_large_destination_heuristic_is_admissible() -> void:
	var city_world := _reset_fixture()
	var destination_tiles: Array[Vector2i] = []

	for x in range(8, 28):
		destination_tiles.append(Vector2i(x, 18))

	var heuristic := (
		CityNavigationSystemScript._make_destination_heuristic(
			destination_tiles
		)
	)
	_expect(
		not bool(heuristic.get("use_exact", true)),
		"Large destination sets must use the bounded constant-time heuristic."
	)

	for sample_tile in [
		Vector2i(2, 2),
		Vector2i(16, 2),
		Vector2i(30, 10),
		Vector2i(16, 18),
	]:
		var bounded_cost := (
			CityNavigationSystemScript._get_destination_heuristic(
				sample_tile,
				heuristic
			)
		)
		var exact_cost := (
			CityNavigationSystemScript._get_minimum_octile_distance(
				sample_tile,
				destination_tiles
			)
		)
		_expect(
			bounded_cost <= exact_cost,
			"The large-set heuristic must remain admissible for optimal road routing."
		)

	var result := CityNavigationSystemScript.find_path_to_any_city_tile({
		"city_world": city_world,
		"start_tile": Vector2i(2, 2),
		"destination_tiles": destination_tiles,
		"max_expanded_nodes": (
			CityNavigationSystemScript.get_city_wide_path_expansion_limit(
				city_world
			)
		),
	})
	_expect(
		bool(result.get("success", false))
		and destination_tiles.has(
			result.get(
				"destination_tile",
				WorldData.INVALID_CITY_TILE_POSITION
			)
		),
		"Large destination routing must still return a real requested destination."
	)


func _test_independent_road_tiles_batch_scheduling() -> void:
	var city_world := _reset_fixture()
	var first_citizen := _add_citizen("Road One", Vector2i(2, 2))
	var second_citizen := _add_citizen("Road Two", Vector2i(2, 3))
	var road_tiles: Array[Vector2i] = [
		Vector2i(8, 2),
		Vector2i(3, 2),
		Vector2i(6, 2),
	]
	var road_sites := CityConstructionSystemScript.create_road_sites(
		road_tiles,
		"player",
		city_world
	)
	_expect(
		road_sites.size() == road_tiles.size(),
		"A painted road must expose one independent scheduler site per tile."
	)

	if road_sites.size() != road_tiles.size():
		return

	var site_id_by_tile: Dictionary = {}

	for road_site in road_sites:
		var footprint_tiles = road_site.get("footprint_tiles", [])

		if footprint_tiles is Array and footprint_tiles.size() == 1:
			site_id_by_tile[footprint_tiles[0]] = int(
				road_site.get("id", -1)
			)

	var first_citizen_id := int(first_citizen.get("id", -1))
	var first_candidate := (
		CityWorkSystemScript.get_best_player_job_for_citizen(
			first_citizen_id
		)
	)
	var nearest_site_id := int(
		site_id_by_tile.get(Vector2i(3, 2), -1)
	)
	_expect(
		nearest_site_id > 0
		and int(first_candidate.get("construction_site_id", -1))
		== nearest_site_id
		and int(first_candidate.get("work_order_id", -1)) > 0,
		"Batched road routing must return the nearest actionable tile with that tile's own site and order IDs."
	)
	_expect(
		CityWorkSystemScript.assign_player_job(
			first_citizen_id,
			first_candidate
		),
		"The first road worker must claim exactly one independent road tile."
	)
	var first_task := WorldData.get_city_citizen_current_task(
		first_citizen_id
	)
	_expect(
		int(first_task.get("target_object_id", -1)) == nearest_site_id,
		"A road labor task must remain owned by one tile site, never the painted stroke."
	)

	var second_candidate := (
		CityWorkSystemScript.get_best_player_job_for_citizen(
			int(second_citizen.get("id", -1))
		)
	)
	_expect(
		int(second_candidate.get("construction_site_id", -1)) > 0
		and int(second_candidate.get("construction_site_id", -1))
		!= nearest_site_id,
		"A claimed one-worker road tile must make the next citizen choose another independent tile."
	)


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
			CityWorkSystem.CITY_PLAYER_COMMAND_TYPE_CHOP_TREE,
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
		CityWorkSystem.CITY_PLAYER_COMMAND_TYPE_CHOP_TREE,
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
	CityWorkSystem.get_current_work_state().work_orders[group_order_id] = neglected_order
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


func _test_new_blueprint_rebalances_uncommitted_construction_travel() -> void:
	var city_world := _reset_fixture()
	var left_builder := _add_citizen("Left Builder", Vector2i(3, 5))
	var second_left_builder := _add_citizen(
		"Second Left Builder",
		Vector2i(3, 7)
	)
	var right_builder := _add_citizen("Right Builder", Vector2i(22, 6))
	var citizens: Array[Dictionary] = [
		left_builder,
		second_left_builder,
		right_builder,
	]
	var far_tile := Vector2i(25, 6)
	var far_tiles: Array[Vector2i] = [
		far_tile,
		far_tile + Vector2i.RIGHT,
		far_tile + Vector2i.RIGHT * 2,
	]
	var far_site := _create_ready_labor_site(far_tiles, 3)
	var far_site_id := int(far_site.get("id", -1))
	_expect(
		far_site_id > 0,
		"The construction-rebalance fixture must create the initial far site."
	)

	if far_site_id <= 0:
		return

	CityWorkSystemScript.synchronize_player_work_board()
	var far_order := _find_order(
		CityWorkSystemScript.ORDER_TYPE_CONSTRUCTION_SITE,
		far_site_id
	)

	for citizen in citizens:
		var citizen_id := int(citizen.get("id", -1))
		var far_candidate := (
			CityWorkSystemScript.get_best_player_job_for_citizen(citizen_id)
		)
		_expect(
			int(far_candidate.get("work_order_id", -1))
			== int(far_order.get("id", -2))
			and CityWorkSystemScript.assign_player_job(
				citizen_id,
				far_candidate
			),
			"Every builder must initially accept the only available far site."
		)

	CitizenTaskSystemScript.run_tick(0, 1)
	var left_builder_id := int(left_builder.get("id", -1))
	var second_left_builder_id := int(second_left_builder.get("id", -1))
	var right_builder_id := int(right_builder.get("id", -1))
	var left_before_blocked_blueprint := _get_assignment_snapshot(
		left_builder_id
	)
	var second_left_before_blocked_blueprint := _get_assignment_snapshot(
		second_left_builder_id
	)
	var right_before_blocked_blueprint := _get_assignment_snapshot(
		right_builder_id
	)
	var blocked_road := _create_material_blocked_site(
		Vector2i(5, 5),
		1
	)
	var blocked_road_id := int(blocked_road.get("id", -1))

	_expect(
		blocked_road_id > 0,
		"The rebalance fixture must create a material-blocked road."
	)
	CityWorkSystemScript.synchronize_player_work_board()
	var blocked_blueprint_switch_count := (
		CityConstructionSystemScript
		.rebalance_uncommitted_construction_workers(blocked_road_id)
	)
	_expect(
		blocked_blueprint_switch_count == 0
		and _get_assignment_snapshot(left_builder_id)
		== left_before_blocked_blueprint
		and _get_assignment_snapshot(second_left_builder_id)
		== second_left_before_blocked_blueprint
		and _get_assignment_snapshot(right_builder_id)
		== right_before_blocked_blueprint,
		"A material-blocked blueprint must not stop or restart existing trips."
	)

	var stone_result := CityLogisticsSystem.add_resource_to_city_ground_piles_with_result({
		"tile_position": Vector2i(4, 7),
		"resource": WorldData.RESOURCE_STONE,
		"amount_delta": 1,
	})
	_expect(
		_first_ground_pile_id(stone_result) > 0,
		"The rebalance fixture must expose one reachable construction stone."
	)
	var near_site := _create_material_blocked_site(
		Vector2i(7, 6),
		1
	)
	var near_site_id := int(near_site.get("id", -1))

	_expect(
		near_site_id > 0,
		"The construction-rebalance fixture must create a reachable nearby site."
	)

	if near_site_id <= 0:
		return

	# This synthetic material-requiring road bypasses the production road
	# placement API, so the test must explicitly invoke the same scheduling
	# boundary that production placement invokes.
	CityWorkSystemScript.synchronize_player_work_board()
	var switched_to_near := (
		CityConstructionSystemScript
		.rebalance_uncommitted_construction_workers(near_site_id)
	)

	var near_order := _find_order(
		CityWorkSystemScript.ORDER_TYPE_CONSTRUCTION_SITE,
		near_site_id
	)
	var left_after_near_blueprint := WorldData.get_city_citizen_current_task(
		left_builder_id
	)
	var left_after_near_citizen := WorldData.get_city_citizen_by_id(
		left_builder_id
	)
	var left_after_near_haul := WorldData.get_city_citizen_current_haul(
		left_builder_id
	)

	_expect(
		switched_to_near == 1
		and str(left_after_near_blueprint.get("kind", ""))
		== WorldData.CITY_CITIZEN_TASK_KIND_HAUL
		and int(left_after_near_blueprint.get("work_order_id", -1))
		== int(near_order.get("id", -2)),
		"The left-side builder must switch and receive the nearby delivery in the same call."
	)
	_expect(
		str(left_after_near_blueprint.get("phase", ""))
		== WorldData.CITY_CITIZEN_TASK_PHASE_TRAVELING
		and str(left_after_near_haul.get("phase", ""))
		== WorldData.CITY_CITIZEN_HAUL_PHASE_TRAVELING_TO_SOURCE
		and str(left_after_near_citizen.get("movement_state", ""))
		== WorldData.CITY_CITIZEN_MOVEMENT_STATE_MOVING
		and left_after_near_citizen.get(
			"movement_destination_tile",
			WorldData.INVALID_CITY_TILE_POSITION
		) == left_after_near_haul.get(
			"source_tile",
			WorldData.INVALID_CITY_TILE_POSITION
		),
		"A redirected worker must begin the replacement route in the same simulation step."
	)
	_expect(
		_get_assignment_snapshot(second_left_builder_id)
		== second_left_before_blocked_blueprint,
		"The first switch must reserve the one-site capacity before the next left-side worker is evaluated."
	)
	_expect(
		_get_assignment_snapshot(right_builder_id)
		== right_before_blocked_blueprint,
		"The right-side builder must continue toward the already-near far site without path churn."
	)

	var stable_left_assignment := _get_assignment_snapshot(left_builder_id)
	var stable_second_left_assignment := _get_assignment_snapshot(
		second_left_builder_id
	)
	var stable_right_assignment := _get_assignment_snapshot(right_builder_id)

	for _repeat in range(3):
		CityConstructionSystemScript.rebalance_uncommitted_construction_workers(
			near_site_id
		)

	_expect(
		_get_assignment_snapshot(left_builder_id) == stable_left_assignment
		and _get_assignment_snapshot(second_left_builder_id)
		== stable_second_left_assignment
		and _get_assignment_snapshot(right_builder_id)
		== stable_right_assignment,
		"Repeated evaluation of one blueprint must not bounce either citizen."
	)

	var marginal_site := _create_ready_labor_site(
		[Vector2i(24, 8)],
		1
	)
	var marginal_site_id := int(marginal_site.get("id", -1))
	var switched_to_marginal := (
		CityConstructionSystemScript
		.rebalance_uncommitted_construction_workers(marginal_site_id)
	)
	_expect(
		switched_to_marginal == 0
		and _get_assignment_snapshot(right_builder_id)
		== stable_right_assignment,
		"A roughly one-tile saving must remain inside the equal-priority hysteresis dead band."
	)

	WorldData.set_city_citizen_task_phase(
		right_builder_id,
		WorldData.CITY_CITIZEN_TASK_PHASE_BLOCKED
	)
	var blocked_switch_count := (
		CityConstructionSystemScript
		.rebalance_uncommitted_construction_workers(marginal_site_id)
	)
	var right_after_blocked_switch := (
		WorldData.get_city_citizen_current_task(right_builder_id)
	)
	var marginal_order := _find_order(
		CityWorkSystemScript.ORDER_TYPE_CONSTRUCTION_SITE,
		marginal_site_id
	)
	_expect(
		blocked_switch_count == 1
		and str(right_after_blocked_switch.get("kind", ""))
		!= WorldData.CITY_CITIZEN_TASK_KIND_NONE
		and int(right_after_blocked_switch.get("work_order_id", -1))
		== int(marginal_order.get("id", -2)),
		"A blocked worker must switch to a reachable site immediately despite the normal distance threshold."
	)

	var right_after_switch := _get_assignment_snapshot(right_builder_id)

	for _repeat in range(3):
		CityConstructionSystemScript.rebalance_uncommitted_construction_workers(
			far_site_id
		)

	_expect(
		_get_assignment_snapshot(right_builder_id) == right_after_switch,
		"Equal-priority placement must not reverse a completed switch through age or neglect weighting."
	)

	WorldData.set_city_citizen_task_phase(
		right_builder_id,
		WorldData.CITY_CITIZEN_TASK_PHASE_PERFORMING
	)
	WorldData.set_city_citizen_task_phase(
		second_left_builder_id,
		WorldData.CITY_CITIZEN_TASK_PHASE_PERFORMING
	)
	var performing_task := _get_assignment_snapshot(right_builder_id)
	var second_performing_task := _get_assignment_snapshot(
		second_left_builder_id
	)
	var protected_delivery := _get_assignment_snapshot(left_builder_id)
	var protected_haul := WorldData.get_city_citizen_current_haul(
		left_builder_id
	)
	var protected_reservation_id := int(
		protected_haul.get("reservation_id", -1)
	)
	var protected_reservation := CityLogisticsSystem.get_city_haul_reservation(
		protected_reservation_id
	)
	var urgent_site := _create_ready_labor_site([Vector2i(22, 7)], 1)
	var urgent_site_id := int(urgent_site.get("id", -1))
	CityWorkSystemScript.synchronize_player_work_board()
	var urgent_order := _find_order(
		CityWorkSystemScript.ORDER_TYPE_CONSTRUCTION_SITE,
		urgent_site_id
	)
	_expect(
		CityWorkSystemScript.set_order_priority(
			int(urgent_order.get("id", -1)),
			CityWorkSystemScript.PRIORITY_HIGH
		),
		"The commitment fixture must raise the attractive alternative's priority."
	)
	var protected_switch_count := (
		CityConstructionSystemScript
		.rebalance_uncommitted_construction_workers(urgent_site_id)
	)
	_expect(
		protected_switch_count == 0
		and _get_assignment_snapshot(right_builder_id) == performing_task
		and _get_assignment_snapshot(second_left_builder_id)
		== second_performing_task,
		"Rebalancing must never interrupt active construction labor, even for higher-priority work."
	)
	_expect(
		_get_assignment_snapshot(left_builder_id) == protected_delivery
		and protected_reservation_id > 0
		and CityLogisticsSystem.get_city_haul_reservation(
			protected_reservation_id
		) == protected_reservation,
		"Rebalancing must preserve an empty-handed construction delivery and its reservation."
	)


func _test_blocked_construction_worker_uses_reachable_existing_alternative() -> void:
	var city_world := _reset_fixture()
	var citizen := _add_citizen("Blocked Builder", Vector2i(2, 4))
	var citizen_id := int(citizen.get("id", -1))
	var current_site := _create_ready_labor_site([Vector2i(8, 4)], 1)
	var alternative_site := _create_ready_labor_site([Vector2i(4, 8)], 1)
	var current_site_id := int(current_site.get("id", -1))
	var alternative_site_id := int(alternative_site.get("id", -1))
	CityWorkSystemScript.synchronize_player_work_board()
	var current_order := _find_order(
		CityWorkSystemScript.ORDER_TYPE_CONSTRUCTION_SITE,
		current_site_id
	)
	var alternative_order := _find_order(
		CityWorkSystemScript.ORDER_TYPE_CONSTRUCTION_SITE,
		alternative_site_id
	)
	var current_candidate := (
		CityWorkSystemScript.get_player_job_for_citizen_and_order(
			citizen_id,
			int(current_order.get("id", -1))
		)
	)

	_expect(
		current_site_id > 0
		and alternative_site_id > 0
		and CityWorkSystemScript.assign_player_job(
			citizen_id,
			current_candidate
		),
		"The blocked-rebalance fixture must assign its original construction site."
	)
	CitizenTaskSystemScript.run_tick(0, 1)
	WorldData.cancel_city_citizen_movement(citizen_id)
	WorldData.set_city_citizen_task_phase(
		citizen_id,
		WorldData.CITY_CITIZEN_TASK_PHASE_BLOCKED
	)
	var material_blocked_site := _create_material_blocked_site(
		Vector2i(20, 4),
		1
	)
	# The helper intentionally creates a low-level synthetic site; mirror the
	# production placement boundary before checking blocked reassignment.
	CityWorkSystemScript.synchronize_player_work_board()
	var blocked_reassignment_count := (
		CityConstructionSystemScript
		.rebalance_uncommitted_construction_workers(
			int(material_blocked_site.get("id", -1))
		)
	)
	var reassigned_task := WorldData.get_city_citizen_current_task(citizen_id)
	var reassigned_citizen := WorldData.get_city_citizen_by_id(citizen_id)

	_expect(
		int(material_blocked_site.get("id", -1)) > 0
		and blocked_reassignment_count == 1
		and int(reassigned_task.get("work_order_id", -1))
		== int(alternative_order.get("id", -2))
		and str(reassigned_task.get("phase", ""))
		== WorldData.CITY_CITIZEN_TASK_PHASE_TRAVELING
		and str(reassigned_citizen.get("movement_state", ""))
		== WorldData.CITY_CITIZEN_MOVEMENT_STATE_MOVING,
		"A blocked worker must choose a reachable existing construction alternative even when the new blueprint cannot start."
	)


func _test_rebalance_preserves_active_construction_clearing() -> void:
	var city_world := _reset_fixture()
	var citizen := _add_citizen("Active Clearer", Vector2i(9, 8))
	var citizen_id := int(citizen.get("id", -1))
	var tree_tile := Vector2i(10, 8)
	city_world.get_tile(tree_tile.x, tree_tile.y)["surface_feature"] = (
		WorldData.CITY_SURFACE_FEATURE_TREE
	)
	var clearing_site := CityConstructionSystemScript.create_road_site(
		[tree_tile],
		"player",
		city_world
	)
	var clearing_site_id := int(clearing_site.get("id", -1))
	CityWorkSystemScript.synchronize_player_work_board()
	var clearing_candidate := (
		CityWorkSystemScript.get_best_player_job_for_citizen(citizen_id)
	)
	_expect(
		clearing_site_id > 0
		and str(clearing_candidate.get("player_work_kind", "")) == "command"
		and CityWorkSystemScript.assign_player_job(
			citizen_id,
			clearing_candidate
		),
		"The active-clearing fixture must assign its construction obstruction command."
	)
	CitizenTaskSystemScript.run_tick(0, 1)
	var performing_task := WorldData.get_city_citizen_current_task(citizen_id)
	_expect(
		str(performing_task.get("phase", ""))
		== WorldData.CITY_CITIZEN_TASK_PHASE_PERFORMING,
		"The construction clearer must cross the physical performing boundary."
	)
	var performing_snapshot := _get_assignment_snapshot(citizen_id)
	var command_before := CityWorkSystem.get_city_player_command_by_id(
		int(performing_task.get("target_object_id", -1))
	)
	var urgent_site := _create_ready_labor_site([Vector2i(9, 10)], 1)
	var urgent_site_id := int(urgent_site.get("id", -1))
	CityWorkSystemScript.synchronize_player_work_board()
	var urgent_order := _find_order(
		CityWorkSystemScript.ORDER_TYPE_CONSTRUCTION_SITE,
		urgent_site_id
	)
	CityWorkSystemScript.set_order_priority(
		int(urgent_order.get("id", -1)),
		CityWorkSystemScript.PRIORITY_HIGH
	)
	var switched_count := (
		CityConstructionSystemScript
		.rebalance_uncommitted_construction_workers(urgent_site_id)
	)
	_expect(
		switched_count == 0
		and _get_assignment_snapshot(citizen_id) == performing_snapshot
		and CityWorkSystem.get_city_player_command_by_id(
			int(performing_task.get("target_object_id", -1))
		) == command_before,
		"Rebalancing must preserve active construction clearing and its command claim."
	)


func _test_unreachable_blueprint_does_not_churn_construction_travel() -> void:
	var city_world := _reset_fixture()
	var citizen := _add_citizen("Reachable Builder", Vector2i(2, 4))
	var citizen_id := int(citizen.get("id", -1))
	var current_site := _create_ready_labor_site([Vector2i(6, 4)], 1)
	var current_site_id := int(current_site.get("id", -1))
	CityWorkSystemScript.synchronize_player_work_board()
	var current_candidate := (
		CityWorkSystemScript.get_best_player_job_for_citizen(citizen_id)
	)
	_expect(
		current_site_id > 0
		and CityWorkSystemScript.assign_player_job(
			citizen_id,
			current_candidate
		),
		"The unreachable-blueprint fixture must assign its reachable current site."
	)
	CitizenTaskSystemScript.run_tick(0, 1)
	var assignment_before := _get_assignment_snapshot(citizen_id)

	for y in range(city_world.height):
		var barrier_tile := city_world.get_tile(10, y)
		barrier_tile["terrain"] = WorldData.TERRAIN_WATER
		barrier_tile["biome"] = WorldData.BIOME_OCEAN
		barrier_tile["is_land"] = false
		barrier_tile.erase("surface_feature")

	var unreachable_site := _create_ready_labor_site(
		[Vector2i(18, 4)],
		1
	)
	var unreachable_site_id := int(unreachable_site.get("id", -1))
	var switched_count := (
		CityConstructionSystemScript
		.rebalance_uncommitted_construction_workers(unreachable_site_id)
	)
	_expect(
		unreachable_site_id > 0
		and switched_count == 0
		and _get_assignment_snapshot(citizen_id) == assignment_before,
		"An unreachable blueprint must leave the current task and movement path untouched."
	)


func _test_food_replenishment_cycle_and_whole_item_consumption() -> void:
	_reset_fixture()
	var citizen := _add_citizen("Food cycle", Vector2i(8, 8))
	var citizen_id := int(citizen.get("id", -1))

	_expect(
		WorldData.get_city_food_hunger_restore(WorldData.RESOURCE_FISH) == 20
		and WorldData.get_city_food_hunger_restore(WorldData.RESOURCE_MEAT) == 20,
		"Fish and meat must each restore exactly 20 hunger."
	)
	_expect(
		WorldData.CITIZEN_FOOD_SEEK_TRIGGER_HUNGER == 70
		and WorldData.CITIZEN_EAT_TARGET_HUNGER == 100,
		"Food seeking must begin at 70 while the eating target remains 100."
	)

	WorldData.set_city_citizen_hunger_state(citizen_id, 90, 0)
	_expect(
		WorldData.add_resource_to_city_citizen_inventory(
			citizen_id,
			WorldData.RESOURCE_FISH,
			1
		) == 1,
		"The food-cycle fixture must add one carried fish."
	)
	CitizenNeedsSystemScript.eat_personal_food_if_hungry(citizen_id)
	_expect(
		WorldData.get_city_citizen_hunger(citizen_id) == 90
		and WorldData.get_city_citizen_inventory_resource_amount(
			citizen_id,
			WorldData.RESOURCE_FISH
		) == 1,
		"A citizen at 90 must keep a 20-point food item instead of wasting half."
	)

	WorldData.set_city_citizen_hunger_state(citizen_id, 80, 0)
	CitizenNeedsSystemScript.eat_personal_food_if_hungry(citizen_id)
	_expect(
		WorldData.get_city_citizen_hunger(citizen_id) == 100
		and WorldData.get_city_citizen_inventory_resource_amount(
			citizen_id,
			WorldData.RESOURCE_FISH
		) == 0,
		"The retained item must be eaten at 80 to reach exactly 100."
	)

	WorldData.set_city_citizen_hunger_state(citizen_id, 70, 0)
	_expect(
		CitizenNeedsSystemScript.citizen_should_seek_food(citizen_id)
		and CitizenNeedsSystemScript.get_citizen_food_need_nutrition(citizen_id)
		== 30,
		"A citizen reaching 70 without food must seek 30 nutrition toward 100."
	)
	_expect(
		WorldData.add_resource_to_city_citizen_inventory(
			citizen_id,
			WorldData.RESOURCE_FISH,
			2
		) == 2,
		"A 30-point deficit must be coverable by two whole 20-point items."
	)
	CitizenNeedsSystemScript.eat_personal_food_if_hungry(citizen_id)
	_expect(
		WorldData.get_city_citizen_hunger(citizen_id) == 90
		and WorldData.get_city_citizen_inventory_resource_amount(
			citizen_id,
			WorldData.RESOURCE_FISH
		) == 1
		and not CitizenNeedsSystemScript.citizen_should_seek_food(citizen_id),
		"At 70, one item must raise hunger to 90 while the second remains carried."
	)

	WorldData.set_city_citizen_hunger_state(citizen_id, 80, 0)
	CitizenNeedsSystemScript.eat_personal_food_if_hungry(citizen_id)
	_expect(
		WorldData.get_city_citizen_hunger(citizen_id) == 100
		and WorldData.get_city_citizen_inventory_resource_amount(
			citizen_id,
			WorldData.RESOURCE_FISH
		) == 0,
		"The carried second item must complete the daily 70-to-100 cycle."
	)


func _test_household_and_public_food_reserve_targets() -> void:
	var city_world := _reset_fixture()
	var first := _add_citizen("Pantry first", Vector2i(8, 8))
	var second := _add_citizen("Pantry second", Vector2i(9, 8))
	var house := WorldData.add_city_object({
		"object_type": WorldData.CITY_OBJECT_HOUSE,
		"top_left": Vector2i(4, 4),
		"size_tiles": WorldData.get_city_object_size_for_type(
			WorldData.CITY_OBJECT_HOUSE
		),
		"object_owner": "player",
		"city_world": city_world,
	})
	var house_id := int(house.get("id", -1))
	_expect(
		WorldData.assign_city_citizen_home(int(first.get("id", -1)), house_id)
		and WorldData.assign_city_citizen_home(
			int(second.get("id", -1)),
			house_id
		),
		"Both pantry-test citizens must reside in the same house."
	)
	house = WorldData.get_city_object_by_id(house_id)
	_expect(
		CityResourceMatcherScript.get_city_home_food_target_nutrition(house)
		== 80
		and CityResourceMatcherScript.get_city_home_requested_food_units(
			house,
			WorldData.RESOURCE_FISH
		) == 4,
		"A two-resident home must target one full day: 80 nutrition or four fish."
	)
	_expect(
		CityResourceMatcherScript.get_city_public_food_reserve_target_nutrition()
		== 40,
		"Two living citizens must protect a half-day public reserve of 40 nutrition."
	)

	var stockpile := WorldData.add_city_object({
		"object_type": WorldData.CITY_OBJECT_STOCKPILE,
		"top_left": Vector2i(12, 6),
		"size_tiles": WorldData.get_city_object_size_for_type(
			WorldData.CITY_OBJECT_STOCKPILE
		),
		"object_owner": "player",
		"city_world": city_world,
	})
	var stockpile_id := int(stockpile.get("id", -1))
	_expect(
		WorldData.add_resource_to_city_object_storage(
			stockpile_id,
			WorldData.RESOURCE_FISH,
			2
		) == 2,
		"The public reserve fixture must store exactly two fish."
	)
	first = WorldData.get_city_citizen_by_id(int(first.get("id", -1)))
	var protected_match := CityResourceMatcherScript.find_best_household_food_source(
		first,
		WorldData.RESOURCE_FISH,
		4
	)
	_expect(
		protected_match.is_empty(),
		"A pantry delivery must not consume the exact half-day public reserve."
	)

	_expect(
		WorldData.add_resource_to_city_object_storage(
			stockpile_id,
			WorldData.RESOURCE_FISH,
			1
		) == 1,
		"The pantry fixture must add one fish above the protected reserve."
	)
	var surplus_match := CityResourceMatcherScript.find_best_household_food_source(
		first,
		WorldData.RESOURCE_FISH,
		4
	)
	_expect(
		int(surplus_match.get("endpoint", {}).get("id", -1)) == stockpile_id
		and int(surplus_match.get("available_amount", 0)) == 1,
		"Only the one public-surplus fish may be offered for pantry delivery."
	)


func _test_normal_home_food_preference_allowance() -> void:
	var home_result := {
		"source_id": 1,
		"path_cost": 125,
	}
	var alternative_result := {
		"source_id": 2,
		"path_cost": 100,
	}
	_expect(
		int(
			CityResourceMatcherScript._choose_normal_survival_food_result(
				home_result,
				alternative_result
			).get("source_id", -1)
		) == 1,
		"Normal hunger may prefer home when its route is no more than 25% longer."
	)
	home_result["path_cost"] = 126
	_expect(
		int(
			CityResourceMatcherScript._choose_normal_survival_food_result(
				home_result,
				alternative_result
			).get("source_id", -1)
		) == 2,
		"A source more than 25% closer must beat the normal home preference."
	)


func _test_survival_food_fallback_and_reservation_accounting() -> void:
	var city_world := _reset_fixture()
	var first := _add_hungry_citizen("First", Vector2i(8, 9))
	var second := _add_hungry_citizen("Second", Vector2i(8, 10))
	var third := _add_hungry_citizen("Third", Vector2i(8, 11))
	var fourth := _add_hungry_citizen("Fourth", Vector2i(8, 12))
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

	var pile_result := CityLogisticsSystem.add_resource_to_city_ground_piles_with_result({
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
		str(third_match.get("source_kind", ""))
		== WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE
		and int(third_match.get("source_id", -1)) == pile_id,
		"One-item allocation must leave the pile's second fish available to a third hungry citizen."
	)
	_expect(
		_assign_food_match(int(third.get("id", -1)), third_match),
		"Assigning the third food request must reserve the pile's final fish."
	)

	var fourth_match := CityResourceMatcherScript.find_best_survival_food_source(
		fourth,
		100,
		10,
		32
	)
	_expect(
		int(fourth_match.get("source_id", -1)) <= 0,
		"Three fully reserved fish must not be promised to a fourth citizen."
	)
	_expect(
		WorldData.get_city_food_endpoint_unreserved_amount(
			int(fourth.get("id", -1)),
			CityLogisticsSystem.make_city_ground_pile_haul_endpoint(pile_id),
			WorldData.RESOURCE_FISH
		) == 0,
		"Food endpoint availability must subtract all competing one-item task reservations."
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

	var pile_result := CityLogisticsSystem.add_resource_to_city_ground_piles_with_result({
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
		int(survival_workplace_match.get("path_requests_used", 0)) == 1,
		"Critical survival matching must search all legal sources in one exact path request."
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
		CityNavigationSystemScript.get_city_wide_path_expansion_limit(
			large_city_world
		)
	)
	_expect(
		expansion_limit == 10_201 and expansion_limit > 10_000,
		"Exact food reachability must cover every city tile instead of stopping at 10,000 nodes."
	)


func _test_unified_food_search_avoids_budget_starvation() -> void:
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
		"The first hungry citizen must own the isolated pantry source."
	)
	_expect(
		WorldData.remove_city_citizen_home(second_id),
		"The later hungry citizen must have no private pantry source."
	)

	for food_object in [house, stockpile, keep, fishery]:
		_expect(
			WorldData.add_resource_to_city_object_storage(
				int(food_object.get("id", -1)),
				WorldData.RESOURCE_FISH,
				1
			) == 1,
			"Every isolated container source must contain one physical fish."
		)

	var pile_result := CityLogisticsSystem.add_resource_to_city_ground_piles_with_result({
		"tile_position": Vector2i(27, 15),
		"resource": WorldData.RESOURCE_FISH,
		"amount_delta": 2,
	})
	var pile_id := _first_ground_pile_id(pile_result)
	_expect(pile_id > 0, "The later citizen needs a reachable food pile.")

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
	var second_probe := CityResourceMatcherScript.find_best_survival_food_source(
		second,
		100,
		10,
		3
	)
	_expect(
		int(first_probe.get("source_id", -1)) <= 0
		and int(first_probe.get("path_requests_used", 0)) == 1,
		"All unreachable sources must be rejected in one complete path request."
	)
	_expect(
		str(second_probe.get("source_kind", ""))
		== WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE
		and int(second_probe.get("source_id", -1)) == pile_id
		and int(second_probe.get("path_requests_used", 0)) == 1,
		"A reachable later citizen must find ground food without tier-budget starvation."
	)

	CitizenDecisionSystemScript.reset_runtime_state()
	CitizenDecisionSystemScript._process_food_needs(true)
	var second_task := WorldData.get_city_citizen_current_task(second_id)
	_expect(
		str(WorldData.get_city_citizen_current_task(first_id).get("kind", ""))
		== WorldData.CITY_CITIZEN_TASK_KIND_NONE
		and str(second_task.get("kind", ""))
		== WorldData.CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD
		and int(second_task.get("target_object_id", -1)) == pile_id,
		"The shared critical-food budget must reach the later citizen in the same pass."
	)

	_expect(
		WorldData.clear_city_citizen_task(
			second_id,
			WorldData.CITY_CITIZEN_TASK_SOURCE_AUTONOMY
		),
		"The fixture must release the critical food reservation before normal seeking."
	)
	WorldData.set_city_citizen_hunger_state(first_id, 40, 0)
	WorldData.set_city_citizen_hunger_state(second_id, 40, 0)
	CitizenDecisionSystemScript._process_food_needs(false)
	second_task = WorldData.get_city_citizen_current_task(second_id)
	_expect(
		str(second_task.get("kind", ""))
		== WorldData.CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD
		and int(second_task.get("target_object_id", -1)) == pile_id,
		"The shared normal-food budget must also reach the later citizen immediately."
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
	var pile_result := CityLogisticsSystem.add_resource_to_city_ground_piles_with_result({
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


func _test_construction_labor_balance() -> void:
	var expected_building_minutes := {
		WorldData.CITY_OBJECT_HOUSE: 135,
		WorldData.CITY_OBJECT_STOCKPILE: 90,
		WorldData.CITY_OBJECT_FISHING_GROUNDS: 180,
	}

	for object_type in expected_building_minutes.keys():
		var definition := WorldData.get_city_object_definition(
			str(object_type)
		)
		_expect(
			int(definition.get("construction_labor_minutes", -1))
			== int(expected_building_minutes[object_type]),
			"Building hammer-and-nails labor must retain its faster balance value."
		)

	var road_definition := WorldData.get_city_object_definition(
		WorldData.CITY_OBJECT_ROAD
	)
	_expect(
		int(road_definition.get("construction_labor_minutes", -1)) == 8
		and road_definition.get("construction_materials", {}).is_empty()
		and int(road_definition.get("construction_max_workers", -1)) == 1
		and CityConstructionSystem.CITY_CONSTRUCTION_LABOR_ATOMIC_MINUTES == 30,
		"Roads must remain fast, labor-only, single-tile construction jobs without changing the scheduler boundary."
	)


func _test_safe_boundary_and_cancellation_preserve_physical_cargo() -> void:
	var city_world := _reset_fixture()
	var citizen := _add_citizen("Carrier", Vector2i(7, 7))
	var citizen_id := int(citizen.get("id", -1))
	var road_site := _create_material_blocked_site(
		Vector2i(9, 7),
		2
	)
	var site_id := int(road_site.get("id", -1))
	_expect(site_id > 0, "The cancellation fixture must create a road site.")

	if site_id <= 0:
		return

	var source_result := CityLogisticsSystem.add_resource_to_city_ground_piles_with_result({
		"tile_position": Vector2i(7, 7),
		"resource": WorldData.RESOURCE_STONE,
		"amount_delta": 2,
	})
	var source_id := _first_ground_pile_id(source_result)
	var source := CityLogisticsSystem.make_city_ground_pile_haul_endpoint(source_id)
	var site_endpoint := CityLogisticsSystem.make_city_construction_site_haul_endpoint(
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
			"priority": CityConstructionSystem.CITY_CONSTRUCTION_TASK_PRIORITY,
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
	var keep_endpoint := CityLogisticsSystem.make_city_citizen_haul_endpoint(
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
		CityLogisticsSystem.make_city_construction_site_haul_endpoint(site_id)
	)

	_expect(
		keep_id > 0
		and site_id > 0
		and str(house_site.get("phase", ""))
		== CityConstructionSystem.CITY_CONSTRUCTION_PHASE_GATHERING,
		"The cargo-routing fixture must create reachable storage and a gathering site."
	)

	if keep_id <= 0 or site_id <= 0:
		return

	var source_result := CityLogisticsSystem.add_resource_to_city_ground_piles_with_result({
		"tile_position": Vector2i(24, 10),
		"resource": WorldData.RESOURCE_STONE,
		"amount_delta": 4,
	})
	var source_id := _first_ground_pile_id(source_result)
	var source_endpoint := CityLogisticsSystem.make_city_ground_pile_haul_endpoint(
		source_id
	)
	var soft_task_assigned := WorldData.assign_city_citizen_task(
		claimant_id,
		{
			"kind": WorldData.CITY_CITIZEN_TASK_KIND_HAUL,
			"source": WorldData.CITY_CITIZEN_TASK_SOURCE_PLAYER,
			"priority": CityConstructionSystem.CITY_CONSTRUCTION_TASK_PRIORITY,
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
		CityLogisticsSystem.get_city_haul_reservation_id_for_citizen(
			claimant_id
		)
	)
	_expect(
		soft_task_assigned
		and CityLogisticsSystem.city_haul_reservation_is_soft(
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
	var final_reservation := CityLogisticsSystem.get_city_haul_reservation(
		CityLogisticsSystem.get_city_haul_reservation_id_for_citizen(
			carrier_id
		)
	)

	_expect(
		CityLogisticsSystem.city_citizen_haul_endpoints_match(
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
		CityLogisticsSystem.get_city_haul_reservation(
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


func _test_off_shift_homeless_idle_wander() -> void:
	var city_world := _reset_fixture()
	CitizenDecisionSystemScript.reset_runtime_state()
	var keep := WorldData.add_city_object({
		"object_type": WorldData.CITY_OBJECT_CITY_CENTER,
		"top_left": Vector2i(2, 2),
		"size_tiles": WorldData.get_city_object_size_for_type(
			WorldData.CITY_OBJECT_CITY_CENTER
		),
		"object_owner": "player",
		"city_world": city_world,
	})
	_expect(
		not keep.is_empty(),
		"The idle-wander fixture must create a civic anchor."
	)

	if keep.is_empty():
		return

	var starting_tile := Vector2i(26, 16)
	var citizen := _add_citizen("Off Shift Wanderer", starting_tile)
	var citizen_id := int(citizen.get("id", -1))
	var fishery := WorldData.add_city_object({
		"object_type": WorldData.CITY_OBJECT_FISHING_GROUNDS,
		"top_left": Vector2i(21, 14),
		"size_tiles": WorldData.get_city_object_size_for_type(
			WorldData.CITY_OBJECT_FISHING_GROUNDS
		),
		"object_owner": "player",
		"city_world": city_world,
	})
	var fishery_id := int(fishery.get("id", -1))
	_expect(
		fishery_id > 0
		and WorldData.assign_city_citizen_job(citizen_id, fishery_id),
		"The off-shift wanderer must retain a distant Fishery job."
	)
	_expect(
		int(citizen.get("home_object_id", -1)) < 0,
		"The off-shift wander fixture citizen must remain homeless."
	)
	var idle_anchor := CitizenDecisionSystemScript._get_idle_anchor_tile(
		citizen,
		starting_tile
	)
	_expect(
		idle_anchor == starting_tile,
		"A homeless citizen far from the Keep must receive a local idle anchor."
	)

	SimulationClock.start_new_game(1, 1, 0)
	var movement_was_assigned := false

	# Force only the decision deadline, not the deterministic choice. Repeated
	# choices include the intended brief standing periods before a short walk.
	for _attempt in range(12):
		CitizenDecisionSystemScript._next_idle_decision_minute_by_citizen_id[
			citizen_id
		] = SimulationClock.absolute_world_minutes
		CitizenDecisionSystemScript._process_bounded_idle_behaviors(false)
		citizen = WorldData.get_city_citizen_by_id(citizen_id)

		if (
			str(citizen.get("movement_state", ""))
			== WorldData.CITY_CITIZEN_MOVEMENT_STATE_MOVING
		):
			movement_was_assigned = true
			break

	_expect(
		movement_was_assigned,
		"A homeless off-shift citizen must eventually begin a short idle walk."
	)
	_expect(
		int(citizen.get("job_object_id", -1)) == fishery_id
		and str(
			WorldData.get_city_citizen_current_task(citizen_id).get(
				"kind",
				""
			)
		) == WorldData.CITY_CITIZEN_TASK_KIND_NONE
		and WorldData.get_city_citizen_haul_cargo_amount(citizen_id) == 0,
		"Idle wandering must preserve the Fishery job without creating a task or cargo."
	)

	if not movement_was_assigned:
		return

	var movement_path: Array = citizen.get("movement_path", [])
	var destination: Vector2i = movement_path.back()
	var destination_distance := (
		absi(destination.x - starting_tile.x)
		+ absi(destination.y - starting_tile.y)
	)
	_expect(
		movement_path.size() >= 2
		and movement_path.size()
		<= CitizenDecisionSystemScript.IDLE_MAXIMUM_PATH_STEPS + 1
		and destination_distance > 0
		and destination_distance
		<= CitizenDecisionSystemScript.IDLE_MAXIMUM_DESTINATION_DISTANCE,
		"Idle movement must remain a short local walk, not a replacement task."
	)

	SimulationClock.start_new_game(1, 8, 0)
	CitizenDecisionSystemScript._queue_all_eligible_scheduled_tasks(
		CitizenDecisionSystemScript.SCHEDULE_PHASE_WORK_SHIFT
	)
	CitizenDecisionSystemScript._process_decision_queue(
		CitizenDecisionSystemScript.SCHEDULE_PHASE_WORK_SHIFT
	)
	citizen = WorldData.get_city_citizen_by_id(citizen_id)
	_expect(
		str(
			WorldData.get_city_citizen_current_task(citizen_id).get(
				"kind",
				""
			)
		) == WorldData.CITY_CITIZEN_TASK_KIND_WORK
		and str(citizen.get("movement_state", ""))
		== WorldData.CITY_CITIZEN_MOVEMENT_STATE_IDLE,
		"The 08:00 work schedule must immediately replace idle movement."
	)


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
	var test_culture := WorldData.create_culture(
		"Work System Test Culture"
	)
	test_culture_id = int(test_culture.get("id", -1))
	return city_world


func _add_citizen(_display_name: String, tile_position: Vector2i) -> Dictionary:
	# An empty name requests the normal deterministic sex-specific pool entry.
	return WorldData.add_city_citizen(
		"",
		tile_position,
		WorldData.CITY_CITIZEN_SEX_FEMALE,
		test_culture_id
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


func _create_material_blocked_site(
	tile_position: Vector2i,
	stone_amount: int
) -> Dictionary:
	var site := CityConstructionSystemScript.create_city_construction_site({
		"target_kind": CityConstructionSystem.CITY_CONSTRUCTION_TARGET_NEW,
		"object_type": WorldData.CITY_OBJECT_ROAD,
		"shape_mode": WorldData.CITY_OBJECT_SHAPE_TILE_AREA,
		"top_left": tile_position,
		"size": Vector2i.ONE,
		"footprint_tiles": [tile_position],
		"owner": "player",
		"material_recipe": {
			WorldData.RESOURCE_STONE: maxi(stone_amount, 1),
		},
		"required_labor_minutes": 8,
		"maximum_workers": 1,
		"work_positions": [tile_position],
	})
	var site_id := int(site.get("id", -1))

	if site_id <= 0:
		return {}

	CityConstructionSystemScript.refresh_city_construction_site(site_id)
	return CityConstructionSystem.get_city_construction_site_by_id(site_id)


func _create_ready_labor_site(
	footprint_tiles: Array,
	maximum_workers: int
) -> Dictionary:
	if footprint_tiles.is_empty():
		return {}

	var top_left: Vector2i = footprint_tiles[0]
	var bottom_right: Vector2i = footprint_tiles[0]

	for tile_position in footprint_tiles:
		top_left.x = mini(top_left.x, tile_position.x)
		top_left.y = mini(top_left.y, tile_position.y)
		bottom_right.x = maxi(bottom_right.x, tile_position.x)
		bottom_right.y = maxi(bottom_right.y, tile_position.y)

	var site := CityConstructionSystemScript.create_city_construction_site({
		"target_kind": CityConstructionSystem.CITY_CONSTRUCTION_TARGET_NEW,
		"object_type": WorldData.CITY_OBJECT_ROAD,
		"shape_mode": WorldData.CITY_OBJECT_SHAPE_TILE_AREA,
		"top_left": top_left,
		"size": bottom_right - top_left + Vector2i.ONE,
		"footprint_tiles": footprint_tiles,
		"owner": "player",
		"material_recipe": {},
		"required_labor_minutes": 600,
		"maximum_workers": maximum_workers,
		"work_positions": footprint_tiles,
	})
	var site_id := int(site.get("id", -1))

	if site_id <= 0:
		return {}

	CityConstructionSystemScript.refresh_city_construction_site(site_id)
	return CityConstructionSystem.get_city_construction_site_by_id(site_id)


func _get_assignment_snapshot(citizen_id: int) -> Dictionary:
	var citizen := WorldData.get_city_citizen_by_id(citizen_id)

	return {
		"task": WorldData.get_city_citizen_current_task(citizen_id),
		"haul": WorldData.get_city_citizen_current_haul(citizen_id),
		"cargo": WorldData.get_city_citizen_haul_cargo(citizen_id),
		"movement_state": str(citizen.get("movement_state", "")),
		"movement_path": citizen.get("movement_path", []).duplicate(),
		"movement_path_index": int(citizen.get("movement_path_index", 0)),
		"movement_destination_tile": citizen.get(
			"movement_destination_tile",
			WorldData.INVALID_CITY_TILE_POSITION
		),
	}


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
