extends Node

const PLAYER_CITY_NAME := "Asterfall"
const PLAYER_CULTURE_NAME := "Valen"
const CPU_CULTURE_NAME := "Maren"
const CityStateValidatorScript = preload(
	"res://scripts/city/simulation/CityStateValidator.gd"
)

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
	_expect(
		player_state.object_state is CityObjectState,
		"Every city state must own a dedicated object-state subsystem."
	)
	_expect(
		player_state.logistics_state is CityLogisticsState,
		"Every city state must own a dedicated logistics-state subsystem."
	)

	# Give the player city unmistakable local state. WorldData remains a
	# compatibility workspace while individual city subsystems are extracted.
	var player_city_world := _make_world(5, 5, 91_101)
	WorldData.official_city_world = player_city_world
	WorldData.official_city_seed = 91_101
	WorldData.city_resource_amounts = {
		WorldData.RESOURCE_FISH: 7,
	}
	var shared_object_tile := Vector2i(2, 2)
	WorldData.next_city_object_id = 16
	WorldData.city_object_version = 3
	var player_road := WorldData.add_city_road_object(
		[shared_object_tile],
		"player",
		player_city_world
	)
	_expect(
		int(player_road.get("id", -1)) == 16
		and WorldData.next_city_object_id == 17
		and WorldData.city_object_version == 4,
		"Player object mutation must route through the compatibility API."
	)
	var player_objects: Array = player_state.object_state.objects
	var player_object_index: Dictionary = (
		player_state.object_state.object_index_by_id
	)
	var player_occupancy: Dictionary = player_state.object_state.occupied_tiles
	var player_validation := CityStateValidatorScript.validate(true, false)
	_expect(
		bool(player_validation.get("valid", false))
		and int(player_validation.get("checked_objects", 0)) == 1
		and int(player_validation.get("checked_occupied_tiles", 0)) == 1,
		"The player City's routed object registry must pass full validation."
	)
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
	CityLogisticsSystem.get_current_state().ground_piles = [
		{"id": 81, "test_owner": "player"},
	]
	CityLogisticsSystem.get_current_state().ground_pile_index_by_id = {81: 0}
	CityLogisticsSystem.get_current_state().next_ground_pile_id = 82
	CityLogisticsSystem.get_current_state().ground_pile_version = 10
	CityLogisticsSystem.get_current_state().haul_reservations = {
		91: {"id": 91, "citizen_id": 1, "test_owner": "player"},
	}
	CityLogisticsSystem.get_current_state().haul_reservation_id_by_citizen_id = {1: 91}
	CityLogisticsSystem.get_current_state().haul_source_reserved_amount_by_key = {"player:source": 3}
	CityLogisticsSystem.get_current_state().haul_destination_reserved_amount_by_key = {"player:destination": 3}
	CityLogisticsSystem.get_current_state().next_haul_reservation_id = 92
	CityLogisticsSystem.get_current_state().haul_reservation_version = 11

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
		cpu_state.object_state is CityObjectState
		and not is_same(cpu_state.object_state, player_state.object_state)
		and not is_same(
			cpu_state.object_state.objects,
			player_state.object_state.objects
		)
		and not is_same(
			cpu_state.object_state.object_index_by_id,
			player_state.object_state.object_index_by_id
		)
		and not is_same(
			cpu_state.object_state.occupied_tiles,
			player_state.object_state.occupied_tiles
		),
		"Two cities must never share object-state collections."
	)
	_expect(
		cpu_state.work_state is CityWorkState
		and cpu_state.work_state != player_state.work_state,
		"Two cities must never share the same work-state object."
	)
	_expect(
		cpu_state.logistics_state is CityLogisticsState
		and cpu_state.logistics_state != player_state.logistics_state,
		"Two cities must never share the same logistics-state object."
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
		is_same(WorldData.city_objects, cpu_state.object_state.objects)
		and is_same(
			WorldData.city_object_index_by_id,
			cpu_state.object_state.object_index_by_id
		)
		and is_same(
			WorldData.city_occupied_tiles,
			cpu_state.object_state.occupied_tiles
		),
		"WorldData must expose the active CPU City's exact object collections."
	)
	_expect(
		CityWorkSystem.get_current_work_state().player_commands.is_empty()
		and CityWorkSystem.get_current_work_state().work_orders.is_empty()
		and CityWorkSystem.get_current_work_state().next_player_command_id == 1
		and CityWorkSystem.get_current_work_state().next_work_order_id == 1,
		"A fresh city must begin with an independent work-state subsystem."
	)
	_expect(
		CityLogisticsSystem.get_current_state().ground_piles.is_empty()
		and CityLogisticsSystem.get_current_state().haul_reservations.is_empty()
		and CityLogisticsSystem.get_current_state().next_ground_pile_id == 1
		and CityLogisticsSystem.get_current_state().next_haul_reservation_id == 1
		and CityLogisticsSystem.get_current_state().ground_pile_version == 0
		and CityLogisticsSystem.get_current_state().haul_reservation_version == 0,
		"A fresh city must begin with an independent logistics-state subsystem."
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
	WorldData.next_city_object_id = 54
	WorldData.city_object_version = 11
	var cpu_road := WorldData.add_city_road_object(
		[shared_object_tile],
		"cpu",
		cpu_city_world
	)
	_expect(
		int(cpu_road.get("id", -1)) == 54
		and WorldData.next_city_object_id == 55
		and WorldData.city_object_version == 12,
		"CPU object mutation must route through the compatibility API."
	)
	var cpu_objects: Array = cpu_state.object_state.objects
	var cpu_object_index: Dictionary = cpu_state.object_state.object_index_by_id
	var cpu_occupancy: Dictionary = cpu_state.object_state.occupied_tiles
	var cpu_validation := CityStateValidatorScript.validate(true, false)
	_expect(
		bool(cpu_validation.get("valid", false))
		and int(cpu_validation.get("checked_objects", 0)) == 1
		and int(cpu_validation.get("checked_occupied_tiles", 0)) == 1,
		"The CPU City's routed object registry must pass full validation."
	)
	_expect(
		player_state.object_state.objects.size() == 1
		and int(player_state.object_state.objects[0].get("id", -1)) == 16
		and int(
			player_state.object_state.object_index_by_id.get(16, -1)
		) == 0
		and int(
			player_state.object_state.occupied_tiles.get(
				shared_object_tile,
				-1
			)
		) == 16
		and player_state.object_state.next_object_id == 17
		and player_state.object_state.object_version == 4,
		"Mutating the CPU City must not alter the inactive player object state."
	)
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
	CityLogisticsSystem.get_current_state().ground_piles = [
		{"id": 31, "test_owner": "cpu"},
	]
	CityLogisticsSystem.get_current_state().ground_pile_index_by_id = {31: 0}
	CityLogisticsSystem.get_current_state().next_ground_pile_id = 32
	CityLogisticsSystem.get_current_state().ground_pile_version = 18
	CityLogisticsSystem.get_current_state().haul_reservations = {
		41: {"id": 41, "citizen_id": 2, "test_owner": "cpu"},
	}
	CityLogisticsSystem.get_current_state().haul_reservation_id_by_citizen_id = {2: 41}
	CityLogisticsSystem.get_current_state().haul_source_reserved_amount_by_key = {"cpu:source": 5}
	CityLogisticsSystem.get_current_state().haul_destination_reserved_amount_by_key = {"cpu:destination": 5}
	CityLogisticsSystem.get_current_state().next_haul_reservation_id = 42
	CityLogisticsSystem.get_current_state().haul_reservation_version = 19

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
		and int(WorldData.city_objects[0].get("id", -1)) == 16
		and int(WorldData.city_object_index_by_id.get(16, -1)) == 0
		and int(WorldData.city_occupied_tiles.get(shared_object_tile, -1)) == 16,
		"Returning to the player city must restore its resources and objects."
	)
	_expect(
		is_same(WorldData.city_objects, player_objects)
		and is_same(WorldData.city_object_index_by_id, player_object_index)
		and is_same(WorldData.city_occupied_tiles, player_occupancy),
		"Returning to the player City must restore exact collection identity."
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
		str(CityLogisticsSystem.get_current_state().ground_piles[0].get("test_owner", "")) == "player"
		and CityLogisticsSystem.get_current_state().next_ground_pile_id == 82
		and CityLogisticsSystem.get_current_state().ground_pile_version == 10
		and CityLogisticsSystem.get_current_state().haul_reservations.has(91)
		and CityLogisticsSystem.get_current_state().next_haul_reservation_id == 92
		and CityLogisticsSystem.get_current_state().haul_reservation_version == 11,
		"Returning to the player city must restore its independent logistics state."
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
		and int(WorldData.city_objects[0].get("id", -1)) == 54
		and int(WorldData.city_object_index_by_id.get(54, -1)) == 0
		and int(WorldData.city_occupied_tiles.get(shared_object_tile, -1)) == 54,
		"Reactivating the CPU city must restore its own resources and objects."
	)
	_expect(
		is_same(WorldData.city_objects, cpu_objects)
		and is_same(WorldData.city_object_index_by_id, cpu_object_index)
		and is_same(WorldData.city_occupied_tiles, cpu_occupancy),
		"Reactivating the CPU City must restore exact collection identity."
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
		str(CityLogisticsSystem.get_current_state().ground_piles[0].get("test_owner", "")) == "cpu"
		and CityLogisticsSystem.get_current_state().next_ground_pile_id == 32
		and CityLogisticsSystem.get_current_state().ground_pile_version == 18
		and CityLogisticsSystem.get_current_state().haul_reservations.has(41)
		and CityLogisticsSystem.get_current_state().next_haul_reservation_id == 42
		and CityLogisticsSystem.get_current_state().haul_reservation_version == 19,
		"Reactivating the CPU city must restore its own independent logistics state."
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
