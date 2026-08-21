extends Node

const MapCameraSessionStateScript := preload(
	"res://scripts/map/MapCameraSessionState.gd"
)
const MapTextureCacheStateScript := preload(
	"res://scripts/map/visuals/MapTextureCacheState.gd"
)

var failure_count: int = 0


func _ready() -> void:
	_test_explicit_helper_binding_and_rebind()
	_test_exact_bound_debug_commands()
	_test_renderer_debug_command_authority_boundary()
	_test_exact_texture_cache_source_identity()
	MapCameraSessionStateScript.reset_city_camera()
	MapTextureCacheStateScript.clear_city_cache()
	WorldData.reset_runtime_session_state()

	if failure_count > 0:
		push_error(
			"City presentation helper binding test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City presentation helper binding test passed.")
	get_tree().quit(0)


func _test_explicit_helper_binding_and_rebind() -> void:
	WorldData.reset_runtime_session_state()
	MapCameraSessionStateScript.reset_city_camera()
	var fixture := _create_two_city_fixture()
	if fixture.is_empty():
		_expect(false, "The A/B presentation-helper fixture must be created.")
		return

	var city_a_id: int = fixture["city_a_id"]
	var city_b_id: int = fixture["city_b_id"]
	var state_a: CitySettlementSimulationState = fixture["state_a"]
	var state_b: CitySettlementSimulationState = fixture["state_b"]
	var context_a: SettlementSimulationContext = fixture["context_a"]
	var context_b: SettlementSimulationContext = fixture["context_b"]
	var fishery_a: Dictionary = fixture["fishery_a"]
	var fishery_b: Dictionary = fixture["fishery_b"]
	var citizen_a: Dictionary = fixture["citizen_a"]
	var citizen_b: Dictionary = fixture["citizen_b"]
	var citizen_b_only: Dictionary = fixture["citizen_b_only"]
	var citizen_a_name := str(citizen_a.get("name", ""))
	var citizen_b_name := str(citizen_b.get("name", ""))
	var citizen_b_only_name := str(citizen_b_only.get("name", ""))
	var citizen_a_id := int(citizen_a.get("id", -1))
	var citizen_b_only_id := int(citizen_b_only.get("id", -1))

	var binding_a := CityPresentationBinding.new()
	var binding_b := CityPresentationBinding.new()
	_expect(
		binding_a.rebind(context_a, 1)
		and binding_b.rebind(context_b, 2),
		"Both helpers must receive valid explicit bindings."
	)
	if not binding_a.is_valid() or not binding_b.is_valid():
		return

	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id),
		"Settlement B must remain globally selected while helpers display A."
	)
	_expect(
		int(fishery_a.get("id", -1)) == int(fishery_b.get("id", -2))
		and fishery_a.get("top_left") == fishery_b.get("top_left")
		and fishery_a.get("size") == fishery_b.get("size")
		and citizen_a_id == int(citizen_b.get("id", -2)),
		"The helper fixture must overlap A/B object and citizen identities."
	)

	var information_ui := CityInformationPanel.new()
	var information_parent := Control.new()
	add_child(information_parent)
	_expect(
		information_ui.bind_city_presentation(binding_a),
		"The city information panel must bind to A explicitly."
	)
	information_ui.setup(information_parent)
	_expect(
		information_ui.city_name_label.text == "Helper City A"
		and information_ui.population_button.text == "Pop\n1"
		and is_equal_approx(information_ui.hunger_bar.value, 80.0)
		and is_equal_approx(information_ui.happiness_bar.value, 90.0)
		and WorldPoliticalState.active_settlement_id == city_b_id,
		"The information panel must show A identity, population, and needs while B is globally selected."
	)

	var citizen_debug := CitizenDebugPanel.new()
	_expect(
		citizen_debug.bind_city_presentation(binding_a),
		"Citizen diagnostics must bind to A explicitly."
	)
	var citizen_text_a := citizen_debug.get_debug_list_text()
	_expect(
		citizen_a_name in citizen_text_a
		and citizen_b_name not in citizen_text_a
		and citizen_b_only_name not in citizen_text_a,
		"A-bound citizen diagnostics must never resolve B citizens with overlapping IDs."
	)

	var debug_presentation := CityDebugPresentation.new()
	_expect(
		debug_presentation.bind_city_presentation(
			binding_a,
			citizen_debug
		),
		"City diagnostics must share the exact A binding."
	)
	var simulation_text_a := debug_presentation.get_simulation_text({})
	_expect(
		("Settlement: " + str(city_a_id)) in simulation_text_a
		and WorldPoliticalState.active_settlement_id == city_b_id,
		"The validator summary must report A without following global selection B."
	)

	state_a.citizen_movement_runtime_state.active_mover_ids = [citizen_a_id]
	state_a.citizen_movement_runtime_state.active_mover_id_lookup = {
		citizen_a_id: true,
	}
	state_b.citizen_movement_runtime_state.active_mover_ids = [
		citizen_b_only_id,
	]
	state_b.citizen_movement_runtime_state.active_mover_id_lookup = {
		citizen_b_only_id: true,
	}
	var movement_presentation := CityCitizenMovementPresentation.new()
	_expect(
		movement_presentation.bind_settlement_presentation(binding_a, 16),
		"Movement presentation must bind to A explicitly."
	)
	var citizen_a_rect := movement_presentation.get_citizen_world_rect(
		citizen_a
	)
	_expect(
		movement_presentation.local_tile_size == 16
		and citizen_a_rect.size == Vector2(8.0, 8.0)
		and movement_presentation.synchronized_movement_version
		== state_a.citizen_movement_runtime_state.citizen_movement_version,
		"Movement presentation must own tile geometry and its synchronized version."
	)
	movement_presentation.track_mover(citizen_b_only_id)
	_expect(
		movement_presentation.get_transitioning_citizen_ids_snapshot()
		== [citizen_a_id],
		"A-bound movement presentation must reject B-only movers."
	)

	var overlay_cache := CityWorkplaceZoneOverlayCache.new()
	_expect(
		overlay_cache.bind_city_presentation(binding_a),
		"The workplace overlay cache must bind to A explicitly."
	)
	var overlay_a := overlay_cache.prepare({
		"city_object": fishery_a,
		"preview_mode": false,
		"city_tile_size": 16,
	})
	var rejected_b_overlay := overlay_cache.prepare({
		"city_object": fishery_b,
		"preview_mode": false,
		"city_tile_size": 16,
	})
	_expect(
		not overlay_a.is_empty()
		and int(overlay_a.get("city_state_instance_id", -1))
		== int(state_a.get_instance_id())
		and int(overlay_a.get("city_world_instance_id", -1))
		== int(state_a.city_world.get_instance_id())
		and int(overlay_a.get("binding_generation", -1)) == 1
		and rejected_b_overlay.is_empty(),
		"The A overlay cache must reject B's equal-ID object by exact owner identity."
	)

	# Every helper retains the binding token itself. Reusing that token for B
	# used to mutate all helpers from A to B without any helper accepting a
	# rebind. The token is now one-shot and its public identity is read-only.
	var rejected_in_place_rebind := not binding_a.rebind(context_b, 3)
	binding_a.settlement_context = context_b
	binding_a.settlement_state = state_b
	binding_a.settlement_id = city_b_id
	binding_a.world = state_b.city_world
	binding_a.seed = state_b.city_seed
	binding_a.generation = 3
	binding_a.highest_accepted_generation = 3
	_expect(
		rejected_in_place_rebind
		and binding_a.matches_context(context_a)
		and binding_a.settlement_id == city_a_id
		and is_same(binding_a.settlement_state, state_a)
		and binding_a.generation == 1
		and binding_a.highest_accepted_generation == 1
		and information_ui.is_bound_to_settlement_presentation(binding_a)
		and citizen_debug.is_bound_to_settlement_presentation(binding_a)
		and debug_presentation.is_bound_to_settlement_presentation(binding_a)
		and movement_presentation.is_bound_to_settlement_presentation(binding_a)
		and overlay_cache.is_bound_to_settlement_presentation(binding_a),
		(
			"Rejected in-place A-to-B mutation must leave the binding token "
			+ "and every helper exactly A-bound."
		)
	)

	_expect(
		MapCameraSessionStateScript.store_city_camera_for_binding(
			binding_a,
			Vector2(11.0, 17.0),
			Vector2(2.0, 2.0)
		)
		and MapCameraSessionStateScript.store_city_camera_for_binding(
			binding_b,
			Vector2(29.0, 31.0),
			Vector2(1.5, 1.5)
		),
		"A and B must store independent presentation-only camera states."
	)
	_expect(
		MapCameraSessionStateScript.get_city_camera_for_binding(binding_a).get(
			"position"
		) == Vector2(11.0, 17.0)
		and MapCameraSessionStateScript.get_city_camera_for_binding(binding_b).get(
			"position"
		) == Vector2(29.0, 31.0)
		and MapCameraSessionStateScript.get_city_camera_entry_count() == 2,
		"Equal-shaped cities must not share one global city camera."
	)

	citizen_debug.is_open = true
	_expect(
		not movement_presentation.bind_settlement_presentation(binding_b, 0)
		and movement_presentation.is_bound_to_settlement_presentation(binding_a),
		"An invalid tile-size rebind must retain the previous settlement presentation."
	)
	_expect(
		information_ui.bind_city_presentation(binding_b)
		and citizen_debug.bind_city_presentation(binding_b)
		and debug_presentation.bind_city_presentation(
			binding_b,
			citizen_debug
		)
		and movement_presentation.bind_settlement_presentation(binding_b, 16)
		and overlay_cache.bind_city_presentation(binding_b),
		"Every renderer-owned helper must accept the same B rebind generation."
	)
	_expect(
		not information_ui.bind_settlement_presentation(binding_a)
		and information_ui.is_bound_to_settlement_presentation(binding_b)
		and not movement_presentation.bind_settlement_presentation(binding_a, 16)
		and movement_presentation.is_bound_to_settlement_presentation(binding_b)
		and not overlay_cache.bind_settlement_presentation(binding_a)
		and overlay_cache.is_bound_to_settlement_presentation(binding_b),
		(
			"Settlement-neutral helpers must reject stale A after accepting "
			+ "newer B and retain B unchanged."
		)
	)

	var reset_information_ui := CityInformationPanel.new()
	_expect(
		reset_information_ui.bind_settlement_presentation(binding_a),
		"The information reset fixture must first accept A."
	)
	reset_information_ui.reset_presentation()
	_expect(
		not reset_information_ui.bind_settlement_presentation(binding_a)
		and reset_information_ui.presentation_binding == null
		and reset_information_ui.highest_accepted_binding_generation == 1
		and reset_information_ui.bind_settlement_presentation(binding_b),
		"Information reset must preserve its binding generation high-water mark."
	)

	var reset_overlay_cache := CityWorkplaceZoneOverlayCache.new()
	_expect(
		reset_overlay_cache.bind_settlement_presentation(binding_a),
		"The overlay reset fixture must first accept A."
	)
	reset_overlay_cache.reset_presentation()
	_expect(
		not reset_overlay_cache.bind_settlement_presentation(binding_a)
		and reset_overlay_cache.presentation_binding == null
		and reset_overlay_cache.highest_accepted_binding_generation == 1
		and reset_overlay_cache.bind_settlement_presentation(binding_b),
		"Overlay reset must preserve its binding generation high-water mark."
	)

	var reset_movement_presentation := CityCitizenMovementPresentation.new()
	_expect(
		reset_movement_presentation.bind_settlement_presentation(binding_a, 16),
		"The reset high-water fixture must first accept A."
	)
	reset_movement_presentation.reset_presentation()
	_expect(
		not reset_movement_presentation.bind_settlement_presentation(
			binding_a,
			16
		)
		and reset_movement_presentation.presentation_binding == null
		and reset_movement_presentation.bound_city_state == null
		and reset_movement_presentation.highest_accepted_binding_generation == 1
		and reset_movement_presentation.bind_settlement_presentation(binding_b, 16),
		(
			"Movement reset must clear mutable state without lowering the binding "
			+ "generation high-water mark."
		)
	)
	var overlay_b := overlay_cache.prepare({
		"city_object": fishery_b,
		"preview_mode": false,
		"city_tile_size": 16,
	})
	var citizen_text_b := citizen_debug.get_debug_list_text()
	_expect(
		information_ui.city_name_label.text == "Helper City B"
		and information_ui.population_button.text == "Pop\n2"
		and is_equal_approx(information_ui.hunger_bar.value, 30.0)
		and is_equal_approx(information_ui.happiness_bar.value, 40.0)
		and citizen_b_name in citizen_text_b
		and citizen_b_only_name in citizen_text_b
		and citizen_a_name not in citizen_text_b
		and not citizen_debug.is_open,
		"Rebind must clear A-only helper state and display B data."
	)
	_expect(
		movement_presentation.get_transitioning_citizen_ids_snapshot()
		== [citizen_b_only_id]
		and not overlay_b.is_empty()
		and int(overlay_b.get("city_state_instance_id", -1))
		== int(state_b.get_instance_id())
		and int(overlay_b.get("binding_generation", -1)) == 2,
		"Rebind must replace mover tracking and workplace cache identity with B."
	)
	var citizen_stale_rebind_rejected := not citizen_debug.bind_city_presentation(
		binding_a
	)
	var presentation_stale_rebind_rejected := not debug_presentation.bind_city_presentation(
		binding_a,
		citizen_debug
	)
	_expect(
		citizen_stale_rebind_rejected
		and presentation_stale_rebind_rejected
		and citizen_debug.is_bound_to_city_presentation(binding_b)
		and debug_presentation.is_bound_to_city_presentation(binding_b),
		"Debug helpers must reject stale generations without replacing B."
	)
	var reset_guard_citizen_debug := CitizenDebugPanel.new()
	var reset_guard_debug_presentation := CityDebugPresentation.new()
	_expect(
		reset_guard_citizen_debug.bind_city_presentation(binding_a)
		and reset_guard_debug_presentation.bind_city_presentation(
			binding_a,
			reset_guard_citizen_debug
		),
		"Debug helper reset guards must accept their first generation."
	)
	reset_guard_debug_presentation.reset()
	var citizen_reset_stale_rejected := not reset_guard_citizen_debug.bind_city_presentation(
		binding_a
	)
	var presentation_reset_stale_rejected := not reset_guard_debug_presentation.bind_city_presentation(
		binding_a,
		reset_guard_citizen_debug
	)
	_expect(
		citizen_reset_stale_rejected
		and presentation_reset_stale_rejected,
		"Debug helper reset must retain the accepted-generation high-water mark."
	)

	# Deliberately create a fresh aggregate owner, then register it under A's
	# existing ID. This makes every context/binding for the former owner stale.
	var replacement_a := CitySettlementSimulationState.new()
	WorldPoliticalState.settlement_city_state_by_id[city_a_id] = replacement_a
	_seed_existing_state(
		replacement_a,
		city_a_id,
		int(fixture["culture_id"]),
		"Helper City A Replacement",
		141_003
	)
	var replacement_context_a: SettlementSimulationContext = (
		WorldPoliticalState.get_settlement_context(city_a_id)
	)
	var replacement_binding_a := CityPresentationBinding.new()
	_expect(
		replacement_binding_a.rebind(replacement_context_a, 3),
		"A replacement state must expose a fresh presentation binding."
	)
	_expect(
		MapCameraSessionStateScript.get_city_camera_for_binding(
			replacement_binding_a
		).is_empty()
		and MapCameraSessionStateScript.get_city_camera_entry_count() == 1,
		"A camera cached for the old state must not survive same-ID state replacement."
	)

	information_parent.queue_free()


