extends Node

const CITY_SCENE := preload("res://scenes/CityScreen.tscn")
const CityStateValidatorScript = preload(
	"res://scripts/city/simulation/CityStateValidator.gd"
)
const CityConstructionSystemScript = preload(
	"res://scripts/city/simulation/systems/CityConstructionSystem.gd"
)
const CityNavigationSystemScript = preload(
	"res://scripts/city/simulation/systems/CityNavigationSystem.gd"
)

const TEST_DAYS: int = 3
const TEST_MINUTES_PER_TICK: int = 120
const VALIDATION_INTERVAL_TICKS: int = 2
const CRITICAL_HUNGER_GRACE_MINUTES: int = 360
const WORKPLACE_FISH_FIXTURE_AMOUNT: int = 48
const MAX_FIXTURE_DETOUR_TILES: int = 32

var failure_count: int = 0
var validation_count: int = 0
var critical_hunger_minutes_by_citizen_id: Dictionary = {}
var reported_stuck_hunger_citizen_ids: Dictionary = {}
var maximum_observed_hunger_by_citizen_id: Dictionary = {}
var relocation_completed_world_minute: int = -1


func _ready() -> void:
	await _run_long_run_test()

	if failure_count > 0:
		push_error(
			"Unified long-run simulation test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print(
		"Unified long-run simulation test passed: ",
		TEST_DAYS,
		" days, ",
		validation_count,
		" forced validations, relocation minute ",
		relocation_completed_world_minute,
		"."
	)
	get_tree().quit(0)


func _run_long_run_test() -> void:
	_prepare_dev_city_region()

	var renderer := CITY_SCENE.instantiate() as CityRenderer
	_expect(renderer != null, "The City scene must instantiate a CityRenderer.")

	if renderer == null:
		return

	add_child(renderer)
	SimulationClock.set_simulation_paused(true)
	await get_tree().process_frame
	await get_tree().process_frame

	_expect(renderer.city_world != null, "The test city world must generate.")

	if renderer.city_world == null:
		renderer.queue_free()
		return

	var fixture := _create_mixed_work_fixture(renderer)

	if fixture.is_empty():
		renderer.queue_free()
		await get_tree().process_frame
		WorldData.reset_runtime_session_state()
		return

	var initial_validation := CityStateValidatorScript.validate(true, false)
	_record_validation(initial_validation, 0)
	var initial_totals := _capture_physical_resource_totals()
	fixture["initial_physical_totals"] = initial_totals
	fixture["initial_fish_total"] = int(
		initial_totals.get(WorldData.RESOURCE_FISH, 0)
	)

	SimulationClock.set_tick_configuration(
		TEST_MINUTES_PER_TICK,
		0.001
	)

	var total_ticks := int(
		(TEST_DAYS * SimulationClock.MINUTES_PER_DAY)
		/ TEST_MINUTES_PER_TICK
	)

	for tick_number in range(1, total_ticks + 1):
		SimulationClock.advance_one_simulation_tick()
		_update_food_liveness(fixture)
		_observe_relocation(fixture)

		if tick_number % VALIDATION_INTERVAL_TICKS == 0:
			var elapsed_minutes := tick_number * TEST_MINUTES_PER_TICK
			var validation := CityStateValidatorScript.validate(true, false)
			_record_validation(validation, elapsed_minutes)
			_check_nonnegative_state(elapsed_minutes)

	var final_validation := CityStateValidatorScript.validate(true, false)
	_record_validation(
		final_validation,
		TEST_DAYS * SimulationClock.MINUTES_PER_DAY
	)
	_check_nonnegative_state(
		TEST_DAYS * SimulationClock.MINUTES_PER_DAY
	)
	_assert_long_run_outcomes(fixture)

	renderer.queue_free()
	await get_tree().process_frame
	WorldData.reset_runtime_session_state()

	for _frame_index in range(4):
		await get_tree().process_frame


func _prepare_dev_city_region() -> void:
	DevCityLauncher.reset_dev_city_state()

	var generator := WorldGenerator.new()
	var dev_world := generator.generate_world(
		DevCityLauncher.DEV_WORLD_SEED
	)
	var region_top_left := DevCityLauncher.find_good_dev_region(
		dev_world,
		DevCityLauncher.DEV_REGION_SIZE
	)
	var region_center := region_top_left + Vector2i(
		int(DevCityLauncher.DEV_REGION_SIZE / 2),
		int(DevCityLauncher.DEV_REGION_SIZE / 2)
	)

	_expect(
		region_top_left != WorldData.INVALID_CITY_TILE_POSITION,
		"A deterministic dev-city region must be available."
	)

	if region_top_left == WorldData.INVALID_CITY_TILE_POSITION:
		return

	SimulationClock.start_new_game()
	SimulationCoordinator.reset_performance_statistics()
	var world_lock_succeeded := WorldData.lock_world_save({
		"source_world": dev_world,
		"region_top_left": region_top_left,
		"region_center": region_center,
		"region_size": DevCityLauncher.DEV_REGION_SIZE,
		"world_scene_path": "res://scenes/MainMenu.tscn",
		"city_scene_path": "res://scenes/CityScreen.tscn",
		"city_name": "Long Run City",
		"culture_name": "Long Run Culture",
	})
	_expect(
		world_lock_succeeded,
		"The long-run world and founding identity must lock."
	)


