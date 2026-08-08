extends Node

const PLAYER_CITY_NAME := "Asterfall"
const PLAYER_CULTURE_NAME := "Valen"
const CPU_CULTURE_NAME := "Maren"

var failure_count: int = 0


func _ready() -> void:
	_run_state_isolation_test()
	WorldPoliticalState.reset_state()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City settlement state isolation test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City settlement state isolation test passed.")
	get_tree().quit(0)


func _run_state_isolation_test() -> void:
	WorldPoliticalState.reset_state()
	WorldData.reset_runtime_session_state()

	var world := _make_world(8, 8, 91_001)
	var locked := WorldData.lock_world_save({
		"source_world": world,
		"region_top_left": Vector2i(1, 1),
		"region_center": Vector2i(2, 2),
		"region_size": 3,
		"world_scene_path": "res://scenes/GameSession.tscn",
		"city_scene_path": "res://scenes/CityScreen.tscn",
		"city_name": PLAYER_CITY_NAME,
		"culture_name": PLAYER_CULTURE_NAME,
	})
	_expect(locked, "Fixture must lock the founding world.")
	if not locked:
		return

	_expect(
		WorldPoliticalState.synchronize_foundation_with_world_data(),
		"Founding must create the player settlement state."
	)
	var player_polity := WorldPoliticalState.get_player_polity()
	if player_polity.is_empty():
		_expect(false, "Player polity must exist after founding.")
		return

	var player_city_id := int(player_polity["capital_settlement_id"])
	var player_state = WorldPoliticalState.get_city_simulation_state(
		player_city_id
	)
	_expect(
		player_state is CitySettlementSimulationState,
		"The founding capital must own an instance city state."
	)
	if player_state == null:
		return

	_expect(
		player_state.work_state is CityWorkState,
		"Every city state must own a dedicated work-state subsystem."
	)

	# Give the player city unmistakable local state. WorldData remains a
	# compatibility workspace while individual city subsystems are extracted.
	var player_city_world := _make_world(5, 5, 91_101)
	WorldData.official_city_world = player_city_world
	WorldData.official_city_seed = 91_101
	WorldData.city_resource_amounts = {
		WorldData.RESOURCE_FISH: 7,
	}
	WorldData.city_objects = [
		{"test_owner": "player"},
	]
	WorldData.next_city_object_id = 17
	WorldData.city_object_version = 4
	WorldData.city_assignment_version = 9
	CityWorkSystem.get_current_work_state().player_commands = [
		{"id": 41, "test_owner": "player"},
	]
	CityWorkSystem.get_current_work_state().player_command_index_by_id = {41: 0}
	CityWorkSystem.get_current_work_state().next_player_command_id = 42
	CityWorkSystem.get_current_work_state().player_command_version = 6
	CityWorkSystem.get_current_work_state().work_orders = {
		71: {"id": 71, "source_key": "test:player"},
	}
	CityWorkSystem.get_current_work_state().work_order_id_by_source_key = {"test:player": 71}
	CityWorkSystem.get_current_work_state().next_work_order_id = 72
	CityWorkSystem.get_current_work_state().work_order_version = 8

	var cpu_culture := WorldData.create_culture(CPU_CULTURE_NAME)
	_expect(
		not cpu_culture.is_empty(),
		"Fixture must create an independent CPU culture."
	)
	if cpu_culture.is_empty():
		return

	var cpu_polity := WorldPoliticalState.create_polity({
		"name": "Maren Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": int(cpu_culture["id"]),
	})
	_expect(
		not cpu_polity.is_empty(),
		"Fixture must create an independent CPU polity."
	)
	if cpu_polity.is_empty():
		return

	var cpu_city := WorldPoliticalState.create_settlement({
		"name": "Marenhold",
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": int(cpu_polity["id"]),
		"world_region_top_left": Vector2i(5, 5),
		"world_region_center": Vector2i(5, 5),
		"world_region_size": 1,
		"simulation_backend_kind": (
			SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE
		),
	})
	_expect(
		not cpu_city.is_empty(),
		"A second city must be able to receive its own city-state backend."
	)
	if cpu_city.is_empty():
		return

	var cpu_city_id := int(cpu_city["id"])
	_expect(
		WorldPoliticalState.set_polity_capital(
			int(cpu_polity["id"]),
			cpu_city_id
		),
		"The CPU city must be assignable as its polity capital."
	)

	var cpu_state = WorldPoliticalState.get_city_simulation_state(cpu_city_id)
	_expect(
		cpu_state is CitySettlementSimulationState,
		"Every city-state backend must own a distinct state object."
	)
	_expect(
		cpu_state != player_state,
		"Two cities must never share the same local state object."
	)
	_expect(
		cpu_state.work_state is CityWorkState
		and cpu_state.work_state != player_state.work_state,
		"Two cities must never share the same work-state object."
	)

	_expect(
		WorldPoliticalState.set_active_settlement(cpu_city_id),
		"The CPU city must become activatable."
	)
	_expect(
		WorldData.official_city_world == null
		and WorldData.official_city_seed == 0,
		"A fresh city must not inherit the previous city's generated local world."
	)
	_expect(
		WorldData.city_resource_amounts.is_empty()
		and WorldData.city_objects.is_empty(),
		"A fresh city must begin with independent resources and objects."
	)
	_expect(
		WorldData.next_city_object_id == 1
		and WorldData.city_object_version == 0
		and WorldData.city_assignment_version == 0,
		"A fresh city must begin with independent counters and change versions."
	)
	_expect(
		CityWorkSystem.get_current_work_state().player_commands.is_empty()
		and CityWorkSystem.get_current_work_state().work_orders.is_empty()
		and CityWorkSystem.get_current_work_state().next_player_command_id == 1
		and CityWorkSystem.get_current_work_state().next_work_order_id == 1,
		"A fresh city must begin with an independent work-state subsystem."
	)

	var cpu_context = WorldPoliticalState.get_active_settlement_context()
	_expect(
		cpu_context != null
		and cpu_context.supports_city_simulation()
		and cpu_context.has_instance_owned_city_state()
		and cpu_context.local_state == cpu_state,
		"The active CPU city context must expose its own local simulation state."
	)

	var cpu_city_world := _make_world(6, 6, 91_202)
	WorldData.official_city_world = cpu_city_world
	WorldData.official_city_seed = 91_202
	WorldData.city_resource_amounts = {
		WorldData.RESOURCE_FISH: 31,
	}
	WorldData.city_objects = [
		{"test_owner": "cpu"},
	]
	WorldData.next_city_object_id = 55
	WorldData.city_object_version = 12
	WorldData.city_assignment_version = 21
	CityWorkSystem.get_current_work_state().player_commands = [
		{"id": 11, "test_owner": "cpu"},
	]
	CityWorkSystem.get_current_work_state().player_command_index_by_id = {11: 0}
	CityWorkSystem.get_current_work_state().next_player_command_id = 12
	CityWorkSystem.get_current_work_state().player_command_version = 14
	CityWorkSystem.get_current_work_state().work_orders = {
		21: {"id": 21, "source_key": "test:cpu"},
	}
	CityWorkSystem.get_current_work_state().work_order_id_by_source_key = {"test:cpu": 21}
	CityWorkSystem.get_current_work_state().next_work_order_id = 22
	CityWorkSystem.get_current_work_state().work_order_version = 16

	_expect(
		WorldPoliticalState.set_active_settlement(player_city_id),
		"The player city must remain activatable after CPU state mutation."
	)
	_expect(
		WorldData.official_city_world == player_city_world
		and WorldData.official_city_seed == 91_101,
		"Returning to the player city must restore its local generated world."
	)
	_expect(
		int(WorldData.city_resource_amounts.get(WorldData.RESOURCE_FISH, 0)) == 7
		and str(WorldData.city_objects[0].get("test_owner", "")) == "player",
		"Returning to the player city must restore its resources and objects."
	)
	_expect(
		WorldData.next_city_object_id == 17
		and WorldData.city_object_version == 4
		and WorldData.city_assignment_version == 9,
		"Returning to the player city must restore its counters and versions."
	)
	_expect(
		str(CityWorkSystem.get_current_work_state().player_commands[0].get("test_owner", "")) == "player"
		and CityWorkSystem.get_current_work_state().next_player_command_id == 42
		and CityWorkSystem.get_current_work_state().player_command_version == 6
		and CityWorkSystem.get_current_work_state().work_orders.has(71)
		and CityWorkSystem.get_current_work_state().next_work_order_id == 72
		and CityWorkSystem.get_current_work_state().work_order_version == 8,
		"Returning to the player city must restore its independent work state."
	)

	_expect(
		WorldPoliticalState.set_active_settlement(cpu_city_id),
		"The CPU city must be reactivatable."
	)
	_expect(
		WorldData.official_city_world == cpu_city_world
		and WorldData.official_city_seed == 91_202,
		"Reactivating the CPU city must restore its own generated world."
	)
	_expect(
		int(WorldData.city_resource_amounts.get(WorldData.RESOURCE_FISH, 0)) == 31
		and str(WorldData.city_objects[0].get("test_owner", "")) == "cpu",
		"Reactivating the CPU city must restore its own resources and objects."
	)
	_expect(
		WorldData.next_city_object_id == 55
		and WorldData.city_object_version == 12
		and WorldData.city_assignment_version == 21,
		"Reactivating the CPU city must restore its own counters and versions."
	)
	_expect(
		str(CityWorkSystem.get_current_work_state().player_commands[0].get("test_owner", "")) == "cpu"
		and CityWorkSystem.get_current_work_state().next_player_command_id == 12
		and CityWorkSystem.get_current_work_state().player_command_version == 14
		and CityWorkSystem.get_current_work_state().work_orders.has(21)
		and CityWorkSystem.get_current_work_state().next_work_order_id == 22
		and CityWorkSystem.get_current_work_state().work_order_version == 16,
		"Reactivating the CPU city must restore its own independent work state."
	)
	_expect(
		WorldPoliticalState.validate_registry_integrity(),
		"Independent city states must preserve political registry integrity."
	)

	# Leave the compatibility workspace on the player's city so existing tests
	# and session teardown see the same player-facing state they expect.
	WorldPoliticalState.set_active_settlement(player_city_id)


func _make_world(width: int, height: int, seed: int) -> WorldData:
	var world := WorldData.new()
	world.setup(width, height, seed)

	for y in range(height):
		for x in range(width):
			world.tiles[y][x] = _make_land_tile()

	world.mark_tile_data_changed()
	return world


func _make_land_tile() -> Dictionary:
	return {
		"fertility": 55.0,
		"elevation": 0.2,
		"temperature": 0.5,
		"precipitation": 0.5,
		"terrain": WorldData.TERRAIN_LAND,
		"biome": WorldData.BIOME_PLAIN,
		"resource": WorldData.RESOURCE_NONE,
		"is_land": true,
	}


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error("City settlement state isolation test: " + message)
