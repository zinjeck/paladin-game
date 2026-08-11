extends Node

const TEST_CITY_NAME := "Task Bootstrap"
const TEST_CULTURE_NAME := "Task Runtime Culture"

var failure_count: int = 0


func _ready() -> void:
	_test_state_defaults()
	_test_pre_context_state_adoption()
	_test_real_founding_bootstrap()
	_test_city_and_session_reset()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City citizen-task runtime bootstrap test failed: "
				+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City citizen-task runtime bootstrap test passed.")
	get_tree().quit(0)


func _test_state_defaults() -> void:
	var state_a := CityCitizenTaskRuntimeState.new()
	var state_b := CityCitizenTaskRuntimeState.new()
	_expect(
		_state_has_clean_defaults(state_a),
		"A new task-runtime owner must have exact clean defaults."
	)
	_expect(
		not is_same(state_a, state_b)
		and not is_same(state_a.active_task_ids, state_b.active_task_ids)
		and not is_same(
			state_a.active_task_id_lookup,
			state_b.active_task_id_lookup
		),
		"Separate owners must never share mutable task-runtime collections."
	)


func _test_pre_context_state_adoption() -> void:
	WorldData.reset_runtime_session_state()
	var world := _make_world(8, 8, 92_001)
	if not _lock_founding_world(world, "Pre-context"):
		return

	var bootstrap_ids: Array[int] = [17]
	var bootstrap_lookup: Dictionary = {17: true}
	var bootstrap_state := (
		CityCitizenTaskRuntimeSystem.get_current_state()
	)
	bootstrap_state.active_task_ids = bootstrap_ids
	bootstrap_state.active_task_id_lookup = bootstrap_lookup
	bootstrap_state.citizen_task_version = 7

	_expect(
		WorldPoliticalState.synchronize_foundation_with_world_data(),
		"Founding must establish a City settlement context."
	)
	var capital_state = WorldPoliticalState.get_active_city_simulation_state()
	var context = WorldPoliticalState.get_active_settlement_context()
	_expect(
		capital_state is CitySettlementSimulationState
		and is_same(capital_state.citizen_task_runtime_state, bootstrap_state)
		and is_same(
			capital_state.citizen_task_runtime_state.active_task_ids,
			bootstrap_ids
		)
		and is_same(
			capital_state.citizen_task_runtime_state.active_task_id_lookup,
			bootstrap_lookup
		),
		"The founding City must adopt the exact pre-context task owner."
	)
	_expect(
		context != null
		and is_same(
			context.get_city_citizen_task_runtime_state(),
			bootstrap_state
		)
		and is_same(CityCitizenTaskRuntimeSystem.get_current_state().active_task_ids, bootstrap_ids)
		and is_same(CityCitizenTaskRuntimeSystem.get_current_state().active_task_id_lookup, bootstrap_lookup)
		and CityCitizenTaskRuntimeSystem.get_current_state().citizen_task_version == 7,
		"Context and compatibility access must resolve one task owner."
	)
	_expect(
		WorldPoliticalState.synchronize_foundation_with_world_data()
		and is_same(
			CityCitizenTaskRuntimeSystem.get_current_state(),
			bootstrap_state
		),
		"Repeated synchronization must not replace the task owner."
	)


func _test_real_founding_bootstrap() -> void:
	WorldData.reset_runtime_session_state()
	var world := _make_world(8, 8, 92_101)
	if not _lock_founding_world(world, "Actual founding"):
		return
	_expect(
		WorldPoliticalState.synchronize_foundation_with_world_data(),
		"The live flow must establish the capital before Keep placement."
	)
	var capital_state = WorldPoliticalState.get_active_city_simulation_state()
	if not capital_state is CitySettlementSimulationState:
		_expect(false, "The live founding fixture requires a City state.")
		return

	var task_state: CityCitizenTaskRuntimeState = (
		capital_state.citizen_task_runtime_state
	)
	var city_world := _make_world(20, 20, 92_102)
	WorldData.store_city_world_save(city_world, 92_102)
	var keep_size := WorldData.get_city_object_size_for_type(
		WorldData.CITY_OBJECT_CITY_CENTER
	)
	var keep := CityObjectSystem.add_city_object({
		"object_type": WorldData.CITY_OBJECT_CITY_CENTER,
		"top_left": Vector2i(6, 6),
		"size_tiles": keep_size,
		"object_owner": "player",
		"city_world": city_world,
	})
	_expect(not keep.is_empty(), "The founding fixture must place a City Keep.")
	if keep.is_empty():
		return

	WorldData.found_player_city({
		"city_world_seed": 92_102,
		"city_map_size": Vector2i(city_world.width, city_world.height),
		"foundation_top_left": keep.get("top_left", Vector2i(-1, -1)),
		"foundation_size": keep.get("size", Vector2i.ZERO),
	})

	_expect(
		WorldData.has_player_city()
		and CityCitizenRegistrySystem.get_current_state().citizens.size()
		== WorldData.STARTING_CITY_POPULATION
		and _all_citizens_have_no_task()
		and _state_has_clean_defaults(task_state),
		"Founding must leave all eight citizens without active tasks."
	)
	var version_before_ensure := task_state.citizen_task_version
	_expect(
		CityCitizenTaskRuntimeSystem.ensure_city_citizen_task_state() == 0
		and task_state.citizen_task_version == version_before_ensure
		and _state_has_clean_defaults(task_state),
		"A clean founding ensure must neither replace nor invalidate runtime."
	)



