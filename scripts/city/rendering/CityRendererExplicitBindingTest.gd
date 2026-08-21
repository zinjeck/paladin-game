extends Node

const CITY_SCENE := preload("res://scenes/CityScreen.tscn")
const CITY_STATE_VALIDATOR := preload(
	"res://scripts/city/simulation/CityStateValidator.gd"
)

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
	var city_control := _create_city(
		"Explicit Renderer Control",
		polity_id,
		Vector2i(10, 10)
	)
	var city_a_id := int(city_a.get("id", -1))
	var city_b_id := int(city_b.get("id", -1))
	var city_control_id := int(city_control.get("id", -1))
	if (
		culture_id <= 0
		or city_a_id <= 0
		or city_b_id <= 0
		or city_control_id <= 0
	):
		_expect(false, "The explicit renderer A/B/control fixture must be created.")
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
		81_001,
		"owner_b"
	)
	var state_control: CitySettlementSimulationState = _seed_city(
		city_control_id,
		culture_id,
		"Explicit Renderer Control",
		81_001,
		"owner_control"
	)
	if state_a == null or state_b == null or state_control == null:
		_expect(false, "All explicit renderer states must be seeded.")
		return

	var context_a: SettlementSimulationContext = (
		WorldPoliticalState.get_settlement_context(city_a_id)
	)
	var context_b: SettlementSimulationContext = (
		WorldPoliticalState.get_settlement_context(city_b_id)
	)
	var context_control: SettlementSimulationContext = (
		WorldPoliticalState.get_settlement_context(city_control_id)
	)
	if context_a == null or context_b == null or context_control == null:
		_expect(false, "All renderer contexts must remain registered.")
		return

	var overlap_projection := _capture_overlap_projection(state_a)
	_expect(
		overlap_projection == _capture_overlap_projection(state_b)
		and overlap_projection == _capture_overlap_projection(state_control)
		and overlap_projection.get("citizen_ids", []) == [1, 2, 3, 4, 5, 6, 7, 8]
		and overlap_projection.get("object_ids", []) == [1, 2]
		and overlap_projection.get("construction_site_ids", []) == [1]
		and overlap_projection.get("ground_pile_ids", []) == [1]
		and overlap_projection.get("active_task_ids", []) == [1]
		and overlap_projection.get("work_order_ids", []) == [1],
		"A, B, and the control must begin with overlapping local IDs and equal numeric versions in every required domain."
	)

	SimulationClock.start_new_game(3, 11, 27)
	SimulationClock.set_speed_multiplier(3.0)
	SimulationClock.set_simulation_paused(true)

	# Present B, then bootstrap, simulate, and validate A. Every B/control owner
	# is captured before the pipeline so any implicit target discovery is visible.
	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id),
		"Settlement B must be selected before City A's explicit pipeline."
	)
	var b_before_a_pipeline := _capture_gameplay_snapshot(state_b)
	var b_identities_before_a_pipeline := _capture_gameplay_identities(state_b)
	var control_before_a_pipeline := _capture_gameplay_snapshot(state_control)
	var control_identities_before_a_pipeline := (
		_capture_gameplay_identities(state_control)
	)
	var bootstrap_a := CitySettlementRuntimeBootstrap.ensure_ready(context_a)
	SimulationCoordinator.run_settlement_simulation_systems(
		context_a,
		1,
		15
	)
	var validation_a := CITY_STATE_VALIDATOR.validate_for_settlement(
		context_a,
		true,
		false
	)
	_expect(
		bool(bootstrap_a.get("success", false))
		and bool(validation_a.get("valid", false))
		and WorldPoliticalState.active_settlement_id == city_b_id,
		"Presented B must survive City A bootstrap, simulation, and validation."
	)
	_expect(
		_capture_gameplay_snapshot(state_b) == b_before_a_pipeline
		and _gameplay_identities_match(state_b, b_identities_before_a_pipeline)
		and _capture_gameplay_snapshot(state_control) == control_before_a_pipeline
		and _gameplay_identities_match(
			state_control,
			control_identities_before_a_pipeline
		),
		"City A's explicit pipeline must leave B and the control untouched."
	)

	# Reverse the target while A is presented, then run the identical B pipeline.
	_expect(
		WorldPoliticalState.set_active_settlement(city_a_id),
		"Settlement A must be selected before the reversed City B pipeline."
	)
	var a_before_b_pipeline := _capture_gameplay_snapshot(state_a)
	var a_identities_before_b_pipeline := _capture_gameplay_identities(state_a)
	var bootstrap_b := CitySettlementRuntimeBootstrap.ensure_ready(context_b)
	SimulationCoordinator.run_settlement_simulation_systems(
		context_b,
		1,
		15
	)
	var validation_b := CITY_STATE_VALIDATOR.validate_for_settlement(
		context_b,
		true,
		false
	)
	_expect(
		bool(bootstrap_b.get("success", false))
		and bool(validation_b.get("valid", false))
		and WorldPoliticalState.active_settlement_id == city_a_id
		and _capture_gameplay_snapshot(state_a) == a_before_b_pipeline
		and _gameplay_identities_match(state_a, a_identities_before_b_pipeline),
		"Reversed City B execution must preserve the presented City A exactly."
	)

	# Run the same pipeline with the control kept selected throughout and compare
	# normalized deterministic outputs before any renderer consumes visual events.
	_expect(
		WorldPoliticalState.set_active_settlement(city_control_id),
		"The control settlement must remain selected for its entire pipeline."
	)
	var bootstrap_control := CitySettlementRuntimeBootstrap.ensure_ready(
		context_control
	)
	SimulationCoordinator.run_settlement_simulation_systems(
		context_control,
		1,
		15
	)
	var validation_control := CITY_STATE_VALIDATOR.validate_for_settlement(
		context_control,
		true,
		false
	)
	var deterministic_a := _capture_deterministic_projection(state_a)
	var deterministic_b := _capture_deterministic_projection(state_b)
	var deterministic_control := _capture_deterministic_projection(state_control)
	_expect(
		bool(bootstrap_control.get("success", false))
		and bool(validation_control.get("valid", false))
		and WorldPoliticalState.active_settlement_id == city_control_id
		and deterministic_a == deterministic_b
		and deterministic_a == deterministic_control,
		"A/B reversed execution must equal a control run whose presentation never changed."
	)

	state_a.citizen_movement_runtime_state.citizen_movement_visual_events = [
		{"settlement": "a"},
	]
	state_b.citizen_movement_runtime_state.citizen_movement_visual_events = [
		{"settlement": "b"},
	]
	state_control.citizen_movement_runtime_state.citizen_movement_visual_events = [
		{"settlement": "control"},
	]
	# The renderer reads the owned-resource summary during UI construction. Prime
	# the exact-source non-authoritative cache in all three otherwise-identical
	# states so presentation startup is compared after the same cache boundary.
	CityResourceAccountingSystem.get_total_owned_city_resource_amounts_for_city_state(
		state_a
	)
	CityResourceAccountingSystem.get_total_owned_city_resource_amounts_for_city_state(
		state_b
	)
	CityResourceAccountingSystem.get_total_owned_city_resource_amounts_for_city_state(
		state_control
	)
	var a_snapshot := _capture_gameplay_snapshot(state_a)
	var b_snapshot := _capture_gameplay_snapshot(state_b)
	var a_identities := _capture_gameplay_identities(state_a)
	var b_identities := _capture_gameplay_identities(state_b)

	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id),
		"Settlement B must remain globally selected during renderer A startup."
	)
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

	# Create the same real task/command IDs in all three targets after their
	# equivalent simulation pipelines, then execute A while B is presented.
	var command_tile := Vector2i(9, 9)
	var prepared_a := _prepare_local_command(state_a, command_tile)
	var prepared_b := _prepare_local_command(state_b, command_tile)
	var prepared_control := _prepare_local_command(state_control, command_tile)
	var prepared_overlap := _capture_overlap_projection(state_a)
	_expect(
		prepared_a
		and prepared_b
		and prepared_control
		and prepared_overlap == _capture_overlap_projection(state_b)
		and prepared_overlap == _capture_overlap_projection(state_control)
		and prepared_overlap.get("player_command_ids", []) == [1]
		and prepared_overlap.get("active_task_ids", []).has(1),
		"A, B, and the control must hold overlapping command and task IDs before local execution."
	)
	var b_before_a_command := _capture_gameplay_snapshot(state_b)
	var b_identities_before_a_command := _capture_gameplay_identities(state_b)
	var control_before_a_command := _capture_gameplay_snapshot(state_control)
	var control_identities_before_a_command := (
		_capture_gameplay_identities(state_control)
	)
	_expect(
		_complete_local_command(state_a, command_tile),
		"A-bound command execution must complete against City A's world and owners."
	)
	_expect(
		WorldPoliticalState.active_settlement_id == city_b_id
		and _capture_gameplay_snapshot(state_b) == b_before_a_command
		and _gameplay_identities_match(state_b, b_identities_before_a_command)
		and _capture_gameplay_snapshot(state_control) == control_before_a_command
		and _gameplay_identities_match(
			state_control,
			control_identities_before_a_command
		),
		"Executing a local command in rendered A must leave B and the control unchanged."
	)

	# Reverse the rendered target: present A, bind B, and execute B's equivalent
	# command without changing A or the control.
	WorldPoliticalState.set_active_settlement(city_a_id)
	var rebound_b := renderer.rebind_city_presentation(context_b)
	var a_before_b_command := _capture_gameplay_snapshot(state_a)
	var a_identities_before_b_command := _capture_gameplay_identities(state_a)
	var control_before_b_command := _capture_gameplay_snapshot(state_control)
	var control_identities_before_b_command := (
		_capture_gameplay_identities(state_control)
	)
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
	_expect(
		_complete_local_command(state_b, command_tile)
		and _capture_gameplay_snapshot(state_a) == a_before_b_command
		and _gameplay_identities_match(state_a, a_identities_before_b_command)
		and _capture_gameplay_snapshot(state_control) == control_before_b_command
		and _gameplay_identities_match(
			state_control,
			control_identities_before_b_command
		),
		"Reversed command execution in B must leave A and the control unchanged."
	)

	# The control remains selected while its renderer bind and command execute.
	WorldPoliticalState.set_active_settlement(city_control_id)
	var rebound_control := renderer.rebind_city_presentation(context_control)
	var a_before_control_command := _capture_gameplay_snapshot(state_a)
	var b_before_control_command := _capture_gameplay_snapshot(state_b)
	_expect(
		rebound_control
		and WorldPoliticalState.active_settlement_id == city_control_id
		and renderer.bound_city_settlement_id == city_control_id
		and _complete_local_command(state_control, command_tile)
		and _capture_gameplay_snapshot(state_a) == a_before_control_command
		and _capture_gameplay_snapshot(state_b) == b_before_control_command,
		"The control command must run with an unchanged presentation target and preserve A/B."
	)
	_expect(
		_capture_deterministic_projection(state_a)
		== _capture_deterministic_projection(state_b)
		and _capture_deterministic_projection(state_a)
		== _capture_deterministic_projection(state_control),
		"Reversed A/B command output must equal the never-switched control output."
	)

	# One final rebind proves the renderer remains reusable after all three
	# pipelines; the completed gameplay states must remain byte-for-byte stable.
	a_snapshot = _capture_gameplay_snapshot(state_a)
	b_snapshot = _capture_gameplay_snapshot(state_b)
	a_identities = _capture_gameplay_identities(state_a)
	b_identities = _capture_gameplay_identities(state_b)
	WorldPoliticalState.set_active_settlement(city_b_id)
	var rebound_a := renderer.rebind_city_presentation(context_a)
	_expect(
		rebound_a
		and WorldPoliticalState.active_settlement_id == city_b_id
		and renderer.bound_city_settlement_id == city_a_id
		and renderer.get_city_object_by_id(shared_object_id).get(
			"owner",
			""
		) == "owner_a"
		and _capture_gameplay_snapshot(state_a) == a_snapshot
		and _capture_gameplay_snapshot(state_b) == b_snapshot
		and _gameplay_identities_match(state_a, a_identities)
		and _gameplay_identities_match(state_b, b_identities),
		"Final renderer rebinding must preserve both completed settlement states."
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
	if city_object.is_empty():
		return null
	if not WorldPoliticalState.found_city_settlement(
		settlement_id,
		{
			"city_world_seed": seed_value,
			"city_map_size": Vector2i(
				state.city_world.width,
				state.city_world.height
			),
			"primary_culture_id": culture_id,
			"foundation_top_left": city_object.get(
				"top_left",
				Vector2i(-1, -1)
			),
			"foundation_size": city_object.get("size", Vector2i.ZERO),
			"can_build": true,
		}
	):
		return null
	if not _seed_overlap_domains(state, 1):
		return null
	return state


func _seed_overlap_domains(
	state: CitySettlementSimulationState,
	citizen_id: int
) -> bool:
	var house := CityObjectSystem.register_completed_city_object_for_city_state(
		state,
		{
			"object_type": CityObjectCatalog.CITY_OBJECT_HOUSE,
			"top_left": Vector2i(7, 2),
			"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
				CityObjectCatalog.CITY_OBJECT_HOUSE
			),
			"object_owner": "player",
		}
	)
	var house_id := int(house.get("id", -1))
	if (
		house_id <= 0
		or not CityAssignmentSystem.assign_city_citizen_home_for_city_state(
			state,
			citizen_id,
			house_id
		)
		or not CityCitizenTaskRuntimeSystem.assign_city_citizen_task_for_city_state(
			state,
			citizen_id,
			{
				"kind": CityCitizens.CITY_CITIZEN_TASK_KIND_RETURN_HOME,
				"source": CityCitizens.CITY_CITIZEN_TASK_SOURCE_SCHEDULE,
				"priority": 50,
				"target_object_id": house_id,
			}
		)
	):
		return false

	var road_sites := CityConstructionSystem.create_road_sites_for_city_state(
		state,
		[Vector2i(10, 1)],
		"player",
		state.city_world
	)
	if road_sites.size() != 1:
		return false
	var site_id := int(road_sites[0].get("id", -1))
	var work_order := (
		CityWorkSystem.synchronize_construction_work_order_for_city_state(
			state,
			site_id
		)
	)
	var pile_result := (
		CityLogisticsSystem.add_resource_to_city_ground_piles_with_result_for_city_state(
			state,
			{
				"tile_position": Vector2i(10, 10),
				"resource": CityResourceCatalog.RESOURCE_STONE,
				"amount_delta": 3,
			}
		)
	)
	return (
		site_id == 1
		and int(work_order.get("id", -1)) == 1
		and int(pile_result.get("added_amount", 0)) == 3
	)


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


