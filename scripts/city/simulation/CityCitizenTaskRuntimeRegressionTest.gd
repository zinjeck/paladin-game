extends Node

const TILE_A := Vector2i(2, 2)
const TILE_B := Vector2i(3, 2)
const TILE_C := Vector2i(4, 2)

var failure_count: int = 0


func _ready() -> void:
	_test_assignment_registry_and_repairs()
	_test_empty_ensure_and_schema_migration()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City citizen-task runtime regression test failed: "
				+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City citizen-task runtime regression test passed.")
	get_tree().quit(0)


func _test_assignment_registry_and_repairs() -> void:
	var fixture := _reset_fixture(90_101)
	var culture_id := int(fixture["culture_id"])
	var house_id := int(fixture["house_id"])
	var first := _add_resident(culture_id, house_id, TILE_A)
	var second := _add_resident(culture_id, house_id, TILE_B)
	var third := _add_resident(culture_id, house_id, TILE_C)
	var first_id := int(first.get("id", -1))
	var second_id := int(second.get("id", -1))
	var third_id := int(third.get("id", -1))
	var state := (
		WorldPoliticalState.get_current_city_citizen_task_runtime_state()
	)

	_expect(
		_assign_return_home(third_id, house_id)
		and _assign_return_home(first_id, house_id),
		"The fixture must assign tasks in reverse ID order."
	)
	_expect(
		first_id == 1
		and second_id == 2
		and third_id == 3
		and state.active_task_ids == [1, 3]
		and _lookup_matches_ids(state.active_task_id_lookup, [1, 3])
		and state.citizen_task_version == 2,
		"Assignment must maintain a sorted array, exact lookup, and one task "
		+ "invalidation per clean assignment."
	)

	var task_snapshot := WorldData.get_city_active_task_ids_snapshot()
	task_snapshot.append(99)
	_expect(
		task_snapshot == [1, 3, 99]
		and state.active_task_ids == [1, 3]
		and not is_same(task_snapshot, state.active_task_ids),
		"The public task snapshot must not alias authoritative runtime."
	)

	var version_before_task_updates := state.citizen_task_version
	_expect(
		WorldData.set_city_citizen_task_phase(
			first_id,
			WorldData.CITY_CITIZEN_TASK_PHASE_TRAVELING
		)
		and WorldData.set_city_citizen_task_activity_state({
			"citizen_id": first_id,
			"target_tile": Vector2i(8, 8),
			"previous_target_tile": TILE_A,
			"next_action_world_minute": 20,
			"relocation_count": 1,
		})
		and state.active_task_ids == [1, 3]
		and state.citizen_task_version == version_before_task_updates + 2,
		"Real phase and activity updates must invalidate the same owner without "
		+ "changing registry membership."
	)

	var version_before_rejection := state.citizen_task_version
	var ids_before_rejection := state.active_task_ids.duplicate()
	var lookup_before_rejection := state.active_task_id_lookup.duplicate(true)
	_expect(
		not WorldData.assign_city_citizen_task(second_id, {
			"kind": WorldData.CITY_CITIZEN_TASK_KIND_RETURN_HOME,
			"source": WorldData.CITY_CITIZEN_TASK_SOURCE_SCHEDULE,
			"priority": 50,
			"target_object_id": 999,
		})
		and state.active_task_ids == ids_before_rejection
		and state.active_task_id_lookup == lookup_before_rejection
		and state.citizen_task_version == version_before_rejection,
		"A rejected assignment must leave both indexes and version untouched."
	)

	var array_only_ids: Array[int] = [1, 2, 3]
	var array_only_lookup: Dictionary = {1: true, 3: true}
	state.active_task_ids = array_only_ids
	state.active_task_id_lookup = array_only_lookup
	var version_before_array_only_repair := state.citizen_task_version
	_expect(
		_assign_return_home(second_id, house_id)
		and is_same(state.active_task_ids, array_only_ids)
		and is_same(state.active_task_id_lookup, array_only_lookup)
		and state.active_task_ids == [1, 2, 3]
		and _lookup_matches_ids(state.active_task_id_lookup, [1, 2, 3])
		and state.citizen_task_version
		== version_before_array_only_repair + 1,
		"Assignment must repair an array-only target without duplicating it."
	)

	var duplicate_ids: Array[int] = [1, 2, 2, 3]
	var duplicate_lookup: Dictionary = {1: true, 2: true, 3: true}
	state.active_task_ids = duplicate_ids
	state.active_task_id_lookup = duplicate_lookup
	var version_before_duplicate_clear := state.citizen_task_version
	_expect(
		WorldData.clear_city_citizen_task(
			second_id,
			WorldData.CITY_CITIZEN_TASK_SOURCE_SCHEDULE
		)
		and is_same(state.active_task_ids, duplicate_ids)
		and is_same(state.active_task_id_lookup, duplicate_lookup)
		and state.active_task_ids == [1, 3]
		and _lookup_matches_ids(state.active_task_id_lookup, [1, 3])
		and state.citizen_task_version
		== version_before_duplicate_clear + 1,
		"Clearing must remove every duplicate and its lookup key."
	)

	var duplicate_add_ids: Array[int] = [1, 2, 2, 3]
	var duplicate_add_lookup: Dictionary = {1: true, 3: true}
	state.active_task_ids = duplicate_add_ids
	state.active_task_id_lookup = duplicate_add_lookup
	var version_before_duplicate_add := state.citizen_task_version
	_expect(
		_assign_return_home(second_id, house_id)
		and is_same(state.active_task_ids, duplicate_add_ids)
		and is_same(state.active_task_id_lookup, duplicate_add_lookup)
		and state.active_task_ids == [1, 2, 3]
		and _lookup_matches_ids(state.active_task_id_lookup, [1, 2, 3])
		and state.citizen_task_version == version_before_duplicate_add + 1,
		"Assignment must compact duplicate target entries in place."
	)
	_expect(
		WorldData.clear_city_citizen_task(
			second_id,
			WorldData.CITY_CITIZEN_TASK_SOURCE_SCHEDULE
		),
		"The lookup-only fixture must begin with citizen 2 idle."
	)

	var lookup_only_ids: Array[int] = [1, 3]
	var lookup_only_lookup: Dictionary = {1: true, 2: true, 3: true}
	state.active_task_ids = lookup_only_ids
	state.active_task_id_lookup = lookup_only_lookup
	var version_before_lookup_only_repair := state.citizen_task_version
	_expect(
		_assign_return_home(second_id, house_id)
		and is_same(state.active_task_ids, lookup_only_ids)
		and is_same(state.active_task_id_lookup, lookup_only_lookup)
		and state.active_task_ids == [1, 2, 3]
		and _lookup_matches_ids(state.active_task_id_lookup, [1, 2, 3])
		and state.citizen_task_version
		== version_before_lookup_only_repair + 1,
		"Assignment must repair a lookup-only target into both indexes."
	)

	var corrupt_ids: Array[int] = [3, 1, 1, 999]
	var corrupt_lookup: Dictionary = {1: false, 999: true}
	state.active_task_ids = corrupt_ids
	state.active_task_id_lookup = corrupt_lookup
	var version_before_rebuild := state.citizen_task_version
	_expect(
		WorldData.rebuild_city_active_task_registry()
		and is_same(state.active_task_ids, corrupt_ids)
		and is_same(state.active_task_id_lookup, corrupt_lookup)
		and state.active_task_ids == [1, 2, 3]
		and _lookup_matches_ids(state.active_task_id_lookup, [1, 2, 3])
		and state.citizen_task_version == version_before_rebuild + 1,
		"Rebuild must repair order, duplicates, ghosts, false values, and "
		+ "missing keys exactly once."
	)
	var version_before_clean_rebuild := state.citizen_task_version
	_expect(
		not WorldData.rebuild_city_active_task_registry()
		and state.citizen_task_version == version_before_clean_rebuild,
		"A clean active-task rebuild must not publish a false change."
	)

	_set_citizen_alive(third_id, false)
	var version_before_dead_cleanup := state.citizen_task_version
	_expect(
		WorldData.rebuild_city_active_task_registry()
		and state.active_task_ids == [1, 2]
		and _lookup_matches_ids(state.active_task_id_lookup, [1, 2])
		and state.citizen_task_version == version_before_dead_cleanup + 1,
		"Rebuild must exclude a non-living citizen exactly once."
	)
	_set_citizen_alive(third_id, true)
	WorldData.rebuild_city_active_task_registry()

	_expect(
		WorldData.clear_city_citizen_task(
			first_id,
			WorldData.CITY_CITIZEN_TASK_SOURCE_SCHEDULE
		),
		"The stale-clear fixture must first clear citizen 1 normally."
	)
	var stale_ids: Array[int] = [1, 2, 3]
	var stale_lookup: Dictionary = {1: true, 2: true, 3: true}
	state.active_task_ids = stale_ids
	state.active_task_id_lookup = stale_lookup
	var version_before_idempotent_repair := state.citizen_task_version
	_expect(
		WorldData.clear_city_citizen_task(
			first_id,
			WorldData.CITY_CITIZEN_TASK_SOURCE_SCHEDULE
		)
		and is_same(state.active_task_ids, stale_ids)
		and is_same(state.active_task_id_lookup, stale_lookup)
		and state.active_task_ids == [2, 3]
		and _lookup_matches_ids(state.active_task_id_lookup, [2, 3])
		and state.citizen_task_version
		== version_before_idempotent_repair + 1,
		"Idempotent clear must repair a stale active-task index entry."
	)