func _test_exact_bound_debug_commands() -> void:
	WorldData.reset_runtime_session_state()
	var fixture := _create_two_city_fixture()
	if fixture.is_empty():
		_expect(false, "The debug-command A/B fixture must be created.")
		return

	var city_b_id: int = fixture["city_b_id"]
	var state_a: CitySettlementSimulationState = fixture["state_a"]
	var state_b: CitySettlementSimulationState = fixture["state_b"]
	var context_a: SettlementSimulationContext = fixture["context_a"]
	var context_b: SettlementSimulationContext = fixture["context_b"]
	var keep_a: Dictionary = fixture["keep_a"]
	var keep_b: Dictionary = fixture["keep_b"]
	var citizen_a: Dictionary = fixture["citizen_a"]
	var citizen_b: Dictionary = fixture["citizen_b"]
	var keep_a_id := int(keep_a.get("id", -1))
	var keep_b_id := int(keep_b.get("id", -1))
	var citizen_a_id := int(citizen_a.get("id", -1))
	var citizen_b_id := int(citizen_b.get("id", -1))
	var resource := CityResourceCatalog.RESOURCE_FISH
	var binding_a := CityPresentationBinding.new()
	var binding_b := CityPresentationBinding.new()
	var debug_presentation := CityDebugPresentation.new()
	var citizen_debug := CitizenDebugPanel.new()
	_expect(
		binding_a.rebind(context_a, 1)
		and binding_b.rebind(context_b, 2)
		and debug_presentation.bind_settlement_presentation(
			binding_a,
			citizen_debug
		)
		and WorldPoliticalState.set_active_settlement(city_b_id),
		"Debug commands must start exactly A-bound while B is globally active."
	)
	if not debug_presentation.is_bound_to_settlement_presentation(binding_a):
		return

	WorldData.debug_mode_enabled = true
	var resource_a_before := (
		CityResourceContainerSystem.get_city_object_stored_resource_amount(
			CityObjectSystem.get_city_object_by_id_for_city_state(
				state_a,
				keep_a_id
			),
			resource
		)
	)
	var resource_b_before := (
		CityResourceContainerSystem.get_city_object_stored_resource_amount(
			CityObjectSystem.get_city_object_by_id_for_city_state(
				state_b,
				keep_b_id
			),
			resource
		)
	)
	var no_storage_selection := (
		debug_presentation.execute_add_resource_to_selected_public_storage(
			binding_a,
			-1,
			resource,
			10
		)
	)
	var invalid_storage_amount := (
		debug_presentation.execute_add_resource_to_selected_public_storage(
			binding_a,
			keep_a_id,
			resource,
			0
		)
	)
	_expect(
		not bool(no_storage_selection.get("success", true))
		and no_storage_selection.get("status")
		== CityDebugPresentation.DEBUG_COMMAND_STATUS_NO_SELECTION
		and not bool(invalid_storage_amount.get("success", true))
		and invalid_storage_amount.get("status")
		== CityDebugPresentation.DEBUG_COMMAND_STATUS_INVALID_AMOUNT
		and CityResourceContainerSystem.get_city_object_stored_resource_amount(
			CityObjectSystem.get_city_object_by_id_for_city_state(
				state_a,
				keep_a_id
			),
			resource
		) == resource_a_before
		and CityResourceContainerSystem.get_city_object_stored_resource_amount(
			CityObjectSystem.get_city_object_by_id_for_city_state(
				state_b,
				keep_b_id
			),
			resource
		) == resource_b_before,
		"No-selection and invalid storage commands must be gameplay no-ops."
	)

	var storage_success := (
		debug_presentation.execute_add_resource_to_selected_public_storage(
			binding_a,
			keep_a_id,
			resource,
			10
		)
	)
	_expect(
		bool(storage_success.get("success", false))
		and bool(storage_success.get("changed", false))
		and int(storage_success.get("settlement_id", -1))
		== int(fixture["city_a_id"])
		and int(storage_success.get("binding_generation", -1)) == 1
		and int(storage_success.get("accepted_amount", 0)) == 10
		and not str(storage_success.get("message", "")).is_empty()
		and CityResourceContainerSystem.get_city_object_stored_resource_amount(
			CityObjectSystem.get_city_object_by_id_for_city_state(
				state_a,
				keep_a_id
			),
			resource
		) == resource_a_before + 10
		and CityResourceContainerSystem.get_city_object_stored_resource_amount(
			CityObjectSystem.get_city_object_by_id_for_city_state(
				state_b,
				keep_b_id
			),
			resource
		) == resource_b_before
		and WorldPoliticalState.active_settlement_id == city_b_id,
		"A-bound storage commands must report their owner and mutate only A."
	)

	var navigation_result := debug_presentation.request_navigation(
		citizen_a_id,
		Vector2i(13, 1)
	)
	var movement_a_before := state_a.citizen_movement_runtime_state.citizen_movement_version
	var movement_b_before := state_b.citizen_movement_runtime_state.citizen_movement_version
	var citizen_b_before := (
		CityCitizenRegistrySystem.get_city_citizen_by_id_for_city_state(
			state_b,
			citizen_b_id
		).duplicate(true)
	)
	var no_citizen_selection := (
		debug_presentation.execute_assign_navigation_path_to_selected_citizen(
			binding_a,
			-1
		)
	)
	var saved_navigation_start := debug_presentation.navigation_start_tile
	debug_presentation.navigation_start_tile = Vector2i.ZERO
	var stale_path := (
		debug_presentation.execute_assign_navigation_path_to_selected_citizen(
			binding_a,
			citizen_a_id
		)
	)
	debug_presentation.navigation_start_tile = saved_navigation_start
	_expect(
		str(navigation_result.get("status", ""))
		== CityNavigationSystem.PATH_STATUS_SUCCESS
		and no_citizen_selection.get("status")
		== CityDebugPresentation.DEBUG_COMMAND_STATUS_NO_SELECTION
		and stale_path.get("status")
		== CityDebugPresentation.DEBUG_COMMAND_STATUS_STALE_PATH
		and state_a.citizen_movement_runtime_state.citizen_movement_version
		== movement_a_before
		and state_b.citizen_movement_runtime_state.citizen_movement_version
		== movement_b_before,
		"No-selection and stale-path movement commands must be gameplay no-ops."
	)

	var movement_success := (
		debug_presentation.execute_assign_navigation_path_to_selected_citizen(
			binding_a,
			citizen_a_id
		)
	)
	var citizen_a_after := (
		CityCitizenRegistrySystem.get_city_citizen_by_id_for_city_state(
			state_a,
			citizen_a_id
		)
	)
	_expect(
		bool(movement_success.get("success", false))
		and int(movement_success.get("citizen_id", -1)) == citizen_a_id
		and int(movement_success.get("settlement_id", -1))
		== int(fixture["city_a_id"])
		and not str(movement_success.get("message", "")).is_empty()
		and str(citizen_a_after.get("movement_state", ""))
		== CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_MOVING
		and state_a.citizen_movement_runtime_state.citizen_movement_version
		> movement_a_before
		and state_b.citizen_movement_runtime_state.citizen_movement_version
		== movement_b_before
		and CityCitizenRegistrySystem.get_city_citizen_by_id_for_city_state(
			state_b,
			citizen_b_id
		) == citizen_b_before,
		"A-bound movement commands must mutate only A despite globally active B."
	)

	_expect(
		debug_presentation.bind_settlement_presentation(binding_b, citizen_debug),
		"The debug-command owner must accept the newer exact B binding."
	)
	var resource_a_before_stale_call := (
		CityResourceContainerSystem.get_city_object_stored_resource_amount(
			CityObjectSystem.get_city_object_by_id_for_city_state(
				state_a,
				keep_a_id
			),
			resource
		)
	)
	var resource_b_before_stale_call := (
		CityResourceContainerSystem.get_city_object_stored_resource_amount(
			CityObjectSystem.get_city_object_by_id_for_city_state(
				state_b,
				keep_b_id
			),
			resource
		)
	)
	var movement_a_before_stale_call := (
		state_a.citizen_movement_runtime_state.citizen_movement_version
	)
	var stale_storage_binding := (
		debug_presentation.execute_add_resource_to_selected_public_storage(
			binding_a,
			keep_a_id,
			resource,
			10
		)
	)
	var stale_movement_binding := (
		debug_presentation.execute_assign_navigation_path_to_selected_citizen(
			binding_a,
			citizen_a_id
		)
	)
	_expect(
		stale_storage_binding.get("status")
		== CityDebugPresentation.DEBUG_COMMAND_STATUS_INVALID_BINDING
		and stale_movement_binding.get("status")
		== CityDebugPresentation.DEBUG_COMMAND_STATUS_INVALID_BINDING
		and CityResourceContainerSystem.get_city_object_stored_resource_amount(
			CityObjectSystem.get_city_object_by_id_for_city_state(
				state_a,
				keep_a_id
			),
			resource
		) == resource_a_before_stale_call
		and CityResourceContainerSystem.get_city_object_stored_resource_amount(
			CityObjectSystem.get_city_object_by_id_for_city_state(
				state_b,
				keep_b_id
			),
			resource
		) == resource_b_before_stale_call
		and state_a.citizen_movement_runtime_state.citizen_movement_version
		== movement_a_before_stale_call
		and state_b.citizen_movement_runtime_state.citizen_movement_version
		== movement_b_before,
		"Stale A command tokens must not target newly bound B, even for equal IDs."
	)
	WorldData.debug_mode_enabled = false