func _prepare_local_command(
	state: CitySettlementSimulationState,
	tile_position: Vector2i
) -> bool:
	var citizen_id := int(
		state.citizen_registry_state.citizens[0].get("id", -1)
	)
	var current_task := (
		CityCitizenTaskRuntimeSystem.get_city_citizen_current_task_for_city_state(
			state,
			citizen_id
		)
	)
	if (
		not current_task.is_empty()
		and not CityCitizenTaskRuntimeSystem.clear_city_citizen_task_for_city_state(
			state,
			citizen_id,
			str(
				current_task.get(
					"source",
					CityCitizens.CITY_CITIZEN_TASK_SOURCE_NONE
				)
			)
		)
	):
		return false
	if (
		not state.city_world.set_tile_surface_feature(
			tile_position,
			WorldData.CITY_SURFACE_FEATURE_TREE
		)
		or CityWorkSystem.add_city_player_command_targets_for_city_state(
			state,
			CityWorkSystem.CITY_PLAYER_COMMAND_TYPE_CHOP_TREE,
			[tile_position]
		) != 1
	):
		return false
	var command := CityWorkSystem.get_city_player_command_at_tile_for_city_state(
		state,
		tile_position
	)
	var command_id := int(command.get("id", -1))
	return (
		command_id > 0
		and CityWorkSystem.claim_city_player_command_for_city_state(
			state,
			command_id,
			citizen_id
		)
		and CityCitizenTaskRuntimeSystem.assign_city_citizen_task_for_city_state(
			state,
			citizen_id,
			{
				"kind": CityCitizens.CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND,
				"source": CityCitizens.CITY_CITIZEN_TASK_SOURCE_PLAYER,
				"priority": 100,
				"target_object_id": command_id,
				"player_locked": true,
			}
		)
	)


