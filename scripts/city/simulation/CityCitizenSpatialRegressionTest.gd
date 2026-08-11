extends Node

const TILE_A := Vector2i(3, 3)
const TILE_B := Vector2i(4, 3)
const TILE_C := Vector2i(7, 3)

var failure_count: int = 0


func _ready() -> void:
	_test_index_mutations_rebuild_and_reset()
	_test_real_movement_batch_atomicity()
	_test_dead_active_mover_cleanup()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City citizen-spatial regression test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City citizen-spatial regression test passed.")
	get_tree().quit(0)


func _test_index_mutations_rebuild_and_reset() -> void:
	var fixture := _reset_fixture(99_101)
	var city_world: WorldData = fixture["world"]
	var culture_id: int = fixture["culture_id"]
	var spatial_state := (
		CityCitizenSpatialSystem.get_current_state()
	)
	var spatial_index: Dictionary = spatial_state.citizen_ids_by_tile

	var first := _add_citizen(culture_id, TILE_A)
	var second := _add_citizen(culture_id, TILE_A)
	var third := _add_citizen(culture_id, TILE_B)
	var first_id := int(first.get("id", -1))
	var second_id := int(second.get("id", -1))
	var third_id := int(third.get("id", -1))
	_expect(
		first_id == 1
		and second_id == 2
		and third_id == 3
		and spatial_index.get(TILE_A, []) == [1, 2]
		and spatial_index.get(TILE_B, []) == [3]
		and spatial_state.citizen_spatial_version == 3,
		"Adds must create sorted shared-tile membership and one version each."
	)

	# A direct move must remove every stale duplicate from the old bucket.
	spatial_index[TILE_A] = [first_id, first_id, second_id]
	var version_before_move := spatial_state.citizen_spatial_version
	_expect(
		CityCitizenSpatialSystem.set_city_citizen_tile_position(
			city_world,
			first_id,
			TILE_B
		)
		and spatial_index.get(TILE_A, []) == [2]
		and spatial_index.get(TILE_B, []) == [1, 3]
		and CityCitizenSpatialSystem.get_city_citizen_tile_position(first_id) == TILE_B
		and spatial_state.citizen_spatial_version == version_before_move + 1,
		"A direct move must atomically remove old and add new membership."
	)

	var version_before_noop := spatial_state.citizen_spatial_version
	var stable_index := spatial_index.duplicate(true)
	_expect(
		CityCitizenSpatialSystem.set_city_citizen_tile_position(
			city_world,
			first_id,
			TILE_B
		)
		and not CityCitizenSpatialSystem.set_city_citizen_tile_position(
			city_world,
			first_id,
			Vector2i(-1, -1)
		)
		and spatial_index == stable_index
		and spatial_state.citizen_spatial_version == version_before_noop,
		"No-op and rejected position changes must leave state untouched."
	)
	spatial_index[TILE_B] = [third_id]
	var version_before_noop_repair := spatial_state.citizen_spatial_version
	_expect(
		CityCitizenSpatialSystem.set_city_citizen_tile_position(
			city_world,
			first_id,
			TILE_B
		)
		and spatial_index.get(TILE_B, []) == [first_id, third_id]
		and spatial_state.citizen_spatial_version
		== version_before_noop_repair + 1,
		"A same-tile set must repair missing membership and invalidate once."
	)

	spatial_index.clear()
	spatial_index[TILE_A] = [first_id, first_id, 999]
	spatial_index[TILE_C] = [second_id]
	var version_before_rebuild := spatial_state.citizen_spatial_version
	_expect(
		CityCitizenSpatialSystem.rebuild_city_citizen_spatial_index()
		and spatial_index.get(TILE_A, []) == [second_id]
		and spatial_index.get(TILE_B, []) == [first_id, third_id]
		and not spatial_index.has(TILE_C)
		and spatial_state.citizen_spatial_version
		== version_before_rebuild + 1,
		"Rebuild must repair duplicates, ghosts, wrong tiles, and invalidate once."
	)
	var version_before_clean_rebuild := spatial_state.citizen_spatial_version
	_expect(
		not CityCitizenSpatialSystem.rebuild_city_citizen_spatial_index()
		and spatial_state.citizen_spatial_version
		== version_before_clean_rebuild,
		"A clean rebuild must not publish a false spatial change."
	)

	var registry_array: Array = CityCitizenRegistrySystem.get_current_state().citizens
	var third_index := CityCitizenRegistrySystem.get_city_citizen_index_by_id(third_id)
	var dead_citizen: Dictionary = registry_array[third_index]
	dead_citizen["alive"] = false
	registry_array[third_index] = dead_citizen
	CityCitizenRegistrySystem.mark_city_citizens_changed()
	var version_before_death_rebuild := spatial_state.citizen_spatial_version
	_expect(
		CityCitizenSpatialSystem.rebuild_city_citizen_spatial_index()
		and spatial_index.get(TILE_B, []) == [first_id]
		and spatial_state.citizen_spatial_version
		== version_before_death_rebuild + 1,
		"Rebuild must remove non-living citizens from spatial membership."
	)

	registry_array.remove_at(CityCitizenRegistrySystem.get_city_citizen_index_by_id(second_id))
	CityCitizenRegistrySystem.rebuild_city_citizen_index()
	CityCitizenRegistrySystem.mark_city_citizens_changed()
	var version_before_removal_rebuild := spatial_state.citizen_spatial_version
	_expect(
		CityCitizenSpatialSystem.rebuild_city_citizen_spatial_index()
		and not spatial_index.has(TILE_A)
		and spatial_index.get(TILE_B, []) == [first_id]
		and spatial_state.citizen_spatial_version
		== version_before_removal_rebuild + 1,
		"Registry removal followed by rebuild must clear stale tile membership."
	)

	var version_before_reset := spatial_state.citizen_spatial_version
	WorldData.reset_city_citizen_state()
	_expect(
		is_same(
			CityCitizenSpatialSystem.get_current_state(),
			spatial_state
		)
		and is_same(CityCitizenSpatialSystem.get_current_state().citizen_ids_by_tile, spatial_index)
		and spatial_index.is_empty()
		and spatial_state.citizen_spatial_version == version_before_reset + 1,
		"Citizen reset must clear the spatial index in place and invalidate once."
	)

	WorldData.reset_runtime_session_state()
	var fresh_state := (
		CityCitizenSpatialSystem.get_current_state()
	)
	_expect(
		not is_same(fresh_state, spatial_state)
		and fresh_state.citizen_ids_by_tile.is_empty()
		and fresh_state.citizen_spatial_version == 0,
		"A global session reset must replace spatial state with clean defaults."
	)