func _create_mixed_work_fixture(renderer: CityRenderer) -> Dictionary:
	var city_world: WorldData = renderer.city_world
	var keep_size := WorldData.get_city_object_size_for_type(
		WorldData.CITY_OBJECT_CITY_CENTER
	)
	var keep_top_left := _find_placeable_rectangle(
		city_world,
		keep_size,
		WorldData.CITY_OBJECT_CITY_CENTER
	)

	_expect(
		keep_top_left != WorldData.INVALID_CITY_TILE_POSITION,
		"The long-run fixture requires a placeable City Keep."
	)

	if keep_top_left == WorldData.INVALID_CITY_TILE_POSITION:
		return {}

	var keep := CityObjectSystem.add_city_object({
		"object_type": WorldData.CITY_OBJECT_CITY_CENTER,
		"top_left": keep_top_left,
		"size_tiles": keep_size,
		"object_owner": "player",
		"city_world": city_world,
	})
	renderer.after_city_center_placed(keep)

	_expect(
		WorldData.get_city_population_count()
		== WorldData.STARTING_CITY_POPULATION,
		"Founding must create the complete starting population."
	)

	if WorldData.city_citizens.is_empty():
		return {}

	var citizen_id := int(WorldData.city_citizens[0].get("id", -1))
	var citizen := WorldData.get_city_citizen_by_id(citizen_id)
	var citizen_tile: Vector2i = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	var fishery_size := WorldData.get_city_object_size_for_type(
		WorldData.CITY_OBJECT_FISHING_GROUNDS
	)
	var fishery_top_left := _find_and_prepare_reachable_rectangle(
		city_world,
		fishery_size,
		WorldData.CITY_OBJECT_FISHING_GROUNDS,
		citizen_id,
		false
	)

	_expect(
		fishery_top_left != WorldData.INVALID_CITY_TILE_POSITION,
		"The fixture requires a reachable Fishing Grounds."
	)

	if fishery_top_left == WorldData.INVALID_CITY_TILE_POSITION:
		return {}

	var fishery_footprint := (
		CityObjectSystem.make_rectangle_city_object_footprint_tiles(
			fishery_top_left,
			fishery_size
		)
	)
	_prepare_fixture_access_for_all_citizens(
		city_world,
		fishery_footprint
	)

	var fishery := CityObjectSystem.add_city_object({
		"object_type": WorldData.CITY_OBJECT_FISHING_GROUNDS,
		"top_left": fishery_top_left,
		"size_tiles": fishery_size,
		"object_owner": "player",
		"city_world": city_world,
	})
	var fishery_id := int(fishery.get("id", -1))
	var accepted_fish := CityResourceContainerSystem.add_resource_to_city_object_storage(
		fishery_id,
		WorldData.RESOURCE_FISH,
		WORKPLACE_FISH_FIXTURE_AMOUNT
	)
	_expect(
		accepted_fish == WORKPLACE_FISH_FIXTURE_AMOUNT,
		"The non-public workplace must hold the fallback fish supply."
	)

	var fishery_access_tiles := WorldData.get_city_object_access_tiles(
		city_world,
		fishery
	)
	_expect(
		_all_citizens_can_reach_tiles(fishery_access_tiles),
		"Every starting citizen must be able to reach workplace fish."
	)

	var keep_id := int(keep.get("id", -1))
	var keep_capacity := CityResourceContainerSystem.get_city_object_storage_capacity(keep)
	var accepted_coal := CityResourceContainerSystem.add_resource_to_city_object_storage(
		keep_id,
		WorldData.RESOURCE_COAL,
		keep_capacity
	)
	_expect(
		accepted_coal == keep_capacity
		and CityResourceContainerSystem.get_city_object_storage_free_space(keep) == 0,
		"The public Keep must be completely full for relocation fallback."
	)

	for raw_citizen in WorldData.city_citizens:
		if not raw_citizen is Dictionary:
			continue

		var current_citizen: Dictionary = raw_citizen
		var current_citizen_id := int(current_citizen.get("id", -1))
		WorldData.set_city_citizen_hunger_state(
			current_citizen_id,
			45,
			0
		)
		critical_hunger_minutes_by_citizen_id[
			current_citizen_id
		] = 0
		maximum_observed_hunger_by_citizen_id[
			current_citizen_id
		] = 45

	var house_size := WorldData.get_city_object_size_for_type(
		WorldData.CITY_OBJECT_HOUSE
	)
	var house_top_left := _find_and_prepare_reachable_rectangle(
		city_world,
		house_size,
		WorldData.CITY_OBJECT_HOUSE,
		citizen_id,
		true
	)

	_expect(
		house_top_left != WorldData.INVALID_CITY_TILE_POSITION,
		"The fixture requires a reachable House construction footprint."
	)

	if house_top_left == WorldData.INVALID_CITY_TILE_POSITION:
		return {}

	var footprint_tiles := (
		CityObjectSystem.make_rectangle_city_object_footprint_tiles(
			house_top_left,
			house_size
		)
	)
	var tree_tile: Vector2i = footprint_tiles[0]
	var rock_tile: Vector2i = footprint_tiles[1]
	var cleanup_tile: Vector2i = footprint_tiles[2]
	_set_surface_feature(
		city_world,
		tree_tile,
		WorldData.CITY_SURFACE_FEATURE_TREE
	)
	_set_surface_feature(
		city_world,
		rock_tile,
		WorldData.CITY_SURFACE_FEATURE_ROCK
	)

	var house_site := CityConstructionSystemScript.create_rectangular_site({
		"object_type": WorldData.CITY_OBJECT_HOUSE,
		"top_left": house_top_left,
		"size_tiles": house_size,
		"object_owner": "player",
		"city_world": city_world,
	})
	var house_site_id := int(house_site.get("id", -1))
	_expect(house_site_id > 0, "The House blueprint must be created.")

	if house_site_id <= 0:
		return {}

	var cleanup_result := (
		CityLogisticsSystem.add_resource_to_city_ground_piles_with_result({
			"tile_position": cleanup_tile,
			"resource": WorldData.RESOURCE_COAL,
			"amount_delta": 1,
		})
	)
	_expect(
		int(cleanup_result.get("added_amount", 0)) == 1,
		"An ordinary coal pile must be added inside the blueprint."
	)

	var open_relocation_tile := _find_open_ground_tile_outside_footprint(
		city_world,
		footprint_tiles,
		cleanup_tile,
		citizen_id
	)
	_expect(
		open_relocation_tile != WorldData.INVALID_CITY_TILE_POSITION,
		"Open reachable ground must exist outside the blueprint."
	)

	var lumber_source_tile := _find_open_ground_tile_outside_footprint(
		city_world,
		footprint_tiles + [open_relocation_tile],
		cleanup_tile,
		citizen_id
	)
	_expect(
		lumber_source_tile != WorldData.INVALID_CITY_TILE_POSITION,
		"A reachable source tile must exist for construction lumber."
	)

	var lumber_result := CityLogisticsSystem.add_resource_to_city_ground_piles_with_result({
		"tile_position": lumber_source_tile,
		"resource": WorldData.RESOURCE_LUMBER,
		"amount_delta": 4,
	})
	_expect(
		int(lumber_result.get("added_amount", 0)) == 4,
		"The construction fixture must seed deliverable lumber outside the site."
	)

	var natural_command_ids: Array[int] = []
	var natural_exclusions: Array = footprint_tiles.duplicate()
	natural_exclusions.append(open_relocation_tile)
	natural_exclusions.append(lumber_source_tile)
	var tree_targets := _prepare_deterministic_natural_targets(
		CityWorkSystem.CITY_PLAYER_COMMAND_TYPE_CHOP_TREE,
		citizen_tile,
		natural_exclusions,
		3
	)
	for tree_target in tree_targets:
		natural_exclusions.append(tree_target)
	var rock_targets := _prepare_deterministic_natural_targets(
		CityWorkSystem.CITY_PLAYER_COMMAND_TYPE_COLLECT_ROCK,
		citizen_tile,
		natural_exclusions,
		3
	)
	var added_trees := CityWorkSystem.add_city_player_command_targets(
		CityWorkSystem.CITY_PLAYER_COMMAND_TYPE_CHOP_TREE,
		tree_targets
	)
	var added_rocks := CityWorkSystem.add_city_player_command_targets(
		CityWorkSystem.CITY_PLAYER_COMMAND_TYPE_COLLECT_ROCK,
		rock_targets
	)
	_expect(
		added_trees >= 2 and added_rocks >= 2,
		"At least two independent tree and rock jobs must be designated."
	)

	for command in CityWorkSystem.get_city_player_command_snapshot():
		if not command is Dictionary:
			continue

		if int(command.get("construction_site_id", -1)) < 0:
			natural_command_ids.append(int(command.get("id", -1)))

	var command_expectations: Dictionary = {}

	for command in CityWorkSystem.get_city_player_command_snapshot():
		if not command is Dictionary:
			continue

		var command_id := int(command.get("id", -1))
		var command_type := str(command.get("type", ""))
		command_expectations[command_id] = {
			"resource": CityWorkSystem.get_city_player_command_resource_type(
				command_type
			),
			"yield": int(command.get("resource_yield", 0)),
		}

	var material_recipe: Dictionary = house_site.get(
		"material_recipe",
		{}
	).duplicate(true)

	return {
		"keep_id": keep_id,
		"fishery_id": fishery_id,
		"fishery_access_tiles": fishery_access_tiles,
		"house_site_id": house_site_id,
		"house_top_left": house_top_left,
		"footprint_tiles": footprint_tiles,
		"cleanup_tile": cleanup_tile,
		"open_relocation_tile": open_relocation_tile,
		"lumber_source_tile": lumber_source_tile,
		"natural_command_ids": natural_command_ids,
		"command_expectations": command_expectations,
		"construction_material_recipe": material_recipe,
	}


