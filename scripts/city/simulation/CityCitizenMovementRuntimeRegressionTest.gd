extends Node

const CitySettlementTestFixtureScript = preload(
	"res://scripts/city/simulation/test_support/CitySettlementTestFixture.gd"
)
const TILE_A := Vector2i(2, 2)
const TILE_B := Vector2i(3, 2)
const TILE_C := Vector2i(5, 2)
const TILE_D := Vector2i(6, 2)
const TILE_E := Vector2i(8, 2)
const TILE_F := Vector2i(9, 2)

var failure_count: int = 0


func _ready() -> void:
	_test_assignment_registry_and_repairs()
	_test_event_buffer_transfer_and_version_independence()
	_test_real_tick_completion_and_reset()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City citizen-movement runtime regression test failed: "
				+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City citizen-movement runtime regression test passed.")
	get_tree().quit(0)


func _test_assignment_registry_and_repairs() -> void:
	var fixture := _reset_fixture(93_101)
	var city_state: CitySettlementSimulationState = fixture["city_state"]
	var city_world: WorldData = fixture["world"]
	var culture_id := int(fixture["culture_id"])
	var first := _add_citizen(city_state, culture_id, TILE_A)
	var second := _add_citizen(city_state, culture_id, TILE_C)
	var third := _add_citizen(city_state, culture_id, TILE_E)
	var first_id := int(first.get("id", -1))
	var second_id := int(second.get("id", -1))
	var third_id := int(third.get("id", -1))
	var state := city_state.citizen_movement_runtime_state

	_expect(
		CityCitizenMovementRuntimeSystem.assign_city_citizen_movement_order_for_city_state(
			city_state,
			third_id,
			[TILE_E, TILE_F]
		)
		and CityCitizenMovementRuntimeSystem.assign_city_citizen_movement_order_for_city_state(
			city_state,
			first_id,
			[TILE_A, TILE_B]
		),
		"The fixture must assign movers in reverse ID order."
	)
	_expect(
		first_id == 1
		and second_id == 2
		and third_id == 3
		and state.active_mover_ids == [1, 3]
		and _lookup_matches_ids(state.active_mover_id_lookup, [1, 3])
		and state.citizen_movement_version == 2,
		"Assignment must maintain a sorted array, exact lookup, and one version each."
	)

	var mover_snapshot := (
		CityCitizenMovementRuntimeSystem.get_city_active_mover_ids_snapshot_for_city_state(
			city_state
		)
	)
	mover_snapshot.append(99)
	_expect(
		mover_snapshot == [1, 3, 99]
		and state.active_mover_ids == [1, 3]
		and not is_same(mover_snapshot, state.active_mover_ids),
		"The public mover snapshot must not alias authoritative runtime."
	)

	var version_before_rejection := state.citizen_movement_version
	var ids_before_rejection := state.active_mover_ids.duplicate()
	var lookup_before_rejection := state.active_mover_id_lookup.duplicate(true)
	_expect(
		not CityCitizenMovementRuntimeSystem.assign_city_citizen_movement_order_for_city_state(
			city_state,
			second_id,
			[TILE_A, TILE_B]
		)
		and state.active_mover_ids == ids_before_rejection
		and state.active_mover_id_lookup == lookup_before_rejection
		and state.citizen_movement_version == version_before_rejection,
		"A rejected order must leave both indexes and the version untouched."
	)

	var array_only_ids: Array[int] = [1, 2, 3]
	var array_only_lookup: Dictionary = {1: true, 3: true}
	state.active_mover_ids = array_only_ids
	state.active_mover_id_lookup = array_only_lookup
	var version_before_array_only_repair := state.citizen_movement_version
	_expect(
		CityCitizenMovementRuntimeSystem.assign_city_citizen_movement_order_for_city_state(
			city_state,
			second_id,
			[TILE_C, TILE_D]
		)
		and is_same(state.active_mover_ids, array_only_ids)
		and is_same(state.active_mover_id_lookup, array_only_lookup)
		and state.active_mover_ids == [1, 2, 3]
		and _lookup_matches_ids(
			state.active_mover_id_lookup,
			[1, 2, 3]
		)
		and state.citizen_movement_version
		== version_before_array_only_repair + 1,
		"Assignment must repair an array-only target without duplicating it."
	)

	var duplicate_ids: Array[int] = [1, 2, 2, 3]
	var duplicate_lookup: Dictionary = {1: true, 2: true, 3: true}
	state.active_mover_ids = duplicate_ids
	state.active_mover_id_lookup = duplicate_lookup
	var version_before_duplicate_cancel := state.citizen_movement_version
	_expect(
		CityCitizenMovementRuntimeSystem.cancel_city_citizen_movement_for_city_state(
			city_state,
			second_id
		)
		and is_same(state.active_mover_ids, duplicate_ids)
		and is_same(state.active_mover_id_lookup, duplicate_lookup)
		and state.active_mover_ids == [1, 3]
		and _lookup_matches_ids(state.active_mover_id_lookup, [1, 3])
		and state.citizen_movement_version
		== version_before_duplicate_cancel + 1,
		"Cancellation must remove every duplicate and its lookup key."
	)

	var lookup_only_ids: Array[int] = [1, 3]
	var lookup_only_lookup: Dictionary = {1: true, 2: true, 3: true}
	state.active_mover_ids = lookup_only_ids
	state.active_mover_id_lookup = lookup_only_lookup
	var version_before_lookup_only_repair := state.citizen_movement_version
	_expect(
		CityCitizenMovementRuntimeSystem.assign_city_citizen_movement_order_for_city_state(
			city_state,
			second_id,
			[TILE_C, TILE_D]
		)
		and is_same(state.active_mover_ids, lookup_only_ids)
		and is_same(state.active_mover_id_lookup, lookup_only_lookup)
		and state.active_mover_ids == [1, 2, 3]
		and _lookup_matches_ids(
			state.active_mover_id_lookup,
			[1, 2, 3]
		)
		and state.citizen_movement_version
		== version_before_lookup_only_repair + 1,
		"Assignment must repair a lookup-only target into both indexes."
	)

	var corrupt_ids: Array[int] = [3, 1, 1, 999]
	var corrupt_lookup: Dictionary = {1: false, 999: true}
	state.active_mover_ids = corrupt_ids
	state.active_mover_id_lookup = corrupt_lookup
	var version_before_rebuild := state.citizen_movement_version
	_expect(
		CityCitizenMovementRuntimeSystem.rebuild_city_active_mover_registry_for_city_state(
			city_state
		)
		and is_same(state.active_mover_ids, corrupt_ids)
		and is_same(state.active_mover_id_lookup, corrupt_lookup)
		and state.active_mover_ids == [1, 2, 3]
		and _lookup_matches_ids(
			state.active_mover_id_lookup,
			[1, 2, 3]
		)
		and state.citizen_movement_version == version_before_rebuild + 1,
		"Rebuild must repair order, duplicates, ghosts, values, and missing keys once."
	)
	var version_before_clean_rebuild := state.citizen_movement_version
	_expect(
		not CityCitizenMovementRuntimeSystem.rebuild_city_active_mover_registry_for_city_state(
			city_state
		)
		and state.citizen_movement_version == version_before_clean_rebuild,
		"A clean active-mover rebuild must not publish a false change."
	)

	state.active_mover_id_lookup.erase(second_id)
	var version_before_commit_repair := state.citizen_movement_version
	var commit_repair := CityCitizenMovementRuntimeSystem.commit_city_citizen_movement_tick_for_city_state(
		city_state,
		city_world,
		[],
		[1, 2, 3]
	)
	_expect(
		bool(commit_repair.get("success", false))
		and int(commit_repair.get("updated_citizen_count", -1)) == 0
		and state.active_mover_ids == [1, 2, 3]
		and _lookup_matches_ids(
			state.active_mover_id_lookup,
			[1, 2, 3]
		)
		and state.citizen_movement_version
		== version_before_commit_repair + 1,
		"A no-update commit must repair lookup-only corruption exactly once."
	)


