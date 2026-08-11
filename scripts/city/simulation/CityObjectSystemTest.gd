extends Node

const TEST_WORLD_SIZE := Vector2i(40, 28)

var failure_count: int = 0


func _ready() -> void:
	_test_fresh_state_defaults()
	_test_completed_object_registration_and_lookup()
	_test_rejected_registration_is_atomic()
	_test_snapshots_do_not_alias_authoritative_state()
	_test_registry_index_and_occupancy_repair()
	_test_object_reset_is_domain_local()
	WorldPoliticalState.reset_state()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City object system test failed: " + str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City object system test passed.")
	get_tree().quit(0)


func _test_fresh_state_defaults() -> void:
	_reset_fixture(93_101)
	var state := CityObjectSystem.get_current_state()

	_expect(
		state is CityObjectState
		and state.objects.is_empty()
		and state.object_index_by_id.is_empty()
		and state.occupied_tiles.is_empty()
		and state.next_object_id == 1
		and state.object_version == 0,
		"A fresh active object system must resolve clean state defaults."
	)


func _test_completed_object_registration_and_lookup() -> void:
	var city_world := _reset_fixture(93_102)
	var state := CityObjectSystem.get_current_state()
	var requests: Array[Dictionary] = [
		_make_rectangle_request(
			CityObjectCatalog.CITY_OBJECT_CITY_CENTER,
			Vector2i(2, 2),
			city_world
		),
		_make_rectangle_request(
			CityObjectCatalog.CITY_OBJECT_HOUSE,
			Vector2i(8, 2),
			city_world
		),
		_make_rectangle_request(
			CityObjectCatalog.CITY_OBJECT_STOCKPILE,
			Vector2i(13, 2),
			city_world
		),
		_make_rectangle_request(
			CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS,
			Vector2i(18, 2),
			city_world
		),
	]

	for request_index in range(requests.size()):
		var expected_id := request_index + 1
		var version_before := state.object_version
		var next_id_before := state.next_object_id
		var city_object := CityObjectSystem.register_completed_city_object(
			requests[request_index]
		)

		_expect(
			int(city_object.get("id", -1)) == expected_id
			and next_id_before == expected_id
			and state.next_object_id == expected_id + 1
			and state.object_version == version_before + 1,
			"Each completed building must allocate one local ID and advance object_version once."
		)
		_assert_registered_object(city_object, request_index)

	var road_tile := Vector2i(24, 2)
	var road_version_before := state.object_version
	var road_next_id_before := state.next_object_id
	var road := CityObjectSystem.add_city_road_object(
		[road_tile],
		"player",
		city_world
	)

	_expect(
		int(road.get("id", -1)) == road_next_id_before
		and state.next_object_id == road_next_id_before + 1
		and state.object_version == road_version_before + 1
		and CityObjectSystem.is_completed_city_road_tile(road_tile),
		"A completed one-tile road must allocate and version exactly once."
	)
	_assert_registered_object(road, requests.size())
	_expect(
		state.objects.size() == 5
		and CityObjectSystem.has_city_object_type(
			CityObjectCatalog.CITY_OBJECT_CITY_CENTER
		)
		and CityObjectSystem.has_city_object_type(
			CityObjectCatalog.CITY_OBJECT_HOUSE
		)
		and CityObjectSystem.has_city_object_type(
			CityObjectCatalog.CITY_OBJECT_STOCKPILE
		)
		and CityObjectSystem.has_city_object_type(
			CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS
		)
		and CityObjectSystem.has_city_object_type(
			CityObjectCatalog.CITY_OBJECT_ROAD
		),
		"The completed registry must recognize every current object type."
	)


func _test_rejected_registration_is_atomic() -> void:
	var city_world := _reset_fixture(93_103)
	var house := CityObjectSystem.register_completed_city_object(
		_make_rectangle_request(
			CityObjectCatalog.CITY_OBJECT_HOUSE,
			Vector2i(4, 4),
			city_world
		)
	)
	_expect(not house.is_empty(), "The rejection fixture must create a House.")

	var state := CityObjectSystem.get_current_state()
	var objects_before := CityObjectSystem.get_city_object_snapshot()
	var index_before := CityObjectSystem.get_city_object_index_snapshot()
	var occupancy_before := CityObjectSystem.get_city_occupied_tiles_snapshot()
	var next_id_before := state.next_object_id
	var version_before := state.object_version
	var overlapping_house := CityObjectSystem.register_completed_city_object(
		_make_rectangle_request(
			CityObjectCatalog.CITY_OBJECT_HOUSE,
			Vector2i(4, 4),
			city_world
		)
	)
	var multi_tile_road := CityObjectSystem.add_city_road_object(
		[Vector2i(20, 4), Vector2i(21, 4)],
		"player",
		city_world
	)
	var unknown_object := CityObjectSystem.register_completed_city_object({
		"object_type": "test_unknown_object",
		"top_left": Vector2i(25, 4),
		"size_tiles": Vector2i.ONE,
		"object_owner": "player",
		"city_world": city_world,
	})

	_expect(
		overlapping_house.is_empty()
		and multi_tile_road.is_empty()
		and unknown_object.is_empty(),
		"Overlapping, multi-tile-road, and unknown registrations must be rejected."
	)
	_expect(
		state.objects == objects_before
		and state.object_index_by_id == index_before
		and state.occupied_tiles == occupancy_before
		and state.next_object_id == next_id_before
		and state.object_version == version_before,
		"Rejected registration must not consume an ID, version, index, or occupancy mutation."
	)