func _update_food_liveness(fixture: Dictionary) -> void:
	var fishery_id := int(fixture.get("fishery_id", -1))
	var fishery := CityObjectSystem.get_city_object_by_id(fishery_id)
	var fish_available := CityResourceContainerSystem.get_city_object_stored_resource_amount(
		fishery,
		WorldData.RESOURCE_FISH
	) > 0
	var fishery_access_tiles: Array = fixture.get(
		"fishery_access_tiles",
		[]
	)

	for raw_citizen in WorldData.city_citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var citizen_id := int(citizen.get("id", -1))
		var hunger := WorldData.get_city_citizen_hunger(citizen_id)
		maximum_observed_hunger_by_citizen_id[citizen_id] = maxi(
			int(maximum_observed_hunger_by_citizen_id.get(citizen_id, hunger)),
			hunger
		)

		var fish_reachable := false

		if fish_available and hunger <= WorldData.CITIZEN_CRITICAL_FOOD_SEEK_TRIGGER_HUNGER:
			fish_reachable = _citizen_can_reach_tiles(
				citizen_id,
				fishery_access_tiles
			)

		if fish_reachable:
			var critical_minutes := int(
				critical_hunger_minutes_by_citizen_id.get(citizen_id, 0)
			) + TEST_MINUTES_PER_TICK
			critical_hunger_minutes_by_citizen_id[citizen_id] = critical_minutes

			if (
				critical_minutes > CRITICAL_HUNGER_GRACE_MINUTES
				and not reported_stuck_hunger_citizen_ids.has(citizen_id)
			):
				reported_stuck_hunger_citizen_ids[citizen_id] = true
				_expect(
					false,
					"Citizen " + str(citizen_id)
					+ " remained critically hungry for more than "
					+ str(CRITICAL_HUNGER_GRACE_MINUTES)
					+ " minutes despite reachable workplace fish."
				)
		else:
			critical_hunger_minutes_by_citizen_id[citizen_id] = 0


