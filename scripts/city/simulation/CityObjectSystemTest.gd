extends Node

const TEST_WORLD_SIZE := Vector2i(40, 28)

var failure_count: int = 0


func _ready() -> void:
	_test_fresh_state_defaults()
	_test_completed_object_registration_and_lookup()
	_test_settlement_local_registration_gate_and_atomic_foundation_rollback()
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
	var city_world := _reset_fixture(93_102, false)
	var state := CityObjectSystem.get_current_state()
	var city_state = WorldPoliticalState.get_current_city_simulation_state()
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
		if request_index == 0:
			city_state.city_runtime_data["founded"] = true
			city_state.city_runtime_data["can_build"] = true

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


func _test_settlement_local_registration_gate_and_atomic_foundation_rollback() -> void:
	var city_world := _reset_fixture(93_107, false)
	var city_state: CitySettlementSimulationState = (
		WorldPoliticalState.get_current_city_simulation_state()
	)
	var object_state := city_state.object_state
	var accounting_state := city_state.resource_accounting_state
	var house_values := _make_rectangle_request(
		CityObjectCatalog.CITY_OBJECT_HOUSE,
		Vector2i(12, 12),
		city_world
	)
	WorldData.player_city_founded = true
	_expect(
		CityObjectSystem.register_completed_city_object(house_values).is_empty()
		and CityObjectSystem.register_completed_city_object_for_city_state(
			city_state,
			house_values
		).is_empty(),
		"Legacy and explicit direct registration must reject requires-city objects for an unfounded target regardless of player globals."
	)

	var keep_top_left := Vector2i(3, 3)
	var keep_values := _make_rectangle_request(
		CityObjectCatalog.CITY_OBJECT_CITY_CENTER,
		keep_top_left,
		city_world
	)
	keep_values["defer_surface_feature_clear"] = true
	_expect(
		city_world.set_tile_surface_feature(
			keep_top_left,
			WorldData.CITY_SURFACE_FEATURE_TREE
		),
		"The foundation rollback fixture must add its tree through WorldData."
	)
	var object_version_before := object_state.object_version
	var workplace_version_before := city_state.workplace_state.workplace_version
	var container_version_before := accounting_state.container_version
	var public_storage_version_before := accounting_state.public_storage_version
	var keep := CityObjectSystem.register_completed_city_object_for_city_state(
		city_state,
		keep_values
	)
	var keep_id := int(keep.get("id", -1))
	_expect(
		keep_id > 0
		and city_world.get_tile(keep_top_left.x, keep_top_left.y).has(
			"surface_feature"
		)
		and not CityObjectSystem.rollback_completed_city_object_for_city_state(
			city_state,
			keep_id + 1
		)
		and CityObjectSystem.rollback_completed_city_object_for_city_state(
			city_state,
			keep_id
		)
		and object_state.objects.is_empty()
		and object_state.object_index_by_id.is_empty()
		and object_state.occupied_tiles.is_empty()
		and object_state.next_object_id == keep_id
		and object_state.object_version == object_version_before
		and city_state.workplace_state.workplace_version
		== workplace_version_before
		and accounting_state.container_version == container_version_before
		and accounting_state.public_storage_version
		== public_storage_version_before
		and city_world.get_tile(keep_top_left.x, keep_top_left.y).has(
			"surface_feature"
		),
		"Deferred Keep rollback must require the exact last ID and restore object, occupancy, allocation, versions, accounting, and untouched terrain exactly."
	)

	var committed_keep := CityObjectSystem.register_completed_city_object(
		keep_values
	)
	var committed_keep_id := int(committed_keep.get("id", -1))
	city_state.city_runtime_data.merge({
		"founded": true,
		"can_build": true,
		"foundation_top_left": keep_top_left,
		"foundation_size": committed_keep.get("size", Vector2i.ZERO),
		"foundation_object_id": committed_keep_id,
		"foundation_object_owner": "player",
	}, true)
	_expect(
		committed_keep_id > 0
		and CityObjectSystem.register_completed_city_object(
			keep_values
		).is_empty()
		and CityObjectSystem.register_completed_city_object_for_city_state(
			city_state,
			keep_values
		).is_empty()
		and CityObjectSystem.finalize_deferred_city_foundation_surface_features_for_city_state(
			city_state,
			committed_keep_id
		)
		and not city_world.get_tile(keep_top_left.x, keep_top_left.y).has(
			"surface_feature"
		),
		"A founded settlement must reject another Keep through both registration roots and finalize terrain only after founding commits."
	)

	object_state.objects.clear()
	object_state.object_index_by_id.clear()
	object_state.occupied_tiles.clear()
	var recovered_keep := (
		CityObjectSystem.register_recovered_city_foundation_object_for_city_state(
			city_state,
			_make_rectangle_request(
				CityObjectCatalog.CITY_OBJECT_CITY_CENTER,
				keep_top_left,
				city_world
			)
		)
	)
	_expect(
		int(recovered_keep.get("id", -1)) > 0
		and int(city_state.city_runtime_data.get("foundation_object_id", -1))
		== int(recovered_keep.get("id", -1)),
		"The narrow founded-Keep recovery path must validate local foundation facts and publish its replacement object ID only after success."
	)

	city_world = _reset_fixture(93_108, true)
	city_state = WorldPoliticalState.get_current_city_simulation_state()
	house_values = _make_rectangle_request(
		CityObjectCatalog.CITY_OBJECT_HOUSE,
		Vector2i(12, 12),
		city_world
	)
	var house_footprint := CityObjectSystem.make_rectangle_city_object_footprint_tiles(
		house_values["top_left"],
		house_values["size_tiles"]
	)
	house_values["footprint_tiles"] = house_footprint
	var site_id := 47
	var site := {
		"id": site_id,
		"target_kind": CityConstructionSystem.CITY_CONSTRUCTION_TARGET_NEW,
		"finalization_state": (
			CityConstructionSystem.CITY_CONSTRUCTION_FINALIZATION_STATE_AWAITING_CLEARANCE
		),
		"object_type": CityObjectCatalog.CITY_OBJECT_HOUSE,
		"owner": "player",
		"top_left": house_values["top_left"],
		"size": house_values["size_tiles"],
		"footprint_tiles": house_footprint,
	}
	city_state.construction_state.construction_sites = [site]
	city_state.construction_state.construction_site_index_by_id = {site_id: 0}
	for tile_position in house_footprint:
		city_state.construction_state.construction_site_id_by_tile[tile_position] = (
			site_id
		)
	house_values["allowed_construction_site_id"] = site_id
	var legacy_bypass := CityObjectSystem.register_completed_city_object(
		house_values
	)
	var explicit_bypass := (
		CityObjectSystem.register_completed_city_object_for_city_state(
			city_state,
			house_values
		)
	)
	city_state.city_runtime_data["founded"] = false
	city_state.city_runtime_data["can_build"] = false
	var authorized_completion := (
		CityObjectSystem.register_completed_city_object_from_construction_site_for_city_state(
			city_state,
			site_id,
			house_values
		)
	)
	_expect(
		legacy_bypass.is_empty()
		and explicit_bypass.is_empty()
		and not authorized_completion.is_empty(),
		"Caller-supplied site IDs must not bypass completed-object registration, while one exact authoritative preauthorized site may complete after local eligibility changes."
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
	var registration_record := CityObjectSystem.register_completed_city_object(
		_make_rectangle_request(
			CityObjectCatalog.CITY_OBJECT_HOUSE,
			Vector2i(4, 4),
			city_world
		)
	)
	var house_id := int(registration_record.get("id", -1))
	var footprint := CityObjectSystem.get_city_object_footprint_tiles(
		registration_record
	)
	var city_state: CitySettlementSimulationState = (
		WorldPoliticalState.get_current_city_simulation_state()
	)
	var state := CityObjectSystem.get_current_state()
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
	var active_registry_view := CityObjectSystem.get_city_objects()
	var explicit_registry_view := (
		CityObjectSystem.get_city_objects_for_city_state(city_state)
	)
	var active_by_id := CityObjectSystem.get_city_object_by_id(house_id)
	var explicit_by_id := (
		CityObjectSystem.get_city_object_by_id_for_city_state(
			city_state,
			house_id
		)
	)
	var active_at_tile := CityObjectSystem.get_city_object_at_tile(
		footprint[0]
	)
	var explicit_at_tile := (
		CityObjectSystem.get_city_object_at_tile_for_city_state(
			city_state,
			footprint[0]
		)
	)
	var public_footprint = active_by_id.get("footprint_tiles", [])
	var public_residents = active_by_id.get("resident_ids", [])
	var public_storage = active_by_id.get("stored_resources", {})

	_expect(
		registration_record.is_read_only()
		and active_registry_view[0].is_read_only()
		and explicit_registry_view[0].is_read_only()
		and active_by_id.is_read_only()
		and explicit_by_id.is_read_only()
		and active_at_tile.is_read_only()
		and explicit_at_tile.is_read_only()
		and public_footprint is Array
		and public_footprint.is_read_only()
		and public_residents is Array
		and public_residents.is_read_only()
		and public_storage is Dictionary
		and public_storage.is_read_only(),
		"Registration, active/explicit by-ID, at-tile, and nested public object records must be recursively read-only."
	)
	active_registry_view.clear()
	explicit_registry_view.clear()
	_expect(
		active_registry_view.is_empty()
		and explicit_registry_view.is_empty()
		and state.objects.size() == 1
		and int(state.objects[0].get("id", -1)) == house_id,
		"Active and explicit registry views must be shallow isolated outer copies."
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
	_expect(
		CityObjectSystem.write_city_object_at_index(
			0,
			CityObjectSystem.get_city_object_by_id_snapshot(house_id)
		),
		"The compatibility writer must accept an identical record as a no-op."
	)

	var compatibility_candidate := (
		CityObjectSystem.get_city_object_by_id_snapshot(house_id)
	)
	var caller_resident_ids: Array = compatibility_candidate.get(
		"resident_ids",
		[]
	).duplicate()
	caller_resident_ids.append(93_104)
	compatibility_candidate["resident_ids"] = caller_resident_ids
	var object_version_before_compatibility_write := state.object_version
	_expect(
		CityObjectSystem.write_city_object_at_index(
			0,
			compatibility_candidate
		)
		and state.object_version == object_version_before_compatibility_write,
		"The compatibility writer must accept one assignment-domain copy-on-write update without publishing a topology version."
	)
	caller_resident_ids.append(93_105)
	compatibility_candidate["resident_ids"] = []
	var committed_after_caller_mutation := (
		CityObjectSystem.get_city_object_by_id(house_id)
	)
	var committed_resident_ids = committed_after_caller_mutation.get(
		"resident_ids",
		[]
	)
	_expect(
		committed_after_caller_mutation.is_read_only()
		and committed_resident_ids is Array
		and committed_resident_ids.is_read_only()
		and committed_resident_ids == [93_104],
		"A successful compatibility write must detach and recursively freeze the caller record."
	)

	var stale_snapshot := CityObjectSystem.get_city_object_by_id_snapshot(
		house_id
	)
	var accounting_state := CityResourceAccountingSystem.get_current_state()
	var container_version_before := accounting_state.container_version
	_expect(
		CityResourceContainerSystem.add_resource_to_city_object_storage(
			house_id,
			WorldData.RESOURCE_FISH,
			1
		) == 1
		and accounting_state.container_version
		== container_version_before + 1,
		"The stale-snapshot fixture must commit one focused storage mutation."
	)
	var stale_resources: Dictionary = stale_snapshot.get(
		"stored_resources",
		{}
	)
	stale_resources[WorldData.RESOURCE_FISH] = 999
	stale_snapshot["resident_ids"] = [93_106]
	var live_after_stale_mutation := CityObjectSystem.get_city_object_by_id(
		house_id
	)
	_expect(
		not CityObjectSystem.write_city_object_at_index(0, stale_snapshot)
		and CityResourceContainerSystem.get_city_object_stored_resource_amount(
			live_after_stale_mutation,
			WorldData.RESOURCE_FISH
		) == 1
		and live_after_stale_mutation.get("resident_ids", []) == [93_104]
		and accounting_state.container_version
		== container_version_before + 1,
		"Mutating a stale snapshot must preserve newer storage, assignment, and focused versions."
	)

	var cross_domain_candidate := (
		CityObjectSystem.get_city_object_by_id_snapshot(house_id)
	)
	cross_domain_candidate["resident_ids"] = [93_107]
	cross_domain_candidate["stored_resources"] = {
		WorldData.RESOURCE_FISH: 2,
	}
	var state_before_rejections := state.objects.duplicate(true)
	var index_before_rejections := state.object_index_by_id.duplicate()
	var occupancy_before_rejections := state.occupied_tiles.duplicate()
	var version_before_rejections := state.object_version
	_expect(
		not CityObjectSystem.write_city_object_at_index(
			0,
			cross_domain_candidate
		),
		"The compatibility writer must reject a cross-domain assignment/storage replacement."
	)

	var topology_candidate := CityObjectSystem.get_city_object_by_id_snapshot(
		house_id
	)
	topology_candidate["top_left"] = Vector2i(20, 20)
	_expect(
		not CityObjectSystem.write_city_object_at_index(
			0,
			topology_candidate
		)
		and not CityObjectSystem.write_city_object_at_index_for_city_state(
			city_state,
			0,
			topology_candidate
		)
		and state.objects == state_before_rejections
		and state.object_index_by_id == index_before_rejections
		and state.occupied_tiles == occupancy_before_rejections
		and state.object_version == version_before_rejections,
		"Active/explicit compatibility writes must reject topology changes atomically."
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


func _reset_fixture(seed: int, founded: bool = true) -> WorldData:
	WorldPoliticalState.reset_state()
	WorldData.reset_runtime_session_state()
	SimulationClock.start_new_game()
	var city_world := WorldData.new()
	city_world.setup(TEST_WORLD_SIZE.x, TEST_WORLD_SIZE.y, seed)

	for y in range(city_world.height):
		for x in range(city_world.width):
			var tile := city_world.make_default_tile()
			tile["terrain"] = WorldData.TERRAIN_LAND
			tile["biome"] = WorldData.BIOME_PLAIN
			tile["is_land"] = true
			tile["fertility"] = 50.0
			city_world.set_tile(x, y, tile)

	WorldData.store_city_world_save(city_world, seed)
	var city_state = WorldPoliticalState.get_current_city_simulation_state()
	city_state.city_runtime_data.clear()
	city_state.city_runtime_data.merge({
		"founded": founded,
		"can_build": founded,
	}, true)
	return city_world


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error("City object system test: " + message)