func _test_snapshots_do_not_alias_authoritative_state() -> void:
	var city_world := _reset_fixture(93_104)
	var house := CityObjectSystem.register_completed_city_object(
		_make_rectangle_request(
			CityObjectCatalog.CITY_OBJECT_HOUSE,
			Vector2i(4, 4),
			city_world
		)
	)
	var house_id := int(house.get("id", -1))
	var footprint := CityObjectSystem.get_city_object_footprint_tiles(house)
	var object_snapshot := CityObjectSystem.get_city_object_snapshot()
	var by_id_snapshot := (
		CityObjectSystem.get_city_object_by_id_snapshot(house_id)
	)
	var index_snapshot := CityObjectSystem.get_city_object_index_snapshot()
	var occupancy_snapshot := (
		CityObjectSystem.get_city_occupied_tiles_snapshot()
	)
	var snapshot_house: Dictionary = object_snapshot[0]
	var snapshot_footprint: Array = snapshot_house.get(
		"footprint_tiles",
		[]
	)

	snapshot_house["owner"] = "snapshot"
	snapshot_footprint.clear()
	by_id_snapshot["owner"] = "by_id_snapshot"
	index_snapshot.clear()
	occupancy_snapshot.clear()

	var live_house := CityObjectSystem.get_city_object_by_id(house_id)
	_expect(
		str(live_house.get("owner", "")) == "player"
		and CityObjectSystem.get_city_object_footprint_tiles(live_house)
		== footprint
		and CityObjectSystem.get_city_object_index_by_id(house_id) == 0
		and CityObjectSystem.get_city_object_id_at_tile(footprint[0])
		== house_id,
		"Object, ID, index, and occupancy snapshots must not alias authoritative state."
	)


func _test_registry_index_and_occupancy_repair() -> void:
	var city_world := _reset_fixture(93_105)
	var house := CityObjectSystem.register_completed_city_object(
		_make_rectangle_request(
			CityObjectCatalog.CITY_OBJECT_HOUSE,
			Vector2i(4, 4),
			city_world
		)
	)
	var stockpile := CityObjectSystem.register_completed_city_object(
		_make_rectangle_request(
			CityObjectCatalog.CITY_OBJECT_STOCKPILE,
			Vector2i(10, 4),
			city_world
		)
	)
	var house_id := int(house.get("id", -1))
	var stockpile_id := int(stockpile.get("id", -1))
	var state := CityObjectSystem.get_current_state()

	state.object_index_by_id = {}
	state.object_index_by_id[house_id] = 1
	state.object_index_by_id[stockpile_id] = 0
	_expect(
		CityObjectSystem.get_city_object_index_by_id(house_id) == 0
		and CityObjectSystem.get_city_object_index_by_id(stockpile_id) == 1,
		"Lookup must repair a stale completed-object ID index from the authoritative array."
	)

	state.object_index_by_id = {
		9_999: 0,
		stockpile_id: 1,
	}
	_expect(
		CityObjectSystem.get_city_object_index_by_id(house_id) == 0,
		"Lookup must repair a full-size index with a wrong object ID key."
	)

	state.object_index_by_id = {
		9_999: 0,
		stockpile_id: 1,
	}
	state.next_object_id = house_id
	var object_count_before_duplicate_id := state.objects.size()
	var version_before_duplicate_id := state.object_version
	var duplicate_id_registration := (
		CityObjectSystem.register_completed_city_object(
			_make_rectangle_request(
				CityObjectCatalog.CITY_OBJECT_HOUSE,
				Vector2i(20, 4),
				city_world
			)
		)
	)
	_expect(
		duplicate_id_registration.is_empty()
		and state.objects.size() == object_count_before_duplicate_id
		and state.object_version == version_before_duplicate_id
		and state.next_object_id == house_id,
		"A corrupt full-size index must not allow allocation of a duplicate object ID."
	)

	state.occupied_tiles.clear()
	CityObjectSystem.rebuild_city_object_registry_indexes()
	var repaired_occupancy := true

	var registered_objects: Array[Dictionary] = [house, stockpile]

	for city_object in registered_objects:
		var object_id := int(city_object.get("id", -1))

		for raw_tile in CityObjectSystem.get_city_object_footprint_tiles(
			city_object
		):
			if int(state.occupied_tiles.get(raw_tile, -1)) != object_id:
				repaired_occupancy = false
				break

	_expect(
		repaired_occupancy
		and state.object_index_by_id.size() == 2
		and state.occupied_tiles.size()
		== (
			CityObjectSystem.get_city_object_footprint_tiles(house).size()
			+ CityObjectSystem.get_city_object_footprint_tiles(stockpile).size()
		),
		"Registry repair must rebuild both ID indexes and complete footprint occupancy."
	)

	var stale_tile := Vector2i(30, 20)
	state.occupied_tiles[stale_tile] = 9_999
	CityObjectSystem.rebuild_city_object_occupancy()
	_expect(
		CityObjectSystem.get_city_object_id_at_tile(stale_tile) < 0
		and not state.occupied_tiles.has(stale_tile),
		"Explicit occupancy repair must discard tiles that point to missing objects."
	)