func _complete_local_command(
	state: CitySettlementSimulationState,
	tile_position: Vector2i
) -> bool:
	var citizen_id := int(
		state.citizen_registry_state.citizens[0].get("id", -1)
	)
	var command := CityWorkSystem.get_city_player_command_at_tile_for_city_state(
		state,
		tile_position
	)
	var command_id := int(command.get("id", -1))
	return (
		command_id > 0
		and CityWorkSystem.complete_city_player_command_for_city_state(
			state,
			command_id,
			citizen_id
		)
		and CityCitizenTaskRuntimeSystem.clear_city_citizen_task_for_city_state(
			state,
			citizen_id,
			CityCitizens.CITY_CITIZEN_TASK_SOURCE_PLAYER
		)
		and CityWorkSystem.get_city_player_command_at_tile_for_city_state(
			state,
			tile_position
		).is_empty()
		and str(
			state.city_world.get_tile(
				tile_position.x,
				tile_position.y
			).get(
				"surface_feature",
				WorldData.CITY_SURFACE_FEATURE_NONE
			)
		) == WorldData.CITY_SURFACE_FEATURE_NONE
	)


func _capture_overlap_projection(
	state: CitySettlementSimulationState
) -> Dictionary:
	var citizen_ids: Array = []
	for citizen in state.citizen_registry_state.citizens:
		citizen_ids.append(int(citizen.get("id", -1)))
	citizen_ids.sort()
	var object_ids: Array = []
	for city_object in state.object_state.objects:
		object_ids.append(int(city_object.get("id", -1)))
	object_ids.sort()
	var construction_site_ids: Array = []
	for site in state.construction_state.construction_sites:
		construction_site_ids.append(int(site.get("id", -1)))
	construction_site_ids.sort()
	var ground_pile_ids: Array = []
	for pile in state.logistics_state.ground_piles:
		ground_pile_ids.append(int(pile.get("id", -1)))
	ground_pile_ids.sort()
	var player_command_ids: Array = []
	for command in state.work_state.player_commands:
		player_command_ids.append(int(command.get("id", -1)))
	player_command_ids.sort()
	var work_order_ids: Array = state.work_state.work_orders.keys()
	work_order_ids.sort()
	return {
		"citizen_ids": citizen_ids,
		"object_ids": object_ids,
		"construction_site_ids": construction_site_ids,
		"ground_pile_ids": ground_pile_ids,
		"active_task_ids": (
			state.citizen_task_runtime_state.active_task_ids.duplicate()
		),
		"player_command_ids": player_command_ids,
		"work_order_ids": work_order_ids,
		"citizen_version": state.citizen_registry_state.citizen_version,
		"object_version": state.object_state.object_version,
		"construction_version": state.construction_state.construction_version,
		"ground_pile_version": state.logistics_state.ground_pile_version,
		"task_version": state.citizen_task_runtime_state.citizen_task_version,
		"player_command_version": state.work_state.player_command_version,
		"work_order_version": state.work_state.work_order_version,
	}


