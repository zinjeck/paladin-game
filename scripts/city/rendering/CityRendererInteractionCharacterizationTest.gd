extends Node

# Locks the current facade-level interaction behavior before the placement,
# selection, command, and input responsibilities are extracted. The test keeps
# City B selected while every controller action explicitly targets renderer A.

const TEST_WORLD_SIZE := Vector2i(40, 40)
const CITY_A_SEED: int = 310_001
const CITY_B_SEED: int = 310_002
const CITY_A_NATURAL_FEATURE_TILE := Vector2i(35, 34)
const CITY_B_NATURAL_FEATURE_TILE := Vector2i(36, 35)
const CITY_A_DIRECT_COMMAND_FEATURE_TILE := Vector2i(36, 6)
const CITY_A_COMMAND_FEATURE_TILES: Array[Vector2i] = [
	Vector2i(30, 4),
	Vector2i(31, 4),
]
const CITY_A_NATURAL_FEATURE_TILES: Array[Vector2i] = [
	Vector2i(30, 4),
	Vector2i(31, 4),
	CITY_A_DIRECT_COMMAND_FEATURE_TILE,
	CITY_A_NATURAL_FEATURE_TILE,
]
const RendererBindingSupportScript := preload(
	"res://scripts/city/rendering/CityRendererBindingSupportTest.gd"
)
const SettlementPlacementControllerScript := preload(
	"res://scripts/settlements/presentation/SettlementPlacementController.gd"
)
const SettlementCommandControllerScript := preload(
	"res://scripts/settlements/presentation/SettlementCommandController.gd"
)
const SettlementPresentationBindingScript := preload(
	"res://scripts/settlements/presentation/SettlementPresentationBinding.gd"
)

var failure_count: int = 0
var culture_id: int = CultureData.INVALID_CULTURE_ID
var polity_id: int = PolityData.INVALID_POLITY_ID
var city_a_id: int = SettlementData.INVALID_SETTLEMENT_ID
var city_a_context: SettlementSimulationContext
var city_a_state: CitySettlementSimulationState
var renderer: CharacterizationRenderer


class CharacterizationRenderer:
	extends CityRenderer

	var characterization_mouse_tile: Vector2i = Vector2i(-1, -1)
	var fail_once_rebind_context: SettlementSimulationContext
	var fail_next_completed_validation: bool = false
	var forced_validation_failure_count: int = 0


	func get_city_tile_under_mouse() -> Vector2i:
		return characterization_mouse_tile


	func get_city_tile_from_mouse() -> Vector2i:
		return characterization_mouse_tile


	func validate_city_presentation_binding(settlement_context) -> bool:
		var base_valid := super.validate_city_presentation_binding(
			settlement_context
		)
		if (
			base_valid
			and fail_next_completed_validation
			and is_same(settlement_context, fail_once_rebind_context)
		):
			fail_next_completed_validation = false
			forced_validation_failure_count += 1
			return false
		return base_valid


class CharacterizationSelectionController:
	extends "res://scripts/settlements/presentation/SettlementSelectionController.gd"

	var characterization_selection_world_rect: Rect2 = Rect2()
	var characterization_hovered_tile: Vector2i = Vector2i(-1, -1)


	func get_selection_world_rect() -> Rect2:
		return characterization_selection_world_rect


	func world_position_to_settlement_tile(
		_world_position: Vector2
	) -> Vector2i:
		return characterization_hovered_tile


class CharacterizationUiController:
	extends "res://scripts/settlements/presentation/SettlementUiController.gd"

	var fail_next_bind_after_preflight: bool = false
	var bind_failures_after_preflight_remaining: int = 0


	func bind_settlement_presentation(
		binding: SettlementPresentationBindingScript
	) -> bool:
		if (
			fail_next_bind_after_preflight
			or bind_failures_after_preflight_remaining > 0
		):
			fail_next_bind_after_preflight = false
			bind_failures_after_preflight_remaining = maxi(
				bind_failures_after_preflight_remaining - 1,
				0
			)
			return false
		return super.bind_settlement_presentation(binding)