func _observe_relocation(fixture: Dictionary) -> void:
	if relocation_completed_world_minute >= 0:
		return

	if not _ordinary_resource_exists_inside_footprint(
		fixture.get("footprint_tiles", []),
		WorldData.RESOURCE_COAL
	):
		relocation_completed_world_minute = (
			SimulationClock.absolute_world_minutes
		)


func _record_validation(validation: Dictionary, elapsed_minutes: int) -> void:
	validation_count += 1

	if bool(validation.get("valid", false)):
		return

	_expect(
		false,
		"CityStateValidator failed after "
		+ str(elapsed_minutes)
		+ " simulated minutes."
	)

	for raw_error in validation.get("errors", []):
		push_error("Long-run validator: " + str(raw_error))


func _check_nonnegative_state(elapsed_minutes: int) -> void:
	for resource in WorldData.get_city_resource_types():
		_expect(
			WorldData.get_total_physical_city_resource_amount(resource) >= 0,
			"Physical " + resource + " became negative after "
			+ str(elapsed_minutes) + " minutes."
		)

	for raw_citizen in WorldData.city_citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var citizen_id := int(citizen.get("id", -1))
		var hunger := WorldData.get_city_citizen_hunger(citizen_id)
		_expect(
			hunger >= 0 and hunger <= WorldData.MAX_CITIZEN_HUNGER,
			"Citizen " + str(citizen_id)
			+ " has invalid hunger after " + str(elapsed_minutes)
			+ " minutes."
		)

		for resource in WorldData.get_city_resource_types():
			_expect(
				WorldData.get_city_citizen_inventory_resource_amount(
					citizen_id,
					resource
				) >= 0,
				"Citizen " + str(citizen_id)
				+ " has negative inventory resource " + resource + "."
			)


func _assert_long_run_outcomes(fixture: Dictionary) -> void:
	var site_id := int(fixture.get("house_site_id", -1))
	var site_completed := CityConstructionSystem.get_city_construction_site_by_id(
		site_id
	).is_empty()
	_expect(
		site_completed,
		"The supplied House construction order must complete within three days."
	)
	_expect(
		str(
			CityObjectSystem.get_city_object_at_tile(
				fixture.get(
					"house_top_left",
					WorldData.INVALID_CITY_TILE_POSITION
				)
			).get("type", "")
		) == WorldData.CITY_OBJECT_HOUSE,
		"Completed construction must leave an operational House."
	)

	_expect(
		not _ordinary_resource_exists_inside_footprint(
			fixture.get("footprint_tiles", []),
			WorldData.RESOURCE_COAL
		),
		"Ordinary footprint cargo must not remain permanently blocked when "
		+ "reachable open ground exists."
	)
	_expect(
		relocation_completed_world_minute >= 0,
		"The test must observe footprint-pile relocation."
	)

	for raw_command_id in fixture.get("natural_command_ids", []):
		var command_id := int(raw_command_id)
		_expect(
			CityWorkSystem.get_city_player_command_by_id(command_id).is_empty(),
			"Natural command " + str(command_id)
			+ " must not starve behind construction work."
		)

	_assert_material_conservation(fixture, site_completed)

	var initial_fish_total := int(fixture.get("initial_fish_total", 0))
	var final_fish_total := WorldData.get_total_physical_city_resource_amount(
		WorldData.RESOURCE_FISH
	)
	var consumed_fish := initial_fish_total - final_fish_total
	_expect(
		consumed_fish > 0 and consumed_fish <= initial_fish_total,
		"The workplace-fallback fish delta must be positive, bounded food "
		+ "consumption."
	)

	for raw_citizen in WorldData.city_citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen_id := int(raw_citizen.get("id", -1))
		_expect(
			int(maximum_observed_hunger_by_citizen_id.get(citizen_id, 0)) > 45,
			"Citizen " + str(citizen_id)
			+ " must successfully eat from the non-public workplace fallback."
		)