func _test_renderer_debug_command_authority_boundary() -> void:
	var renderer_source := FileAccess.get_file_as_string(
		"res://scripts/city/rendering/CityRenderer.gd"
	)
	_expect(
		not renderer_source.is_empty()
		and "CityResourceContainerSystem" not in renderer_source
		and "CityCitizenMovementRuntimeSystem" not in renderer_source
		and "add_resource_to_city_object_storage_for_city_state" not in renderer_source
		and "assign_city_citizen_movement_order_for_city_state" not in renderer_source,
		"CityRenderer must contain no direct debug gameplay-system mutation calls."
	)


func _test_exact_texture_cache_source_identity() -> void:
	MapTextureCacheStateScript.clear_city_cache()
	var world_a := _make_world(5, 5, 142_001)
	var world_b := _make_world(5, 5, 142_001)
	_expect(
		world_a.seed == world_b.seed
		and world_a.width == world_b.width
		and world_a.height == world_b.height
		and world_a.tile_data_version == world_b.tile_data_version
		and not is_same(world_a, world_b),
		"The texture-cache fixture must collide on metadata but not source identity."
	)
	var texture_cache := _make_complete_texture_cache()
	MapTextureCacheStateScript.store_city_cache(
		world_a,
		142_001,
		texture_cache
	)
	_expect(
		MapTextureCacheStateScript.has_valid_city_cache(
			world_a,
			142_001
		)
		and not MapTextureCacheStateScript.has_valid_city_cache(
			world_b,
			142_001
		),
		"A complete A texture cache must never validate for metadata-identical B."
	)
	MapTextureCacheStateScript.clear_city_cache()