func _test_event_buffer_transfer_and_version_independence() -> void:
	var fixture := _reset_fixture(93_202)
	var city_state: CitySettlementSimulationState = fixture["city_state"]
	var state := city_state.citizen_movement_runtime_state
	var version_before_events := state.citizen_movement_version
	CityCitizenMovementRuntimeSystem.begin_city_citizen_movement_visual_tick_for_city_state(
		city_state,
		40
	)
	state.citizen_movement_visual_events.append({"marker": 1})
	_expect(
		state.citizen_movement_visual_tick_index == 40
		and state.citizen_movement_visual_events.size() == 1
		and state.citizen_movement_version == version_before_events,
		"Beginning and writing a visual tick must not invalidate movement state."
	)
	_expect(
		CityCitizenMovementRuntimeSystem.take_city_citizen_movement_visual_events_for_city_state(
			city_state,
			39
		).is_empty()
		and state.citizen_movement_visual_events.is_empty()
		and state.citizen_movement_visual_tick_index == -1
		and state.citizen_movement_version == version_before_events,
		"A stale take must clear the buffer without changing movement version."
	)

	CityCitizenMovementRuntimeSystem.begin_city_citizen_movement_visual_tick_for_city_state(
		city_state,
		41
	)
	state.citizen_movement_visual_events.append({"marker": 2})
	var transferred_buffer: Array = state.citizen_movement_visual_events
	var taken_events := (
		CityCitizenMovementRuntimeSystem.take_city_citizen_movement_visual_events_for_city_state(
			city_state,
			41
		)
	)
	_expect(
		is_same(taken_events, transferred_buffer)
		and taken_events.size() == 1
		and int(taken_events[0].get("marker", -1)) == 2
		and not is_same(
			state.citizen_movement_visual_events,
			transferred_buffer
		)
		and state.citizen_movement_visual_events.is_empty()
		and state.citizen_movement_visual_tick_index == -1
		and state.citizen_movement_version == version_before_events
		and CityCitizenMovementRuntimeSystem.take_city_citizen_movement_visual_events_for_city_state(
			city_state,
			41
		).is_empty(),
		"Matching take must transfer the old buffer exactly once without invalidating."
	)
	CityCitizenMovementRuntimeSystem.clear_city_citizen_movement_visual_events_for_city_state(
		city_state
	)
	_expect(
		state.citizen_movement_visual_events.is_empty()
		and state.citizen_movement_visual_tick_index == -1
		and state.citizen_movement_version == version_before_events,
		"Explicit visual clearing must remain version-independent."
	)