func _assert_material_conservation(
	fixture: Dictionary,
	site_completed: bool
) -> void:
	var initial_totals: Dictionary = fixture.get(
		"initial_physical_totals",
		{}
	)
	var command_expectations: Dictionary = fixture.get(
		"command_expectations",
		{}
	)
	var recipe: Dictionary = fixture.get(
		"construction_material_recipe",
		{}
	)

	for resource in [
		WorldData.RESOURCE_LUMBER,
		WorldData.RESOURCE_STONE,
		WorldData.RESOURCE_COAL,
	]:
		var expected_total := int(initial_totals.get(resource, 0))

		for raw_command_id in command_expectations.keys():
			var command_id := int(raw_command_id)
			var expectation: Dictionary = command_expectations[raw_command_id]

			if (
				str(expectation.get("resource", "")) == resource
				and CityWorkSystem.get_city_player_command_by_id(command_id).is_empty()
			):
				expected_total += int(expectation.get("yield", 0))

		if site_completed:
			expected_total -= int(recipe.get(resource, 0))

		var actual_total := WorldData.get_total_physical_city_resource_amount(
			resource
		)
		_expect(
			actual_total == expected_total,
			"Physical " + resource + " must conserve exactly: expected "
			+ str(expected_total) + ", got " + str(actual_total) + "."
		)


func _capture_physical_resource_totals() -> Dictionary:
	var totals: Dictionary = {}

	for resource in WorldData.get_city_resource_types():
		totals[resource] = WorldData.get_total_physical_city_resource_amount(
			resource
		)

	return totals


func _ordinary_resource_exists_inside_footprint(
	raw_footprint_tiles: Array,
	resource: String
) -> bool:
	for raw_pile in CityLogisticsSystem.get_city_ground_pile_snapshot():
		if not raw_pile is Dictionary:
			continue

		var pile: Dictionary = raw_pile

		if (
			str(pile.get("resource_type", "")) == resource
			and int(pile.get("construction_site_id", -1)) < 0
			and raw_footprint_tiles.has(
				pile.get(
					"tile_position",
					WorldData.INVALID_CITY_TILE_POSITION
				)
			)
		):
			return true

	return false


func _all_citizens_can_reach_tiles(destination_tiles: Array) -> bool:
	for raw_citizen in WorldData.city_citizens:
		if not raw_citizen is Dictionary:
			continue

		if not _citizen_can_reach_tiles(
			int(raw_citizen.get("id", -1)),
			destination_tiles
		):
			return false

	return true


func _citizen_can_reach_tiles(
	citizen_id: int,
	destination_tiles: Array
) -> bool:
	var citizen := WorldData.get_city_citizen_by_id(citizen_id)
	var raw_tile = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if not raw_tile is Vector2i:
		return false

	var city_world: WorldData = WorldData.official_city_world
	var path_result := CityNavigationSystemScript.find_path_to_any_city_tile({
		"city_world": city_world,
		"start_tile": raw_tile,
		"destination_tiles": destination_tiles,
		"max_expanded_nodes": maxi(city_world.width * city_world.height, 1),
		"citizen_id": citizen_id,
		"heuristic_weight": 1,
	})
	return bool(path_result.get("success", false))


func _prepare_fixture_access_for_all_citizens(
	city_world: WorldData,
	footprint_tiles: Array
) -> void:
	for raw_citizen in WorldData.city_citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen_id := int(raw_citizen.get("id", -1))
		var raw_start_tile = raw_citizen.get(
			"city_tile_position",
			WorldData.INVALID_CITY_TILE_POSITION
		)

		if not raw_start_tile is Vector2i:
			continue

		var access_target := _select_external_access_target(
			city_world,
			footprint_tiles,
			raw_start_tile
		)

		if access_target == WorldData.INVALID_CITY_TILE_POSITION:
			continue

		var corridor := _find_clear_fixture_corridor(
			city_world,
			raw_start_tile,
			access_target
		)

		if corridor.is_empty():
			continue

		for corridor_tile in corridor:
			var tile := city_world.get_tile(corridor_tile.x, corridor_tile.y)
			tile["terrain"] = WorldData.TERRAIN_LAND
			tile["is_land"] = true
			_set_surface_feature(
				city_world,
				corridor_tile,
				WorldData.CITY_SURFACE_FEATURE_NONE
			)

	city_world.mark_tile_data_changed()