func _test_real_movement_batch_atomicity() -> void:
	var fixture := _reset_fixture(99_202)
	var city_world: WorldData = fixture["world"]
	var culture_id: int = fixture["culture_id"]
	var valid_citizen := _add_citizen(culture_id, TILE_A)
	var rejected_citizen := _add_citizen(culture_id, TILE_C)
	var valid_id := int(valid_citizen.get("id", -1))
	var rejected_id := int(rejected_citizen.get("id", -1))
	var valid_update: Dictionary = valid_citizen.duplicate(true)
	var rejected_update: Dictionary = rejected_citizen.duplicate(true)
	var spatial_state := (
		CityCitizenSpatialSystem.get_current_state()
	)
	var spatial_index: Dictionary = spatial_state.citizen_ids_by_tile
	var version_before_commit := spatial_state.citizen_spatial_version

	var commit_result := CityCitizenMovementRuntimeSystem.commit_city_citizen_movement_tick(
		city_world,
		[
			{
				"citizen_id": valid_id,
				"citizen": valid_update,
				"final_tile": TILE_B,
				"traversed_tiles": [TILE_A, TILE_B],
			},
			{
				"citizen_id": rejected_id,
				"citizen": rejected_update,
				"final_tile": Vector2i(-1, -1),
				"traversed_tiles": [TILE_C],
			},
		],
		[]
	)
	_expect(
		bool(commit_result.get("success", false))
		and int(commit_result.get("updated_citizen_count", 0)) == 1
		and int(commit_result.get("moved_citizen_count", 0)) == 1
		and int(commit_result.get("rejected_update_count", 0)) == 1
		and CityCitizenSpatialSystem.get_city_citizen_tile_position(valid_id) == TILE_B
		and CityCitizenSpatialSystem.get_city_citizen_tile_position(rejected_id) == TILE_C
		and not spatial_index.has(TILE_A)
		and spatial_index.get(TILE_B, []) == [valid_id]
		and spatial_index.get(TILE_C, []) == [rejected_id]
		and spatial_state.citizen_spatial_version == version_before_commit + 1
		and _each_citizen_has_one_membership(spatial_index),
		"A movement batch must commit valid spatial change once and isolate rejection."
	)

	var rejected_index := CityCitizenRegistrySystem.get_city_citizen_index_by_id(rejected_id)
	var dead_update: Dictionary = CityCitizenRegistrySystem.get_current_state().citizens[rejected_index]
	dead_update["alive"] = false
	CityCitizenRegistrySystem.get_current_state().citizens[rejected_index] = dead_update
	CityCitizenRegistrySystem.mark_city_citizens_changed()
	var version_before_death_commit := spatial_state.citizen_spatial_version
	var death_result := CityCitizenMovementRuntimeSystem.commit_city_citizen_movement_tick(
		city_world,
		[{
			"citizen_id": rejected_id,
			"citizen": dead_update.duplicate(true),
			"final_tile": TILE_C,
			"traversed_tiles": [TILE_C],
		}],
		[]
	)
	_expect(
		bool(death_result.get("success", false))
		and int(death_result.get("updated_citizen_count", 0)) == 1
		and not spatial_index.has(TILE_C)
		and spatial_state.citizen_spatial_version
		== version_before_death_commit + 1,
		"A committed non-living update must clear membership without quarantine."
	)

	# Simulate a damaged derived index while the authoritative citizen position
	# remains correct. A same-tile movement update must repair and invalidate it.
	spatial_index.erase(TILE_B)
	var repair_update := CityCitizenRegistrySystem.get_city_citizen_by_id(valid_id).duplicate(true)
	var version_before_repair := spatial_state.citizen_spatial_version
	var repair_result := CityCitizenMovementRuntimeSystem.commit_city_citizen_movement_tick(
		city_world,
		[{
			"citizen_id": valid_id,
			"citizen": repair_update,
			"final_tile": TILE_B,
			"traversed_tiles": [TILE_B],
		}],
		[]
	)
	_expect(
		bool(repair_result.get("success", false))
		and int(repair_result.get("moved_citizen_count", -1)) == 0
		and spatial_index.get(TILE_B, []) == [valid_id]
		and spatial_state.citizen_spatial_version == version_before_repair + 1
		and _each_citizen_has_one_membership(spatial_index),
		"Same-tile commit must repair missing membership and invalidate once."
	)