func _capture_deterministic_projection(
	state: CitySettlementSimulationState
) -> Dictionary:
	var object_projection: Array = []
	for city_object in state.object_state.objects:
		object_projection.append({
			"id": int(city_object.get("id", -1)),
			"type": str(city_object.get("type", "")),
			"top_left": city_object.get("top_left", Vector2i(-1, -1)),
			"size": city_object.get("size", Vector2i.ZERO),
			"resident_ids": city_object.get("resident_ids", []).duplicate(),
			"assigned_worker_ids": (
				city_object.get("assigned_worker_ids", []).duplicate()
			),
			"stored_resources": (
				city_object.get("stored_resources", {}).duplicate(true)
			),
		})
	return {
		"citizens": state.citizen_registry_state.citizens.duplicate(true),
		"objects": object_projection,
		"construction_sites": (
			state.construction_state.construction_sites.duplicate(true)
		),
		"ground_piles": state.logistics_state.ground_piles.duplicate(true),
		"player_commands": state.work_state.player_commands.duplicate(true),
		"work_orders": state.work_state.work_orders.duplicate(true),
		"active_task_ids": (
			state.citizen_task_runtime_state.active_task_ids.duplicate()
		),
		"decision_initialized": (
			state.citizen_decision_runtime_state.runtime_initialized
		),
		"decision_pending": (
			state.citizen_decision_runtime_state.pending_decision_ids.duplicate()
		),
		"versions": _capture_overlap_projection(state),
		"tile_data_version": state.city_world.tile_data_version,
		"surface_feature_version": (
			state.city_world.city_surface_feature_change_version
		),
	}


