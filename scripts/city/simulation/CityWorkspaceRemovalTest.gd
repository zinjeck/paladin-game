extends Node

var failure_count: int = 0

func _ready() -> void:
	_test_direct_city_runtime_selection()
	_test_pre_context_runtime_adoption()
	WorldData.reset_runtime_session_state()
	if failure_count > 0:
		push_error("City workspace removal test failed: " + str(failure_count))
		get_tree().quit(1)
		return
	print("City workspace removal test passed.")
	get_tree().quit(0)

func _test_direct_city_runtime_selection() -> void:
	WorldData.reset_runtime_session_state()
	var culture := WorldData.create_culture("Workspace Culture")
	var polity := WorldPoliticalState.create_polity({
		"name": "Workspace Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": int(culture.get("id", -1)),
	})
	var city_a := _create_city("Workspace A", int(polity.get("id", -1)), Vector2i(1, 1))
	var city_b := _create_city("Workspace B", int(polity.get("id", -1)), Vector2i(2, 2))
	var state_a = WorldPoliticalState.get_city_simulation_state(int(city_a.get("id", -1)))
	var state_b = WorldPoliticalState.get_city_simulation_state(int(city_b.get("id", -1)))
	var world_a := _make_world(6, 6, 12001)
	var world_b := _make_world(7, 7, 12002)
	state_a.city_world = world_a
	state_a.city_seed = 111
	state_a.city_runtime_data = {"marker": "A"}
	state_b.city_world = world_b
	state_b.city_seed = 222
	state_b.city_runtime_data = {"marker": "B"}
	_expect(WorldPoliticalState.set_active_settlement(int(city_a["id"])), "City A must activate.")
	_expect(WorldPoliticalState.get_current_city_world() == world_a and WorldPoliticalState.get_current_city_seed() == 111 and WorldPoliticalState.get_current_city_runtime_data().get("marker") == "A", "City A runtime must resolve directly.")
	WorldPoliticalState.get_current_city_runtime_data()["local_only"] = 1
	_expect(WorldPoliticalState.set_active_settlement(int(city_b["id"])), "City B must activate.")
	_expect(WorldPoliticalState.get_current_city_world() == world_b and WorldPoliticalState.get_current_city_seed() == 222 and WorldPoliticalState.get_current_city_runtime_data().get("marker") == "B" and not state_b.city_runtime_data.has("local_only"), "City B must not receive City A workspace data.")
	WorldPoliticalState.get_current_city_runtime_data()["local_only"] = 2
	_expect(WorldPoliticalState.set_active_settlement(int(city_a["id"])), "City A must reactivate.")
	_expect(WorldPoliticalState.get_current_city_runtime_data().get("local_only") == 1 and state_b.city_runtime_data.get("local_only") == 2, "A/B/A switching must select owners without copying.")

func _test_pre_context_runtime_adoption() -> void:
	WorldData.reset_runtime_session_state()
	var city_world := _make_world(5, 5, 13001)
	var runtime_data := {"marker": "bootstrap"}
	WorldPoliticalState.store_current_city_world(city_world, 31337)
	WorldPoliticalState.replace_current_city_runtime_data(runtime_data)
	var world := _make_world(8, 8, 13002)
	_expect(WorldData.lock_world_save({
		"source_world": world,
		"region_top_left": Vector2i(1, 1),
		"region_center": Vector2i(2, 2),
		"region_size": 3,
		"world_scene_path": "res://scenes/GameSession.tscn",
		"city_scene_path": "res://scenes/CityScreen.tscn",
		"city_name": "Bootstrap City",
		"culture_name": "Bootstrap Culture",
	}), "Founding world must lock.")
	_expect(WorldPoliticalState.synchronize_foundation_with_world_data(), "Foundation must synchronize.")
	var state = WorldPoliticalState.get_active_city_simulation_state()
	_expect(state != null and state.city_world == city_world and state.city_seed == 31337 and is_same(state.city_runtime_data, runtime_data), "Foundation must adopt the exact pre-context runtime owner values.")

func _create_city(name: String, polity_id: int, center: Vector2i) -> Dictionary:
	return WorldPoliticalState.create_settlement({
		"name": name,
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": polity_id,
		"world_region_top_left": center,
		"world_region_center": center,
		"world_region_size": 1,
		"simulation_backend_kind": SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE,
	})

func _make_world(width: int, height: int, seed_value: int) -> WorldData:
	var world := WorldData.new()
	world.setup(width, height, seed_value)
	return world

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error("City workspace removal test: " + message)
