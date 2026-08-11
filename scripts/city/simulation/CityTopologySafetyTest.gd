extends Node

const CityConstructionSystemScript = preload(
	"res://scripts/city/simulation/systems/CityConstructionSystem.gd"
)
const CitizenMovementSystemScript = preload(
	"res://scripts/citizens/simulation/systems/CitizenMovementSystem.gd"
)

const TEST_WORLD_SIZE := Vector2i(32, 24)
const TEST_WORLD_SEED: int = 92_417

var failure_count: int = 0
var test_primary_culture_id: int = -1


func _ready() -> void:
	_test_low_level_topology_gate_is_generic()
	_test_construction_waits_for_footprint_clearance()
	_test_one_bad_mover_does_not_freeze_the_batch()
	_test_legacy_occupant_can_escape_but_not_reenter()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City topology safety tests failed: " + str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City topology safety tests passed.")
	get_tree().quit(0)


func _test_low_level_topology_gate_is_generic() -> void:
	print("Topology test: generic authoritative placement gate")

	for object_type in [
		CityObjectCatalog.CITY_OBJECT_HOUSE,
		CityObjectCatalog.CITY_OBJECT_STOCKPILE,
		CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS,
	]:
		var city_world := _reset_fixture()
		var top_left := Vector2i(10, 8)
		var citizen := _add_citizen(top_left)
		var created_object := CityObjectSystem.add_city_object({
			"object_type": object_type,
			"top_left": top_left,
			"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
				object_type
			),
			"object_owner": "player",
			"city_world": city_world,
		})

		_expect(
			created_object.is_empty(),
			"The low-level topology gate must reject "
				+ object_type
				+ " while a living citizen occupies its footprint."
		)
		_expect(
			CityObjectSystem.get_city_object_at_tile(top_left).is_empty()
			and citizen.get("city_tile_position") == top_left,
			"Rejected topology mutations must leave both object and citizen state untouched."
		)

	var road_world := _reset_fixture()
	var road_tile := Vector2i(10, 8)
	var road_citizen := _add_citizen(road_tile)
	var road := CityObjectSystem.add_city_road_object(
		[road_tile],
		"player",
		road_world
	)
	_expect(
		not road.is_empty()
		and CityNavigationSystem.is_city_tile_walkable_for_citizen(
			road_world,
			road_tile,
			int(road_citizen.get("id", -1))
		),
		"A road may complete beneath a citizen because it preserves walkability."
	)