func _test_dead_active_mover_cleanup() -> void:
	var fixture := _reset_fixture(99_303)
	var city_world: WorldData = fixture["world"]
	var culture_id: int = fixture["culture_id"]
	var citizen := _add_citizen(culture_id, TILE_A)
	var citizen_id := int(citizen.get("id", -1))
	_expect(
		CityCitizenMovementRuntimeSystem.assign_city_citizen_movement_order(
			citizen_id,
			[TILE_A, TILE_B]
		),
		"The death-cleanup fixture must begin with an active mover."
	)
	var occupied_tile: Dictionary = city_world.tiles[TILE_A.y][TILE_A.x]
	occupied_tile["terrain"] = WorldData.TERRAIN_WATER
	occupied_tile["is_land"] = false
	city_world.tiles[TILE_A.y][TILE_A.x] = occupied_tile
	city_world.mark_tile_data_changed()
	_expect(
		not CityNavigationSystem.is_city_tile_walkable_for_citizen(
			city_world,
			TILE_A,
			citizen_id
		),
		"The death-cleanup fixture must exercise a non-walkable current tile."
	)
	var citizen_index := CityCitizenRegistrySystem.get_city_citizen_index_by_id(citizen_id)
	var dead_citizen: Dictionary = CityCitizenRegistrySystem.get_current_state().citizens[citizen_index]
	dead_citizen["alive"] = false
	CityCitizenRegistrySystem.get_current_state().citizens[citizen_index] = dead_citizen
	CityCitizenRegistrySystem.mark_city_citizens_changed()
	var spatial_state := (
		CityCitizenSpatialSystem.get_current_state()
	)
	var version_before_tick := spatial_state.citizen_spatial_version

	CitizenMovementSystem.run_tick(701, 1)
	var after := CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
	_expect(
		str(after.get("movement_state", ""))
		== WorldData.CITY_CITIZEN_MOVEMENT_STATE_IDLE
		and CityCitizenMovementRuntimeSystem.get_city_active_mover_ids_snapshot().is_empty()
		and not CityCitizenSpatialSystem.get_current_state().citizen_ids_by_tile.has(TILE_A)
		and spatial_state.citizen_spatial_version == version_before_tick + 1,
		"The real movement tick must retire a dead mover and clear membership."
	)


func _each_citizen_has_one_membership(spatial_index: Dictionary) -> bool:
	var membership_count_by_id: Dictionary = {}
	for raw_ids in spatial_index.values():
		if not raw_ids is Array:
			return false
		for raw_id in raw_ids:
			if typeof(raw_id) != TYPE_INT:
				return false
			var citizen_id: int = raw_id
			membership_count_by_id[citizen_id] = int(
				membership_count_by_id.get(citizen_id, 0)
			) + 1
	var living_citizen_count := 0
	for raw_citizen in CityCitizenRegistrySystem.get_current_state().citizens:
		if not raw_citizen is Dictionary:
			return false
		var citizen: Dictionary = raw_citizen
		if not bool(citizen.get("alive", false)):
			continue
		living_citizen_count += 1
		var citizen_id := int(citizen.get("id", -1))
		if int(membership_count_by_id.get(citizen_id, 0)) != 1:
			return false
	return membership_count_by_id.size() == living_citizen_count


func _reset_fixture(seed_value: int) -> Dictionary:
	WorldData.reset_runtime_session_state()
	var city_world := _make_world(12, 12, seed_value)
	WorldPoliticalState.set_current_city_world(city_world)
	WorldPoliticalState.set_current_city_seed(seed_value)
	var culture := WorldData.create_culture(
		"Citizen Spatial Regression Culture " + str(seed_value)
	)
	return {
		"world": city_world,
		"culture_id": int(culture.get("id", -1)),
	}


func _add_citizen(culture_id: int, tile: Vector2i) -> Dictionary:
	return WorldData.add_city_citizen(
		"",
		tile,
		WorldData.CITY_CITIZEN_SEX_MALE,
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
	push_error("City citizen-spatial regression test: " + message)