func _create_two_city_fixture() -> Dictionary:
	var culture := WorldData.create_culture("Helper Binding Culture")
	var culture_id := int(culture.get("id", -1))
	var polity := WorldPoliticalState.create_polity({
		"name": "Helper Binding Realm",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})
	var polity_id := int(polity.get("id", -1))
	var city_a := _create_city("Helper City A", polity_id, Vector2i(2, 2))
	var city_b := _create_city("Helper City B", polity_id, Vector2i(4, 4))
	var city_a_id := int(city_a.get("id", -1))
	var city_b_id := int(city_b.get("id", -1))
	if culture_id <= 0 or city_a_id <= 0 or city_b_id <= 0:
		return {}

	var state_a = WorldPoliticalState.get_city_simulation_state(city_a_id)
	var state_b = WorldPoliticalState.get_city_simulation_state(city_b_id)
	if (
		not state_a is CitySettlementSimulationState
		or not state_b is CitySettlementSimulationState
	):
		return {}
	var typed_state_a: CitySettlementSimulationState = state_a
	var typed_state_b: CitySettlementSimulationState = state_b
	var fixture_a := _seed_existing_state(
		typed_state_a,
		city_a_id,
		culture_id,
		"Helper City A",
		141_001
	)
	var fixture_b := _seed_existing_state(
		typed_state_b,
		city_b_id,
		culture_id,
		"Helper City B",
		141_002
	)
	if fixture_a.is_empty() or fixture_b.is_empty():
		return {}

	var citizen_a: Dictionary = fixture_a["citizen"]
	var citizen_b: Dictionary = fixture_b["citizen"]
	var male_names := CityCitizens.get_city_citizen_name_pool_for_sex(
		CityCitizens.CITY_CITIZEN_SEX_MALE
	)
	var citizen_b_only_name := (
		str(male_names[0]) if not male_names.is_empty() else ""
	)
	var citizen_b_only := CityCitizenRegistrySystem.add_city_citizen_for_city_state(
		typed_state_b,
		citizen_b_only_name,
		Vector2i(14, 2),
		CityCitizens.CITY_CITIZEN_SEX_MALE,
		culture_id
	)
	if citizen_b_only.is_empty():
		return {}
	CitizenNeedsSystem.set_city_citizen_hunger_state_for_city_state(
		typed_state_a,
		int(citizen_a.get("id", -1)),
		80,
		0
	)
	CitizenNeedsSystem.set_city_citizen_happiness_for_city_state(
		typed_state_a,
		int(citizen_a.get("id", -1)),
		90
	)
	CitizenNeedsSystem.set_city_citizen_hunger_state_for_city_state(
		typed_state_b,
		int(citizen_b.get("id", -1)),
		20,
		0
	)
	CitizenNeedsSystem.set_city_citizen_happiness_for_city_state(
		typed_state_b,
		int(citizen_b.get("id", -1)),
		30
	)
	CitizenNeedsSystem.set_city_citizen_hunger_state_for_city_state(
		typed_state_b,
		int(citizen_b_only.get("id", -1)),
		40,
		0
	)
	CitizenNeedsSystem.set_city_citizen_happiness_for_city_state(
		typed_state_b,
		int(citizen_b_only.get("id", -1)),
		50
	)

	var context_a = WorldPoliticalState.get_settlement_context(city_a_id)
	var context_b = WorldPoliticalState.get_settlement_context(city_b_id)
	if (
		not context_a is SettlementSimulationContext
		or not context_b is SettlementSimulationContext
	):
		return {}
	return {
		"culture_id": culture_id,
		"city_a_id": city_a_id,
		"city_b_id": city_b_id,
		"state_a": typed_state_a,
		"state_b": typed_state_b,
		"context_a": context_a,
		"context_b": context_b,
		"keep_a": fixture_a["keep"],
		"keep_b": fixture_b["keep"],
		"fishery_a": fixture_a["fishery"],
		"fishery_b": fixture_b["fishery"],
		"citizen_a": citizen_a,
		"citizen_b": citizen_b,
		"citizen_b_only": citizen_b_only,
	}


