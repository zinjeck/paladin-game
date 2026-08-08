extends Node

const TEST_CITY_NAME := "Logistics Bootstrap City"
const TEST_CULTURE_NAME := "Logistics Bootstrap Culture"

var failure_count: int = 0


func _ready() -> void:
	_run_bootstrap_test()
	WorldPoliticalState.reset_state()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City logistics-state bootstrap test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City logistics-state bootstrap test passed.")
	get_tree().quit(0)


func _run_bootstrap_test() -> void:
	WorldPoliticalState.reset_state()
	WorldData.reset_runtime_session_state()

	var world := _make_world(8, 8, 84_021)
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

	# Low-level fixtures can create physical logistics state before the first
	# simulation tick establishes the founding settlement context.
	CityLogisticsSystem.get_current_state().ground_piles = [
		{
			"id": 17,
			"tile_position": Vector2i(3, 3),
			"resource_type": WorldData.RESOURCE_FISH,
			"amount": 4,
			"test_owner": "bootstrap",
		},
	]
	CityLogisticsSystem.get_current_state().ground_pile_index_by_id = {17: 0}
	CityLogisticsSystem.get_current_state().next_ground_pile_id = 18
	CityLogisticsSystem.get_current_state().ground_pile_version = 5
	CityLogisticsSystem.get_current_state().haul_reservations = {
		23: {"id": 23, "citizen_id": 3, "test_owner": "bootstrap"},
	}
	CityLogisticsSystem.get_current_state().haul_reservation_id_by_citizen_id = {3: 23}
	CityLogisticsSystem.get_current_state().haul_source_reserved_amount_by_key = {"test:source": 2}
	CityLogisticsSystem.get_current_state().haul_destination_reserved_amount_by_key = {"test:destination": 2}
	CityLogisticsSystem.get_current_state().next_haul_reservation_id = 24
	CityLogisticsSystem.get_current_state().haul_reservation_version = 7

	var bootstrap_state = WorldPoliticalState.get_current_city_logistics_state()
	_expect(
		bootstrap_state is CityLogisticsState,
		"Pre-context logistics must live in the unbound CityLogisticsState."
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
		capital_state.logistics_state == bootstrap_state,
		"Founding City must adopt the exact pre-context logistics-state object."
	)
	_expect(
		str(capital_state.logistics_state.ground_piles[0].get("test_owner", ""))
		== "bootstrap"
		and capital_state.logistics_state.next_ground_pile_id == 18
		and capital_state.logistics_state.ground_pile_version == 5,
		"Bootstrap ground-pile state must survive context establishment."
	)
	_expect(
		capital_state.logistics_state.haul_reservations.has(23)
		and capital_state.logistics_state.next_haul_reservation_id == 24
		and capital_state.logistics_state.haul_reservation_version == 7,
		"Bootstrap haul-reservation state must survive context establishment."
	)
	_expect(
		CityLogisticsSystem.get_current_state().ground_piles == capital_state.logistics_state.ground_piles
		and CityLogisticsSystem.get_current_state().haul_reservations
		== capital_state.logistics_state.haul_reservations,
		"CityLogisticsSystem must resolve to the active City's logistics state."
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
	push_error("City logistics-state bootstrap test: " + message)