func _test_empty_ensure_and_schema_migration() -> void:
	WorldData.reset_runtime_session_state()
	var empty_state := (
		WorldPoliticalState.get_current_city_citizen_task_runtime_state()
	)
	var stale_ids: Array[int] = [99]
	var stale_lookup: Dictionary = {99: true}
	empty_state.active_task_ids = stale_ids
	empty_state.active_task_id_lookup = stale_lookup
	empty_state.citizen_task_version = 10
	_expect(
		WorldData.ensure_city_citizen_task_state() == 0
		and is_same(empty_state.active_task_ids, stale_ids)
		and is_same(empty_state.active_task_id_lookup, stale_lookup)
		and empty_state.active_task_ids.is_empty()
		and empty_state.active_task_id_lookup.is_empty()
		and empty_state.citizen_task_version == 11,
		"Empty ensure must repair stale runtime in place and invalidate once."
	)
	var version_before_clean_empty_ensure := empty_state.citizen_task_version
	_expect(
		WorldData.ensure_city_citizen_task_state() == 0
		and empty_state.citizen_task_version
		== version_before_clean_empty_ensure,
		"A second clean empty ensure must not invalidate."
	)

	var fixture := _reset_fixture(90_202)
	var citizen := _add_resident(
		int(fixture["culture_id"]),
		int(fixture["house_id"]),
		TILE_A
	)
	var citizen_id := int(citizen.get("id", -1))
	var citizen_index := WorldData.get_city_citizen_index_by_id(citizen_id)
	var stored_citizen: Dictionary = WorldData.city_citizens[citizen_index]
	stored_citizen["current_task"] = {
		"kind": WorldData.CITY_CITIZEN_TASK_KIND_NONE,
	}
	WorldData.city_citizens[citizen_index] = stored_citizen
	var task_state := (
		WorldPoliticalState.get_current_city_citizen_task_runtime_state()
	)
	var migration_ids: Array[int] = [citizen_id]
	var migration_lookup: Dictionary = {}
	task_state.active_task_ids = migration_ids
	task_state.active_task_id_lookup = migration_lookup
	task_state.citizen_task_version = 40
	_expect(
		WorldData.ensure_city_citizen_task_state() == 1
		and is_same(task_state.active_task_ids, migration_ids)
		and is_same(task_state.active_task_id_lookup, migration_lookup)
		and task_state.active_task_ids.is_empty()
		and task_state.active_task_id_lookup.is_empty()
		and task_state.citizen_task_version == 41,
		"Schema migration plus registry repair must publish one invalidation."
	)
	var version_before_missing_clear := task_state.citizen_task_version
	_expect(
		not WorldData.clear_city_citizen_task(
			999,
			WorldData.CITY_CITIZEN_TASK_SOURCE_SCHEDULE
		)
		and task_state.citizen_task_version == version_before_missing_clear,
		"Rejected clear must not invalidate task runtime."
	)


