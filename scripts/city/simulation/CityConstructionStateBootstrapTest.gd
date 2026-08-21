extends Node

const TEST_CITY_NAME := "Construction Bootstrap City"
const TEST_CULTURE_NAME := "Construction Bootstrap Culture"

var failure_count: int = 0


func _ready() -> void:
	_run_bootstrap_test()
	WorldPoliticalState.reset_state()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City construction-state bootstrap test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City construction-state bootstrap test passed.")
	get_tree().quit(0)


func _run_bootstrap_test() -> void:
	WorldPoliticalState.reset_state()
	WorldData.reset_runtime_session_state()

	var world := _make_world(8, 8, 85_021)
	var locked := WorldData.lock_world_save({
		"source_world": world,
		"region_top_left": Vector2i(1, 1),
		"region_center": Vector2i(2, 2),
		"region_size": 3,
		"world_scene_path": "res://scenes/GameSession.tscn",
		"city_scene_path": "res://scenes/CityScreen.tscn",
		"city_name": TEST_CITY_NAME,
		"culture_name": TEST_CULTURE_NAME,
	})
	_expect(locked, "Fixture must lock a founding world.")
	if not locked:
		return

	_expect(
		WorldPoliticalState.synchronize_foundation_with_world_data(),
		"Founding must establish a city settlement context."
	)
	var capital_id := WorldPoliticalState.get_player_capital_settlement_id()
	var capital_state: CitySettlementSimulationState = WorldPoliticalState.get_city_simulation_state(capital_id)
	_expect(
		capital_state is CitySettlementSimulationState,
		"Founding capital must own city simulation state."
	)
	if capital_state == null:
		return

	var construction_state: CityConstructionState = capital_state.construction_state
	construction_state.construction_sites = [
		{
			"id": 17,
			"test_owner": "bootstrap",
		},
	]
	construction_state.construction_site_index_by_id = {17: 0}
	construction_state.construction_site_id_by_tile = {Vector2i(3, 3): 17}
	construction_state.next_construction_site_id = 18
	construction_state.construction_version = 5

	_expect(
		str(construction_state.construction_sites[0].get("test_owner", ""))
		== "bootstrap"
		and construction_state.next_construction_site_id == 18
		and construction_state.construction_version == 5,
		"The registered capital must retain exact construction-state mutations."
	)
	_expect(
		CityConstructionSystem.get_state_for_city_state(capital_state)
		== capital_state.construction_state
		and capital_state.construction_state.next_construction_site_id == 18
		and capital_state.construction_state.construction_version == 5,
		"The exact city-state API must resolve the adopted capital construction owner."
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
	push_error("City construction-state bootstrap test: " + message)