func _seed_existing_state(
	state: CitySettlementSimulationState,
	settlement_id: int,
	culture_id: int,
	city_name: String,
	seed_value: int
) -> Dictionary:
	state.city_world = _make_world(16, 16, seed_value)
	state.city_seed = seed_value
	state.city_runtime_data = {
		"id": settlement_id,
		"name": city_name,
		"primary_culture_id": culture_id,
		"founded": false,
		"can_build": false,
	}
	var keep := CityObjectSystem.register_completed_city_object_for_city_state(
		state,
		{
			"object_type": CityObjectCatalog.CITY_OBJECT_CITY_CENTER,
			"top_left": Vector2i(1, 1),
			"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
				CityObjectCatalog.CITY_OBJECT_CITY_CENTER
			),
			"object_owner": "player",
		}
	)
	if keep.is_empty():
		return {}
	state.city_runtime_data.merge({
		"city_world_seed": seed_value,
		"city_map_size": Vector2i(
			state.city_world.width,
			state.city_world.height
		),
		"foundation_top_left": keep.get(
			"top_left",
			Vector2i(-1, -1)
		),
		"foundation_size": keep.get("size", Vector2i.ZERO),
		"foundation_object_id": int(keep.get("id", -1)),
		"foundation_object_owner": str(keep.get("owner", "")),
		"founded": true,
		"can_build": true,
	}, true)
	var fishery := CityObjectSystem.register_completed_city_object_for_city_state(
		state,
		{
			"object_type": CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS,
			"top_left": Vector2i(8, 8),
			"size_tiles": CityObjectCatalog.get_city_object_size_for_type(
				CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS
			),
			"object_owner": "player",
		}
	)
	var female_names := CityCitizens.get_city_citizen_name_pool_for_sex(
		CityCitizens.CITY_CITIZEN_SEX_FEMALE
	)
	var citizen_name_index := 0 if "A" in city_name else 1
	var citizen_name := (
		str(female_names[citizen_name_index])
		if female_names.size() > citizen_name_index
		else ""
	)
	var citizen := CityCitizenRegistrySystem.add_city_citizen_for_city_state(
		state,
		citizen_name,
		Vector2i(14, 1),
		CityCitizens.CITY_CITIZEN_SEX_FEMALE,
		culture_id
	)
	if fishery.is_empty() or citizen.is_empty():
		return {}
	return {
		"keep": keep,
		"fishery": fishery,
		"citizen": citizen,
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


func _make_complete_texture_cache() -> Dictionary:
	var texture_cache: Dictionary = {}
	for raw_mode in MapVisuals.get_all_view_modes():
		var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.25, 0.5, 0.75, 1.0))
		texture_cache[int(raw_mode)] = ImageTexture.create_from_image(image)
	return texture_cache


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error("City presentation helper binding test: " + message)
