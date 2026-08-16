extends Node

const CITY_SCENE := preload("res://scenes/CityScreen.tscn")

var failure_count: int = 0


func _ready() -> void:
	await _test_explicit_renderer_binding_and_presentation_only_ready()
	WorldData.reset_runtime_session_state()
	SimulationClock.reset_clock_state()

	if failure_count > 0:
		push_error(
			"City renderer explicit-binding test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City renderer explicit-binding test passed.")
	get_tree().quit(0)


func _test_explicit_renderer_binding_and_presentation_only_ready() -> void:
	WorldData.reset_runtime_session_state()
	SimulationClock.reset_clock_state()
	var culture := WorldData.create_culture("Explicit Renderer Culture")
	var culture_id := int(culture.get("id", -1))
	var polity := WorldPoliticalState.create_polity({
		"name": "Explicit Renderer Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})
	var polity_id := int(polity.get("id", -1))
	var city_a := _create_city(
		"Explicit Renderer A",
		polity_id,
		Vector2i(1, 1)
	)
	var city_b := _create_city(
		"Explicit Renderer B",
		polity_id,
		Vector2i(8, 8)
	)
	var city_a_id := int(city_a.get("id", -1))
	var city_b_id := int(city_b.get("id", -1))
	if culture_id <= 0 or city_a_id <= 0 or city_b_id <= 0:
		_expect(false, "The explicit renderer A/B fixture must be created.")
		return

	var state_a: CitySettlementSimulationState = _seed_city(
		city_a_id,
		culture_id,
		"Explicit Renderer A",
		81_001,
		"owner_a"
	)
	var state_b: CitySettlementSimulationState = _seed_city(
		city_b_id,
		culture_id,
		"Explicit Renderer B",
		82_002,
		"owner_b"
	)
	if state_a == null or state_b == null:
		_expect(false, "Both explicit renderer states must be seeded.")
		return

	var context_a: SettlementSimulationContext = (
		WorldPoliticalState.get_settlement_context(city_a_id)
	)
	var context_b: SettlementSimulationContext = (
		WorldPoliticalState.get_settlement_context(city_b_id)
	)
	var bootstrap_a := CitySettlementRuntimeBootstrap.ensure_ready(context_a)
	var bootstrap_b := CitySettlementRuntimeBootstrap.ensure_ready(context_b)
	if (
		not bool(bootstrap_a.get("success", false))
		or not bool(bootstrap_b.get("success", false))
	):
		_expect(false, "Both explicit renderer settlements must bootstrap headlessly.")
		return

	# Prove rendering can follow a prior headless simulation of A while B remains
	# the globally selected presentation target.
	SimulationCoordinator.run_settlement_simulation_systems(
		context_a,
		1,
		15
	)
	state_a.citizen_movement_runtime_state.citizen_movement_visual_events = [
		{"settlement": "a"},
	]
	state_b.citizen_movement_runtime_state.citizen_movement_visual_events = [
		{"settlement": "b"},
	]
	var a_snapshot := _capture_gameplay_snapshot(state_a)
	var b_snapshot := _capture_gameplay_snapshot(state_b)
	var a_identities := _capture_gameplay_identities(state_a)
	var b_identities := _capture_gameplay_identities(state_b)

	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id),
		"Settlement B must remain globally selected during renderer A startup."
	)
	SimulationClock.start_new_game(3, 11, 27)
	SimulationClock.set_speed_multiplier(3.0)
	SimulationClock.set_simulation_paused(true)
	var clock_minutes_before := SimulationClock.absolute_world_minutes
	var clock_tick_before := SimulationClock.tick_index

	var renderer := CITY_SCENE.instantiate() as CityRenderer
	_expect(renderer != null, "CityScreen must instantiate a CityRenderer.")
	if renderer == null:
		return
	var binding := CityRendererBindingSupport.bootstrap_and_configure_renderer(
		renderer,
		context_a
	)
	_expect(
		not binding.is_empty(),
		"Renderer A must be explicitly configured before entering the tree."
	)
	if binding.is_empty():
		renderer.free()
		return

	add_child(renderer)
	await get_tree().process_frame
	await get_tree().process_frame

	var object_a: Dictionary = state_a.object_state.objects[0]
	var object_b: Dictionary = state_b.object_state.objects[0]
	var shared_object_id := int(object_a.get("id", -1))
	_expect(
		WorldPoliticalState.active_settlement_id == city_b_id
		and renderer.bound_city_settlement_id == city_a_id
		and is_same(renderer.bound_settlement_context, context_a)
		and is_same(renderer.bound_city_state, state_a)
		and is_same(renderer.city_world, state_a.city_world)
		and renderer.city_seed == state_a.city_seed
		and renderer.get_city_object_by_id(shared_object_id).get(
			"owner",
			""
		) == "owner_a"
		and str(object_b.get("owner", "")) == "owner_b",
		"Renderer startup must use A's bound owners even when B is globally selected and local IDs overlap."
	)
	_expect(
		SimulationClock.simulation_paused
		and is_equal_approx(SimulationClock.speed_multiplier, 3.0)
		and SimulationClock.absolute_world_minutes == clock_minutes_before
		and SimulationClock.tick_index == clock_tick_before,
		"Constructing CityRenderer must not resume, reset, or advance the global clock."
	)
	_expect(
		_capture_gameplay_snapshot(state_a) == a_snapshot
		and _capture_gameplay_snapshot(state_b) == b_snapshot
		and _gameplay_identities_match(state_a, a_identities)
		and _gameplay_identities_match(state_b, b_identities),
		"Presentation-only _ready() must preserve every gameplay value, version, and owner in A and B."
	)
	_expect(
		state_a.citizen_movement_runtime_state
		.citizen_movement_visual_events.is_empty()
		and state_b.citizen_movement_runtime_state
		.citizen_movement_visual_events == [{"settlement": "b"}],
		"Renderer startup may consume only the bound settlement's visual-event queue."
	)

	# Direct renderer rebinding is independent from session presentation choice.
	WorldPoliticalState.set_active_settlement(city_a_id)
	var rebound_b := renderer.rebind_city_presentation(context_b)
	_expect(
		rebound_b
		and WorldPoliticalState.active_settlement_id == city_a_id
		and renderer.bound_city_settlement_id == city_b_id
		and renderer.get_city_object_by_id(shared_object_id).get(
			"owner",
			""
		) == "owner_b",
		"Renderer must bind B while global presentation intentionally remains A."
	)
	WorldPoliticalState.set_active_settlement(city_b_id)
	var rebound_a := renderer.rebind_city_presentation(context_a)
	_expect(
		rebound_a
		and WorldPoliticalState.active_settlement_id == city_b_id
		and renderer.bound_city_settlement_id == city_a_id
		and renderer.get_city_object_by_id(shared_object_id).get(
			"owner",
			""
		) == "owner_a",
		"Renderer must rebind A while global presentation intentionally remains B."
	)
	_expect(
		_capture_gameplay_snapshot(state_a) == a_snapshot
		and _capture_gameplay_snapshot(state_b) == b_snapshot
		and _gameplay_identities_match(state_a, a_identities)
		and _gameplay_identities_match(state_b, b_identities),
		"A/B/A presentation rebinding must never mutate either settlement's gameplay state."
	)

	renderer.queue_free()
	await get_tree().process_frame