func _prepare_deterministic_natural_targets(
	command_type: String,
	start_tile: Vector2i,
	excluded_tiles: Array,
	maximum_count: int
) -> Array[Vector2i]:
	var results: Array[Vector2i] = []
	var city_world: WorldData = WorldData.official_city_world
	var feature := WorldData.CITY_SURFACE_FEATURE_TREE

	if command_type == CityWorkSystem.CITY_PLAYER_COMMAND_TYPE_COLLECT_ROCK:
		feature = WorldData.CITY_SURFACE_FEATURE_ROCK

	for radius in range(2, maxi(city_world.width, city_world.height) + 1):
		for offset_y in range(-radius, radius + 1):
			for offset_x in range(-radius, radius + 1):
				if maxi(absi(offset_x), absi(offset_y)) != radius:
					continue

				var tile_position := start_tile + Vector2i(offset_x, offset_y)

				if (
					not city_world.is_in_bounds(tile_position.x, tile_position.y)
					or excluded_tiles.has(tile_position)
					or not CityObjectSystem.get_city_object_at_tile(tile_position).is_empty()
					or not CityConstructionSystem.get_city_construction_site_at_tile(
						tile_position
					).is_empty()
					or CityLogisticsSystem.has_city_ground_pile_at_tile(tile_position)
					or WorldData.has_living_city_citizen_at_tile(tile_position)
				):
					continue

				var tile := city_world.get_tile(tile_position.x, tile_position.y)
				tile["terrain"] = WorldData.TERRAIN_LAND
				tile["is_land"] = true
				_set_surface_feature(city_world, tile_position, feature)
				city_world.mark_tile_data_changed()

				if not CityWorkSystem.can_designate_city_player_command_at_tile(
					command_type,
					tile_position
				):
					continue

				var work_tiles := CityWorkSystem.get_city_player_command_work_tiles({
					"tile_position": tile_position,
				}, -1)
				var path_result := CityNavigationSystemScript.find_path_to_any_city_tile({
					"city_world": city_world,
					"start_tile": start_tile,
					"destination_tiles": work_tiles,
					"max_expanded_nodes": maxi(city_world.width * city_world.height, 1),
					"citizen_id": -1,
					"heuristic_weight": 1,
				})

				if not bool(path_result.get("success", false)):
					continue

				results.append(tile_position)

				if results.size() >= maximum_count:
					return results

	return results


func _find_open_ground_tile_outside_footprint(
	city_world: WorldData,
	footprint_tiles: Array,
	start_tile: Vector2i,
	citizen_id: int
) -> Vector2i:
	for radius in range(1, maxi(city_world.width, city_world.height) + 1):
		for offset_y in range(-radius, radius + 1):
			for offset_x in range(-radius, radius + 1):
				if maxi(absi(offset_x), absi(offset_y)) != radius:
					continue

				var tile_position := start_tile + Vector2i(offset_x, offset_y)

				if (
					footprint_tiles.has(tile_position)
					or not CityLogisticsSystem.can_city_ground_pile_exist_at_tile(
						city_world,
						tile_position
					)
				):
					continue

				var path_result := (
					CityNavigationSystemScript.find_path_to_any_city_tile({
						"city_world": city_world,
						"start_tile": start_tile,
						"destination_tiles": [tile_position],
						"max_expanded_nodes": maxi(city_world.width * city_world.height, 1),
						"citizen_id": citizen_id,
						"heuristic_weight": 1,
					})
				)

				if bool(path_result.get("success", false)):
					return tile_position

	return WorldData.INVALID_CITY_TILE_POSITION