func _capture_gameplay_snapshot(
	state: CitySettlementSimulationState
) -> Dictionary:
	var owner_values := {}
	var owners := _get_gameplay_owner_map(state)
	for owner_key in owners.keys():
		owner_values[owner_key] = _capture_script_variable_values(
			owners[owner_key]
		)
	# Presentation consumers intentionally drain these event queues. They are not
	# authoritative gameplay values and are asserted separately at the bind site.
	owner_values["citizen_movement_runtime_state"].erase(
		"citizen_movement_visual_events"
	)
	owner_values["citizen_movement_runtime_state"].erase(
		"citizen_movement_visual_tick_index"
	)
	var world_values := _capture_script_variable_values(state.city_world)
	world_values.erase("pending_city_surface_feature_changes")
	return {
		"city_seed": state.city_seed,
		"runtime": state.city_runtime_data.duplicate(true),
		"world": world_values,
		"owners": owner_values,
	}


func _capture_gameplay_identities(
	state: CitySettlementSimulationState
) -> Dictionary:
	var identities := {
		"world": state.city_world,
		"runtime": state.city_runtime_data,
	}
	identities.merge(_get_gameplay_owner_map(state))
	return identities


func _gameplay_identities_match(
	state: CitySettlementSimulationState,
	identities: Dictionary
) -> bool:
	if (
		not is_same(state.city_world, identities.get("world"))
		or not is_same(state.city_runtime_data, identities.get("runtime"))
	):
		return false
	var owners := _get_gameplay_owner_map(state)
	for owner_key in owners.keys():
		if not is_same(owners[owner_key], identities.get(owner_key)):
			return false
	return true


