extends Node

const TEST_CITY_NAME := "Bootstrap City"
const TEST_CULTURE_NAME := "Bootstrap Culture"

var failure_count: int = 0


func _ready() -> void:
	_run_bootstrap_test()
	WorldPoliticalState.reset_state()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City work-state bootstrap test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City work-state bootstrap test passed.")
	get_tree().quit(0)


func _run_bootstrap_test() -> void:
	WorldPoliticalState.reset_state()
	WorldData.reset_runtime_session_state()

	var world := _make_world(8, 8, 73_011)
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

	# Low-level simulation fixtures can create work before the first simulation
	# tick asks WorldPoliticalState to establish the founding settlement.
	CityWorkSystem.get_current_work_state().player_commands = [
		{"id": 7, "test_owner": "bootstrap"},
	]
	CityWorkSystem.get_current_work_state().player_command_index_by_id = {7: 0}
	CityWorkSystem.get_current_work_state().next_player_command_id = 8
	CityWorkSystem.get_current_work_state().player_command_version = 4
	CityWorkSystem.get_current_work_state().work_orders = {
		11: {"id": 11, "source_key": "test:bootstrap"},
	}
	CityWorkSystem.get_current_work_state().work_order_id_by_source_key = {"test:bootstrap": 11}
	CityWorkSystem.get_current_work_state().next_work_order_id = 12
	CityWorkSystem.get_current_work_state().work_order_version = 6

	var bootstrap_state = WorldPoliticalState.get_current_city_work_state()
	_expect(
		bootstrap_state is CityWorkState,
		"Pre-context work must live in the unbound CityWorkState."
	)

	_expect(
		WorldPoliticalState.synchronize_foundation_with_world_data(),
		"Founding must establish a city settlement context."
	)

	var capital_state = WorldPoliticalState.get_active_city_simulation_state()
	_expect(
		capital_state is CitySettlementSimulationState,
		"Founding capital must own city simulation state."
	)
	if capital_state == null:
		return

	_expect(
		capital_state.work_state == bootstrap_state,
		"Founding City must adopt the exact pre-context work-state object."
	)
	_expect(
		str(capital_state.work_state.player_commands[0].get("test_owner", ""))
		== "bootstrap"
		and capital_state.work_state.next_player_command_id == 8
		and capital_state.work_state.player_command_version == 4,
		"Bootstrap player-command state must survive context establishment."
	)
	_expect(
		capital_state.work_state.work_orders.has(11)
		and capital_state.work_state.next_work_order_id == 12
		and capital_state.work_state.work_order_version == 6,
		"Bootstrap parent work-order state must survive context establishment."
	)
	_expect(
		CityWorkSystem.get_current_work_state().player_commands
		== capital_state.work_state.player_commands
		and CityWorkSystem.get_current_work_state().work_orders == capital_state.work_state.work_orders,
		"WorldData compatibility fields must resolve to the active City's work state."
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
	push_error("City work-state bootstrap test: " + message)