func _find_and_prepare_reachable_rectangle(
	city_world: WorldData,
	size_tiles: Vector2i,
	object_type: String,
	citizen_id: int,
	for_construction: bool
) -> Vector2i:
	var citizen := WorldData.get_city_citizen_by_id(citizen_id)
	var raw_citizen_tile = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if not raw_citizen_tile is Vector2i:
		return WorldData.INVALID_CITY_TILE_POSITION

	var citizen_tile: Vector2i = raw_citizen_tile

	for radius in range(maxi(city_world.width, city_world.height) + 1):
		for offset_y in range(-radius, radius + 1):
			for offset_x in range(-radius, radius + 1):
				if (
					radius > 0
					and maxi(absi(offset_x), absi(offset_y)) != radius
				):
					continue

				var top_left := citizen_tile + Vector2i(offset_x, offset_y)

				if (
					not city_world.is_in_bounds(top_left.x, top_left.y)
					or not city_world.is_in_bounds(
						top_left.x + size_tiles.x - 1,
						top_left.y + size_tiles.y - 1
					)
				):
					continue

				var footprint_tiles := (
					CityObjectSystem.make_rectangle_city_object_footprint_tiles(
						top_left,
						size_tiles
					)
				)

				if not _footprint_is_unoccupied(footprint_tiles):
					continue

				var access_target := _select_external_access_target(
					city_world,
					footprint_tiles,
					citizen_tile
				)

				if access_target == WorldData.INVALID_CITY_TILE_POSITION:
					continue

				var corridor_tiles := _make_cardinal_fixture_path(
					citizen_tile,
					access_target,
					true
				)

				if not _fixture_path_is_clear(corridor_tiles):
					corridor_tiles = _make_cardinal_fixture_path(
						citizen_tile,
						access_target,
						false
					)

				if not _fixture_path_is_clear(corridor_tiles):
					continue

				var prepared_tiles: Array = footprint_tiles.duplicate()

				for corridor_tile in corridor_tiles:
					if not prepared_tiles.has(corridor_tile):
						prepared_tiles.append(corridor_tile)

				for raw_prepared_tile in prepared_tiles:
					if not raw_prepared_tile is Vector2i:
						continue

					var prepared_tile: Vector2i = raw_prepared_tile
					var tile := city_world.get_tile(
						prepared_tile.x,
						prepared_tile.y
					)
					tile["terrain"] = WorldData.TERRAIN_LAND
					tile["is_land"] = true
					_set_surface_feature(
						city_world,
						prepared_tile,
						WorldData.CITY_SURFACE_FEATURE_NONE
					)

				city_world.mark_tile_data_changed()

				var access_tiles := _make_external_boundary_tiles(
					city_world,
					footprint_tiles
				)
				var path_result := (
					CityNavigationSystemScript.find_path_to_any_city_tile({
						"city_world": city_world,
						"start_tile": citizen_tile,
						"destination_tiles": access_tiles,
						"max_expanded_nodes": maxi(city_world.width * city_world.height, 1),
						"citizen_id": citizen_id,
						"heuristic_weight": 1,
					})
				)

				if not bool(path_result.get("success", false)):
					continue

				var can_place := CityObjectSystem.can_place_city_object(
					city_world,
					top_left,
					size_tiles,
					object_type
				)

				if for_construction:
					can_place = CityConstructionSystem.can_place_city_object_construction(
						city_world,
						top_left,
						size_tiles,
						object_type
					)

				if can_place:
					return top_left

	return WorldData.INVALID_CITY_TILE_POSITION


func _select_external_access_target(
	city_world: WorldData,
	footprint_tiles: Array,
	start_tile: Vector2i
) -> Vector2i:
	var footprint_lookup: Dictionary = {}
	var candidates: Array[Vector2i] = []

	for raw_tile in footprint_tiles:
		if raw_tile is Vector2i:
			footprint_lookup[raw_tile] = true

	for raw_tile in footprint_tiles:
		if not raw_tile is Vector2i:
			continue

		for offset in [
			Vector2i.UP,
			Vector2i.LEFT,
			Vector2i.RIGHT,
			Vector2i.DOWN,
		]:
			var candidate: Vector2i = raw_tile + offset

			if (
				footprint_lookup.has(candidate)
				or candidates.has(candidate)
				or not city_world.is_in_bounds(candidate.x, candidate.y)
				or not CityObjectSystem.get_city_object_at_tile(candidate).is_empty()
				or not CityConstructionSystem.get_city_construction_site_at_tile(
					candidate
				).is_empty()
				or CityLogisticsSystem.has_city_ground_pile_at_tile(candidate)
			):
				continue

			candidates.append(candidate)

	if candidates.is_empty():
		return WorldData.INVALID_CITY_TILE_POSITION

	candidates.sort_custom(func(tile_a: Vector2i, tile_b: Vector2i) -> bool:
		var distance_a := start_tile.distance_squared_to(tile_a)
		var distance_b := start_tile.distance_squared_to(tile_b)

		if distance_a == distance_b:
			if tile_a.y == tile_b.y:
				return tile_a.x < tile_b.x

			return tile_a.y < tile_b.y

		return distance_a < distance_b
	)
	return candidates[0]


func _find_clear_fixture_corridor(
	city_world: WorldData,
	start_tile: Vector2i,
	destination_tile: Vector2i
) -> Array[Vector2i]:
	var corridor := _make_cardinal_fixture_path(
		start_tile,
		destination_tile,
		true
	)

	if _fixture_path_is_clear(corridor):
		return corridor

	corridor = _make_cardinal_fixture_path(
		start_tile,
		destination_tile,
		false
	)

	if _fixture_path_is_clear(corridor):
		return corridor

	var maximum_detour := mini(
		MAX_FIXTURE_DETOUR_TILES,
		maxi(city_world.width, city_world.height)
	)

	for detour_distance in range(1, maximum_detour + 1):
		for direction in [-1, 1]:
			var detour_y := (
				start_tile.y + detour_distance * int(direction)
			)

			if detour_y >= 0 and detour_y < city_world.height:
				corridor = _make_two_bend_fixture_path(
					start_tile,
					destination_tile,
					Vector2i(start_tile.x, detour_y),
					Vector2i(destination_tile.x, detour_y)
				)

				if _fixture_path_is_clear(corridor):
					return corridor

			var detour_x := (
				start_tile.x + detour_distance * int(direction)
			)

			if detour_x >= 0 and detour_x < city_world.width:
				corridor = _make_two_bend_fixture_path(
					start_tile,
					destination_tile,
					Vector2i(detour_x, start_tile.y),
					Vector2i(detour_x, destination_tile.y)
				)

				if _fixture_path_is_clear(corridor):
					return corridor

	return []


