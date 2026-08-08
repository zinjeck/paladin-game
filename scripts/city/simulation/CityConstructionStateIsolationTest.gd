extends Node

var failure_count: int = 0


func _ready() -> void:
	_run_isolation_test()
	WorldPoliticalState.reset_state()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City construction-state isolation test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City construction-state isolation test passed.")
	get_tree().quit(0)


func _run_isolation_test() -> void:
	WorldPoliticalState.reset_state()
	WorldData.reset_runtime_session_state()

	var world := _make_world(8, 8, 86_001)
	var locked := WorldData.lock_world_save({
		"source_world": world,
		"region_top_left": Vector2i(1, 1),
		"region_center": Vector2i(2, 2),
		"region_size": 3,
		"world_scene_path": "res://scenes/GameSession.tscn",
		"city_scene_path": "res://scenes/CityScreen.tscn",
		"city_name": "Construction Isolation City",
		"culture_name": "Construction Isolation Culture",
	})
	_expect(locked, "Fixture must lock the founding world.")
	if not locked:
		return
	_expect(
		WorldPoliticalState.synchronize_foundation_with_world_data(),
		"Founding must establish the player City."
	)

	var player_polity := WorldPoliticalState.get_player_polity()
	var player_city_id := int(player_polity.get("capital_settlement_id", -1))
	var player_state = WorldPoliticalState.get_city_simulation_state(player_city_id)
	_expect(
		player_state != null
		and player_state.construction_state is CityConstructionState,
		"Player City must own a construction state."
	)
	if player_state == null:
		return

	WorldData.city_construction_sites = [{"id": 41, "test_owner": "player"}]
	WorldData.city_construction_site_index_by_id = {41: 0}
	WorldData.city_construction_site_id_by_tile = {Vector2i(2, 2): 41}
	WorldData.next_city_construction_site_id = 42
	WorldData.city_construction_version = 6

	var cpu_culture := WorldData.create_culture("Construction CPU Culture")
	var cpu_polity := WorldPoliticalState.create_polity({
		"name": "Construction CPU Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": int(cpu_culture.get("id", -1)),
	})
	var cpu_city := WorldPoliticalState.create_settlement({
		"name": "Construction CPU City",
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": int(cpu_polity.get("id", -1)),
		"world_region_top_left": Vector2i(5, 5),
		"world_region_center": Vector2i(5, 5),
		"world_region_size": 1,
		"simulation_backend_kind": SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE,
	})
	_expect(not cpu_city.is_empty(), "Fixture must create a second City.")
	if cpu_city.is_empty():
		return

	var cpu_city_id := int(cpu_city["id"])
	var cpu_state = WorldPoliticalState.get_city_simulation_state(cpu_city_id)
	_expect(
		cpu_state != null
		and cpu_state.construction_state is CityConstructionState
		and cpu_state.construction_state != player_state.construction_state,
		"Two Cities must own distinct construction-state objects."
	)

	_expect(
		WorldPoliticalState.set_active_settlement(cpu_city_id),
		"CPU City must become active."
	)
	_expect(
		WorldData.city_construction_sites.is_empty()
		and WorldData.city_construction_site_index_by_id.is_empty()
		and WorldData.city_construction_site_id_by_tile.is_empty()
		and WorldData.next_city_construction_site_id == 1
		and WorldData.city_construction_version == 0,
		"Fresh CPU City must start with independent construction state."
	)

	WorldData.city_construction_sites = [{"id": 71, "test_owner": "cpu"}]
	WorldData.city_construction_site_index_by_id = {71: 0}
	WorldData.city_construction_site_id_by_tile = {Vector2i(6, 6): 71}
	WorldData.next_city_construction_site_id = 72
	WorldData.city_construction_version = 9

	_expect(
		WorldPoliticalState.set_active_settlement(player_city_id),
		"Player City must become active again."
	)
	_expect(
		str(WorldData.city_construction_sites[0].get("test_owner", "")) == "player"
		and WorldData.city_construction_site_index_by_id.has(41)
		and int(WorldData.city_construction_site_id_by_tile.get(Vector2i(2, 2), -1)) == 41
		and WorldData.next_city_construction_site_id == 42
		and WorldData.city_construction_version == 6,
		"Player construction state must survive a settlement switch."
	)

	_expect(
		WorldPoliticalState.set_active_settlement(cpu_city_id),
		"CPU City must become active again."
	)
	_expect(
		str(WorldData.city_construction_sites[0].get("test_owner", "")) == "cpu"
		and WorldData.city_construction_site_index_by_id.has(71)
		and int(WorldData.city_construction_site_id_by_tile.get(Vector2i(6, 6), -1)) == 71
		and WorldData.next_city_construction_site_id == 72
		and WorldData.city_construction_version == 9,
		"CPU construction state must survive a settlement switch."
	)


func _make_world(width: int, height: int, seed: int) -> WorldData:
	var world := WorldData.new()
	world.setup(width, height, seed)
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
	push_error("City construction-state isolation test: " + message)