func _test_object_reset_is_domain_local() -> void:
	var city_world := _reset_fixture(93_106)
	var stockpile := CityObjectSystem.register_completed_city_object(
		_make_rectangle_request(
			CityObjectCatalog.CITY_OBJECT_STOCKPILE,
			Vector2i(5, 5),
			city_world
		)
	)
	_expect(not stockpile.is_empty(), "The reset fixture must create a Stockpile.")

	var state := CityObjectSystem.get_current_state()
	var object_version_before := state.object_version
	var container_version_before := (
		CityResourceAccountingSystem.get_city_container_version()
	)
	var public_storage_version_before := (
		CityResourceAccountingSystem.get_city_public_storage_version()
	)
	var assignment_version_before := CityAssignmentSystem.get_city_assignment_version()
	var workplace_version_before := CityEmploymentSystem.get_city_workplace_version()
	var logistics_state := CityLogisticsSystem.get_current_state()
	var construction_state := CityConstructionSystem.get_current_state()
	var ground_pile_version_before := logistics_state.ground_pile_version
	var construction_version_before := construction_state.construction_version

	CityObjectSystem.reset_city_object_state()

	_expect(
		state.objects.is_empty()
		and state.object_index_by_id.is_empty()
		and state.occupied_tiles.is_empty()
		and state.next_object_id == 1
		and state.object_version == object_version_before + 1,
		"Object reset must clear only its five fields and publish one object change."
	)
	_expect(
		CityResourceAccountingSystem.get_city_container_version()
		== container_version_before
		and CityResourceAccountingSystem.get_city_public_storage_version()
		== public_storage_version_before
		and CityAssignmentSystem.get_current_state().assignment_version == assignment_version_before
		and CityEmploymentSystem.get_current_state().workplace_version == workplace_version_before
		and logistics_state.ground_pile_version
		== ground_pile_version_before
		and construction_state.construction_version
		== construction_version_before,
		"The focused object reset must not reset or version unrelated domains."
	)


func _assert_registered_object(
	city_object: Dictionary,
	expected_index: int
) -> void:
	var object_id := int(city_object.get("id", -1))
	var footprint := CityObjectSystem.get_city_object_footprint_tiles(
		city_object
	)
	var occupancy_is_complete := not footprint.is_empty()

	for raw_tile in footprint:
		if (
			not raw_tile is Vector2i
			or CityObjectSystem.get_city_object_id_at_tile(raw_tile)
			!= object_id
			or int(
				CityObjectSystem.get_city_object_at_tile(raw_tile).get(
					"id",
					-1
				)
			) != object_id
		):
			occupancy_is_complete = false
			break

	_expect(
		object_id > 0
		and CityObjectSystem.get_city_object_index_by_id(object_id)
		== expected_index
		and int(
			CityObjectSystem.get_city_object_by_id(object_id).get("id", -1)
		) == object_id
		and occupancy_is_complete,
		"A completed object must be indexed and own every footprint tile."
	)


func _make_rectangle_request(
	object_type: String,
	top_left: Vector2i,
	city_world: WorldData
) -> Dictionary:
	return {
		"object_type": object_type,
		"top_left": top_left,
		"size_tiles": CityObjectCatalog.get_city_object_size_for_type(object_type),
		"object_owner": "player",
		"city_world": city_world,
	}


func _reset_fixture(seed: int) -> WorldData:
	WorldPoliticalState.reset_state()
	WorldData.reset_runtime_session_state()
	SimulationClock.start_new_game()
	var city_world := WorldData.new()
	city_world.setup(TEST_WORLD_SIZE.x, TEST_WORLD_SIZE.y, seed)

	for y in range(city_world.height):
		for x in range(city_world.width):
			var tile := city_world.get_tile(x, y)
			tile["terrain"] = WorldData.TERRAIN_LAND
			tile["biome"] = WorldData.BIOME_PLAIN
			tile["is_land"] = true
			tile["fertility"] = 50.0
			tile.erase("surface_feature")

	city_world.mark_tile_data_changed()
	WorldData.store_city_world_save(city_world, seed)
	return city_world


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error("City object system test: " + message)
