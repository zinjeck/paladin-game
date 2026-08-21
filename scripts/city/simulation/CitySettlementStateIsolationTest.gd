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
	_test_validator_cache_tracks_object_state_identity()
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
	_seed_city_runtime_data(
		player_state,
		player_city_id,
		PLAYER_CITY_NAME,
		WorldData.get_official_founding_culture_id()
	)

	_expect(
		player_state.work_state is CityWorkState,
		"Every city state must own a dedicated work-state subsystem."
	)
	_expect(
		player_state.object_state is CityObjectState,
		"Every city state must own a dedicated object-state subsystem."
	)
	_expect(
		player_state.resource_accounting_state is CityResourceAccountingState,
		"Every city state must own dedicated resource-accounting state."
	)
	_expect(
		player_state.logistics_state is CityLogisticsState,
		"Every city state must own a dedicated logistics-state subsystem."
	)

	# Give the player city unmistakable state through its explicit local owner.
	var player_city_world := _make_world(8, 8, 91_101)
	_expect(
		WorldPoliticalState.store_city_world_for_settlement(
			player_city_id,
			player_city_world,
			91_101
		),
		"The player fixture must store its world through the exact settlement owner."
	)
	var shared_object_tile := Vector2i(2, 2)
	var player_keep := _register_keep(
		player_state,
		player_city_world,
		Vector2i(4, 0),
		"player"
	)
	_mark_city_founded(player_state, player_keep)
	player_state.object_state.next_object_id = 16
	player_state.object_state.object_version = 3
	var player_road := CityObjectSystem.add_city_road_object_for_city_state(
		player_state,
		[shared_object_tile],
		"player",
		player_city_world
	)
	_expect(
		int(player_road.get("id", -1)) == 16
		and player_state.object_state.next_object_id == 17
		and player_state.object_state.object_version == 4,
		"Player object mutation must route through CityObjectSystem."
	)
	var player_objects: Array = player_state.object_state.objects
	var player_object_index: Dictionary = (
		player_state.object_state.object_index_by_id
	)
	var player_occupancy: Dictionary = player_state.object_state.occupied_tiles
	var player_validation := CityStateValidatorScript.validate_for_settlement(
		WorldPoliticalState.get_settlement_context(player_city_id),
		true,
		false
	)
	_expect(
		bool(player_validation.get("valid", false))
		and int(player_validation.get("checked_objects", 0)) == 2
		and int(player_validation.get("checked_occupied_tiles", 0)) == 22,
		"The player City's routed object registry must pass full validation."
	)
	player_state.assignment_state.assignment_version = 9
	player_state.work_state.player_commands = [
		{"id": 41, "test_owner": "player"},
	]
	player_state.work_state.player_command_index_by_id = {41: 0}
	player_state.work_state.next_player_command_id = 42
	player_state.work_state.player_command_version = 6
	player_state.work_state.work_orders = {
		71: {"id": 71, "source_key": "test:player"},
	}
	player_state.work_state.work_order_id_by_source_key = {"test:player": 71}
	player_state.work_state.next_work_order_id = 72
	player_state.work_state.work_order_version = 8
	player_state.logistics_state.ground_piles = [
		{"id": 81, "test_owner": "player"},
	]
	player_state.logistics_state.ground_pile_index_by_id = {81: 0}
	player_state.logistics_state.next_ground_pile_id = 82
	player_state.logistics_state.ground_pile_version = 10
	player_state.logistics_state.haul_reservations = {
		91: {"id": 91, "citizen_id": 1, "test_owner": "player"},
	}
	player_state.logistics_state.haul_reservation_id_by_citizen_id = {1: 91}
	player_state.logistics_state.haul_source_reserved_amount_by_key = {"player:source": 3}
	player_state.logistics_state.haul_destination_reserved_amount_by_key = {"player:destination": 3}
	player_state.logistics_state.next_haul_reservation_id = 92
	player_state.logistics_state.haul_reservation_version = 11

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
		cpu_state.resource_accounting_state is CityResourceAccountingState
		and not is_same(
			cpu_state.resource_accounting_state,
			player_state.resource_accounting_state
		)
		and not is_same(
			cpu_state.resource_accounting_state.owned_resource_amount_cache,
			player_state.resource_accounting_state.owned_resource_amount_cache
		),
		"Two cities must never share resource-accounting state or cache identity."
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
	_seed_city_runtime_data(
		cpu_state,
		cpu_city_id,
		"Marenhold",
		int(cpu_culture["id"])
	)

	_expect(
		WorldPoliticalState.set_active_settlement(cpu_city_id),
		"The CPU city must become activatable."
	)
	_expect(
		cpu_state.city_world == null
		and cpu_state.city_seed == 0,
		"A fresh city must not inherit the previous city's generated local world."
	)
	_expect(
		cpu_state.object_state.objects.is_empty()
		and cpu_state.resource_accounting_state.owned_resource_amount_cache.is_empty()
		and cpu_state.resource_accounting_state.owned_resource_amount_cache_container_version == -1,
		"A fresh city must begin with independent objects and accounting cache."
	)
	_expect(
		cpu_state.object_state.next_object_id == 1
		and cpu_state.object_state.object_version == 0
		and cpu_state.resource_accounting_state.container_version == 0
		and cpu_state.resource_accounting_state.public_storage_version == 0
		and cpu_state.assignment_state.assignment_version == 0,
		"A fresh city must begin with independent counters and change versions."
	)
	_expect(
		is_same(
			CityObjectSystem.get_state_for_city_state(cpu_state).objects,
			cpu_state.object_state.objects
		)
		and is_same(
			CityObjectSystem.get_state_for_city_state(cpu_state).object_index_by_id,
			cpu_state.object_state.object_index_by_id
		)
		and is_same(
			CityObjectSystem.get_state_for_city_state(cpu_state).occupied_tiles,
			cpu_state.object_state.occupied_tiles
		),
		"CityObjectSystem must expose the active CPU City's exact object collections."
	)
	_expect(
		cpu_state.work_state.player_commands.is_empty()
		and cpu_state.work_state.work_orders.is_empty()
		and cpu_state.work_state.next_player_command_id == 1
		and cpu_state.work_state.next_work_order_id == 1,
		"A fresh city must begin with an independent work-state subsystem."
	)
	_expect(
		cpu_state.logistics_state.ground_piles.is_empty()
		and cpu_state.logistics_state.haul_reservations.is_empty()
		and cpu_state.logistics_state.next_ground_pile_id == 1
		and cpu_state.logistics_state.next_haul_reservation_id == 1
		and cpu_state.logistics_state.ground_pile_version == 0
		and cpu_state.logistics_state.haul_reservation_version == 0,
		"A fresh city must begin with an independent logistics-state subsystem."
	)

	var cpu_context = WorldPoliticalState.get_settlement_context(cpu_city_id)
	_expect(
		cpu_context != null
		and cpu_context.supports_city_simulation()
		and cpu_context.has_instance_owned_city_state()
		and cpu_context.local_state == cpu_state,
		"The active CPU city context must expose its own local simulation state."
	)

	var cpu_city_world := _make_world(8, 8, 91_202)
	_expect(
		WorldPoliticalState.store_city_world_for_settlement(
			cpu_city_id,
			cpu_city_world,
			91_202
		),
		"The CPU fixture must store its world through the exact settlement owner."
	)
	var cpu_keep := _register_keep(
		cpu_state,
		cpu_city_world,
		Vector2i(4, 0),
		"cpu"
	)
	_mark_city_founded(cpu_state, cpu_keep)
	cpu_state.object_state.next_object_id = 16
	cpu_state.object_state.object_version = 11
	var cpu_road := CityObjectSystem.add_city_road_object_for_city_state(
		cpu_state,
		[shared_object_tile],
		"cpu",
		cpu_city_world
	)
	_expect(
		int(cpu_road.get("id", -1)) == 16
		and cpu_state.object_state.next_object_id == 17
		and cpu_state.object_state.object_version == 12,
		"CPU object mutation must route through CityObjectSystem."
	)
	var cpu_objects: Array = cpu_state.object_state.objects
	var cpu_object_index: Dictionary = cpu_state.object_state.object_index_by_id
	var cpu_occupancy: Dictionary = cpu_state.object_state.occupied_tiles
	var cpu_validation := CityStateValidatorScript.validate_for_settlement(
		WorldPoliticalState.get_settlement_context(cpu_city_id),
		true,
		false
	)
	_expect(
		bool(cpu_validation.get("valid", false))
		and int(cpu_validation.get("checked_objects", 0)) == 2
		and int(cpu_validation.get("checked_occupied_tiles", 0)) == 22,
		"The CPU City's routed object registry must pass full validation."
	)
	_expect(
		player_state.object_state.objects.size() == 2
		and int(player_state.object_state.objects[1].get("id", -1)) == 16
		and int(
			player_state.object_state.object_index_by_id.get(16, -1)
		) == 1
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
	cpu_state.assignment_state.assignment_version = 21
	cpu_state.work_state.player_commands = [
		{"id": 41, "test_owner": "cpu"},
	]
	cpu_state.work_state.player_command_index_by_id = {41: 0}
	cpu_state.work_state.next_player_command_id = 42
	cpu_state.work_state.player_command_version = 14
	cpu_state.work_state.work_orders = {
		71: {"id": 71, "source_key": "test:cpu"},
	}
	cpu_state.work_state.work_order_id_by_source_key = {"test:cpu": 71}
	cpu_state.work_state.next_work_order_id = 72
	cpu_state.work_state.work_order_version = 16
	cpu_state.logistics_state.ground_piles = [
		{"id": 81, "test_owner": "cpu"},
	]
	cpu_state.logistics_state.ground_pile_index_by_id = {81: 0}
	cpu_state.logistics_state.next_ground_pile_id = 82
	cpu_state.logistics_state.ground_pile_version = 18
	cpu_state.logistics_state.haul_reservations = {
		91: {"id": 91, "citizen_id": 2, "test_owner": "cpu"},
	}
	cpu_state.logistics_state.haul_reservation_id_by_citizen_id = {2: 91}
	cpu_state.logistics_state.haul_source_reserved_amount_by_key = {"cpu:source": 5}
	cpu_state.logistics_state.haul_destination_reserved_amount_by_key = {"cpu:destination": 5}
	cpu_state.logistics_state.next_haul_reservation_id = 92
	cpu_state.logistics_state.haul_reservation_version = 19

	_expect(
		WorldPoliticalState.set_active_settlement(player_city_id),
		"The player city must remain activatable after CPU state mutation."
	)
	_expect(
		player_state.city_world == player_city_world
		and player_state.city_seed == 91_101,
		"Returning to the player city must restore its local generated world."
	)
	_expect(
		int(player_state.object_state.objects[1].get("id", -1)) == 16
		and int(player_state.object_state.object_index_by_id.get(16, -1)) == 1
		and int(player_state.object_state.occupied_tiles.get(shared_object_tile, -1)) == 16,
		"Returning to the player city must restore its objects."
	)
	_expect(
		is_same(player_state.object_state.objects, player_objects)
		and is_same(player_state.object_state.object_index_by_id, player_object_index)
		and is_same(player_state.object_state.occupied_tiles, player_occupancy),
		"Returning to the player City must restore exact collection identity."
	)
	_expect(
		player_state.object_state.next_object_id == 17
		and player_state.object_state.object_version == 4
		and player_state.assignment_state.assignment_version == 9,
		"Returning to the player city must restore its counters and versions."
	)
	_expect(
		str(player_state.work_state.player_commands[0].get("test_owner", "")) == "player"
		and player_state.work_state.next_player_command_id == 42
		and player_state.work_state.player_command_version == 6
		and player_state.work_state.work_orders.has(71)
		and player_state.work_state.next_work_order_id == 72
		and player_state.work_state.work_order_version == 8,
		"Returning to the player city must restore its independent work state."
	)
	_expect(
		str(player_state.logistics_state.ground_piles[0].get("test_owner", "")) == "player"
		and player_state.logistics_state.next_ground_pile_id == 82
		and player_state.logistics_state.ground_pile_version == 10
		and player_state.logistics_state.haul_reservations.has(91)
		and player_state.logistics_state.next_haul_reservation_id == 92
		and player_state.logistics_state.haul_reservation_version == 11,
		"Returning to the player city must restore its independent logistics state."
	)

	_expect(
		WorldPoliticalState.set_active_settlement(cpu_city_id),
		"The CPU city must be reactivatable."
	)
	_expect(
		cpu_state.city_world == cpu_city_world
		and cpu_state.city_seed == 91_202,
		"Reactivating the CPU city must restore its own generated world."
	)
	_expect(
		int(cpu_state.object_state.objects[1].get("id", -1)) == 16
		and int(cpu_state.object_state.object_index_by_id.get(16, -1)) == 1
		and int(cpu_state.object_state.occupied_tiles.get(shared_object_tile, -1)) == 16,
		"Reactivating the CPU city must restore its own objects."
	)
	_expect(
		is_same(cpu_state.object_state.objects, cpu_objects)
		and is_same(cpu_state.object_state.object_index_by_id, cpu_object_index)
		and is_same(cpu_state.object_state.occupied_tiles, cpu_occupancy),
		"Reactivating the CPU City must restore exact collection identity."
	)
	_expect(
		cpu_state.object_state.next_object_id == 17
		and cpu_state.object_state.object_version == 12
		and cpu_state.assignment_state.assignment_version == 21,
		"Reactivating the CPU city must restore its own counters and versions."
	)
	_expect(
		str(cpu_state.work_state.player_commands[0].get("test_owner", "")) == "cpu"
		and cpu_state.work_state.next_player_command_id == 42
		and cpu_state.work_state.player_command_version == 14
		and cpu_state.work_state.work_orders.has(71)
		and cpu_state.work_state.next_work_order_id == 72
		and cpu_state.work_state.work_order_version == 16,
		"Reactivating the CPU city must restore its own independent work state."
	)
	_expect(
		str(cpu_state.logistics_state.ground_piles[0].get("test_owner", "")) == "cpu"
		and cpu_state.logistics_state.next_ground_pile_id == 82
		and cpu_state.logistics_state.ground_pile_version == 18
		and cpu_state.logistics_state.haul_reservations.has(91)
		and cpu_state.logistics_state.next_haul_reservation_id == 92
		and cpu_state.logistics_state.haul_reservation_version == 19,
		"Reactivating the CPU city must restore its own independent logistics state."
	)
	_expect(
		WorldPoliticalState.validate_registry_integrity(),
		"Independent city states must preserve political registry integrity."
	)

	# Leave the player settlement selected so existing tests and session teardown
	# see the same player-facing state they expect.
	WorldPoliticalState.set_active_settlement(player_city_id)


func _test_validator_cache_tracks_object_state_identity() -> void:
	WorldPoliticalState.reset_state()
	WorldData.reset_runtime_session_state()
	var city_world := _make_world(8, 8, 91_303)
	var first_city_state := _create_owned_city_fixture(
		"Validator Identity City A",
		"Validator Identity Culture A",
		city_world,
		91_303
	)
	if first_city_state == null:
		_expect(false, "The validator-cache fixture must create its first City.")
		return
	var first_keep := _register_keep(
		first_city_state,
		city_world,
		Vector2i(4, 0),
		"first_state"
	)
	_mark_city_founded(first_city_state, first_keep)
	var shared_tile := Vector2i(3, 3)
	var first_road := CityObjectSystem.add_city_road_object_for_city_state(
		first_city_state,
		[shared_tile],
		"first_state",
		city_world
	)
	var first_state := CityObjectSystem.get_state_for_city_state(
		first_city_state
	)
	var first_result := CityStateValidatorScript.validate_for_city_state(
		int(first_city_state.city_runtime_data.get("id", -1)),
		first_city_state,
		true,
		false
	)

	_expect(
		not first_road.is_empty()
		and int(first_result.get("checked_objects", -1)) == 2,
		"The validator-cache fixture must cache the Keep and road for its first state."
	)

	# Rotate only the selected object-state owner. Every numeric version used by
	# the validator remains equal, so identity is the only valid cache boundary.
	WorldPoliticalState.reset_state()
	var second_city_world := _make_world(8, 8, 91_304)
	var second_city_state := _create_owned_city_fixture(
		"Validator Identity City B",
		"Validator Identity Culture B",
		second_city_world,
		91_304
	)
	if second_city_state == null:
		_expect(false, "The validator-cache fixture must create its second City.")
		return
	var second_state := second_city_state.object_state
	second_state.object_version = first_state.object_version
	var second_result := CityStateValidatorScript.validate_for_city_state(
		int(second_city_state.city_runtime_data.get("id", -1)),
		second_city_state,
		false,
		false
	)

	_expect(
		not is_same(second_state, first_state)
		and second_state.objects.is_empty()
		and second_state.object_version == first_state.object_version
		and int(second_result.get("checked_objects", -1)) == 0,
		"CityStateValidator must invalidate equal-version cache data when object-state identity changes."
	)


func _create_owned_city_fixture(
	city_name: String,
	culture_name: String,
	city_world: WorldData,
	city_seed: int
) -> CitySettlementSimulationState:
	var culture := WorldData.create_culture(culture_name)
	var culture_id := int(culture.get("id", -1))
	var polity := WorldPoliticalState.create_polity({
		"name": city_name + " Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})
	var city := WorldPoliticalState.create_settlement({
		"name": city_name,
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": int(polity.get("id", -1)),
		"world_region_top_left": Vector2i.ZERO,
		"world_region_center": Vector2i.ZERO,
		"world_region_size": 1,
		"simulation_backend_kind": (
			SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE
		),
	})
	var city_id := int(city.get("id", -1))
	var city_state = WorldPoliticalState.get_city_simulation_state(city_id)
	if (
		not city_state is CitySettlementSimulationState
		or not WorldPoliticalState.set_active_settlement(city_id)
	):
		return null

	city_state.city_world = city_world
	city_state.city_seed = city_seed
	_seed_city_runtime_data(city_state, city_id, city_name, culture_id)
	return city_state


func _register_keep(
	city_state: CitySettlementSimulationState,
	city_world: WorldData,
	top_left: Vector2i,
	object_owner: String
) -> Dictionary:
	return CityObjectSystem.register_completed_city_object_for_city_state(
		city_state,
		{
			"object_type": CityObjectCatalog.CITY_OBJECT_CITY_CENTER,
			"top_left": top_left,
			"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
				CityObjectCatalog.CITY_OBJECT_CITY_CENTER
			),
			"object_owner": object_owner,
			"city_world": city_world,
		}
	)


func _seed_city_runtime_data(
	city_state: CitySettlementSimulationState,
	city_id: int,
	city_name: String,
	culture_id: int
) -> void:
	if city_state == null:
		return

	city_state.city_runtime_data.merge({
		"id": city_id,
		"name": city_name,
		"primary_culture_id": culture_id,
		"founded": false,
		"can_build": false,
	}, true)


func _mark_city_founded(
	city_state: CitySettlementSimulationState,
	keep: Dictionary
) -> void:
	if city_state == null or city_state.city_world == null or keep.is_empty():
		return

	city_state.city_runtime_data.merge({
		"city_world_seed": city_state.city_seed,
		"city_map_size": Vector2i(
			city_state.city_world.width,
			city_state.city_world.height
		),
		"foundation_top_left": keep.get("top_left", Vector2i(-1, -1)),
		"foundation_size": keep.get("size", Vector2i.ZERO),
		"foundation_object_id": int(keep.get("id", -1)),
		"foundation_object_owner": str(keep.get("owner", "")),
		"founded": true,
		"can_build": true,
	}, true)


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