func _make_two_bend_fixture_path(
	start_tile: Vector2i,
	destination_tile: Vector2i,
	first_turn: Vector2i,
	second_turn: Vector2i
) -> Array[Vector2i]:
	var path: Array[Vector2i] = [start_tile]
	var turn_tiles: Array[Vector2i] = [
		first_turn,
		second_turn,
		destination_tile,
	]

	for turn_tile in turn_tiles:
		var leg := _make_cardinal_fixture_path(
			path[path.size() - 1],
			turn_tile,
			true
		)

		for leg_index in range(1, leg.size()):
			path.append(leg[leg_index])

	return path


func _make_cardinal_fixture_path(
	start_tile: Vector2i,
	destination_tile: Vector2i,
	horizontal_first: bool
) -> Array[Vector2i]:
	var path: Array[Vector2i] = [start_tile]
	var current_tile := start_tile

	if horizontal_first:
		while current_tile.x != destination_tile.x:
			current_tile.x += (
				1 if destination_tile.x > current_tile.x else -1
			)
			path.append(current_tile)

		while current_tile.y != destination_tile.y:
			current_tile.y += (
				1 if destination_tile.y > current_tile.y else -1
			)
			path.append(current_tile)
	else:
		while current_tile.y != destination_tile.y:
			current_tile.y += (
				1 if destination_tile.y > current_tile.y else -1
			)
			path.append(current_tile)

		while current_tile.x != destination_tile.x:
			current_tile.x += (
				1 if destination_tile.x > current_tile.x else -1
			)
			path.append(current_tile)

	return path


func _fixture_path_is_clear(path_tiles: Array[Vector2i]) -> bool:
	for path_index in range(1, path_tiles.size()):
		var tile_position := path_tiles[path_index]

		if (
			not CityObjectSystem.get_city_object_at_tile(tile_position).is_empty()
			or not CityConstructionSystem.get_city_construction_site_at_tile(
				tile_position
			).is_empty()
			or CityLogisticsSystem.has_city_ground_pile_at_tile(tile_position)
		):
			return false

	return true


func _make_external_boundary_tiles(
	city_world: WorldData,
	footprint_tiles: Array
) -> Array[Vector2i]:
	var boundary_tiles: Array[Vector2i] = []
	var footprint_lookup: Dictionary = {}

	for raw_tile in footprint_tiles:
		if raw_tile is Vector2i:
			footprint_lookup[raw_tile] = true

	for raw_tile in footprint_tiles:
		if not raw_tile is Vector2i:
			continue

		for offset in [
			Vector2i.UP,
			Vector2i.LEFT,
			Vector2i.RIGHT,
			Vector2i.DOWN,
		]:
			var candidate: Vector2i = raw_tile + offset

			if (
				footprint_lookup.has(candidate)
				or boundary_tiles.has(candidate)
				or not WorldData.is_city_tile_walkable_for_citizen(
					city_world,
					candidate
				)
			):
				continue

			boundary_tiles.append(candidate)

	return boundary_tiles


func _footprint_is_unoccupied(footprint_tiles: Array) -> bool:
	for raw_tile in footprint_tiles:
		if not raw_tile is Vector2i:
			return false

		if (
			not CityObjectSystem.get_city_object_at_tile(raw_tile).is_empty()
			or not CityConstructionSystem.get_city_construction_site_at_tile(
				raw_tile
			).is_empty()
			or CityLogisticsSystem.has_city_ground_pile_at_tile(raw_tile)
			or WorldData.has_living_city_citizen_at_tile(raw_tile)
		):
			return false

	return true


func _set_surface_feature(
	city_world: WorldData,
	tile_position: Vector2i,
	feature: String
) -> void:
	var tile := city_world.get_tile(tile_position.x, tile_position.y)
	var previous_feature := WorldData.get_city_surface_feature(tile)

	if feature == WorldData.CITY_SURFACE_FEATURE_NONE:
		tile.erase("surface_feature")
	else:
		tile["surface_feature"] = feature

	city_world.mark_city_surface_feature_changed(
		tile_position,
		previous_feature,
		feature
	)


func _find_placeable_rectangle(
	city_world: WorldData,
	size_tiles: Vector2i,
	object_type: String
) -> Vector2i:
	for y in range(city_world.height - size_tiles.y + 1):
		for x in range(city_world.width - size_tiles.x + 1):
			var top_left := Vector2i(x, y)

			if CityObjectSystem.can_place_city_object(
				city_world,
				top_left,
				size_tiles,
				object_type
			):
				return top_left

	return WorldData.INVALID_CITY_TILE_POSITION


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error(message)