func _ready() -> void:
	await _test_registered_renderer_interaction_controllers()
	await _cleanup()

	if failure_count > 0:
		push_error(
			"CityRenderer interaction characterization test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("CityRenderer interaction characterization test passed.")
	get_tree().quit(0)


func _test_registered_renderer_interaction_controllers() -> void:
	WorldData.reset_runtime_session_state()
	SimulationClock.reset_clock_state()
	if not _create_registered_city_a():
		_expect(false, "A registered renderer fixture must be created.")
		return

	var city_b := WorldPoliticalState.create_settlement({
		"name": "Renderer Characterization B",
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": polity_id,
		"world_region_top_left": Vector2i(8, 8),
		"world_region_center": Vector2i(8, 8),
		"world_region_size": 1,
		"simulation_backend_kind": (
			SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE
		),
	})
	var city_b_id := int(
		city_b.get("id", SettlementData.INVALID_SETTLEMENT_ID)
	)
	var city_b_world := _make_world(TEST_WORLD_SIZE, CITY_B_SEED)
	var stored_b := WorldPoliticalState.store_city_world_for_settlement(
		city_b_id,
		city_b_world,
		CITY_B_SEED
	)
	var city_b_state: CitySettlementSimulationState = (
		WorldPoliticalState.get_city_simulation_state(city_b_id)
	)
	var city_b_context: SettlementSimulationContext = (
		WorldPoliticalState.get_settlement_context(city_b_id)
	)
	var city_b_bootstrap: Dictionary = (
		CitySettlementRuntimeBootstrap.ensure_ready(city_b_context)
		if city_b_context != null
		else {}
	)
	_expect(
		city_b_id > 0
		and stored_b
		and city_b_state != null
		and city_b_context != null
		and bool(city_b_bootstrap.get("success", false)),
		"The explicit non-rendered B fixture must be registered."
	)
	if (
		city_b_id <= 0
		or not stored_b
		or city_b_state == null
		or city_b_context == null
		or not bool(city_b_bootstrap.get("success", false))
	):
		return

	SimulationClock.set_speed_multiplier(3.0)
	SimulationClock.set_simulation_paused(true)
	renderer = CharacterizationRenderer.new()
	renderer.settlement_selection_controller = (
		CharacterizationSelectionController.new()
	)
	renderer.settlement_ui_controller = CharacterizationUiController.new()
	var binding_result := (
		RendererBindingSupportScript.bootstrap_and_configure_renderer(
			renderer,
			city_a_context
		)
	)
	_expect(
		not binding_result.is_empty(),
		"Renderer A must receive its registered binding before _ready()."
	)
	if binding_result.is_empty():
		renderer.free()
		renderer = null
		return

	_expect(
		WorldPoliticalState.set_active_settlement(city_b_id),
		"City B must remain selected while renderer A handles commands."
	)
	add_child(renderer)
	await get_tree().process_frame
	await get_tree().process_frame

	var binding := renderer.get_city_presentation_binding()
	var binding_generation := binding.generation if binding != null else -1
	_expect(
		binding != null
		and binding.is_valid()
		and is_same(binding.city_state, city_a_state)
		and WorldPoliticalState.active_settlement_id == city_b_id,
		"The live renderer must retain A while presentation selection is B."
	)
	if binding == null or not binding.is_valid():
		return
	# Found A through the same immediate-building placement facade used by play.
	var keep_center := Vector2i(10, 10)
	_set_mouse_tile(keep_center)
	var keep_size := CityObjectCatalog.get_city_object_size_for_type(
		CityObjectCatalog.CITY_OBJECT_CITY_CENTER
	)
	renderer.start_city_object_placement(
		CityObjectCatalog.CITY_OBJECT_CITY_CENTER,
		keep_size
	)
	var keep_preview := renderer.get_active_city_object_placement_preview()
	_expect(
		not keep_preview.is_empty()
		and str(keep_preview.get("type", ""))
		== CityObjectCatalog.CITY_OBJECT_CITY_CENTER,
		"Building placement must expose the cursor-attached Keep preview."
	)
	renderer.confirm_active_city_object_placement()
	var keep := CityObjectSystem.get_city_object_at_tile_for_city_state(
		city_a_state,
		keep_preview.get("top_left", Vector2i(-1, -1))
	)
	_expect(
		city_a_state.is_city_founded()
		and not keep.is_empty()
		and str(keep.get("type", ""))
		== CityObjectCatalog.CITY_OBJECT_CITY_CENTER
		and city_a_state.citizen_registry_state.citizens.size() == 8,
		"Confirming the initial building preview must found exactly one Keep and eight citizens."
	)

	# Prevent ordinary frame polling from obscuring the synchronous controller
	# boundaries characterized below.
	renderer.set_process(false)
	if renderer.camera != null:
		renderer.camera.set_process(false)
	CityResourceAccountingSystem.get_total_owned_city_resource_amounts_for_city_state(
		city_a_state
	)
	CityResourceAccountingSystem.get_total_owned_city_resource_amounts_for_city_state(
		city_b_state
	)
	_test_direct_settlement_command_controller(
		binding,
		city_b_context,
		city_b_state
	)
	var city_b_before := _capture_gameplay_snapshot(city_b_state)
	var city_b_identities := _capture_gameplay_identities(city_b_state)

	_test_building_preview_place_and_cancel()
	_test_road_drag_preview_place_and_cancel()
	_test_player_command_drag_and_cancel()
	_test_selection_drag_hover_and_reset(keep)

	_expect(
		_capture_gameplay_snapshot(city_b_state) == city_b_before
		and _gameplay_identities_match(city_b_state, city_b_identities),
		"Every A-bound interaction must preserve all B values and owner identities."
	)
	_expect(
		_renderer_contract_is_stable(
			binding,
			binding_generation,
			city_b_id
		),
		"Interaction controllers must not change target, generation, pause, or speed."
	)

	# Force a helper to pass its pure preflight and then reject the commit after
	# earlier helpers have accepted the target generation. The facade must
	# restore A with a fresh higher token; retrying the failed generation would
	# violate every helper's monotonic high-water contract.
	var a_before_helper_failure := _capture_gameplay_snapshot(city_a_state)
	var b_before_helper_failure := _capture_gameplay_snapshot(city_b_state)
	var a_identities_before_helper_failure := (
		_capture_gameplay_identities(city_a_state)
	)
	var b_identities_before_helper_failure := (
		_capture_gameplay_identities(city_b_state)
	)
	var a_tree_multimesh_before_helper_failure = (
		renderer.settlement_natural_feature_presenter.tree_multimesh
	)
	var a_rock_multimesh_before_helper_failure = (
		renderer.settlement_natural_feature_presenter.rock_multimesh
	)
	renderer.settlement_ui_controller.fail_next_bind_after_preflight = true
	var helper_commit_result := renderer.rebind_city_presentation(city_b_context)
	var helper_rollback_binding := renderer.get_city_presentation_binding()
	var helper_binding_restored: bool = (
		not helper_commit_result
		and helper_rollback_binding != null
		and helper_rollback_binding.matches_context(city_a_context)
		and helper_rollback_binding.generation == binding_generation + 2
		and renderer.city_presentation_binding_generation
		== helper_rollback_binding.generation
		and renderer.validate_city_presentation_binding(city_a_context)
		and renderer.settlement_ui_controller.is_bound_to_settlement_presentation(
			helper_rollback_binding
		)
	)
	var helper_features_restored: bool = (
		_natural_feature_presentation_matches(
			CITY_A_NATURAL_FEATURE_TILES,
			[]
		)
		and is_same(
			renderer.settlement_natural_feature_presenter.tree_multimesh,
			a_tree_multimesh_before_helper_failure
		)
		and is_same(
			renderer.settlement_natural_feature_presenter.rock_multimesh,
			a_rock_multimesh_before_helper_failure
		)
	)
	var helper_gameplay_preserved: bool = (
		_capture_gameplay_snapshot(city_a_state) == a_before_helper_failure
		and _gameplay_identities_match(
			city_a_state,
			a_identities_before_helper_failure
		)
		and _capture_gameplay_snapshot(city_b_state) == b_before_helper_failure
		and _gameplay_identities_match(
			city_b_state,
			b_identities_before_helper_failure
		)
	)
	_expect(
		helper_binding_restored,
		"A post-preflight helper failure must restore A at a fresh generation."
	)
	_expect(
		helper_features_restored,
		"A post-preflight helper failure must restore A's retained natural features."
	)
	_expect(
		helper_gameplay_preserved,
		"A post-preflight helper failure must preserve every A/B gameplay value and owner."
	)
	if helper_rollback_binding != null:
		binding = helper_rollback_binding
		binding_generation = helper_rollback_binding.generation

	var valid_draw_layers: Array[String] = [
		"active_workplace_preview",
		"background",
		"citizen",
		"interaction",
	]
	_expect(
		renderer.city_presentation_draw_count > 0
		and renderer.city_presentation_total_draw_duration_usec
		>= renderer.city_presentation_last_draw_duration_usec
		and renderer.city_presentation_last_draw_duration_usec >= 0
		and valid_draw_layers.has(renderer.city_presentation_last_draw_layer),
		"A visible renderer must record a real retained-layer draw timing baseline."
	)

	renderer._collect_city_change_flags()
	CityResourceAccountingSystem.get_total_owned_city_resource_amounts_for_city_state(
		city_a_state
	)
	CityResourceAccountingSystem.get_total_owned_city_resource_amounts_for_city_state(
		city_b_state
	)
	var city_a_before_rebind := _capture_gameplay_snapshot(city_a_state)
	var city_a_identities_before_rebind := (
		_capture_gameplay_identities(city_a_state)
	)
	var city_b_before_rebind := _capture_gameplay_snapshot(city_b_state)
	var city_b_identities_before_rebind := (
		_capture_gameplay_identities(city_b_state)
	)
	var active_settlement_before_rebind := WorldPoliticalState.active_settlement_id
	var paused_before_rebind := SimulationClock.simulation_paused
	var speed_before_rebind := SimulationClock.speed_multiplier
	var duration_before_rebind := renderer.city_last_rebind_duration_usec
	var draw_count_before_rebind := renderer.city_presentation_draw_count
	var a_tree_multimesh_before_completed_failure = (
		renderer.settlement_natural_feature_presenter.tree_multimesh
	)
	var a_rock_multimesh_before_completed_failure = (
		renderer.settlement_natural_feature_presenter.rock_multimesh
	)
	renderer.fail_once_rebind_context = city_b_context
	renderer.fail_next_completed_validation = true
	var failed_rebind_result := renderer.rebind_city_presentation(
		city_b_context
	)
	var rollback_binding := renderer.get_city_presentation_binding()
	var rollback_generation := (
		rollback_binding.generation
		if rollback_binding != null
		else -1
	)
	_expect(
		not failed_rebind_result
		and renderer.forced_validation_failure_count == 1
		and rollback_binding != null
		and rollback_binding.matches_context(city_a_context)
		and is_same(rollback_binding.city_state, city_a_state)
		and rollback_generation == binding_generation + 2
		and renderer.city_presentation_binding_generation
		== rollback_generation
		and renderer.city_presentation_invalidation_tracker.binding_generation
		== rollback_generation
		and renderer.validate_city_presentation_binding(city_a_context)
		and not renderer.city_presentation_rebind_pending
		and renderer.city_last_rebind_duration_usec
		== duration_before_rebind
		and renderer.visible
		and renderer.session_view_active
		and _all_city_render_layers_are_visible()
		and WorldPoliticalState.active_settlement_id
		== active_settlement_before_rebind
		and SimulationClock.simulation_paused == paused_before_rebind
		and is_equal_approx(
			SimulationClock.speed_multiplier,
			speed_before_rebind
		),
		"A failed completed B assembly must roll back to a valid, visible A with a fresh generation."
	)
	_expect(
		_capture_gameplay_snapshot(city_a_state) == city_a_before_rebind
		and _gameplay_identities_match(
			city_a_state,
			city_a_identities_before_rebind
		)
		and _capture_gameplay_snapshot(city_b_state) == city_b_before_rebind
		and _gameplay_identities_match(
			city_b_state,
			city_b_identities_before_rebind
		),
		"Failed rebind rollback must preserve every A/B gameplay value and owner identity."
	)
	_expect(
		_natural_feature_presentation_matches(
			CITY_A_NATURAL_FEATURE_TILES,
			[]
		)
		and is_same(
			renderer.settlement_natural_feature_presenter.tree_multimesh,
			a_tree_multimesh_before_completed_failure
		)
		and is_same(
			renderer.settlement_natural_feature_presenter.rock_multimesh,
			a_rock_multimesh_before_completed_failure
		),
		"Completed B validation rollback must restore A's exact feature tiles, arrays, visible counts, and cached MultiMeshes."
	)
	_expect(
		renderer.rebind_city_presentation(city_b_context),
		"The same B target must remain retryable after rollback."
	)
	await get_tree().process_frame
	await get_tree().process_frame

	var binding_b := renderer.get_city_presentation_binding()
	_expect(
		binding_b != null
		and binding_b.matches_context(city_b_context)
		and is_same(binding_b.city_state, city_b_state)
		and binding_b.generation == rollback_generation + 1
		and binding_b.generation == binding_generation + 3
		and renderer.city_last_rebind_duration_usec >= 0
		and not renderer.city_presentation_rebind_pending
		and renderer.city_presentation_draw_count > draw_count_before_rebind
		and WorldPoliticalState.active_settlement_id
		== active_settlement_before_rebind
		and SimulationClock.simulation_paused == paused_before_rebind
		and is_equal_approx(
			SimulationClock.speed_multiplier,
			speed_before_rebind
		)
		and renderer.city_presentation_total_draw_duration_usec
		>= renderer.city_presentation_last_draw_duration_usec
		and renderer.city_presentation_last_draw_duration_usec >= 0
		and valid_draw_layers.has(renderer.city_presentation_last_draw_layer),
		"Changed-target rebind must reveal B and record a real draw without stale timing."
	)
	_expect(
		_capture_gameplay_snapshot(city_a_state) == city_a_before_rebind
		and _gameplay_identities_match(
			city_a_state,
			city_a_identities_before_rebind
		)
		and _capture_gameplay_snapshot(city_b_state) == city_b_before_rebind
		and _gameplay_identities_match(
			city_b_state,
			city_b_identities_before_rebind
		),
		"Retried presentation-only A-to-B rebind must preserve every A/B gameplay value and owner identity."
	)
	_expect(
		_natural_feature_presentation_matches(
			[],
			[CITY_B_NATURAL_FEATURE_TILE]
		),
		"The successful B retry must expose only B's distinct rock fixture."
	)
	await _test_hidden_rebind_rollback(city_a_context, city_b_context, binding_b.generation)
	_test_direct_settlement_placement_controller(city_b_context, city_b_state)
	await _test_double_helper_failure_fails_closed(
		city_a_context,
		city_b_context
	)
	print(
		"PASS10_TIMING_BASELINE",
		" init=", renderer.city_initialization_duration_usec,
		" generation=", renderer.city_generation_duration_usec,
		" map=", renderer.city_map_texture_setup_duration_usec,
		" features=", renderer.city_natural_feature_setup_duration_usec,
		" rebind=", renderer.city_last_rebind_duration_usec,
		" draw_count=", renderer.city_presentation_draw_count,
		" draw_total=", renderer.city_presentation_total_draw_duration_usec,
		" draw_last=", renderer.city_presentation_last_draw_duration_usec
	)


func _test_direct_settlement_placement_controller(
	city_b_context: SettlementSimulationContext,
	city_b_state: CitySettlementSimulationState
) -> void:
	var binding_a := CityPresentationBinding.new()
	var binding_b := CityPresentationBinding.new()
	var binding_a_new := CityPresentationBinding.new()
	_expect(
		binding_a.rebind(city_a_context, 1)
		and binding_b.rebind(city_b_context, 2)
		and binding_a_new.rebind(city_a_context, 3),
		"Direct placement-controller bindings must use registered exact contexts."
	)
	if (
		not binding_a.is_valid()
		or not binding_b.is_valid()
		or not binding_a_new.is_valid()
	):
		return

	var controller = SettlementPlacementControllerScript.new()
	var a_object_count := city_a_state.object_state.objects.size()
	var a_site_count := (
		CityConstructionSystem.get_city_construction_site_snapshot_for_city_state(
			city_a_state
		).size()
	)
	var b_object_count := city_b_state.object_state.objects.size()
	var b_site_count := (
		CityConstructionSystem.get_city_construction_site_snapshot_for_city_state(
			city_b_state
		).size()
	)
	var active_settlement_before := WorldPoliticalState.active_settlement_id
	_expect(
		controller.bind_settlement_presentation(binding_a, 2),
		"The placement controller must accept its first exact binding."
	)
	_expect(
		controller.start_object_placement(
			CityObjectCatalog.CITY_OBJECT_HOUSE,
			CityObjectCatalog.get_city_object_size_for_type(
				CityObjectCatalog.CITY_OBJECT_HOUSE
			)
		)
		and not controller.get_active_object_placement_preview(
			Vector2i(28, 9)
		).is_empty()
		and controller.cancel_active_object_placement()
		== CityObjectCatalog.CITY_OBJECT_HOUSE,
		"Direct building preview and cancel must remain controller-local."
	)
	_expect(
		controller.start_road_placement()
		and controller.start_road_drag_selection(Vector2i(2, 37))
		and controller.update_road_drag_selection(Vector2i(4, 37))
		and controller.handle_road_left_mouse_released(),
		"Direct road drag must create a retained preview before confirmation."
	)
	_expect(
		controller.bind_settlement_presentation(binding_b, 2)
		and controller.is_interaction_state_clear()
		and not controller.bind_settlement_presentation(binding_a, 2)
		and controller.is_bound_to_settlement_presentation(binding_b),
		"A higher generation must clear previews and reject stale A-after-B binding."
	)
	controller.reset_presentation()
	_expect(
		controller.is_interaction_state_clear()
		and not controller.bind_settlement_presentation(binding_b, 2)
		and controller.bind_settlement_presentation(binding_a_new, 2),
		"Reset must preserve the generation high-water mark while allowing a newer bind."
	)
	_expect(
		city_a_state.object_state.objects.size() == a_object_count
		and CityConstructionSystem.get_city_construction_site_snapshot_for_city_state(
			city_a_state
		).size() == a_site_count
		and city_b_state.object_state.objects.size() == b_object_count
		and CityConstructionSystem.get_city_construction_site_snapshot_for_city_state(
			city_b_state
		).size() == b_site_count
		and WorldPoliticalState.active_settlement_id == active_settlement_before,
		"Preview, cancel, rebind, and reset must mutate neither settlement nor selection."
	)

	_expect(
		controller.start_road_placement()
		and controller.start_road_drag_selection(Vector2i(2, 37))
		and controller.update_road_drag_selection(Vector2i(4, 37))
		and controller.handle_road_left_mouse_released(),
		"The rebound A controller must produce a committable exact-state road preview."
	)
	var commit := controller.confirm_road_preview()
	var placed_tile_count := int(commit.get("placed_tile_count", 0))
	_expect(
		str(commit.get("status", ""))
		== SettlementPlacementControllerScript.COMMIT_STATUS_COMMITTED
		and placed_tile_count > 0
		and CityConstructionSystem.get_city_construction_site_snapshot_for_city_state(
			city_a_state
		).size() == a_site_count + placed_tile_count
		and CityConstructionSystem.get_city_construction_site_snapshot_for_city_state(
			city_b_state
		).size() == b_site_count
		and city_b_state.object_state.objects.size() == b_object_count
		and WorldPoliticalState.active_settlement_id == active_settlement_before,
		"Direct road commit must target bound A while active/presented selection remains B."
	)
	controller.cancel_road_placement()
	_expect(
		controller.is_interaction_state_clear(),
		"Cancel after direct commit must clear only retained placement state."
	)


func _test_hidden_rebind_rollback(
	target_context: SettlementSimulationContext,
	expected_restored_context: SettlementSimulationContext,
	previous_generation: int
) -> void:
	renderer.set_session_view_active(false)
	renderer.fail_once_rebind_context = target_context
	renderer.fail_next_completed_validation = true
	var failed_rebind_result := renderer.rebind_city_presentation(target_context)
	var rollback_binding := renderer.get_city_presentation_binding()
	_expect(
		not failed_rebind_result
		and renderer.forced_validation_failure_count == 2
		and rollback_binding != null
		and rollback_binding.matches_context(expected_restored_context)
		and rollback_binding.generation == previous_generation + 2
		and not renderer.city_presentation_rebind_pending
		and not renderer.visible
		and _all_city_render_layers_are_visible()
		and _no_city_render_layer_is_visible_in_tree(),
		"A failed hidden rebind must restore exact layer state without revealing the city."
	)
	renderer.set_session_view_active(true)
	_expect(
		renderer.visible
		and _all_city_render_layers_are_visible()
		and not _no_city_render_layer_is_visible_in_tree(),
		"The restored hidden presentation must reveal normally when reactivated."
	)
	await _test_pending_reveal_rollback(target_context, expected_restored_context)


func _test_pending_reveal_rollback(
	initial_context: SettlementSimulationContext,
	pending_context: SettlementSimulationContext
) -> void:
	_expect(
		renderer.rebind_city_presentation(initial_context),
		"The pending-reveal fixture must first return to visible city A."
	)
	await get_tree().process_frame
	await get_tree().process_frame
	var initial_binding := renderer.get_city_presentation_binding()
	if initial_binding == null or not initial_binding.matches_context(initial_context):
		_expect(false, "The pending-reveal fixture must bind city A exactly.")
		return
	var initial_generation := initial_binding.generation

	_expect(
		renderer.rebind_city_presentation(pending_context),
		"The pending-reveal fixture must begin a successful A-to-B rebind."
	)
	var pending_binding := renderer.get_city_presentation_binding()
	_expect(
		pending_binding != null
		and pending_binding.matches_context(pending_context)
		and pending_binding.generation == initial_generation + 1
		and renderer.city_presentation_rebind_pending
		and _no_city_render_layer_is_visible_in_tree(),
		"Successful A-to-B assembly must remain hidden until its deferred reveal."
	)

	renderer.fail_once_rebind_context = initial_context
	renderer.fail_next_completed_validation = true
	var failed_rebind_result := renderer.rebind_city_presentation(initial_context)
	var rollback_binding := renderer.get_city_presentation_binding()
	_expect(
		not failed_rebind_result
		and renderer.forced_validation_failure_count == 3
		and rollback_binding != null
		and rollback_binding.matches_context(pending_context)
		and rollback_binding.generation == initial_generation + 3
		and renderer.city_presentation_rebind_pending
		and _no_city_render_layer_is_visible_in_tree(),
		"Immediate failed B-to-A assembly must restore B's pending reveal at a fresh generation."
	)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(
		not renderer.city_presentation_rebind_pending
		and renderer.validate_city_presentation_binding(pending_context)
		and _all_city_render_layers_are_visible()
		and not _no_city_render_layer_is_visible_in_tree(),
		"The restored B reveal must resolve despite the invalidated stale callback."
	)
	_expect(
		renderer.rebind_city_presentation(pending_context)
		and renderer.get_city_presentation_binding().generation
		== initial_generation + 3
		and _all_city_render_layers_are_visible(),
		"The revealed rollback target must remain retryable through the same-target path."
	)


func _test_double_helper_failure_fails_closed(
	initial_context: SettlementSimulationContext,
	pending_context: SettlementSimulationContext
) -> void:
	var isolated_renderer := CharacterizationRenderer.new()
	isolated_renderer.settlement_selection_controller = (
		CharacterizationSelectionController.new()
	)
	isolated_renderer.settlement_ui_controller = CharacterizationUiController.new()
	var binding_result := (
		RendererBindingSupportScript.bootstrap_and_configure_renderer(
			isolated_renderer,
			initial_context
		)
	)
	_expect(
		not binding_result.is_empty(),
		"The double-failure fixture must configure an isolated A renderer."
	)
	if binding_result.is_empty():
		isolated_renderer.free()
		return

	add_child(isolated_renderer)
	await get_tree().process_frame
	await get_tree().process_frame
	var initial_binding := isolated_renderer.get_city_presentation_binding()
	_expect(
		initial_binding != null
		and isolated_renderer.rebind_city_presentation(pending_context),
		"The double-failure fixture must begin a pending A-to-B reveal."
	)
	var pending_binding := isolated_renderer.get_city_presentation_binding()
	var pending_reveal_generation := (
		isolated_renderer.city_presentation_rebind_generation
	)
	if pending_binding == null:
		_expect(false, "The double-failure fixture must publish B before reveal.")
		isolated_renderer.queue_free()
		await get_tree().process_frame
		return

	isolated_renderer.settlement_ui_controller.bind_failures_after_preflight_remaining = 2
	var failed_result := isolated_renderer.rebind_city_presentation(initial_context)
	var reserved_generation := pending_binding.generation + 2
	_expect(
		not failed_result
		and isolated_renderer.city_presentation_binding_generation
		== reserved_generation
		and isolated_renderer.get_city_presentation_binding() == null
		and isolated_renderer.get_bound_settlement_context() == null
		and isolated_renderer.bound_city_state == null
		and isolated_renderer.bound_city_settlement_id
		== SettlementData.INVALID_SETTLEMENT_ID
		and isolated_renderer.city_world == null
		and isolated_renderer.city_seed == 0
		and not isolated_renderer.initial_city_presentation_configured
		and not isolated_renderer.city_presentation_rebind_pending
		and isolated_renderer.city_presentation_rebind_generation
		== pending_reveal_generation + 1
		and not isolated_renderer.session_view_active
		and not isolated_renderer.visible
		and isolated_renderer.process_mode == Node.PROCESS_MODE_DISABLED
		and not _renderer_has_visible_render_layer(isolated_renderer),
		"A helper commit and recovery double failure must retire every facade identity and fail closed."
	)
	await get_tree().process_frame
	await get_tree().process_frame
	isolated_renderer.set_session_view_active(true)
	_expect(
		not isolated_renderer.session_view_active
		and not isolated_renderer.visible
		and not isolated_renderer.city_presentation_rebind_pending
		and not _renderer_has_visible_render_layer(isolated_renderer),
		"The invalidated stale reveal and a later activation attempt must not expose a mixed helper graph."
	)
	isolated_renderer.queue_free()
	await get_tree().process_frame


func _test_building_preview_place_and_cancel() -> void:
	var city_state := city_a_state
	var house_size := CityObjectCatalog.get_city_object_size_for_type(
		CityObjectCatalog.CITY_OBJECT_HOUSE
	)
	_set_mouse_tile(Vector2i(25, 20))
	var before_cancel := _capture_gameplay_snapshot(city_state)
	var identities_before_cancel := _capture_gameplay_identities(city_state)
	renderer.start_city_object_placement(
		CityObjectCatalog.CITY_OBJECT_HOUSE,
		house_size
	)
	var cancel_preview := renderer.get_active_city_object_placement_preview()
	_expect(
		not cancel_preview.is_empty()
		and renderer.is_uncommitted_city_placement_preview_active(),
		"Starting House placement must expose an uncommitted preview."
	)
	renderer.cancel_active_city_object_placement()
	_expect(
		not renderer.has_active_city_object_placement()
		and _capture_gameplay_snapshot(city_state) == before_cancel
		and _gameplay_identities_match(city_state, identities_before_cancel),
		"Canceling a building preview must cause zero gameplay mutation."
	)

	_set_mouse_tile(Vector2i(25, 20))
	var site_count_before := city_state.construction_state.construction_sites.size()
	renderer.start_city_object_placement(
		CityObjectCatalog.CITY_OBJECT_HOUSE,
		house_size
	)
	var placement_preview := renderer.get_active_city_object_placement_preview()
	renderer.confirm_active_city_object_placement()
	var placed_site := (
		CityConstructionSystem.get_city_construction_site_at_tile_for_city_state(
			city_state,
			placement_preview.get("top_left", Vector2i(-1, -1))
		)
	)
	_expect(
		city_state.construction_state.construction_sites.size()
		== site_count_before + 1
		and not placed_site.is_empty()
		and str(placed_site.get("object_type", ""))
		== CityObjectCatalog.CITY_OBJECT_HOUSE
		and not renderer.has_active_city_object_placement(),
		"Confirming a House preview must create one explicit-state blueprint and retire the preview."
	)


func _test_road_drag_preview_place_and_cancel() -> void:
	var city_state := city_a_state
	var before_cancel := _capture_gameplay_snapshot(city_state)
	var identities_before_cancel := _capture_gameplay_identities(city_state)
	renderer.start_road_placement()
	_set_mouse_tile(Vector2i(4, 31))
	renderer.start_road_drag_selection()
	_set_mouse_tile(Vector2i(6, 31))
	renderer.update_road_drag_selection()
	renderer.handle_road_left_mouse_released()
	_expect(
		not renderer.is_road_dragging
		and renderer.road_preview_tiles
		== [Vector2i(4, 31), Vector2i(5, 31), Vector2i(6, 31)],
		"Road dragging must retain the deterministic rectangular preview until confirmation."
	)
	renderer.cancel_road_placement()
	_expect(
		not renderer.is_road_placement_active
		and renderer.road_preview_tiles.is_empty()
		and _capture_gameplay_snapshot(city_state) == before_cancel
		and _gameplay_identities_match(city_state, identities_before_cancel),
		"Canceling a road drag preview must cause zero gameplay mutation."
	)

	var site_count_before := city_state.construction_state.construction_sites.size()
	renderer.start_road_placement()
	_set_mouse_tile(Vector2i(4, 33))
	renderer.start_road_drag_selection()
	_set_mouse_tile(Vector2i(6, 33))
	renderer.update_road_drag_selection()
	renderer.handle_road_left_mouse_released()
	renderer.confirm_road_preview()
	_expect(
		city_state.construction_state.construction_sites.size()
		== site_count_before + 3
		and renderer.is_road_placement_active
		and renderer.road_preview_tiles.is_empty(),
		"Confirming a road preview must create one independent blueprint per explicit-state tile."
	)
	renderer.cancel_road_placement()


func _test_player_command_drag_and_cancel() -> void:
	var city_state := city_a_state
	var command_tiles: Array[Vector2i] = CITY_A_COMMAND_FEATURE_TILES.duplicate()
	for command_tile in command_tiles:
		_expect(
			WorldData.get_city_surface_feature(
				renderer.city_world.tiles[command_tile.y][command_tile.x]
			) == WorldData.CITY_SURFACE_FEATURE_TREE,
			"The command fixture must retain a tree on each target tile."
		)

	renderer.settlement_ui_controller.command_chop_trees_button.pressed.emit()
	var before_cancel := _capture_gameplay_snapshot(city_state)
	var identities_before_cancel := _capture_gameplay_identities(city_state)
	_set_mouse_tile(command_tiles[0])
	renderer.start_city_player_command_drag(
		Vector2(10.0, 10.0),
		false,
		_command_tile_world_center(command_tiles[0])
	)
	_set_mouse_tile(command_tiles[1])
	renderer.update_city_player_command_drag(
		Vector2(50.0, 10.0),
		_command_tile_world_center(command_tiles[1])
	)
	_expect(
		renderer.settlement_command_controller.is_dragging
		and renderer.settlement_command_controller.drag_preview_tiles
		== command_tiles,
		"Player-command dragging must preview the exact eligible explicit-state tiles."
	)
	renderer.cancel_city_player_command_drag()
	_expect(
		not renderer.settlement_command_controller.is_dragging
		and renderer.settlement_command_controller.drag_preview_tiles.is_empty()
		and _capture_gameplay_snapshot(city_state) == before_cancel
		and _gameplay_identities_match(city_state, identities_before_cancel),
		"Canceling a player-command drag must cause zero gameplay mutation."
	)

	var command_count_before := city_state.work_state.player_commands.size()
	_set_mouse_tile(command_tiles[0])
	renderer.start_city_player_command_drag(
		Vector2(10.0, 10.0),
		false,
		_command_tile_world_center(command_tiles[0])
	)
	_set_mouse_tile(command_tiles[1])
	renderer.update_city_player_command_drag(
		Vector2(50.0, 10.0),
		_command_tile_world_center(command_tiles[1])
	)
	renderer.finish_city_player_command_drag(
		Vector2(50.0, 10.0),
		_command_tile_world_center(command_tiles[1])
	)
	var both_commands_exist := true
	for command_tile in command_tiles:
		both_commands_exist = (
			both_commands_exist
			and not CityWorkSystem.get_city_player_command_at_tile_for_city_state(
				city_state,
				command_tile
			).is_empty()
		)
	_expect(
		both_commands_exist
		and city_state.work_state.player_commands.size()
		== command_count_before + command_tiles.size()
		and not renderer.settlement_command_controller.is_dragging,
		"Finishing a player-command drag must commit only its eligible explicit-state targets."
	)
	renderer.settlement_ui_controller.deactivate_command_tool()


func _test_direct_settlement_command_controller(
	binding_a: CityPresentationBinding,
	context_b: SettlementSimulationContext,
	state_b: CitySettlementSimulationState
) -> void:
	var controller = SettlementCommandControllerScript.new()
	var tile_size := renderer.city_tile_size
	var equal_generation_binding_b := CityPresentationBinding.new()
	var binding_b := CityPresentationBinding.new()
	_expect(
		controller.bind_settlement_presentation(binding_a, tile_size)
		and controller.can_bind_settlement_presentation(
			binding_a,
			tile_size
		)
		and controller.bind_settlement_presentation(binding_a, tile_size)
		and equal_generation_binding_b.rebind(
			context_b,
			binding_a.generation
		)
		and not controller.can_bind_settlement_presentation(
			equal_generation_binding_b,
			tile_size
		)
		and not controller.bind_settlement_presentation(
			equal_generation_binding_b,
			tile_size
		),
		(
			"Command binding must be idempotent only for the exact binding and "
			+ "reject a different settlement at the same generation."
		)
	)

	var command_tile := CITY_A_DIRECT_COMMAND_FEATURE_TILE
	_expect(
		WorldData.get_city_surface_feature(
			city_a_state.city_world.tiles[command_tile.y][command_tile.x]
		) == WorldData.CITY_SURFACE_FEATURE_TREE,
		"The direct command-controller fixture must retain its A-owned tree."
	)
	var a_commands_before := city_a_state.work_state.player_commands.duplicate(true)
	var a_version_before := city_a_state.work_state.player_command_version
	var b_commands_before := state_b.work_state.player_commands.duplicate(true)
	var b_version_before := state_b.work_state.player_command_version
	var world_point := _command_tile_world_center(command_tile)
	_expect(
		controller.select_command_type(
			SettlementCommandControllerScript.COMMAND_TYPE_CHOP_TREE
		)
		and controller.begin_drag(
			Vector2(10.0, 10.0),
			world_point,
			false
		)
		and controller.drag_preview_tiles == [command_tile],
		"A direct command drag must derive its preview from the exact binding."
	)
	controller.cancel_drag()
	var no_op_commit := controller.finish_drag(
		Vector2(10.0, 10.0),
		world_point
	)
	_expect(
		city_a_state.work_state.player_commands == a_commands_before
		and city_a_state.work_state.player_command_version == a_version_before
		and state_b.work_state.player_commands == b_commands_before
		and state_b.work_state.player_command_version == b_version_before
		and str(no_op_commit.get("status", ""))
		== SettlementCommandControllerScript.COMMIT_STATUS_NO_OP,
		"Cancel and finish-without-drag must cause zero gameplay mutation."
	)

	controller.begin_drag(Vector2(10.0, 10.0), world_point, false)
	var add_commit := controller.finish_drag(
		Vector2(10.0, 10.0),
		world_point
	)
	_expect(
		str(add_commit.get("status", ""))
		== SettlementCommandControllerScript.COMMIT_STATUS_COMMITTED
		and int(add_commit.get("affected_count", 0)) == 1
		and not CityWorkSystem.get_city_player_command_at_tile_for_city_state(
			city_a_state,
			command_tile
		).is_empty()
		and state_b.work_state.player_commands == b_commands_before
		and state_b.work_state.player_command_version == b_version_before,
		"Command commit must mutate A only while B remains globally active."
	)

	controller.toggle_cancel_mode()
	controller.begin_drag(Vector2(10.0, 10.0), world_point, true)
	var remove_commit := controller.finish_drag(
		Vector2(10.0, 10.0),
		world_point
	)
	_expect(
		str(remove_commit.get("status", ""))
		== SettlementCommandControllerScript.COMMIT_STATUS_COMMITTED
		and int(remove_commit.get("affected_count", 0)) == 1
		and CityWorkSystem.get_city_player_command_at_tile_for_city_state(
			city_a_state,
			command_tile
		).is_empty()
		and state_b.work_state.player_commands == b_commands_before
		and state_b.work_state.player_command_version == b_version_before,
		"Cancel-mode commit must remove the exact A command without touching B."
	)

	var a_after_commits := city_a_state.work_state.player_commands.duplicate(true)
	var a_version_after_commits := city_a_state.work_state.player_command_version
	_expect(
		binding_b.rebind(context_b, binding_a.generation + 1)
		and controller.bind_settlement_presentation(binding_b, tile_size)
		and controller.is_interaction_state_clear()
		and not controller.bind_settlement_presentation(binding_a, tile_size)
		and controller.is_bound_to_settlement_presentation(binding_b)
		and city_a_state.work_state.player_commands == a_after_commits
		and city_a_state.work_state.player_command_version
		== a_version_after_commits
		and state_b.work_state.player_commands == b_commands_before
		and state_b.work_state.player_command_version == b_version_before,
		"A-to-B rebind and stale-A rejection must be presentation-pure."
	)
	controller.reset_presentation()
	var fresh_binding_a := CityPresentationBinding.new()
	_expect(
		not controller.bind_settlement_presentation(binding_b, tile_size)
		and controller.highest_accepted_binding_generation
		== binding_b.generation
		and fresh_binding_a.rebind(
			binding_a.settlement_context,
			binding_b.generation + 1
		)
		and controller.bind_settlement_presentation(
			fresh_binding_a,
			tile_size
		),
		"Command reset must retain its monotonic generation high-water mark."
	)


func _test_selection_drag_hover_and_reset(keep: Dictionary) -> void:
	var city_state := city_a_state
	CityResourceAccountingSystem.get_total_owned_city_resource_amounts_for_city_state(
		city_state
	)
	var before_selection := _capture_gameplay_snapshot(city_state)
	var identities_before_selection := _capture_gameplay_identities(city_state)
	var keep_rect := renderer.get_city_object_world_rect(keep)
	renderer.settlement_selection_controller.characterization_selection_world_rect = Rect2(
		keep_rect.position - Vector2.ONE,
		keep_rect.size + Vector2(2.0, 2.0)
	)
	renderer.start_object_selection_drag(Vector2(10.0, 10.0))
	renderer.finish_object_selection_drag(Vector2(100.0, 100.0))
	_expect(
		renderer.selected_city_object_id == int(keep.get("id", -1)),
		"Object-selection drag must select the largest intersecting bound object."
	)

	renderer.settlement_selection_controller.characterization_selection_world_rect = Rect2(
		Vector2(70.0, 70.0),
		Vector2(6.0, 6.0)
	)
	renderer.start_object_selection_drag(Vector2(10.0, 10.0))
	renderer.finish_object_selection_drag(Vector2(100.0, 100.0))
	_expect(
		not renderer.has_selected_city_entity(),
		"Dragging over empty space must clear the previous selection."
	)

	var keep_top_left: Vector2i = keep.get("top_left", Vector2i(-1, -1))
	_set_mouse_tile(keep_top_left)
	var hover_changed := renderer._update_city_hover_state()
	_expect(
		hover_changed
		and renderer.hovered_city_tile == keep_top_left
		and renderer.get_city_hover_highlight_tiles(keep_top_left)
		== CityObjectSystem.get_city_object_footprint_tiles(keep),
		"Hover characterization must resolve the complete bound object footprint."
	)
	_expect(
		_capture_gameplay_snapshot(city_state) == before_selection
		and _gameplay_identities_match(
			city_state,
			identities_before_selection
		),
		"Selection and hover queries must cause zero gameplay mutation."
	)

	# Rebind/reset will use this same facade operation until the four controllers
	# have independent reset entry points. It must remain idempotent and pure.
	var before_reset := _capture_gameplay_snapshot(city_state)
	var identities_before_reset := _capture_gameplay_identities(city_state)
	renderer.start_city_object_placement(
		CityObjectCatalog.CITY_OBJECT_HOUSE,
		CityObjectCatalog.get_city_object_size_for_type(
			CityObjectCatalog.CITY_OBJECT_HOUSE
		)
	)
	renderer.is_road_placement_active = true
	renderer.is_road_dragging = true
	renderer.road_preview_tiles = [Vector2i(35, 35)]
	renderer.road_preview_lookup = {Vector2i(35, 35): true}
	renderer.settlement_command_controller.active_command_type = (
		CityWorkSystem.CITY_PLAYER_COMMAND_TYPE_CHOP_TREE
	)
	renderer.settlement_command_controller.is_dragging = true
	renderer.settlement_command_controller.drag_preview_tiles.assign([
		Vector2i(30, 4)
	])
	renderer.is_object_selection_dragging = true
	renderer._clear_city_presentation_interactions()
	_expect(
		not renderer.has_active_city_object_placement()
		and not renderer.is_road_placement_active
		and not renderer.is_road_dragging
		and renderer.road_preview_tiles.is_empty()
		and not renderer.is_city_player_command_tool_active()
		and not renderer.settlement_command_controller.is_dragging
		and renderer.settlement_command_controller.drag_preview_tiles.is_empty()
		and not renderer.is_object_selection_dragging
		and _capture_gameplay_snapshot(city_state) == before_reset
		and _gameplay_identities_match(city_state, identities_before_reset),
		"The shared interaction reset must clear every transient controller without gameplay mutation."
	)


func _renderer_contract_is_stable(
	initial_binding: CityPresentationBinding,
	initial_generation: int,
	presented_city_id: int
) -> bool:
	var current_binding := renderer.get_city_presentation_binding()
	return (
		current_binding != null
		and current_binding.matches_binding(initial_binding)
		and current_binding.generation == initial_generation
		and is_same(current_binding.city_state, city_a_state)
		and WorldPoliticalState.active_settlement_id == presented_city_id
		and SimulationClock.simulation_paused
		and is_equal_approx(SimulationClock.speed_multiplier, 3.0)
	)


func _all_city_render_layers_are_visible() -> bool:
	for render_layer in [
		renderer.city_active_workplace_preview_render_layer,
		renderer.city_background_render_layer,
		renderer.city_citizen_render_layer,
		renderer.city_interaction_render_layer,
	]:
		if render_layer == null or not render_layer.visible:
			return false
	return true


func _no_city_render_layer_is_visible_in_tree() -> bool:
	for render_layer in [
		renderer.city_active_workplace_preview_render_layer,
		renderer.city_background_render_layer,
		renderer.city_citizen_render_layer,
		renderer.city_interaction_render_layer,
	]:
		if render_layer != null and render_layer.is_visible_in_tree():
			return false
	return true


func _renderer_has_visible_render_layer(target_renderer: CityRenderer) -> bool:
	for render_layer in [
		target_renderer.city_active_workplace_preview_render_layer,
		target_renderer.city_background_render_layer,
		target_renderer.city_citizen_render_layer,
		target_renderer.city_interaction_render_layer,
	]:
		if render_layer != null and render_layer.visible:
			return true
	return false


func _natural_feature_presentation_matches(
	expected_tree_tiles: Array[Vector2i],
	expected_rock_tiles: Array[Vector2i]
) -> bool:
	var presenter = renderer.settlement_natural_feature_presenter
	if (
		presenter.tree_multimesh == null
		or presenter.rock_multimesh == null
		or presenter.tree_index_by_tile.size() != expected_tree_tiles.size()
		or presenter.tree_tile_by_index.size() != expected_tree_tiles.size()
		or presenter.tree_multimesh.visible_instance_count
		!= expected_tree_tiles.size()
		or presenter.rock_index_by_tile.size() != expected_rock_tiles.size()
		or presenter.rock_tile_by_index.size() != expected_rock_tiles.size()
		or presenter.rock_multimesh.visible_instance_count
		!= expected_rock_tiles.size()
	):
		return false
	for index in range(expected_tree_tiles.size()):
		var tile_position := expected_tree_tiles[index]
		if (
			presenter.tree_tile_by_index[index] != tile_position
			or int(presenter.tree_index_by_tile.get(tile_position, -1)) != index
		):
			return false
	for index in range(expected_rock_tiles.size()):
		var tile_position := expected_rock_tiles[index]
		if (
			presenter.rock_tile_by_index[index] != tile_position
			or int(presenter.rock_index_by_tile.get(tile_position, -1)) != index
		):
			return false
	return true


func _set_mouse_tile(tile_position: Vector2i) -> void:
	renderer.characterization_mouse_tile = tile_position
	renderer.settlement_selection_controller.characterization_hovered_tile = (
		tile_position
	)


func _command_tile_world_center(tile_position: Vector2i) -> Vector2:
	return (
		Vector2(tile_position) + Vector2(0.5, 0.5)
	) * float(renderer.city_tile_size)


func _create_registered_city_a() -> bool:
	var culture := WorldData.create_culture(
		"Renderer Characterization Culture"
	)
	culture_id = int(culture.get("id", CultureData.INVALID_CULTURE_ID))
	if culture_id <= 0:
		return false

	var polity := WorldPoliticalState.create_polity({
		"name": "Renderer Characterization Polity",
		"polity_type": PolityData.POLITY_TYPE_KINGDOM,
		"primary_culture_id": culture_id,
	})
	polity_id = int(polity.get("id", PolityData.INVALID_POLITY_ID))
	if polity_id <= 0:
		return false

	var settlement := WorldPoliticalState.create_settlement({
		"name": "Renderer Characterization A",
		"settlement_type": SettlementData.SETTLEMENT_TYPE_CITY,
		"polity_id": polity_id,
		"world_region_top_left": Vector2i(1, 1),
		"world_region_center": Vector2i(1, 1),
		"world_region_size": 1,
		"simulation_backend_kind": (
			SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE
		),
	})
	city_a_id = int(
		settlement.get("id", SettlementData.INVALID_SETTLEMENT_ID)
	)
	if city_a_id <= 0:
		return false

	WorldPoliticalState.player_polity_id = polity_id
	if not WorldPoliticalState.set_polity_capital(polity_id, city_a_id):
		return false
	if not WorldPoliticalState.store_city_world_for_settlement(
		city_a_id,
		_make_world(TEST_WORLD_SIZE, CITY_A_SEED),
		CITY_A_SEED
	):
		return false

	city_a_context = WorldPoliticalState.get_settlement_context(city_a_id)
	city_a_state = WorldPoliticalState.get_city_simulation_state(city_a_id)
	return city_a_context != null and city_a_state != null


func _make_world(size: Vector2i, seed_value: int) -> WorldData:
	var world := WorldData.new()
	world.setup(size.x, size.y, seed_value)
	for y in range(size.y):
		for x in range(size.x):
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
	if seed_value == CITY_A_SEED:
		for natural_feature_tile in CITY_A_NATURAL_FEATURE_TILES:
			world.set_tile_surface_feature(
				natural_feature_tile,
				WorldData.CITY_SURFACE_FEATURE_TREE
			)
	else:
		world.set_tile_surface_feature(
			CITY_B_NATURAL_FEATURE_TILE,
			WorldData.CITY_SURFACE_FEATURE_ROCK
		)
	world.consume_city_surface_feature_changes()
	return world


func _capture_gameplay_snapshot(
	city_state: CitySettlementSimulationState
) -> Dictionary:
	var owner_values := {}
	for owner_key in _get_gameplay_owner_map(city_state).keys():
		owner_values[owner_key] = _capture_script_variable_values(
			_get_gameplay_owner_map(city_state)[owner_key]
		)
	# These are presentation event queues rather than gameplay authority.
	owner_values["citizen_movement_runtime_state"].erase(
		"citizen_movement_visual_events"
	)
	owner_values["citizen_movement_runtime_state"].erase(
		"citizen_movement_visual_tick_index"
	)
	var world_values := _capture_script_variable_values(city_state.city_world)
	world_values.erase("pending_city_surface_feature_changes")
	return {
		"city_seed": city_state.city_seed,
		"runtime": city_state.city_runtime_data.duplicate(true),
		"world": world_values,
		"owners": owner_values,
	}


func _capture_gameplay_identities(
	city_state: CitySettlementSimulationState
) -> Dictionary:
	var identities := {
		"world": city_state.city_world,
		"runtime": city_state.city_runtime_data,
	}
	identities.merge(_get_gameplay_owner_map(city_state))
	return identities


func _gameplay_identities_match(
	city_state: CitySettlementSimulationState,
	identities: Dictionary
) -> bool:
	if (
		not is_same(city_state.city_world, identities.get("world"))
		or not is_same(city_state.city_runtime_data, identities.get("runtime"))
	):
		return false
	for owner_key in _get_gameplay_owner_map(city_state).keys():
		if not is_same(
			_get_gameplay_owner_map(city_state)[owner_key],
			identities.get(owner_key)
		):
			return false
	return true


func _get_gameplay_owner_map(
	city_state: CitySettlementSimulationState
) -> Dictionary:
	return {
		"object_state": city_state.object_state,
		"resource_accounting_state": city_state.resource_accounting_state,
		"citizen_registry_state": city_state.citizen_registry_state,
		"assignment_state": city_state.assignment_state,
		"workplace_state": city_state.workplace_state,
		"citizen_spatial_state": city_state.citizen_spatial_state,
		"citizen_movement_runtime_state": (
			city_state.citizen_movement_runtime_state
		),
		"citizen_task_runtime_state": city_state.citizen_task_runtime_state,
		"citizen_decision_runtime_state": (
			city_state.citizen_decision_runtime_state
		),
		"work_state": city_state.work_state,
		"logistics_state": city_state.logistics_state,
		"construction_state": city_state.construction_state,
		"navigation_state": city_state.navigation_state,
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


func _cleanup() -> void:
	if renderer != null:
		renderer.queue_free()
		await get_tree().process_frame
		renderer = null
	culture_id = CultureData.INVALID_CULTURE_ID
	polity_id = PolityData.INVALID_POLITY_ID
	city_a_id = SettlementData.INVALID_SETTLEMENT_ID
	city_a_context = null
	city_a_state = null
	WorldData.reset_runtime_session_state()
	SimulationClock.reset_clock_state()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	failure_count += 1
	push_error(message)