func _test_construction_waits_for_footprint_clearance() -> void:
	print("Topology test: staged construction finalization")
	var city_world := _reset_fixture()
	var top_left := Vector2i(12, 8)
	var fishery_size := CityObjectCatalog.get_city_object_size_for_type(
		CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS
	)
	var site := CityConstructionSystemScript.create_rectangular_site({
		"object_type": CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS,
		"top_left": top_left,
		"size_tiles": fishery_size,
		"object_owner": "player",
		"city_world": city_world,
	})
	var site_id := int(site.get("id", -1))
	_expect(site_id > 0, "The fixture must create a Fishing Grounds site.")

	if site_id <= 0:
		return

	_expect(
		CityConstructionSystemScript.add_resource_to_city_construction_site(
			site_id,
			WorldData.RESOURCE_LUMBER,
			10
		) == 10
		and CityConstructionSystemScript.add_resource_to_city_construction_site(
			site_id,
			WorldData.RESOURCE_STONE,
			4
		) == 4,
		"The finalization fixture must contain the complete physical recipe."
	)
	CityConstructionSystemScript.refresh_city_construction_site(site_id)
	site = CityConstructionSystem.get_city_construction_site_by_id(site_id)
	site["completed_labor_minutes"] = int(
		site.get("required_labor_minutes", 1)
	)
	_expect(
		CityConstructionSystemScript.update_city_construction_site(site),
		"The fixture must mark labor complete."
	)

	var trapped_tile := top_left + Vector2i.ONE
	var trapped_citizen := _add_citizen(trapped_tile)
	var trapped_id := int(trapped_citizen.get("id", -1))
	var unrelated_citizen := _add_citizen(Vector2i(3, 3))
	var unrelated_id := int(unrelated_citizen.get("id", -1))
	var unrelated_path := [
		Vector2i(3, 3),
		Vector2i(4, 3),
		Vector2i(5, 3),
		Vector2i(6, 3),
		Vector2i(7, 3),
	]
	_expect(
		CityCitizenMovementRuntimeSystem.assign_city_citizen_movement_order(
			unrelated_id,
			unrelated_path
		),
		"The fixture must start an unrelated mover."
	)
	var object_state := CityObjectSystem.get_current_state()
	var object_count_before := object_state.objects.size()
	var next_object_id_before := object_state.next_object_id
	var object_version_before := object_state.object_version

	var immediate_completion := (
		CityConstructionSystemScript.complete_city_construction_site(site_id)
	)
	var pending_site := CityConstructionSystem.get_city_construction_site_by_id(site_id)
	var trapped_after_request := CityCitizenRegistrySystem.get_city_citizen_by_id(trapped_id)

	_expect(
		immediate_completion.is_empty()
		and not pending_site.is_empty()
		and str(
			pending_site.get(
				"finalization_state",
				CityConstructionSystem.CITY_CONSTRUCTION_FINALIZATION_STATE_NONE
			)
		) == CityConstructionSystem.CITY_CONSTRUCTION_FINALIZATION_STATE_AWAITING_CLEARANCE,
		"Completed labor must enter durable clearance instead of creating a building over a citizen."
	)
	_expect(
		trapped_after_request.get("city_tile_position") == trapped_tile
		and str(trapped_after_request.get("movement_state", ""))
		== CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_MOVING,
		"Clearance must give the citizen a real route without teleporting them."
	)
	_expect(
		CityConstructionSystem.get_city_construction_site_reserved_resource_amount(
			site_id,
			WorldData.RESOURCE_LUMBER
		) == 10
		and CityConstructionSystem.get_city_construction_site_reserved_resource_amount(
			site_id,
			WorldData.RESOURCE_STONE
		) == 4,
		"Materials must remain physical and reserved while clearance is pending."
	)

	for tick_index in range(1, 48):
		CitizenMovementSystemScript.run_tick(tick_index, 2)
		CityConstructionSystemScript.refresh_all_city_construction_sites()

		if CityConstructionSystem.get_city_construction_site_by_id(site_id).is_empty():
			break

	var completed_fishery := CityObjectSystem.get_city_object_at_tile(top_left)
	var trapped_after_completion := CityCitizenRegistrySystem.get_city_citizen_by_id(trapped_id)
	var unrelated_after_completion := CityCitizenRegistrySystem.get_city_citizen_by_id(
		unrelated_id
	)
	var footprint_tiles := CityObjectSystem.make_rectangle_city_object_footprint_tiles(
		top_left,
		fishery_size
	)
	var completed_object_id := int(completed_fishery.get("id", -1))

	_expect(
		CityConstructionSystem.get_city_construction_site_by_id(site_id).is_empty()
		and str(completed_fishery.get("type", ""))
		== CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS,
		"The Fishing Grounds must finalize once its footprint is physically clear."
	)
	_expect(
		is_same(CityObjectSystem.get_current_state().objects, object_state.objects)
		and is_same(
			CityObjectSystem.get_current_state().object_index_by_id,
			object_state.object_index_by_id
		)
		and is_same(
			CityObjectSystem.get_current_state().occupied_tiles,
			object_state.occupied_tiles
		),
		"Construction finalization must mutate the selected object state by identity."
	)
	_expect(
		object_state.objects.size() == object_count_before + 1
		and completed_object_id == next_object_id_before
		and int(
			object_state.object_index_by_id.get(completed_object_id, -1)
		) == object_count_before
		and object_state.next_object_id == next_object_id_before + 1
		and object_state.object_version == object_version_before + 1,
		"Construction finalization must register exactly one indexed object and advance its state once."
	)
	var finalized_count := object_state.objects.size()
	var finalized_next_id := object_state.next_object_id
	var finalized_version := object_state.object_version
	CityConstructionSystemScript.refresh_all_city_construction_sites()
	CityConstructionSystemScript.refresh_all_city_construction_sites()
	_expect(
		object_state.objects.size() == finalized_count
		and object_state.next_object_id == finalized_next_id
		and object_state.object_version == finalized_version,
		"Refreshing after finalization must not register the completed object a second time."
	)
	var footprint_is_registered := true
	for tile_position in footprint_tiles:
		if int(
			object_state.occupied_tiles.get(tile_position, -1)
		) != completed_object_id:
			footprint_is_registered = false
			break
	_expect(
		footprint_is_registered,
		"Construction finalization must register every footprint tile in object occupancy."
	)
	_expect(
		not footprint_tiles.has(
			trapped_after_completion.get(
				"city_tile_position",
				CityCitizens.INVALID_CITY_TILE_POSITION
			)
		),
		"The displaced citizen must finish outside the completed footprint."
	)
	_expect(
		unrelated_after_completion.get("city_tile_position")
		!= Vector2i(3, 3),
		"An unrelated citizen must keep moving while clearance occurs."
	)