func _test_real_tick_completion_and_reset() -> void:
	var fixture := _reset_fixture(93_303)
	var city_state: CitySettlementSimulationState = fixture["city_state"]
	var culture_id := int(fixture["culture_id"])
	var first := _add_citizen(city_state, culture_id, TILE_A)
	var second := _add_citizen(city_state, culture_id, TILE_C)
	var first_id := int(first.get("id", -1))
	var second_id := int(second.get("id", -1))
	var state := city_state.citizen_movement_runtime_state
	_expect(
		CityCitizenMovementRuntimeSystem.assign_city_citizen_movement_order_for_city_state(
			city_state,
			first_id,
			[TILE_A, TILE_B]
		)
		and CityCitizenMovementRuntimeSystem.assign_city_citizen_movement_order_for_city_state(
			city_state,
			second_id,
			[TILE_C, TILE_D]
		),
		"The real-tick fixture must assign two movers."
	)
	var version_before_first_tick := state.citizen_movement_version
	CitizenMovementSystem.run_tick_for_city_state(city_state, 901, 1)
	_expect(
		state.active_mover_ids == [1, 2]
		and _lookup_matches_ids(state.active_mover_id_lookup, [1, 2])
		and state.citizen_movement_visual_events.size() == 2
		and state.citizen_movement_visual_tick_index == 901
		and state.citizen_movement_version == version_before_first_tick + 1
		and int(
			CityCitizenRegistrySystem.get_city_citizen_by_id_for_city_state(
				city_state,
				first_id
			).get(
				"movement_progress_basis_points",
				-1
			)
		) == 5_000,
		"One batched partial tick must update two movers with one invalidation."
	)

	var version_before_completion := state.citizen_movement_version
	CitizenMovementSystem.run_tick_for_city_state(city_state, 902, 1)
	_expect(
		state.active_mover_ids.is_empty()
		and state.active_mover_id_lookup.is_empty()
		and state.citizen_movement_visual_events.size() == 2
		and state.citizen_movement_visual_tick_index == 902
		and state.citizen_movement_version == version_before_completion + 1
		and CityCitizenSpatialSystem.get_city_citizen_tile_position_for_city_state(
			city_state,
			first_id
		) == TILE_B
		and CityCitizenSpatialSystem.get_city_citizen_tile_position_for_city_state(
			city_state,
			second_id
		) == TILE_D
		and str(
			CityCitizenRegistrySystem.get_city_citizen_by_id_for_city_state(
				city_state,
				first_id
			).get(
				"movement_state",
				""
			)
		) == CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_IDLE,
		"The next real tick must finish both routes and retire both movers once."
	)

	var mover_ids_ref: Array[int] = state.active_mover_ids
	var mover_lookup_ref: Dictionary = state.active_mover_id_lookup
	var visual_events_ref: Array = state.citizen_movement_visual_events
	var version_before_reset := state.citizen_movement_version
	CityCitizenRegistrySystem.reset_city_citizen_state_for_city_state(city_state)
	_expect(
		is_same(city_state.citizen_movement_runtime_state, state)
		and is_same(state.active_mover_ids, mover_ids_ref)
		and is_same(state.active_mover_id_lookup, mover_lookup_ref)
		and is_same(state.citizen_movement_visual_events, visual_events_ref)
		and state.active_mover_ids.is_empty()
		and state.active_mover_id_lookup.is_empty()
		and state.citizen_movement_visual_events.is_empty()
		and state.citizen_movement_visual_tick_index == -1
		and state.citizen_movement_version == version_before_reset + 1,
		"Citizen reset must clear current runtime in place and invalidate once."
	)

	var stale_ids: Array[int] = [99]
	var stale_lookup: Dictionary = {99: true}
	state.active_mover_ids = stale_ids
	state.active_mover_id_lookup = stale_lookup
	var version_before_empty_ensure := state.citizen_movement_version
	_expect(
		CityCitizenMovementRuntimeSystem.ensure_city_citizen_movement_state_for_city_state(
			city_state
		) == 0
		and is_same(state.active_mover_ids, stale_ids)
		and is_same(state.active_mover_id_lookup, stale_lookup)
		and state.active_mover_ids.is_empty()
		and state.active_mover_id_lookup.is_empty()
		and state.citizen_movement_version
		== version_before_empty_ensure + 1,
		"Empty ensure must repair stale runtime and publish exactly one change."
	)
	var version_before_clean_ensure := state.citizen_movement_version
	_expect(
		CityCitizenMovementRuntimeSystem.ensure_city_citizen_movement_state_for_city_state(
			city_state
		) == 0
		and state.citizen_movement_version == version_before_clean_ensure,
		"A second clean empty ensure must not invalidate."
	)

	var fresh_fixture := _reset_fixture(93_313)
	var fresh_state = fresh_fixture["city_state"].citizen_movement_runtime_state
	_expect(
		not is_same(fresh_state, state)
		and fresh_state.active_mover_ids.is_empty()
		and fresh_state.active_mover_id_lookup.is_empty()
		and fresh_state.citizen_movement_visual_events.is_empty()
		and fresh_state.citizen_movement_visual_tick_index == -1
		and fresh_state.citizen_movement_version == 0,
		"Global session reset must replace runtime with clean defaults."
	)


