extends Node

const SHARED_OBJECT_TOP_LEFT := Vector2i(8, 8)
const TEST_WORLD_SIZE := Vector2i(24, 24)

var failure_count: int = 0


func _ready() -> void:
	_test_navigation_cache_is_settlement_owned()
	_test_base_land_component_guard_and_invalidation()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City navigation state isolation test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City navigation state isolation test passed.")
	get_tree().quit(0)


func _test_navigation_cache_is_settlement_owned() -> void:
	WorldData.reset_runtime_session_state()
	var culture := WorldData.create_culture("Navigation Isolation Culture")
	var culture_id := int(culture.get("id", -1))
	var polity := WorldPoliticalState.create_polity({
		"name": "Navigation Isolation Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})
	var polity_id := int(polity.get("id", -1))
	var city_a := _create_city("Navigation City A", polity_id, Vector2i(1, 1))
	var city_b := _create_city("Navigation City B", polity_id, Vector2i(8, 8))

	_expect(
		culture_id > 0 and not city_a.is_empty() and not city_b.is_empty(),
		"The isolation fixture must create two Cities."
	)
	if city_a.is_empty() or city_b.is_empty():
		return

	var state_a := _exercise_city(int(city_a["id"]), culture_id, 71_101)
	var state_b := _exercise_city(int(city_b["id"]), culture_id, 71_102)
	if state_a.is_empty() or state_b.is_empty():
		return

	var navigation_state_a: CityNavigationState = state_a["navigation_state"]
	var navigation_state_b: CityNavigationState = state_b["navigation_state"]
	var city_state_a: CitySettlementSimulationState = state_a["city_state"]
	var city_state_b: CitySettlementSimulationState = state_b["city_state"]
	_expect(
		not is_same(navigation_state_a, navigation_state_b)
		and not is_same(
			navigation_state_a.object_access_tile_cache,
			navigation_state_b.object_access_tile_cache
		)
		and not is_same(
			navigation_state_a.base_land_component_world,
			navigation_state_b.base_land_component_world
		)
		and not is_same(
			navigation_state_a.base_land_component_membership,
			navigation_state_b.base_land_component_membership
		)
		and not navigation_state_a.base_land_component_membership.is_empty()
		and not navigation_state_b.base_land_component_membership.is_empty(),
		"Each City must own an independent navigation cache and dictionary."
	)
	_expect(
		int(state_a.get("object_id", -1)) == int(state_b.get("object_id", -2)),
		"Both Cities should safely reuse the same settlement-local object ID."
	)

	var object_id := int(state_a.get("object_id", -1))
	var cache_a: Dictionary = navigation_state_a.object_access_tile_cache
	var cache_b: Dictionary = navigation_state_b.object_access_tile_cache
	_expect(
		cache_a.has(object_id)
		and cache_b.has(object_id)
		and int(cache_a[object_id].get("world_instance_id", 0))
		!= int(cache_b[object_id].get("world_instance_id", 0)),
		"Equal local object IDs must cache against their own City world identity."
	)

	_expect(
		WorldPoliticalState.set_active_settlement(int(city_a["id"]))
		and is_same(
			CityNavigationSystem.get_state_for_city_state(city_state_a),
			navigation_state_a
		),
		"Switching to City A must select City A's navigation owner directly."
	)
	CityNavigationSystem.reset_city_navigation_state_for_city_state(city_state_a)
	_expect(
		navigation_state_a.object_access_tile_cache.is_empty()
		and navigation_state_a.base_land_component_membership.is_empty()
		and not navigation_state_b.object_access_tile_cache.is_empty()
		and not navigation_state_b.base_land_component_membership.is_empty(),
		"Resetting City A navigation state must not clear City B."
	)

	_expect(
		WorldPoliticalState.set_active_settlement(int(city_b["id"]))
		and is_same(
			CityNavigationSystem.get_state_for_city_state(city_state_b),
			navigation_state_b
		)
		and navigation_state_b.object_access_tile_cache.has(object_id)
		and not navigation_state_b.base_land_component_membership.is_empty(),
		"A -> B must restore City B's cache without capture/apply copying."
	)
	_expect(
		WorldPoliticalState.set_active_settlement(int(city_a["id"]))
		and CityNavigationSystem.get_state_for_city_state(
			city_state_a
		).object_access_tile_cache.is_empty(),
		"B -> A must preserve City A's independent cleared cache."
	)
	_expect(
		WorldPoliticalState.set_active_settlement(int(city_b["id"]))
		and CityNavigationSystem.get_state_for_city_state(
			city_state_b
		).object_access_tile_cache.has(object_id),
		"A -> B -> A -> B must preserve City B navigation state."
	)


func _test_base_land_component_guard_and_invalidation() -> void:
	WorldData.reset_runtime_session_state()
	var culture := WorldData.create_culture("Navigation Component Culture")
	var polity := WorldPoliticalState.create_polity({
		"name": "Navigation Component Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": int(culture.get("id", -1)),
	})
	var city := _create_city(
		"Navigation Component City",
		int(polity.get("id", -1)),
		Vector2i(3, 3)
	)

	_expect(
		not city.is_empty()
		and WorldPoliticalState.set_active_settlement(int(city.get("id", -1))),
		"The component fixture must create and activate one City."
	)
	if city.is_empty():
		return
	var city_state: CitySettlementSimulationState = (
		WorldPoliticalState.get_city_simulation_state(
			int(city.get("id", -1))
		)
	)
	_expect(
		city_state is CitySettlementSimulationState,
		"The component fixture must expose its settlement-owned City state."
	)
	if not city_state is CitySettlementSimulationState:
		return
	var navigation_state := CityNavigationSystem.get_state_for_city_state(
		city_state
	)

	var direct_world := _make_world(4, 4, 71_201)
	WorldData.store_city_world_for_state(city_state, direct_world, 71_201)
	var direct_result := CityNavigationSystem.find_path_to_any_city_tile_for_city_state(city_state, {
		"city_world": direct_world,
		"start_tile": Vector2i(1, 1),
		"destination_tiles": [Vector2i(2, 2)],
	})
	_expect(
		bool(direct_result.get("success", false))
		and direct_result.get("path", [])
		== [Vector2i(1, 1), Vector2i(2, 2)]
		and int(direct_result.get("path_cost", -1))
		== CityCitizens.CITY_CITIZEN_DIAGONAL_MOVEMENT_COST
		and int(direct_result.get("expanded_node_count", 0)) == 2,
		"A reachable direct path must retain its exact path, cost, and A* work."
	)

	var disconnected_world := _make_disconnected_world(8, 5, 71_202)
	WorldData.store_city_world_for_state(city_state, disconnected_world, 71_202)
	var limited_result := CityNavigationSystem.find_path_to_any_city_tile_for_city_state(city_state, {
		"city_world": disconnected_world,
		"start_tile": Vector2i(1, 2),
		"destination_tiles": [Vector2i(6, 2)],
		"max_expanded_nodes": 1,
	})
	_expect(
		not bool(limited_result.get("success", true))
		and str(limited_result.get("status", ""))
		== CityNavigationSystem.PATH_STATUS_SEARCH_LIMIT_REACHED
		and int(limited_result.get("expanded_node_count", -1)) == 1,
		"A bounded search must retain its original search-limit result."
	)
	var disconnected_result := (
		CityNavigationSystem.find_path_to_any_city_tile_for_city_state(city_state, {
			"city_world": disconnected_world,
			"start_tile": Vector2i(1, 2),
			"destination_tiles": [Vector2i(6, 2)],
			"max_expanded_nodes": 40,
		})
	)
	var disconnected_version := disconnected_world.tile_data_version
	_expect(
		not bool(disconnected_result.get("success", true))
		and str(disconnected_result.get("status", ""))
		== CityNavigationSystem.PATH_STATUS_UNREACHABLE
		and int(disconnected_result.get("expanded_node_count", -1)) == 0,
		"Separate permissive land components must reject before A* expansion."
	)

	var corner_world := WorldData.new()
	corner_world.setup(3, 3, 71_204)
	_set_land_tile(corner_world, Vector2i(0, 0))
	_set_land_tile(corner_world, Vector2i(1, 1))
	WorldData.store_city_world_for_state(city_state, corner_world, 71_204)
	var corner_result := CityNavigationSystem.find_path_to_any_city_tile_for_city_state(city_state, {
		"city_world": corner_world,
		"start_tile": Vector2i(0, 0),
		"destination_tiles": [Vector2i(1, 1)],
		"max_expanded_nodes": 9,
	})
	_expect(
		not bool(corner_result.get("success", true))
		and str(corner_result.get("status", ""))
		== CityNavigationSystem.PATH_STATUS_UNREACHABLE
		and int(corner_result.get("expanded_node_count", -1)) == 0,
		"Corner-touching land must reject before A* because legal diagonal traversal requires both side tiles."
	)
	var corner_version_before_bridge := corner_world.tile_data_version
	_expect(
		corner_world.set_tile_terrain(
			Vector2i(1, 0),
			WorldData.TERRAIN_LAND
		)
		and not corner_world.set_tile_terrain(
			Vector2i(1, 0),
			WorldData.TERRAIN_LAND
		)
		and corner_world.set_tile_terrain(
			Vector2i(0, 1),
			WorldData.TERRAIN_LAND
		)
		and corner_world.tile_data_version
		== corner_version_before_bridge + 2,
		"Each effective terrain mutation must publish exactly once and an identical retry must be a no-op."
	)
	var bridged_corner_result := (
		CityNavigationSystem.find_path_to_any_city_tile_for_city_state(
			city_state,
			{
				"city_world": corner_world,
				"start_tile": Vector2i(0, 0),
				"destination_tiles": [Vector2i(1, 1)],
				"max_expanded_nodes": 9,
			}
		)
	)
	_expect(
		bool(bridged_corner_result.get("success", false))
		and int(bridged_corner_result.get("expanded_node_count", 0)) > 0,
		"A versioned cardinal bridge must invalidate the corner rejection and run the original A*."
	)
	WorldData.store_city_world_for_state(city_state, disconnected_world, 71_202)
	CityNavigationSystem.find_path_to_any_city_tile_for_city_state(city_state, {
		"city_world": disconnected_world,
		"start_tile": Vector2i(1, 2),
		"destination_tiles": [Vector2i(6, 2)],
		"max_expanded_nodes": 40,
	})
	_expect(
		is_same(
			navigation_state.base_land_component_world,
			disconnected_world
		)
		and navigation_state.base_land_component_world_size == Vector2i(8, 5)
		and navigation_state.base_land_component_tile_data_version
		== disconnected_version
		and navigation_state.base_land_component_seed_tile == Vector2i(1, 2),
		"The component cache key must record exact world, size, and tile version."
	)

	_expect(
		disconnected_world.set_tile_terrain(
			Vector2i(3, 2),
			WorldData.TERRAIN_LAND
		)
		and disconnected_world.set_tile_terrain(
			Vector2i(4, 2),
			WorldData.TERRAIN_LAND
		)
		and not disconnected_world.set_tile_terrain(
			Vector2i(4, 2),
			WorldData.TERRAIN_LAND
		)
		and disconnected_world.tile_data_version
		== disconnected_version + 2,
		"Opening a bridge must publish one broad tile-data change per effective terrain mutation."
	)
	var bridged_result := (
		CityNavigationSystem.find_path_to_any_city_tile_for_city_state(city_state, {
			"city_world": disconnected_world,
			"start_tile": Vector2i(1, 2),
			"destination_tiles": [Vector2i(6, 2)],
		})
	)
	_expect(
		bool(bridged_result.get("success", false))
		and int(bridged_result.get("expanded_node_count", 0)) > 0
		and navigation_state.base_land_component_tile_data_version
		== disconnected_world.tile_data_version,
		"The terrain owner API must invalidate the cached rejection before pathfinding."
	)

	var resized_tile_count := 9 * 5
	while disconnected_world.tile_data_version < resized_tile_count:
		disconnected_world.mark_tile_data_changed()
	var retained_version := disconnected_world.tile_data_version
	disconnected_world.setup(9, 5, 71_203)
	_fill_world_with_land(disconnected_world)
	while disconnected_world.tile_data_version < retained_version:
		disconnected_world.mark_tile_data_changed()
	var resized_result := CityNavigationSystem.find_path_to_any_city_tile_for_city_state(city_state, {
		"city_world": disconnected_world,
		"start_tile": Vector2i(1, 2),
		"destination_tiles": [Vector2i(7, 2)],
	})
	_expect(
		bool(resized_result.get("success", false))
		and disconnected_world.tile_data_version == retained_version
		and navigation_state.base_land_component_world_size == Vector2i(9, 5)
		and navigation_state.base_land_component_membership.size() == 45,
		"A same-instance size change must invalidate even at the same version."
	)


func _exercise_city(
	city_id: int,
	culture_id: int,
	world_seed: int
) -> Dictionary:
	_expect(
		WorldPoliticalState.set_active_settlement(city_id),
		"The City under test must become active."
	)
	if WorldPoliticalState.active_settlement_id != city_id:
		return {}

	var city_state: CitySettlementSimulationState = (
		WorldPoliticalState.get_city_simulation_state(city_id)
	)
	_expect(
		city_state is CitySettlementSimulationState,
		"The navigation fixture must expose its settlement-owned City state."
	)
	if not city_state is CitySettlementSimulationState:
		return {}
	var city_world := _make_world(TEST_WORLD_SIZE.x, TEST_WORLD_SIZE.y, world_seed)
	_expect(
		WorldData.store_city_world_for_state(city_state, city_world, world_seed),
		"The navigation fixture must store its world on the exact City owner."
	)
	var settlement := WorldPoliticalState.get_settlement(city_id)
	city_state.city_runtime_data.clear()
	city_state.city_runtime_data.merge({
		"name": str(settlement.get("name", "Navigation City")),
		"primary_culture_id": culture_id,
		"founded": true,
		"can_build": true,
	}, true)
	var city_object := (
		CityObjectSystem.register_completed_city_object_for_city_state(
			city_state,
			{
				"object_type": CityObjectCatalog.CITY_OBJECT_HOUSE,
				"top_left": SHARED_OBJECT_TOP_LEFT,
				"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
					CityObjectCatalog.CITY_OBJECT_HOUSE
				),
				"object_owner": "player",
				"city_world": city_world,
			}
		)
	)
	var object_id := int(city_object.get("id", -1))
	var access_tiles := CityNavigationSystem.get_city_object_access_tiles_for_city_state(
		city_state,
		city_world,
		city_object
	)
	var path_result := CityNavigationSystem.find_path_to_any_city_tile_for_city_state(city_state, {
		"city_world": city_world,
		"start_tile": Vector2i(1, 1),
		"destination_tiles": [Vector2i(2, 2)],
	})
	var navigation_state := CityNavigationSystem.get_state_for_city_state(city_state)

	_expect(
		object_id > 0
		and not access_tiles.is_empty()
		and bool(path_result.get("success", false))
		and navigation_state.object_access_tile_cache.has(object_id)
		and not navigation_state.base_land_component_membership.is_empty(),
		"Access-tile lookup must populate the target City's navigation cache."
	)
	if object_id <= 0 or access_tiles.is_empty():
		return {}

	return {
		"city_id": city_id,
		"city_state": city_state,
		"object_id": object_id,
		"world": city_world,
		"navigation_state": navigation_state,
		"access_tiles": access_tiles,
	}


func _create_city(
	city_name: String,
	polity_id: int,
	region_center: Vector2i
) -> Dictionary:
	return WorldPoliticalState.create_settlement({
		"name": city_name,
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": polity_id,
		"world_region_top_left": region_center,
		"world_region_center": region_center,
		"world_region_size": 1,
		"simulation_backend_kind": (
			SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE
		),
	})


func _make_world(width: int, height: int, seed_value: int) -> WorldData:
	var world := WorldData.new()
	world.setup(width, height, seed_value)
	_fill_world_with_land(world)
	return world


func _make_disconnected_world(
	width: int,
	height: int,
	seed_value: int
) -> WorldData:
	var world := WorldData.new()
	world.setup(width, height, seed_value)

	for y in range(height):
		for x in range(width):
			if x <= 2 or x >= width - 3:
				_set_land_tile(world, Vector2i(x, y))

	return world


func _fill_world_with_land(world: WorldData) -> void:
	for y in range(world.height):
		for x in range(world.width):
			_set_land_tile(world, Vector2i(x, y))


func _set_land_tile(world: WorldData, tile_position: Vector2i) -> void:
	world.set_tile(tile_position.x, tile_position.y, {
		"fertility": 50.0,
		"elevation": 0.2,
		"temperature": 0.5,
		"precipitation": 0.5,
		"terrain": WorldData.TERRAIN_LAND,
		"biome": WorldData.BIOME_PLAIN,
		"resource": WorldData.RESOURCE_NONE,
		"is_land": true,
	})


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error("City navigation state isolation test: " + message)