func _test_one_bad_mover_does_not_freeze_the_batch() -> void:
	print("Topology test: movement fault containment")
	var city_world := _reset_fixture()
	var valid_citizen := _add_citizen(Vector2i(4, 4))
	var invalid_citizen := _add_citizen(Vector2i(8, 4))
	var valid_id := int(valid_citizen.get("id", -1))
	var invalid_id := int(invalid_citizen.get("id", -1))
	var valid_update: Dictionary = valid_citizen.duplicate(true)
	var invalid_update: Dictionary = invalid_citizen.duplicate(true)
	var commit_result := CityCitizenMovementRuntimeSystem.commit_city_citizen_movement_tick(
		city_world,
		[
			{
				"citizen_id": valid_id,
				"citizen": valid_update,
				"final_tile": Vector2i(5, 4),
				"traversed_tiles": [Vector2i(4, 4), Vector2i(5, 4)],
			},
			{
				"citizen_id": invalid_id,
				"citizen": invalid_update,
				"final_tile": Vector2i(-1, -1),
				"traversed_tiles": [Vector2i(8, 4)],
			},
		],
		[]
	)

	_expect(
		bool(commit_result.get("success", false))
		and int(commit_result.get("updated_citizen_count", 0)) == 1
		and int(commit_result.get("rejected_update_count", 0)) == 1,
		"The movement transaction must commit valid citizens and quarantine only the bad update."
	)
	_expect(
		CityCitizenSpatialSystem.get_city_citizen_tile_position(valid_id) == Vector2i(5, 4)
		and CityCitizenSpatialSystem.get_city_citizen_tile_position(invalid_id) == Vector2i(8, 4),
		"A rejected mover must not roll back a valid mover or move itself illegally."
	)
	_expect(
		str(
			CityCitizenRegistrySystem.get_city_citizen_by_id(invalid_id).get(
				"movement_state",
				""
			)
		) == CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_BLOCKED,
		"The bad mover must enter an explicit recoverable quarantine state."
	)


func _test_legacy_occupant_can_escape_but_not_reenter() -> void:
	print("Topology test: defensive legacy escape")
	var city_world := _reset_fixture()
	var top_left := Vector2i(12, 8)
	var fishery := CityObjectSystem.add_city_object({
		"object_type": CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS,
		"top_left": top_left,
		"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
			CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS
		),
		"object_owner": "player",
		"city_world": city_world,
	})
	var trapped := _add_citizen(Vector2i(5, 5))
	var outsider := _add_citizen(Vector2i(6, 5))
	var trapped_id := int(trapped.get("id", -1))
	var trapped_tile := top_left + Vector2i.ONE
	trapped["city_tile_position"] = trapped_tile
	CityCitizenSpatialSystem.rebuild_city_citizen_spatial_index()

	_expect(
		not fishery.is_empty()
		and CityNavigationSystem.is_city_tile_walkable_for_citizen(
			city_world,
			trapped_tile,
			trapped_id
		),
		"A citizen already inside corrupted legacy topology must be allowed to start escaping."
	)
	_expect(
		not CityNavigationSystem.is_city_tile_walkable_for_citizen(
			city_world,
			trapped_tile,
			int(outsider.get("id", -1))
		),
		"The recovery rule must not let an outside citizen enter the blocked building."
	)


func _reset_fixture() -> WorldData:
	WorldData.reset_runtime_session_state()
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
			tile.erase("surface_feature")

	city_world.mark_tile_data_changed()
	WorldData.store_city_world_save(city_world, TEST_WORLD_SEED)
	var primary_culture := WorldData.create_culture(
		"Topology Safety Test Culture"
	)
	test_primary_culture_id = int(primary_culture.get("id", -1))
	WorldData.official_city_name = "Topology Safety Test City"
	WorldData.official_founding_culture_id = test_primary_culture_id
	WorldData.player_city_founded = true
	WorldPoliticalState.replace_current_city_runtime_data({
		"id": 1,
		"name": "Topology Safety Test City",
		"primary_culture_id": test_primary_culture_id,
		"city_world_seed": TEST_WORLD_SEED,
		"city_map_size": TEST_WORLD_SIZE,
		"can_build": true,
		"founded": true,
	})
	return city_world


func _add_citizen(tile_position: Vector2i) -> Dictionary:
	return CityCitizenRegistrySystem.add_city_citizen(
		"",
		tile_position,
		CityCitizens.CITY_CITIZEN_SEX_FEMALE,
		test_primary_culture_id
	)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error(message)