func _lookup_matches_ids(lookup: Dictionary, expected_ids: Array) -> bool:
	if lookup.size() != expected_ids.size():
		return false
	for raw_id in expected_ids:
		var citizen_id := int(raw_id)
		if not lookup.has(citizen_id) or not bool(lookup[citizen_id]):
			return false
	return true


func _reset_fixture(seed_value: int) -> Dictionary:
	var city_world := _make_world(12, 12, seed_value)
	var fixture = CitySettlementTestFixtureScript.create({
		"label": "Movement Runtime Regression " + str(seed_value),
		"city_world": city_world,
		"city_seed": seed_value,
	})
	_expect(fixture != null, "The movement fixture must be created.")
	if fixture == null:
		return {}
	return {
		"fixture": fixture,
		"city_state": fixture.city_state,
		"world": city_world,
		"culture_id": fixture.culture_id,
	}


func _add_citizen(
	city_state: CitySettlementSimulationState,
	culture_id: int,
	tile: Vector2i
) -> Dictionary:
	return CityCitizenRegistrySystem.add_city_citizen_for_city_state(
		city_state,
		"",
		tile,
		CityCitizens.CITY_CITIZEN_SEX_MALE,
		culture_id
	)


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
	push_error("City citizen-movement runtime regression test: " + message)
