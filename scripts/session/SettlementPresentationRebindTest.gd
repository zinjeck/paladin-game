extends Node

const CITY_SCENE := preload("res://scenes/CityScreen.tscn")

var failure_count: int = 0


func _ready() -> void:
	await _test_atomic_settlement_presentation_rebind()
	WorldData.reset_runtime_session_state()
	SimulationClock.set_speed_multiplier(1.0)
	SimulationClock.set_simulation_paused(true)

	if failure_count > 0:
		push_error(
			"Settlement presentation rebind test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("Settlement presentation rebind test passed.")
	get_tree().quit(0)


func _test_atomic_settlement_presentation_rebind() -> void:
	WorldData.reset_runtime_session_state()
	var culture := WorldData.create_culture("Presentation Culture")
	var culture_id := int(culture.get("id", -1))
	var polity := WorldPoliticalState.create_polity({
		"name": "Presentation Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})
	var polity_id := int(polity.get("id", -1))
	var city_a := _create_city("Presentation A", polity_id, Vector2i(2, 2))
	var city_b := _create_city("Presentation B", polity_id, Vector2i(4, 4))
	var city_a_id := int(city_a.get("id", -1))
	var city_b_id := int(city_b.get("id", -1))
	var fixture_a := _seed_city(
		city_a_id,
		culture_id,
		"Presentation A",
		18,
		14,
		91_001,
		WorldData.CITY_SURFACE_FEATURE_TREE,
		"owner_a"
	)
	var fixture_b := _seed_city(
		city_b_id,
		culture_id,
		"Presentation B",
		13,
		21,
		92_002,
		WorldData.CITY_SURFACE_FEATURE_ROCK,
		"owner_b"
	)

	if (
		culture_id <= 0
		or city_a_id <= 0
		or city_b_id <= 0
		or fixture_a.is_empty()
		or fixture_b.is_empty()
	):
		_expect(false, "The A/B presentation fixture must be created.")
		return

	var context_a = WorldPoliticalState.get_settlement_context(city_a_id)
	var context_b = WorldPoliticalState.get_settlement_context(city_b_id)
	var bootstrap_b := CitySettlementRuntimeBootstrap.ensure_ready(context_b)
	SimulationClock.set_speed_multiplier(2.0)
	SimulationClock.set_simulation_paused(true)
	var renderer := CITY_SCENE.instantiate() as CityRenderer
	_expect(renderer != null, "The City scene must instantiate its renderer.")
	if renderer == null:
		return

	var binding_a := CityRendererBindingSupport.bootstrap_and_configure_renderer(
		renderer,
		context_a
	)
	if (
		binding_a.is_empty()
		or not bool(bootstrap_b.get("success", false))
		or not WorldPoliticalState.set_active_settlement(city_b_id)
	):
		_expect(false, "Both settlements must bootstrap before the presentation test.")
		renderer.free()
		return

	add_child(renderer)
	await get_tree().process_frame
	await get_tree().process_frame

	var state_a: CitySettlementSimulationState = fixture_a["state"]
	var state_b: CitySettlementSimulationState = fixture_b["state"]
	var object_a: Dictionary = fixture_a["object"]
	var object_b: Dictionary = fixture_b["object"]
	var citizen_a: Dictionary = fixture_a["citizen"]
	var citizen_b: Dictionary = fixture_b["citizen"]
	var citizen_a_name := str(citizen_a.get("name", ""))
	var citizen_b_name := str(citizen_b.get("name", ""))
	var feature_a: Vector2i = fixture_a["feature_tile"]
	var feature_b: Vector2i = fixture_b["feature_tile"]
	var state_a_snapshot := _capture_gameplay_snapshot(state_a)
	var state_b_snapshot := _capture_gameplay_snapshot(state_b)
	var state_a_identities := _capture_gameplay_identities(state_a)
	var state_b_identities := _capture_gameplay_identities(state_b)

	_expect(
		WorldPoliticalState.active_settlement_id == city_b_id
		and renderer.bound_city_settlement_id == city_a_id
		and is_same(renderer.bound_settlement_context, context_a)
		and is_same(renderer.city_world, state_a.city_world)
		and renderer.city_seed == state_a.city_seed
		and renderer.city_tree_multimesh_index_by_tile.has(feature_a)
		and renderer.city_rock_multimesh_index_by_tile.is_empty()
		and renderer.get_city_object_by_id(int(object_a.get("id", -1))).get(
			"owner", ""
		) == "owner_a"
		and SimulationClock.simulation_paused
		and is_equal_approx(SimulationClock.speed_multiplier, 2.0),
		"Renderer _ready() must retain its explicit A binding while global presentation remains B and must not resume the clock."
	)
	var renderer_binding_a := renderer.get_city_presentation_binding()
	_expect_renderer_helpers_bound(
		renderer,
		renderer_binding_a,
		0,
		citizen_a_name,
		citizen_b_name,
		null,
		"Every renderer-owned helper must share A's exact binding generation and diagnostic source."
	)

	var a_camera_position := Vector2(23.0, 17.0)
	var a_camera_zoom := Vector2(2.0, 2.0)
	renderer.camera.edge_scroll_enabled = false
	renderer.camera.position = a_camera_position
	renderer.camera.zoom = a_camera_zoom
	renderer.camera.clamp_camera_to_map_bounds()
	a_camera_position = renderer.camera.position
	a_camera_zoom = renderer.camera.zoom
	_arm_stale_city_a_presentation(renderer, int(object_a.get("id", -1)))

	var session := GameSession.new()
	session.city_view = renderer
	session.active_view = renderer
	session.city_view_has_been_entered = true
	SimulationClock.set_speed_multiplier(3.0)
	SimulationClock.set_simulation_paused(false)
	var switched_to_b := session.show_settlement_city_view(city_b_id)

	_expect(
		switched_to_b
		and WorldPoliticalState.active_settlement_id == city_b_id
		and renderer.bound_city_settlement_id == city_b_id
		and is_same(renderer.city_world, state_b.city_world)
		and renderer.city_seed == state_b.city_seed
		and renderer.city_terrain_texture.get_width() == state_b.city_world.width
		and renderer.city_terrain_texture.get_height() == state_b.city_world.height
		and renderer.camera.map_width_tiles == state_b.city_world.width
		and renderer.camera.map_height_tiles == state_b.city_world.height,
		"The transaction must atomically select and bind City B's differently sized world."
	)
	_expect(
		not SimulationClock.simulation_paused
		and is_equal_approx(SimulationClock.speed_multiplier, 3.0),
		"A view rebind must restore the exact intended simulation pause and speed state."
	)
	_expect(
		not renderer.has_selected_city_entity()
		and not renderer.has_debug_selected_city_tile()
		and not renderer.has_active_city_object_placement()
		and not renderer.is_road_placement_active
		and not renderer.is_road_dragging
		and renderer.road_preview_tiles.is_empty()
		and renderer.road_preview_lookup.is_empty()
		and not renderer.is_city_player_command_tool_active()
		and not renderer.is_city_player_command_dragging
		and renderer.city_player_command_drag_preview_tiles.is_empty()
		and not renderer.is_object_selection_dragging
		and renderer.debug_navigation_path.is_empty()
		and not renderer.workplace_details_open,
		"Selections, attached panels, placement ghosts, roads, commands, and debug paths from A must not cross into B."
	)
	_expect(
		renderer.get_city_object_by_id(int(object_b.get("id", -1))).get(
			"owner", ""
		) == "owner_b"
		and renderer.city_information_ui.city_name_label.text
		== "Presentation B"
		and renderer.city_tree_multimesh_index_by_tile.is_empty()
		and renderer.city_rock_multimesh_index_by_tile.has(feature_b)
		and not renderer.city_rock_multimesh_index_by_tile.has(feature_a),
		"B's object, UI identity, and natural-feature cache must replace every A presentation source."
	)
	var renderer_binding_b := renderer.get_city_presentation_binding()
	_expect_renderer_helpers_bound(
		renderer,
		renderer_binding_b,
		renderer_binding_a.generation,
		citizen_b_name,
		citizen_a_name,
		renderer_binding_a,
		"A-to-B rebind must replace every helper binding and diagnostic source in one generation."
	)
	_expect(
		_capture_gameplay_snapshot(state_a) == state_a_snapshot
		and _capture_gameplay_snapshot(state_b) == state_b_snapshot
		and _gameplay_identities_match(state_a, state_a_identities)
		and _gameplay_identities_match(state_b, state_b_identities),
		"Switching A to B must not reset or replace gameplay state in either settlement."
	)

	await get_tree().process_frame
	await get_tree().process_frame
	_expect(
		not renderer.city_presentation_rebind_pending
		and renderer.city_background_render_layer.visible
		and renderer.city_citizen_render_layer.visible
		and renderer.city_interaction_render_layer.visible,
		"Retained render layers must stay hidden until their B redraw is ready, then reveal together."
	)

	renderer.camera.position = Vector2(7.0, 29.0)
	renderer.camera.zoom = Vector2(1.5, 1.5)
	renderer.camera.clamp_camera_to_map_bounds()
	renderer.set_selected_city_object(int(object_b.get("id", -1)))
	renderer.start_city_object_placement(
		CityObjectCatalog.CITY_OBJECT_HOUSE,
		CityObjectCatalog.get_city_object_size_for_type(
			CityObjectCatalog.CITY_OBJECT_HOUSE
		)
	)
	var switched_back_to_a := session.show_settlement_city_view(city_a_id)
	await get_tree().process_frame
	await get_tree().process_frame

	_expect(
		switched_back_to_a
		and WorldPoliticalState.active_settlement_id == city_a_id
		and renderer.bound_city_settlement_id == city_a_id
		and is_same(renderer.city_world, state_a.city_world)
		and renderer.city_information_ui.city_name_label.text
		== "Presentation A"
		and renderer.city_tree_multimesh_index_by_tile.has(feature_a)
		and renderer.city_rock_multimesh_index_by_tile.is_empty()
		and renderer.get_city_object_by_id(int(object_a.get("id", -1))).get(
			"owner", ""
		) == "owner_a",
		"A/B/A must restore City A presentation from A authority, never from B's equal local IDs."
	)
	var renderer_binding_a_again := renderer.get_city_presentation_binding()
	_expect_renderer_helpers_bound(
		renderer,
		renderer_binding_a_again,
		renderer_binding_b.generation,
		citizen_a_name,
		citizen_b_name,
		renderer_binding_b,
		"A/B/A must bind every helper to the new A generation rather than reusing stale helper state."
	)
	_expect(
		renderer.camera.position.is_equal_approx(a_camera_position)
		and renderer.camera.zoom.is_equal_approx(a_camera_zoom),
		"Each settlement must retain its own presentation-only camera state across A/B/A."
	)
	_expect(
		_capture_gameplay_snapshot(state_a) == state_a_snapshot
		and _capture_gameplay_snapshot(state_b) == state_b_snapshot
		and _gameplay_identities_match(state_a, state_a_identities)
		and _gameplay_identities_match(state_b, state_b_identities),
		"A/B/A must reconstruct presentation only and preserve exact gameplay values and owners."
	)

	var active_before_rejection := WorldPoliticalState.active_settlement_id
	var world_before_rejection := renderer.city_world
	_expect(
		not session.show_settlement_city_view(city_b_id, {
			"city_world": state_a.city_world,
			"city_seed": state_a.city_seed,
		})
		and WorldPoliticalState.active_settlement_id == active_before_rejection
		and is_same(renderer.city_world, world_before_rejection),
		"A mismatched prepared payload must be rejected before the presentation target changes."
	)

	session.free()
	renderer.queue_free()
	await get_tree().process_frame


func _expect_renderer_helpers_bound(
	renderer: CityRenderer,
	binding: CityPresentationBinding,
	minimum_generation: int,
	included_citizen_name: String,
	excluded_citizen_name: String,
	stale_binding: CityPresentationBinding,
	message: String
) -> void:
	var citizen_debug_text := renderer.get_citizen_debug_list_text()
	var helpers_match := (
		binding != null
		and binding.is_valid()
		and binding.generation > minimum_generation
		and renderer.city_information_ui.is_bound_to_city_presentation(binding)
		and renderer.citizen_debug_ui.is_bound_to_city_presentation(binding)
		and renderer.city_debug_presentation.is_bound_to_city_presentation(binding)
		and renderer.city_citizen_movement_presentation.is_bound_to_city_presentation(
			binding
		)
		and renderer.workplace_zone_overlay_cache.is_bound_to_city_presentation(
			binding
		)
		and included_citizen_name in citizen_debug_text
		and excluded_citizen_name not in citizen_debug_text
	)
	if stale_binding != null:
		helpers_match = (
			helpers_match
			and not renderer.city_information_ui.is_bound_to_city_presentation(
				stale_binding
			)
		)
	_expect(helpers_match, message)


func _arm_stale_city_a_presentation(renderer: CityRenderer, object_id: int) -> void:
	renderer.set_selected_city_object(object_id)
	renderer.start_city_object_placement(
		CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS,
		CityObjectCatalog.get_city_object_size_for_type(
			CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS
		)
	)
	renderer.is_road_placement_active = true
	renderer.is_road_dragging = true
	renderer.road_preview_tiles = [Vector2i(4, 4)]
	renderer.road_preview_lookup = {Vector2i(4, 4): true}
	renderer.active_city_player_command_type = (
		CityWorkSystem.CITY_PLAYER_COMMAND_TYPE_CHOP_TREE
	)
	renderer.is_city_player_command_dragging = true
	renderer.city_player_command_drag_preview_tiles = [Vector2i(5, 5)]
	renderer.is_object_selection_dragging = true
	renderer.debug_navigation_path = [Vector2i(1, 1), Vector2i(2, 1)]
	renderer.workplace_details_open = true


func _seed_city(
	settlement_id: int,
	culture_id: int,
	city_name: String,
	width: int,
	height: int,
	seed_value: int,
	feature: String,
	object_owner: String
) -> Dictionary:
	var state = WorldPoliticalState.get_city_simulation_state(settlement_id)
	if not state is CitySettlementSimulationState:
		return {}

	state.city_world = _make_world(width, height, seed_value)
	state.city_seed = seed_value
	state.city_runtime_data = {
		"name": city_name,
		"primary_culture_id": culture_id,
		"founded": false,
		"can_build": false,
	}
	var city_object := CityObjectSystem.register_completed_city_object_for_city_state(
		state,
		{
			"object_type": CityObjectCatalog.CITY_OBJECT_CITY_CENTER,
			"top_left": Vector2i(1, 1),
			"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
				CityObjectCatalog.CITY_OBJECT_CITY_CENTER
			),
			"object_owner": object_owner,
		}
	)
	var female_names := CityCitizens.get_city_citizen_name_pool_for_sex(
		CityCitizens.CITY_CITIZEN_SEX_FEMALE
	)
	var citizen_name_index := 0 if object_owner == "owner_a" else 1
	var citizen_name := (
		str(female_names[citizen_name_index])
		if female_names.size() > citizen_name_index
		else ""
	)
	var citizen := CityCitizenRegistrySystem.add_city_citizen_for_city_state(
		state,
		citizen_name,
		Vector2i(width - 2, 1),
		CityCitizens.CITY_CITIZEN_SEX_FEMALE,
		culture_id
	)
	var feature_tile := Vector2i(width - 2, height - 2)
	if (
		city_object.is_empty()
		or citizen.is_empty()
		or not state.city_world.set_tile_surface_feature(feature_tile, feature)
	):
		return {}

	return {
		"state": state,
		"object": city_object,
		"citizen": citizen,
		"feature_tile": feature_tile,
	}


func _create_city(
	city_name: String,
	polity_id: int,
	region_center: Vector2i
) -> Dictionary:
	return WorldPoliticalState.create_settlement({
		"name": city_name,
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": polity_id,
		"world_region_top_left": region_center,
		"world_region_center": region_center,
		"world_region_size": 1,
		"simulation_backend_kind": (
			SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE
		),
	})


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
		"public_storage_version": state.resource_accounting_state.public_storage_version,
		"movement_version": state.citizen_movement_runtime_state.citizen_movement_version,
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
		and is_same(state.citizen_spatial_state.citizen_ids_by_tile, identities["spatial"])
		and is_same(state.citizen_task_runtime_state.active_task_ids, identities["tasks"])
		and is_same(state.citizen_movement_runtime_state.active_mover_ids, identities["movement"])
		and is_same(state.logistics_state.ground_piles, identities["piles"])
		and is_same(state.construction_state.construction_sites, identities["sites"])
	)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error("Settlement presentation rebind test: " + message)