func _get_gameplay_owner_map(
	state: CitySettlementSimulationState
) -> Dictionary:
	return {
		"object_state": state.object_state,
		"resource_accounting_state": state.resource_accounting_state,
		"citizen_registry_state": state.citizen_registry_state,
		"assignment_state": state.assignment_state,
		"workplace_state": state.workplace_state,
		"citizen_spatial_state": state.citizen_spatial_state,
		"citizen_movement_runtime_state": (
			state.citizen_movement_runtime_state
		),
		"citizen_task_runtime_state": state.citizen_task_runtime_state,
		"citizen_decision_runtime_state": (
			state.citizen_decision_runtime_state
		),
		"work_state": state.work_state,
		"logistics_state": state.logistics_state,
		"construction_state": state.construction_state,
		"navigation_state": state.navigation_state,
	}


func _capture_script_variable_values(owner) -> Dictionary:
	if owner == null or not owner.has_method("get_property_list"):
		return {}
	var values := {}
	for property in owner.get_property_list():
		var usage := int(property.get("usage", 0))
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var property_name := str(property.get("name", ""))
		if property_name.is_empty():
			continue
		var value = owner.get(property_name)
		if value is Dictionary:
			values[property_name] = value.duplicate(true)
		elif value is Array:
			values[property_name] = value.duplicate(true)
		else:
			values[property_name] = value
	return values


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error(message)
