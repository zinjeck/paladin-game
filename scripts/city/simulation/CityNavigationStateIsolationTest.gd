extends Node

const SHARED_OBJECT_TOP_LEFT := Vector2i(8, 8)
const TEST_WORLD_SIZE := Vector2i(24, 24)

var failure_count: int = 0


func _ready() -> void:
	_test_navigation_cache_is_settlement_owned()
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

	var state_a := _exercise_city(int(city_a["id"]), 71_101)
	var state_b := _exercise_city(int(city_b["id"]), 71_102)
	if state_a.is_empty() or state_b.is_empty():
		return

	var navigation_state_a: CityNavigationState = state_a["navigation_state"]
	var navigation_state_b: CityNavigationState = state_b["navigation_state"]
	_expect(
		not is_same(navigation_state_a, navigation_state_b)
		and not is_same(
			navigation_state_a.object_access_tile_cache,
			navigation_state_b.object_access_tile_cache
		),
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
		and is_same(CityNavigationSystem.get_current_state(), navigation_state_a),
		"Switching to City A must select City A's navigation owner directly."
	)
	CityNavigationSystem.reset_city_navigation_state()
	_expect(
		navigation_state_a.object_access_tile_cache.is_empty()
		and not navigation_state_b.object_access_tile_cache.is_empty(),
		"Resetting City A navigation state must not clear City B."
	)

	_expect(
		WorldPoliticalState.set_active_settlement(int(city_b["id"]))
		and is_same(CityNavigationSystem.get_current_state(), navigation_state_b)
		and navigation_state_b.object_access_tile_cache.has(object_id),
		"A -> B must restore City B's cache without capture/apply copying."
	)
	_expect(
		WorldPoliticalState.set_active_settlement(int(city_a["id"]))
		and CityNavigationSystem.get_current_state().object_access_tile_cache.is_empty(),
		"B -> A must preserve City A's independent cleared cache."
	)
	_expect(
		WorldPoliticalState.set_active_settlement(int(city_b["id"]))
		and CityNavigationSystem.get_current_state().object_access_tile_cache.has(object_id),
		"A -> B -> A -> B must preserve City B navigation state."
	)


func _exercise_city(city_id: int, world_seed: int) -> Dictionary:
	_expect(
		WorldPoliticalState.set_active_settlement(city_id),
		"The City under test must become active."
	)
	if WorldPoliticalState.active_settlement_id != city_id:
		return {}

	var city_world := _make_world(TEST_WORLD_SIZE.x, TEST_WORLD_SIZE.y, world_seed)
	WorldPoliticalState.set_current_city_world(city_world)
	WorldPoliticalState.set_current_city_seed(world_seed)
	var city_object := CityObjectSystem.register_completed_city_object({
		"object_type": WorldData.CITY_OBJECT_HOUSE,
		"top_left": SHARED_OBJECT_TOP_LEFT,
		"size_tiles": WorldData.get_city_object_size_for_type(WorldData.CITY_OBJECT_HOUSE),
		"object_owner": "player",
		"city_world": city_world,
	})
	var object_id := int(city_object.get("id", -1))
	var access_tiles := CityNavigationSystem.get_city_object_access_tiles(
		city_world,
		city_object
	)
	var navigation_state := CityNavigationSystem.get_current_state()

	_expect(
		object_id > 0
		and not access_tiles.is_empty()
		and navigation_state.object_access_tile_cache.has(object_id),
		"Access-tile lookup must populate the active City's navigation cache."
	)
	if object_id <= 0 or access_tiles.is_empty():
		return {}

	return {
		"city_id": city_id,
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
	push_error("City navigation state isolation test: " + message)