func _assign_return_home(citizen_id: int, house_id: int) -> bool:
	return WorldData.assign_city_citizen_task(citizen_id, {
		"kind": WorldData.CITY_CITIZEN_TASK_KIND_RETURN_HOME,
		"source": WorldData.CITY_CITIZEN_TASK_SOURCE_SCHEDULE,
		"priority": 50,
		"target_object_id": house_id,
	})


func _set_citizen_alive(citizen_id: int, alive: bool) -> void:
	var citizen_index := WorldData.get_city_citizen_index_by_id(citizen_id)
	if citizen_index < 0:
		_expect(false, "The alive-state fixture requires an indexed citizen.")
		return
	var citizen: Dictionary = WorldData.city_citizens[citizen_index]
	citizen["alive"] = alive
	WorldData.city_citizens[citizen_index] = citizen


func _lookup_matches_ids(lookup: Dictionary, expected_ids: Array) -> bool:
	if lookup.size() != expected_ids.size():
		return false
	for raw_id in expected_ids:
		var citizen_id := int(raw_id)
		if not lookup.has(citizen_id) or not bool(lookup[citizen_id]):
			return false
	return true


func _reset_fixture(seed_value: int) -> Dictionary:
	WorldData.reset_runtime_session_state()
	var city_world := _make_world(16, 16, seed_value)
	WorldData.official_city_world = city_world
	WorldData.official_city_seed = seed_value
	var culture := WorldData.create_culture(
		"Task Runtime Regression Culture " + str(seed_value)
	)
	var house := CityObjectSystem.add_city_object({
		"object_type": WorldData.CITY_OBJECT_HOUSE,
		"top_left": Vector2i(8, 8),
		"size_tiles": WorldData.get_city_object_size_for_type(
			WorldData.CITY_OBJECT_HOUSE
		),
		"object_owner": "player",
		"city_world": city_world,
	})
	return {
		"culture_id": int(culture.get("id", -1)),
		"house_id": int(house.get("id", -1)),
	}


func _add_resident(
	culture_id: int,
	house_id: int,
	tile: Vector2i
) -> Dictionary:
	var citizen := WorldData.add_city_citizen(
		"",
		tile,
		WorldData.CITY_CITIZEN_SEX_FEMALE,
		culture_id
	)
	var citizen_id := int(citizen.get("id", -1))
	_expect(
		citizen_id > 0
		and WorldData.assign_city_citizen_home(citizen_id, house_id),
		"The task fixture must add one assigned resident."
	)
	return citizen


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
	push_error("City citizen-task runtime regression test: " + message)