func _create_city(
	city_name: String,
	polity_id: int,
	world_region: Vector2i
) -> Dictionary:
	return WorldPoliticalState.create_settlement({
		"name": city_name,
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": polity_id,
		"world_region_top_left": world_region,
		"world_region_center": world_region,
		"world_region_size": 1,
		"simulation_backend_kind": (
			SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE
		),
	})


func _seed_city(
	settlement_id: int,
	culture_id: int,
	city_name: String,
	seed_value: int,
	object_owner: String
) -> CitySettlementSimulationState:
	var state: CitySettlementSimulationState = (
		WorldPoliticalState.get_city_simulation_state(settlement_id)
	)
	if not state is CitySettlementSimulationState:
		return null

	state.city_world = _make_world(12, 12, seed_value)
	state.city_seed = seed_value
	state.city_runtime_data = {
		"id": settlement_id,
		"name": city_name,
		"primary_culture_id": culture_id,
		"founded": false,
		"can_build": false,
	}
	var city_object := CityObjectSystem.register_completed_city_object_for_city_state(
		state,
		{
			"object_type": CityObjectCatalog.CITY_OBJECT_CITY_CENTER,
			"top_left": Vector2i(2, 2),
			"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
				CityObjectCatalog.CITY_OBJECT_CITY_CENTER
			),
			"object_owner": object_owner,
		}
	)
	var citizen := CityCitizenRegistrySystem.add_city_citizen_for_city_state(
		state,
		"",
		Vector2i(8, 8),
		CityCitizens.CITY_CITIZEN_SEX_FEMALE,
		culture_id
	)
	if city_object.is_empty() or citizen.is_empty():
		return null
	return state


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


func _capture_gameplay_snapshot(
	state: CitySettlementSimulationState
) -> Dictionary:
	return {
		"runtime": state.city_runtime_data.duplicate(true),
		"objects": state.object_state.objects.duplicate(true),
		"object_version": state.object_state.object_version,
		"citizens": state.citizen_registry_state.citizens.duplicate(true),
		"citizen_version": state.citizen_registry_state.citizen_version,
		"spatial_version": state.citizen_spatial_state.citizen_spatial_version,
		"assignment_version": state.assignment_state.assignment_version,
		"workplace_version": state.workplace_state.workplace_version,
		"container_version": state.resource_accounting_state.container_version,
		"public_storage_version": (
			state.resource_accounting_state.public_storage_version
		),
		"movement_version": (
			state.citizen_movement_runtime_state.citizen_movement_version
		),
		"task_version": state.citizen_task_runtime_state.citizen_task_version,
		"ground_pile_version": state.logistics_state.ground_pile_version,
		"construction_version": state.construction_state.construction_version,
	}


func _capture_gameplay_identities(
	state: CitySettlementSimulationState
) -> Dictionary:
	return {
		"world": state.city_world,
		"objects": state.object_state.objects,
		"citizens": state.citizen_registry_state.citizens,
		"spatial": state.citizen_spatial_state.citizen_ids_by_tile,
		"tasks": state.citizen_task_runtime_state.active_task_ids,
		"movement": state.citizen_movement_runtime_state.active_mover_ids,
		"piles": state.logistics_state.ground_piles,
		"sites": state.construction_state.construction_sites,
	}


func _gameplay_identities_match(
	state: CitySettlementSimulationState,
	identities: Dictionary
) -> bool:
	return (
		is_same(state.city_world, identities["world"])
		and is_same(state.object_state.objects, identities["objects"])
		and is_same(state.citizen_registry_state.citizens, identities["citizens"])
		and is_same(
			state.citizen_spatial_state.citizen_ids_by_tile,
			identities["spatial"]
		)
		and is_same(
			state.citizen_task_runtime_state.active_task_ids,
			identities["tasks"]
		)
		and is_same(
			state.citizen_movement_runtime_state.active_mover_ids,
			identities["movement"]
		)
		and is_same(state.logistics_state.ground_piles, identities["piles"])
		and is_same(
			state.construction_state.construction_sites,
			identities["sites"]
		)
	)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error(message)