func _test_city_and_session_reset() -> void:
	WorldData.reset_runtime_session_state()
	var state := (
		CityCitizenTaskRuntimeSystem.get_current_state()
	)
	var task_ids: Array[int] = [44]
	var task_lookup: Dictionary = {44: true}
	state.active_task_ids = task_ids
	state.active_task_id_lookup = task_lookup
	state.citizen_task_version = 20

	WorldData.reset_city_citizen_state()
	_expect(
		is_same(
			CityCitizenTaskRuntimeSystem.get_current_state(),
			state
		)
		and is_same(state.active_task_ids, task_ids)
		and is_same(state.active_task_id_lookup, task_lookup)
		and state.active_task_ids.is_empty()
		and state.active_task_id_lookup.is_empty()
		and state.citizen_task_version == 22,
		"Citizen reset must clear the exact owner in place and preserve both "
		+ "haul-reservation and task invalidations."
	)

	WorldData.reset_runtime_session_state()
	var fresh_state := (
		CityCitizenTaskRuntimeSystem.get_current_state()
	)
	_expect(
		not is_same(fresh_state, state)
		and _state_has_clean_defaults(fresh_state),
		"A global session reset must replace task runtime with defaults."
	)


func _state_has_clean_defaults(state: CityCitizenTaskRuntimeState) -> bool:
	return (
		state.active_task_ids.is_empty()
		and state.active_task_id_lookup.is_empty()
		and state.citizen_task_version == 0
	)


func _all_citizens_have_no_task() -> bool:
	for raw_citizen in CityCitizenRegistrySystem.get_current_state().citizens:
		if not raw_citizen is Dictionary:
			return false
		var raw_task = raw_citizen.get("current_task", {})
		if not raw_task is Dictionary:
			return false
		if (
			str(raw_task.get("kind", ""))
			!= WorldData.CITY_CITIZEN_TASK_KIND_NONE
		):
			return false
	return true


func _lock_founding_world(world: WorldData, label: String) -> bool:
	var locked := WorldData.lock_world_save({
		"source_world": world,
		"region_top_left": Vector2i(1, 1),
		"region_center": Vector2i(2, 2),
		"region_size": 3,
		"world_scene_path": "res://scenes/GameSession.tscn",
		"city_scene_path": "res://scenes/CityScreen.tscn",
		"city_name": TEST_CITY_NAME + " " + label,
		"culture_name": TEST_CULTURE_NAME + " " + label,
	})
	_expect(locked, label + " fixture must lock its founding world.")
	return locked


func _create_city(
	city_name: String,
	polity_id: int,
	region_center: Vector2i,
	backend_kind: String
) -> Dictionary:
	return WorldPoliticalState.create_settlement({
		"name": city_name,
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": polity_id,
		"world_region_top_left": region_center,
		"world_region_center": region_center,
		"world_region_size": 1,
		"simulation_backend_kind": backend_kind,
	})


func _make_world(width: int, height: int, seed_value: int) -> WorldData:
	var world := WorldData.new()
	world.setup(width, height, seed_value)

	for y in range(height):
		for x in range(width):
			world.tiles[y][x] = {
				"fertility": 50.0,
				"elevation": 0.2,
				"temperature": 0.5,
				"precipitation": 0.5,
				"terrain": WorldData.TERRAIN_LAND,
				"biome": WorldData.BIOME_PLAIN,
				"resource": WorldData.RESOURCE_NONE,
				"is_land": true,
			}

	world.mark_tile_data_changed()
	return world


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error("City citizen-task runtime bootstrap test: " + message)
