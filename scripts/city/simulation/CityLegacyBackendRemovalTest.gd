extends Node

var failure_count: int = 0

func _ready() -> void:
	_test_single_city_backend_contract()
	WorldData.reset_runtime_session_state()
	if failure_count > 0:
		push_error("Legacy city backend removal test failed: " + str(failure_count))
		get_tree().quit(1)
		return
	print("Legacy city backend removal test passed.")
	get_tree().quit(0)

func _test_single_city_backend_contract() -> void:
	WorldData.reset_runtime_session_state()
	var culture := WorldData.create_culture("Pass 13 Culture")
	var polity := WorldPoliticalState.create_polity({
		"name": "Pass 13 Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": int(culture.get("id", -1)),
	})
	var invalid := WorldPoliticalState.create_settlement({
		"name": "Retired Backend City",
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": int(polity.get("id", -1)),
		"world_region_top_left": Vector2i.ZERO,
		"world_region_center": Vector2i.ZERO,
		"world_region_size": 1,
		"simulation_backend_kind": "legacy_" + "city_world_data",
	})
	_expect(invalid.is_empty(), "The retired legacy backend string must be rejected.")
	var a := _create_city("Pass 13 A", int(polity.get("id", -1)), Vector2i(1, 1))
	var b := _create_city("Pass 13 B", int(polity.get("id", -1)), Vector2i(2, 2))
	_expect(not a.is_empty() and not b.is_empty(), "Both instance-owned Cities must be created.")
	if a.is_empty() or b.is_empty():
		return
	var state_a = WorldPoliticalState.get_city_simulation_state(int(a["id"]))
	var state_b = WorldPoliticalState.get_city_simulation_state(int(b["id"]))
	_expect(state_a is CitySettlementSimulationState and state_b is CitySettlementSimulationState and not is_same(state_a, state_b), "Every City must receive its own state owner.")
	state_a.city_runtime_data["marker"] = "A"
	state_b.city_runtime_data["marker"] = "B"
	_expect(WorldPoliticalState.set_active_settlement(int(a["id"])), "City A must activate.")
	_expect(WorldPoliticalState.get_active_settlement_context().supports_city_simulation() and WorldPoliticalState.get_current_city_runtime_data().get("marker") == "A", "City A must resolve through the sole city backend.")
	_expect(WorldPoliticalState.set_active_settlement(int(b["id"])), "City B must activate.")
	_expect(WorldPoliticalState.get_active_settlement_context().supports_city_simulation() and WorldPoliticalState.get_current_city_runtime_data().get("marker") == "B", "City B must resolve independently.")
	_expect(WorldPoliticalState.set_active_settlement(int(a["id"])) and WorldPoliticalState.get_current_city_runtime_data().get("marker") == "A", "A/B/A selection must preserve direct owner isolation.")

func _create_city(name: String, polity_id: int, tile: Vector2i) -> Dictionary:
	return WorldPoliticalState.create_settlement({
		"name": name,
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": polity_id,
		"world_region_top_left": tile,
		"world_region_center": tile,
		"world_region_size": 1,
		"simulation_backend_kind": SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE,
	})

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error("Legacy city backend removal test: " + message)
