extends Node2D
class_name CityRenderer

# File responsibility: settlement-view lifecycle/input facade, render-layer
# orchestration, and high-level drawing for the current detailed backend.
# Stateful UI, caches, and diagnostics live with dedicated presentation owners.

const MapTextureCacheStateScript = preload(
	"res://scripts/map/visuals/MapTextureCacheState.gd"
)
const CityCitizenMovementPresentationScript = preload(
	"res://scripts/citizens/rendering/CityCitizenMovementPresentation.gd"
)
const CityInformationPanelScript = preload(
	"res://scripts/ui/city/CityInformationPanel.gd"
)
const CityObjectPanelAnchorScript = preload(
	"res://scripts/ui/city/CityObjectPanelAnchor.gd"
)
const CityDebugPresentationScript = preload(
	"res://scripts/city/rendering/CityDebugPresentation.gd"
)
const CityRenderLayerScript = preload(
	"res://scripts/city/rendering/CityRenderLayer.gd"
)
const CityPresentationInvalidationTrackerScript = preload(
	"res://scripts/city/rendering/CityPresentationInvalidationTracker.gd"
)
const SettlementPresentationBindingScript = preload(
	"res://scripts/settlements/presentation/SettlementPresentationBinding.gd"
)
const SettlementPlacementControllerScript = preload(
	"res://scripts/settlements/presentation/SettlementPlacementController.gd"
)
const SettlementSelectionControllerScript = preload(
	"res://scripts/settlements/presentation/SettlementSelectionController.gd"
)
const SettlementCommandControllerScript = preload(
	"res://scripts/settlements/presentation/SettlementCommandController.gd"
)
const SettlementUiControllerScript = preload(
	"res://scripts/settlements/presentation/SettlementUiController.gd"
)
const SettlementInfrastructurePresenterScript = preload(
	"res://scripts/settlements/presentation/SettlementInfrastructurePresenter.gd"
)
const SettlementNaturalFeaturePresenterScript = preload(
	"res://scripts/map/visuals/SettlementNaturalFeaturePresenter.gd"
)
const CityWorkplaceZoneOverlayCacheScript = preload(
	"res://scripts/city/rendering/CityWorkplaceZoneOverlayCache.gd"
)
const CityWorldGeneratorScript = preload(
	"res://scripts/city/generation/CityWorldGenerator.gd"
)
@export var local_tiles_per_world_tile: int = CityWorldGeneratorScript.DEFAULT_LOCAL_TILES_PER_WORLD_TILE
@export var city_tile_size: int = 2

var city_presentation_binding: CityPresentationBinding
var city_presentation_binding_generation: int = 0
var city_presentation_invalidation_tracker = (
	CityPresentationInvalidationTrackerScript.new()
)
var bound_settlement_context: SettlementSimulationContext
var bound_city_state: CitySettlementSimulationState
var bound_city_settlement_id: int = SettlementData.INVALID_SETTLEMENT_ID
var city_world: WorldData
var city_seed: int = 0
var session_prepared_city_payload: Dictionary = {}
var initial_city_presentation_configured: bool = false
var session_view_active: bool = true
var city_layers_have_been_presented: bool = false
var city_presentation_rebind_generation: int = 0
var city_presentation_rebind_pending: bool = false
var city_last_rebind_duration_usec: int = 0
var city_presentation_draw_count: int = 0
var city_presentation_last_draw_duration_usec: int = 0
var city_presentation_total_draw_duration_usec: int = 0
var city_presentation_last_draw_layer: String = ""
var camera: Camera2D
var ui_layer: CanvasLayer
var ui_root: Control
var city_information_ui = CityInformationPanelScript.new()
var settlement_entity_panel_presentation: CityObjectPanelAnchor
var city_terrain_texture: Texture2D
var city_terrain_sprite: Sprite2D
var city_texture_cache := MapTextureCache.new()
var settlement_natural_feature_presenter = (
	SettlementNaturalFeaturePresenterScript.new()
)
var city_initialization_duration_usec: int = 0
var city_generation_duration_usec: int = 0
var city_map_texture_setup_duration_usec: int = 0
var city_natural_feature_setup_duration_usec: int = 0
var city_map_texture_cache_reused_on_entry: bool = false
var city_natural_feature_cache_reused_on_entry: bool:
	get: return settlement_natural_feature_presenter.cache_reused_on_entry
var city_active_workplace_preview_render_layer: CityRenderLayer
var city_background_render_layer: CityRenderLayer
var city_citizen_render_layer: CityRenderLayer
var city_interaction_render_layer: CityRenderLayer
var city_debug_presentation = CityDebugPresentationScript.new()
var settlement_placement_controller = SettlementPlacementControllerScript.new()
var settlement_selection_controller = SettlementSelectionControllerScript.new()
var settlement_command_controller = SettlementCommandControllerScript.new()
var settlement_ui_controller = SettlementUiControllerScript.new()
var settlement_infrastructure_presenter = (
	SettlementInfrastructurePresenterScript.new()
)
# Narrow facade views used by the lifecycle/input coordinator; the controller
# remains the sole owner of the underlying placement and selection state.
var is_road_placement_active: bool:
	get: return settlement_placement_controller.is_road_placement_active
	set(value): settlement_placement_controller.is_road_placement_active = value
var is_road_dragging: bool:
	get: return settlement_placement_controller.is_road_dragging
	set(value): settlement_placement_controller.is_road_dragging = value
var road_preview_tiles: Array:
	get: return settlement_placement_controller.road_preview_tiles
	set(value): settlement_placement_controller.road_preview_tiles = value
var road_preview_lookup: Dictionary:
	get: return settlement_placement_controller.road_preview_lookup
	set(value): settlement_placement_controller.road_preview_lookup = value
var hovered_city_tile: Vector2i:
	get: return settlement_selection_controller.hovered_settlement_tile
	set(value): settlement_selection_controller.hovered_settlement_tile = value
const CITY_SELECTION_KIND_NONE := SettlementSelectionControllerScript.SELECTION_KIND_NONE
const CITY_SELECTION_KIND_OBJECT := SettlementSelectionControllerScript.SELECTION_KIND_OBJECT
const CITY_SELECTION_KIND_CITIZEN := SettlementSelectionControllerScript.SELECTION_KIND_CITIZEN

var selected_city_entity_kind: String:
	get: return settlement_selection_controller.selected_settlement_entity_kind
	set(value): settlement_selection_controller.selected_settlement_entity_kind = value
var selected_city_entity_id: int:
	get: return settlement_selection_controller.selected_settlement_entity_id
	set(value): settlement_selection_controller.selected_settlement_entity_id = value

# Compatibility view for existing object-only systems.
# This is derived state, not a second selection owner.
var selected_city_object_id: int:
	get: return settlement_selection_controller.get_selected_settlement_object_id()

var selected_city_citizen_id: int:
	get: return settlement_selection_controller.get_selected_settlement_citizen_id()

var selected_city_construction_site_id: int:
	get: return settlement_selection_controller.get_selected_settlement_construction_site_id()

var city_citizen_movement_presentation = (
	CityCitizenMovementPresentationScript.new()
)
var active_workplace_preview_refresh_pending: bool = false
var workplace_zone_overlay_cache = (
	CityWorkplaceZoneOverlayCacheScript.new()
)
var is_object_selection_dragging: bool:
	get: return settlement_selection_controller.is_selection_dragging
	set(value): settlement_selection_controller.is_selection_dragging = value
#region Lifecycle and input

func configure_initial_settlement_presentation(
	settlement_context: SettlementSimulationContext,
	prepared_payload: Dictionary
) -> bool:
	return configure_initial_city_presentation(
		settlement_context,
		prepared_payload
	)


func can_rebind_settlement_presentation(
	settlement_context: SettlementSimulationContext,
	prepared_payload: Dictionary = {}
) -> bool:
	return can_rebind_city_presentation(settlement_context, prepared_payload)


func rebind_settlement_presentation(
	settlement_context: SettlementSimulationContext,
	prepared_payload: Dictionary = {}
) -> bool:
	return rebind_city_presentation(settlement_context, prepared_payload)


func validate_settlement_presentation_binding(
	settlement_context: SettlementSimulationContext
) -> bool:
	return validate_city_presentation_binding(settlement_context)


func get_settlement_presentation_binding() -> SettlementPresentationBindingScript:
	return city_presentation_binding

func _ready() -> void:
	if not _has_valid_bound_city_presentation():
		push_error(
			"CityRenderer requires configure_initial_settlement_presentation() "
			+ "with a registered settlement context before entering the tree."
		)
		process_mode = Node.PROCESS_MODE_DISABLED
		visible = false
		return

	var initialization_start_usec := Time.get_ticks_usec()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	RenderingServer.set_default_clear_color(Color.BLACK)

	setup_city_texture_cache()
	city_generation_duration_usec = int(
		session_prepared_city_payload.get("preparation_duration_usec", 0)
	)
	install_session_prepared_city_map_textures()
	city_citizen_movement_presentation.discard_pending_visual_events()
	_capture_bound_city_presentation_versions(bound_city_state)
	var natural_feature_start_usec := Time.get_ticks_usec()
	setup_city_natural_feature_rendering()
	city_natural_feature_setup_duration_usec = (
		Time.get_ticks_usec() - natural_feature_start_usec
	)
	create_city_terrain_sprite()
	create_city_render_layers()
	var map_texture_start_usec := Time.get_ticks_usec()
	rebuild_city_terrain_texture()
	city_map_texture_setup_duration_usec = (
		Time.get_ticks_usec() - map_texture_start_usec
	)
	create_city_camera()
	create_city_ui()
	create_debug_panel()
	connect_simulation_clock_signals()
	update_debug_panel_text()
	queue_all_city_render_layers_redraw()
	city_initialization_duration_usec = (
		Time.get_ticks_usec() - initialization_start_usec
	)

	if WorldData.debug_mode_enabled:
		print(
			"City scene initialization (ms): total=",
			"%.3f" % (float(city_initialization_duration_usec) / 1000.0),
			", generation=",
			"%.3f" % (float(city_generation_duration_usec) / 1000.0),
			", map=",
			"%.3f" % (float(city_map_texture_setup_duration_usec) / 1000.0),
			", features=",
			"%.3f" % (float(city_natural_feature_setup_duration_usec) / 1000.0),
			", texture_cache_reused=",
			city_map_texture_cache_reused_on_entry,
			", feature_cache_reused=",
			city_natural_feature_cache_reused_on_entry
		)

	session_prepared_city_payload.clear()


func configure_initial_city_presentation(
	settlement_context: SettlementSimulationContext,
	prepared_payload: Dictionary = {}
) -> bool:
	if is_inside_tree() or initial_city_presentation_configured:
		return false

	if not can_rebind_city_presentation(settlement_context, prepared_payload):
		return false

	if not _bind_city_presentation_references(
		settlement_context,
		prepared_payload
	):
		return false
	initial_city_presentation_configured = true
	return true


func _bind_city_presentation_references(
	settlement_context: SettlementSimulationContext,
	prepared_payload: Dictionary
) -> bool:
	var next_generation := city_presentation_binding_generation + 1
	var next_binding := CityPresentationBinding.new()
	if not next_binding.rebind(
		settlement_context,
		next_generation
	):
		return false
	if not city_presentation_invalidation_tracker.can_rebind_city_presentation(
		next_binding
	):
		return false

	var previous_binding := city_presentation_binding
	if not _bind_city_presentation_helpers(next_binding):
		var helper_recovered := _recover_city_presentation_binding_after_failed_commit(
			previous_binding,
			next_generation
		)
		if not helper_recovered:
			_fail_city_presentation_closed()
		return false
	if not city_presentation_invalidation_tracker.rebind_city_presentation(
		next_binding
	):
		var tracker_recovered := _recover_city_presentation_binding_after_failed_commit(
			previous_binding,
			next_generation
		)
		if not tracker_recovered:
			_fail_city_presentation_closed()
		return false

	_publish_city_presentation_binding(next_binding, next_generation)
	session_prepared_city_payload = prepared_payload.duplicate(true)
	return true


func _recover_city_presentation_binding_after_failed_commit(
	previous_binding: CityPresentationBinding,
	failed_generation: int
) -> bool:
	# A helper that fails after a successful preflight may have advanced some
	# owners to failed_generation. Retrying that generation—or attempting to
	# restore the older token—would be rejected by their monotonic high-water
	# guards. Reserve the failed generation, then restore through a fresh token.
	city_presentation_binding_generation = max(
		city_presentation_binding_generation,
		failed_generation
	)
	if previous_binding == null or not previous_binding.is_valid():
		return false

	var rollback_generation := city_presentation_binding_generation + 1
	var rollback_binding := CityPresentationBinding.new()
	if (
		not rollback_binding.rebind(
			previous_binding.settlement_context,
			rollback_generation
		)
		or not _can_bind_city_presentation_helpers(rollback_binding)
		or not city_presentation_invalidation_tracker.can_rebind_city_presentation(
			rollback_binding
		)
		or not _bind_city_presentation_helpers(rollback_binding)
		or not city_presentation_invalidation_tracker.rebind_city_presentation(
			rollback_binding
		)
		or not settlement_natural_feature_presenter.initialize_presentation(
			rollback_generation,
			city_tile_size,
			settlement_ui_controller.view_mode,
			session_prepared_city_payload
		)
	):
		city_presentation_binding_generation = rollback_generation
		push_warning(
			"Settlement presentation helper rollback failed after generation "
			+ str(failed_generation)
		)
		return false

	_publish_city_presentation_binding(
		rollback_binding,
		rollback_generation
	)
	return true


func _fail_city_presentation_closed() -> void:
	# A failed commit followed by a failed recovery leaves component high-water
	# marks intentionally non-rewindable. Retire the facade identity and every
	# pending reveal so no mixed-generation helper graph can become interactive.
	city_presentation_rebind_generation += 1
	city_presentation_rebind_pending = false
	initial_city_presentation_configured = false
	session_view_active = false
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	_set_city_render_layers_visible(false)
	_set_descendant_canvas_layers_visible(self, false)
	if camera != null:
		camera.enabled = false
	city_presentation_binding = null
	bound_settlement_context = null
	bound_city_state = null
	bound_city_settlement_id = SettlementData.INVALID_SETTLEMENT_ID
	city_world = null
	city_seed = 0
	session_prepared_city_payload.clear()


func _publish_city_presentation_binding(
	binding: CityPresentationBinding,
	binding_generation: int
) -> void:
	city_presentation_binding_generation = binding_generation
	city_presentation_binding = binding
	bound_settlement_context = binding.settlement_context
	bound_city_state = binding.city_state
	bound_city_settlement_id = binding.settlement_id
	city_world = binding.city_world
	city_seed = binding.city_seed


func _bind_city_presentation_helpers(
	binding: CityPresentationBinding
) -> bool:
	if not _can_bind_city_presentation_helpers(binding):
		return false
	return (
		city_information_ui.bind_settlement_presentation(binding)
		and city_debug_presentation.citizen_debug_panel.bind_settlement_presentation(binding)
		and settlement_entity_panel_presentation.bind_settlement_presentation(
			binding,
			city_tile_size,
			city_debug_presentation.citizen_debug_panel
		)
		and city_citizen_movement_presentation.bind_settlement_presentation(
			binding,
			city_tile_size
		)
		and settlement_placement_controller.bind_settlement_presentation(
			binding,
			city_tile_size
		)
		and settlement_selection_controller.bind_settlement_presentation(
			binding,
			city_tile_size
		)
		and settlement_command_controller.bind_settlement_presentation(
			binding,
			city_tile_size
		)
		and settlement_ui_controller.bind_settlement_presentation(binding)
		and settlement_infrastructure_presenter.bind_settlement_presentation(
			binding,
			city_tile_size
		)
		and workplace_zone_overlay_cache.bind_settlement_presentation(
			binding
		)
		and city_debug_presentation.bind_settlement_presentation(
			binding,
			city_debug_presentation.citizen_debug_panel
		)
		and settlement_natural_feature_presenter.bind_settlement_presentation(
			binding
		)
	)


func _can_bind_city_presentation_helpers(
	binding: CityPresentationBinding
) -> bool:
	if not _ensure_settlement_entity_panel_presentation():
		return false
	return (
		city_information_ui.can_bind_settlement_presentation(binding)
		and city_debug_presentation.citizen_debug_panel.can_bind_settlement_presentation(binding)
		and settlement_entity_panel_presentation.can_bind_settlement_presentation(
			binding,
			city_tile_size
		)
		and city_citizen_movement_presentation.can_bind_settlement_presentation(
			binding,
			city_tile_size
		)
		and settlement_placement_controller.can_bind_settlement_presentation(
			binding,
			city_tile_size
		)
		and settlement_selection_controller.can_bind_settlement_presentation(
			binding,
			city_tile_size
		)
		and settlement_command_controller.can_bind_settlement_presentation(
			binding,
			city_tile_size
		)
		and settlement_ui_controller.can_bind_settlement_presentation(binding)
		and settlement_infrastructure_presenter.can_bind_settlement_presentation(
			binding,
			city_tile_size
		)
		and workplace_zone_overlay_cache.can_bind_settlement_presentation(binding)
		and city_debug_presentation.can_bind_settlement_presentation(
			binding,
			city_debug_presentation.citizen_debug_panel
		)
		and settlement_natural_feature_presenter.can_bind_settlement_presentation(
			binding
		)
	)


func _ensure_settlement_entity_panel_presentation() -> bool:
	if settlement_entity_panel_presentation != null:
		return true
	var scene_panel_owner := get_node_or_null("ObjectPanelAnchor")
	if scene_panel_owner is CityObjectPanelAnchor:
		settlement_entity_panel_presentation = scene_panel_owner
		return true
	settlement_entity_panel_presentation = CityObjectPanelAnchorScript.new()
	settlement_entity_panel_presentation.name = "ObjectPanelAnchor"
	add_child(settlement_entity_panel_presentation)
	return true


func _has_valid_bound_city_presentation() -> bool:
	return (
		initial_city_presentation_configured
		and city_presentation_binding != null
		and city_presentation_binding.is_valid()
		and city_presentation_invalidation_tracker.is_bound_to_city_presentation(
			city_presentation_binding
		)
		and bound_settlement_context != null
		and bound_city_state != null
		and WorldPoliticalState.is_registered_settlement_context(
			bound_settlement_context
		)
		and is_same(
			bound_settlement_context.get_detailed_simulation_state(),
			bound_city_state
		)
		and bound_city_settlement_id
		== bound_settlement_context.settlement_id
		and city_world != null
		and is_same(city_world, bound_city_state.city_world)
		and city_seed == bound_city_state.city_seed
		and city_information_ui.is_bound_to_settlement_presentation(
			city_presentation_binding
		)
		and city_debug_presentation.citizen_debug_panel.is_bound_to_settlement_presentation(
			city_presentation_binding
		)
		and settlement_entity_panel_presentation.is_bound_to_settlement_presentation(
			city_presentation_binding
		)
		and city_citizen_movement_presentation.is_bound_to_settlement_presentation(
			city_presentation_binding
		)
		and settlement_placement_controller.is_bound_to_settlement_presentation(
			city_presentation_binding
		)
		and settlement_selection_controller.is_bound_to_settlement_presentation(
			city_presentation_binding
		)
		and settlement_command_controller.is_bound_to_settlement_presentation(
			city_presentation_binding
		)
		and settlement_ui_controller.is_bound_to_settlement_presentation(
			city_presentation_binding
		)
		and settlement_infrastructure_presenter.is_bound_to_settlement_presentation(
			city_presentation_binding
		)
		and workplace_zone_overlay_cache.is_bound_to_settlement_presentation(
			city_presentation_binding
		)
		and city_debug_presentation.is_bound_to_settlement_presentation(
			city_presentation_binding
		)
		and settlement_natural_feature_presenter.is_bound_to_settlement_presentation(
			city_presentation_binding
		)
	)


func get_bound_settlement_context():
	return bound_settlement_context


func get_city_presentation_binding() -> CityPresentationBinding:
	return city_presentation_binding


func set_session_view_active(is_active: bool) -> void:
	if is_active and not _has_valid_bound_city_presentation():
		is_active = false
	session_view_active = is_active
	visible = is_active
	process_mode = (
		Node.PROCESS_MODE_INHERIT
		if is_active
		else Node.PROCESS_MODE_DISABLED
	)
	_set_descendant_canvas_layers_visible(self, is_active)

	if camera != null:
		camera.enabled = is_active

		if is_active:
			camera.make_current()

	if is_active:
		# The first reveal must populate custom draw layers because the city is
		# constructed while hidden. Later reveals retain those draw lists and rely
		# on version-driven invalidation instead of redrawing everything.
		if not city_layers_have_been_presented:
			queue_all_city_render_layers_redraw()
			city_layers_have_been_presented = true

		city_information_ui.refresh_all()
		update_debug_panel_text()

		if city_presentation_rebind_pending:
			_request_all_city_render_layers_redraw_even_if_hidden()
			call_deferred(
				"_finish_city_presentation_rebind",
				city_presentation_rebind_generation
			)


func can_rebind_city_presentation(
	settlement_context,
	prepared_payload: Dictionary = {}
) -> bool:
	if (
		settlement_context == null
		or not settlement_context is SettlementSimulationContext
		or not settlement_context.supports_detailed_simulation()
		or not WorldPoliticalState.is_registered_settlement_context(
			settlement_context
		)
	):
		return false

	var target_state = settlement_context.get_detailed_simulation_state()
	if (
		not target_state is CitySettlementSimulationState
		or not target_state.city_world is WorldData
		or target_state.city_world.width <= 0
		or target_state.city_world.height <= 0
		or target_state.city_seed <= 0
	):
		return false

	var prepared_world = prepared_payload.get("city_world")
	if prepared_world != null and not is_same(prepared_world, target_state.city_world):
		return false

	var prepared_seed = prepared_payload.get("city_seed")
	if prepared_seed != null and int(prepared_seed) != target_state.city_seed:
		return false

	return true


func rebind_city_presentation(
	settlement_context,
	prepared_payload: Dictionary = {}
) -> bool:
	if not can_rebind_city_presentation(settlement_context, prepared_payload):
		return false

	var target_settlement_id: int = settlement_context.settlement_id
	var target_state: CitySettlementSimulationState = (
		settlement_context.get_detailed_simulation_state()
	)
	var target_world: WorldData = target_state.city_world

	if (
		bound_city_settlement_id == target_settlement_id
		and is_same(bound_settlement_context, settlement_context)
		and is_same(bound_city_state, target_state)
		and city_world != null
		and is_same(city_world, target_world)
		and city_seed == target_state.city_seed
	):
		var change_flags := _collect_city_change_flags()
		city_citizen_movement_presentation.synchronize_for_changes(change_flags)
		_apply_city_change_refreshes(change_flags, false, false)
		city_information_ui.refresh_all()
		settlement_ui_controller.refresh_all()
		update_debug_panel_text()
		_request_all_city_render_layers_redraw_even_if_hidden()
		return validate_city_presentation_binding(settlement_context)

	var previous_context: SettlementSimulationContext = bound_settlement_context
	if (
		previous_context == null
		or city_presentation_binding == null
		or not city_presentation_binding.matches_context(previous_context)
		or not city_presentation_invalidation_tracker.is_bound_to_city_presentation(
			city_presentation_binding
		)
	):
		return false
	var previous_prepared_payload := (
		session_prepared_city_payload.duplicate(true)
	)
	var previous_rebind_was_pending := city_presentation_rebind_pending
	var previous_render_layer_visibility := {}
	for render_layer in [
		city_active_workplace_preview_render_layer,
		city_background_render_layer,
		city_citizen_render_layer,
		city_interaction_render_layer,
	]:
		if render_layer is CanvasItem:
			previous_render_layer_visibility[render_layer] = render_layer.visible
	var rebind_start_usec := Time.get_ticks_usec()
	_store_bound_city_camera_state()
	if not _bind_city_presentation_references(
		settlement_context,
		prepared_payload
	):
		return false

	city_presentation_rebind_generation += 1
	city_presentation_rebind_pending = true
	_set_city_render_layers_visible(false)

	_clear_city_presentation_interactions()
	_reset_city_presentation_observers()
	workplace_zone_overlay_cache.invalidate_all()
	initial_city_presentation_configured = true
	city_citizen_movement_presentation.discard_pending_visual_events()

	install_session_prepared_city_map_textures()
	rebuild_city_terrain_texture()
	rebuild_city_natural_feature_multimeshes()
	city_world.consume_city_surface_feature_changes()
	_configure_city_camera_for_bound_settlement()
	_capture_bound_city_presentation_versions(bound_city_state)

	city_information_ui.refresh_all()
	settlement_ui_controller.refresh_all()
	update_debug_panel_text()
	_request_all_city_render_layers_redraw_even_if_hidden()

	if (
		not validate_city_presentation_binding(settlement_context)
		or not _city_presentation_interactions_are_cleared()
	):
		city_presentation_rebind_pending = false
		city_presentation_rebind_generation += 1
		var restored := (
			WorldPoliticalState.is_registered_settlement_context(
				previous_context
			)
			and _bind_city_presentation_references(
				previous_context,
				previous_prepared_payload
			)
		)
		if restored:
			_clear_city_presentation_interactions()
			_reset_city_presentation_observers()
			workplace_zone_overlay_cache.invalidate_all()
			initial_city_presentation_configured = true
			city_citizen_movement_presentation.discard_pending_visual_events()

			install_session_prepared_city_map_textures()
			rebuild_city_terrain_texture()
			setup_city_natural_feature_rendering()
			city_world.consume_city_surface_feature_changes()
			_configure_city_camera_for_bound_settlement()
			_capture_bound_city_presentation_versions(bound_city_state)

			city_information_ui.refresh_all()
			settlement_ui_controller.refresh_all()
			update_debug_panel_text()
			_request_all_city_render_layers_redraw_even_if_hidden()
			city_presentation_rebind_pending = false
			restored = (
				validate_city_presentation_binding(previous_context)
				and _city_presentation_interactions_are_cleared()
			)
			if restored:
				for render_layer in previous_render_layer_visibility.keys():
					if render_layer is CanvasItem:
						(render_layer as CanvasItem).visible = bool(
							previous_render_layer_visibility[render_layer]
						)
				if previous_rebind_was_pending:
					city_presentation_rebind_pending = true
					if session_view_active:
						call_deferred(
							"_finish_city_presentation_rebind",
							city_presentation_rebind_generation
						)
		if not restored:
			if (
				city_presentation_binding != null
				or initial_city_presentation_configured
				or session_view_active
			):
				_fail_city_presentation_closed()
			push_error(
				"City presentation rebind rollback failed for settlement #"
				+ str(previous_context.settlement_id)
			)
		return false

	if session_view_active:
		call_deferred(
			"_finish_city_presentation_rebind",
			city_presentation_rebind_generation
		)
	city_last_rebind_duration_usec = (
		Time.get_ticks_usec() - rebind_start_usec
	)
	return true


func validate_city_presentation_binding(settlement_context) -> bool:
	if not can_rebind_city_presentation(settlement_context):
		return false

	var target_state: CitySettlementSimulationState = (
		settlement_context.get_detailed_simulation_state()
	)
	if (
		bound_city_settlement_id != settlement_context.settlement_id
		or not is_same(bound_settlement_context, settlement_context)
		or not is_same(bound_city_state, target_state)
		or not is_same(city_world, target_state.city_world)
		or city_seed != target_state.city_seed
		or city_presentation_binding == null
		or not city_presentation_binding.matches_context(settlement_context)
		or not city_presentation_invalidation_tracker.is_bound_to_city_presentation(
			city_presentation_binding
		)
		or not city_information_ui.is_bound_to_settlement_presentation(
			city_presentation_binding
		)
		or not city_debug_presentation.citizen_debug_panel.is_bound_to_settlement_presentation(
			city_presentation_binding
		)
		or not settlement_entity_panel_presentation.is_bound_to_settlement_presentation(
			city_presentation_binding
		)
		or not city_citizen_movement_presentation.is_bound_to_settlement_presentation(
			city_presentation_binding
		)
		or not settlement_placement_controller.is_bound_to_settlement_presentation(
			city_presentation_binding
		)
		or not settlement_selection_controller.is_bound_to_settlement_presentation(
			city_presentation_binding
		)
		or not settlement_command_controller.is_bound_to_settlement_presentation(
			city_presentation_binding
		)
		or not settlement_ui_controller.is_bound_to_settlement_presentation(
			city_presentation_binding
		)
		or not settlement_infrastructure_presenter.is_bound_to_settlement_presentation(
			city_presentation_binding
		)
		or not workplace_zone_overlay_cache.is_bound_to_settlement_presentation(
			city_presentation_binding
		)
		or not city_debug_presentation.is_bound_to_settlement_presentation(
			city_presentation_binding
		)
		or not settlement_natural_feature_presenter.is_bound_to_settlement_presentation(
			city_presentation_binding
		)
		or city_terrain_texture == null
		or city_terrain_texture.get_width() != city_world.width
		or city_terrain_texture.get_height() != city_world.height
	):
		return false

	var expected_tree_count: int = 0
	var expected_rock_count: int = 0
	for tile_row in city_world.tiles:
		for tile in tile_row:
			var surface_feature := WorldData.get_city_surface_feature(tile)
			if surface_feature == WorldData.CITY_SURFACE_FEATURE_TREE:
				expected_tree_count += 1
			elif surface_feature == WorldData.CITY_SURFACE_FEATURE_ROCK:
				expected_rock_count += 1
	if (
		settlement_natural_feature_presenter.tree_multimesh == null
		or settlement_natural_feature_presenter.rock_multimesh == null
		or settlement_natural_feature_presenter.tree_index_by_tile.size()
		!= expected_tree_count
		or settlement_natural_feature_presenter.tree_tile_by_index.size()
		!= expected_tree_count
		or settlement_natural_feature_presenter.tree_multimesh.visible_instance_count
		!= expected_tree_count
		or settlement_natural_feature_presenter.rock_index_by_tile.size()
		!= expected_rock_count
		or settlement_natural_feature_presenter.rock_tile_by_index.size()
		!= expected_rock_count
		or settlement_natural_feature_presenter.rock_multimesh.visible_instance_count
		!= expected_rock_count
	):
		return false

	for tile_position in settlement_natural_feature_presenter.tree_index_by_tile.keys():
		if (
			not tile_position is Vector2i
			or not city_world.is_in_bounds(tile_position.x, tile_position.y)
			or WorldData.get_city_surface_feature(
				city_world.tiles[tile_position.y][tile_position.x]
			) != WorldData.CITY_SURFACE_FEATURE_TREE
		):
			return false

	for tile_position in settlement_natural_feature_presenter.rock_index_by_tile.keys():
		if (
			not tile_position is Vector2i
			or not city_world.is_in_bounds(tile_position.x, tile_position.y)
			or WorldData.get_city_surface_feature(
				city_world.tiles[tile_position.y][tile_position.x]
			) != WorldData.CITY_SURFACE_FEATURE_ROCK
		):
			return false

	return true


func _city_presentation_interactions_are_cleared() -> bool:
	return (
		settlement_selection_controller.is_interaction_state_clear()
		and settlement_placement_controller.is_interaction_state_clear()
		and settlement_command_controller.is_interaction_state_clear()
		and settlement_ui_controller.is_interaction_state_clear()
		and city_debug_presentation.is_interaction_state_clear()
	)


func _clear_city_presentation_interactions() -> void:
	settlement_ui_controller.close_map_menu()
	settlement_ui_controller.close_build_menu()
	settlement_ui_controller.close_all_object_menus()
	settlement_ui_controller.close_command_menu()
	cancel_active_city_object_placement()
	cancel_road_placement()
	cancel_city_player_command_drag()
	settlement_selection_controller.cancel_selection_drag()
	clear_selected_city_entity()
	clear_debug_selected_city_tile()
	hide_workplace_details_ui()
	hide_construction_site_info_panel()
	_hide_selected_city_object_panel()
	settlement_selection_controller.clear_interaction_state()
	clear_debug_navigation_result()


func _reset_city_presentation_observers() -> void:
	city_presentation_invalidation_tracker.reset_observations()
	active_workplace_preview_refresh_pending = false
	city_debug_presentation.clear_refresh_request()


func _capture_bound_city_presentation_versions(
	city_state: CitySettlementSimulationState
) -> void:
	if (
		city_presentation_binding == null
		or not is_same(city_state, city_presentation_binding.city_state)
	):
		return
	city_presentation_invalidation_tracker.capture_current_versions(
		city_presentation_binding.generation
	)


func _store_bound_city_camera_state() -> void:
	if camera == null or city_presentation_binding == null:
		return
	if camera is StrategyCamera2D:
		(camera as StrategyCamera2D).store_settlement_presentation_transform(
			city_presentation_binding
		)


func _configure_city_camera_for_bound_settlement() -> void:
	if camera == null or city_presentation_binding == null:
		return
	if camera is StrategyCamera2D:
		(camera as StrategyCamera2D).configure_for_settlement_presentation(
			city_presentation_binding,
			city_tile_size
		)


func _set_city_render_layers_visible(is_visible: bool) -> void:
	for render_layer in [
		city_active_workplace_preview_render_layer,
		city_background_render_layer,
		city_citizen_render_layer,
		city_interaction_render_layer,
	]:
		if render_layer is CanvasItem:
			(render_layer as CanvasItem).visible = is_visible


func _request_all_city_render_layers_redraw_even_if_hidden() -> void:
	for render_layer in [
		city_active_workplace_preview_render_layer,
		city_background_render_layer,
		city_citizen_render_layer,
		city_interaction_render_layer,
	]:
		if render_layer is CityRenderLayer:
			(render_layer as CityRenderLayer).request_redraw()


func _finish_city_presentation_rebind(generation: int) -> void:
	if (
		generation != city_presentation_rebind_generation
		or not city_presentation_rebind_pending
		or not session_view_active
	):
		return
	if (
		bound_settlement_context == null
		or city_presentation_binding == null
		or not city_presentation_binding.matches_context(
			bound_settlement_context
		)
		or not validate_city_presentation_binding(bound_settlement_context)
	):
		_fail_city_presentation_closed()
		return
	city_presentation_rebind_pending = false
	_set_city_render_layers_visible(true)


func _set_descendant_canvas_layers_visible(root: Node, is_visible: bool) -> void:
	for child in root.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = is_visible

		_set_descendant_canvas_layers_visible(child, is_visible)


func get_game_session_controller() -> Node:
	var current: Node = self

	while current != null:
		if current.is_in_group("game_session"):
			return current

		current = current.get_parent()

	return null


func _process(delta: float) -> void:
	var city_camera_transform_changed := _process_texture_cache_and_camera()
	var city_hover_tile_changed := _update_city_hover_state()
	_update_active_city_interaction_state()
	var change_flags := _collect_city_change_flags()
	city_citizen_movement_presentation.synchronize_for_changes(change_flags)

	if city_citizen_movement_presentation.update(delta):
		queue_city_citizen_layer_redraw()

	_apply_city_change_refreshes(
		change_flags,
		city_hover_tile_changed,
		city_camera_transform_changed
	)


func _process_texture_cache_and_camera() -> bool:
	if not camera is StrategyCamera2D:
		return false
	var transform_changes := (
		(camera as StrategyCamera2D).consume_transform_changes()
	)
	if bool(transform_changes.get("zoom_changed", false)):
		queue_city_interaction_layer_redraw()
	return bool(transform_changes.get("changed", false))


func _update_city_hover_state() -> bool:
	var current_hovered_tile := (
		settlement_selection_controller.world_position_to_settlement_tile(
			get_global_mouse_position()
		)
	)
	if not settlement_selection_controller.update_hovered_settlement_tile(
		current_hovered_tile
	):
		return false
	update_debug_panel_text()

	var hover_visual_can_change: bool = (
		not has_selected_city_entity()
		or has_active_city_object_placement()
		or is_road_placement_active
		or is_road_dragging
		or is_object_selection_dragging
		or is_city_player_command_tool_active()
		or settlement_command_controller.is_dragging
	)

	if hover_visual_can_change:
		queue_city_interaction_layer_redraw()

	return true


func _update_active_city_interaction_state() -> void:
	if is_road_placement_active:
		settlement_ui_controller.update_road_cursor_position(
			get_viewport().get_mouse_position()
		)

	if settlement_command_controller.is_cancel_mode_active:
		settlement_command_controller.update_cancel_cursor_visual(
			get_viewport().get_mouse_position()
		)

	if is_road_dragging:
		update_road_drag_selection()

	if selected_city_construction_site_id > 0:
		update_construction_site_info_panel_screen_position()


func _collect_city_change_flags() -> Dictionary:
	var change_flags: Dictionary = (
		city_presentation_invalidation_tracker.create_change_flags()
	)

	_collect_city_world_change_flags(change_flags)
	_collect_world_data_change_flags(change_flags)
	return change_flags


func _collect_city_world_change_flags(
	change_flags: Dictionary
) -> void:
	if city_presentation_binding == null:
		return
	if not city_presentation_invalidation_tracker.collect_city_world_version_change_flags(
		city_presentation_binding.generation,
		change_flags
	):
		return

	if bool(change_flags.get("city_tile_data_changed", false)):
		workplace_zone_overlay_cache.invalidate_all()
		rebuild_city_natural_feature_multimeshes()
		city_world.consume_city_surface_feature_changes()
		# Tile-data edits can change biome, terrain, resources, or fertility.
		# Rebuild the complete atomic cache in one shared pass. No later frame
		# receives deferred map-mode generation work.
		rebuild_city_terrain_texture()
		settlement_ui_controller.update_map_mode_button_visuals()
		return

	if not bool(change_flags.get("city_surface_features_changed", false)):
		return

	var surface_feature_changes := (
		city_world.consume_city_surface_feature_changes()
	)

	if surface_feature_changes.is_empty():
		change_flags["city_surface_features_changed"] = false
		return

	if not apply_city_surface_feature_changes(surface_feature_changes):
		rebuild_city_natural_feature_multimeshes()
	else:
		store_city_natural_feature_cache()


func _collect_world_data_change_flags(
	change_flags: Dictionary
) -> void:
	if city_presentation_binding == null:
		return
	if not city_presentation_invalidation_tracker.collect_city_state_change_flags(
		city_presentation_binding.generation,
		change_flags
	):
		return


func _apply_city_change_refreshes(
	change_flags: Dictionary,
	city_hover_tile_changed: bool,
	city_camera_transform_changed: bool = false
) -> void:
	var city_objects_changed := bool(
		change_flags.get("city_objects_changed", false)
	)
	var city_containers_changed := bool(
		change_flags.get("city_containers_changed", false)
	)
	var public_storage_changed := bool(
		change_flags.get("public_storage_changed", false)
	)
	var city_citizens_changed := bool(
		change_flags.get("city_citizens_changed", false)
	)
	var city_citizen_spatial_changed := bool(
		change_flags.get("city_citizen_spatial_changed", false)
	)
	var city_citizen_movement_changed := bool(
		change_flags.get("city_citizen_movement_changed", false)
	)
	var city_citizen_task_changed := bool(
		change_flags.get("city_citizen_task_changed", false)
	)
	var city_ground_piles_changed := bool(
		change_flags.get("city_ground_piles_changed", false)
	)
	var city_player_commands_changed := bool(
		change_flags.get("city_player_commands_changed", false)
	)
	var city_haul_reservations_changed := bool(
		change_flags.get("city_haul_reservations_changed", false)
	)
	var city_construction_changed := bool(
		change_flags.get("city_construction_changed", false)
	)
	var city_assignments_changed := bool(
		change_flags.get("city_assignments_changed", false)
	)
	var city_workplaces_changed := bool(
		change_flags.get("city_workplaces_changed", false)
	)
	var city_tile_data_changed := bool(
		change_flags.get("city_tile_data_changed", false)
	)
	var city_surface_features_changed := bool(
		change_flags.get("city_surface_features_changed", false)
	)

	if has_active_city_object_placement():
		if not active_city_object_placement_uses_environmental_source():
			active_workplace_preview_refresh_pending = false
		elif (
			city_hover_tile_changed
			or city_camera_transform_changed
			or city_tile_data_changed
		):
			# Edge scrolling can move the cursor across hundreds of two-pixel
			# city tiles. Clear the stale retained zone now, then wait for one
			# stable-hover frame before rebuilding its CPU image/GPU texture.
			active_workplace_preview_refresh_pending = true
			queue_city_active_workplace_preview_layer_redraw()
		elif active_workplace_preview_refresh_pending:
			refresh_active_workplace_zone_preview_cache()
			active_workplace_preview_refresh_pending = false
			queue_city_active_workplace_preview_layer_redraw()
	else:
		active_workplace_preview_refresh_pending = false

	if (
		has_selected_city_entity()
		and (
			city_objects_changed
			or city_tile_data_changed
		)
	):
		refresh_selected_workplace_zone_cache()

	if city_containers_changed or public_storage_changed:
		settlement_ui_controller.update_resource_bar_values()

	if city_citizens_changed:
		city_information_ui.refresh_citizen_data()

	if (
		city_objects_changed
		or city_containers_changed
		or city_citizens_changed
		or city_citizen_movement_changed
		or city_citizen_task_changed
		or city_ground_piles_changed
		or city_player_commands_changed
		or city_haul_reservations_changed
		or city_construction_changed
		or city_assignments_changed
		or city_workplaces_changed
		or city_tile_data_changed
		or city_surface_features_changed
	):
		update_selected_entity_panel()

	if (
		city_objects_changed
		or city_tile_data_changed
		or city_ground_piles_changed
		or city_construction_changed
		or city_surface_features_changed
	):
		queue_city_background_layer_redraw()

	if (
		city_citizens_changed
		or city_citizen_spatial_changed
		or city_citizen_movement_changed
		or city_tile_data_changed
		or city_surface_features_changed
	):
		queue_city_citizen_layer_redraw()

	if (
		city_objects_changed
		or city_tile_data_changed
		or city_player_commands_changed
		or city_construction_changed
		or city_surface_features_changed
	):
		queue_city_interaction_layer_redraw()

	if (
		city_debug_presentation.refresh_pending
		or city_objects_changed
		or city_citizens_changed
		or city_citizen_spatial_changed
		or city_assignments_changed
		or city_tile_data_changed
		or city_citizen_movement_changed
		or city_citizen_task_changed
		or city_ground_piles_changed
		or city_player_commands_changed
		or city_haul_reservations_changed
		or city_construction_changed
		or city_surface_features_changed
	):
		update_debug_panel_text()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event: InputEventKey = event

		var is_debug_toggle_key: bool = (
			key_event.keycode == KEY_QUOTELEFT
			or key_event.physical_keycode == KEY_QUOTELEFT
			or key_event.unicode == 96
			or key_event.unicode == 126
		)

		if is_debug_toggle_key:
			toggle_debug_mode()
			get_viewport().set_input_as_handled()
			return

		if key_event.keycode == KEY_ESCAPE:
			if settlement_command_controller.menu_open:
				settlement_ui_controller.close_command_menu()
				get_viewport().set_input_as_handled()
				return

		if WorldData.debug_mode_enabled:
			if (
				key_event.keycode == KEY_P
				or key_event.physical_keycode == KEY_P
			):
				request_debug_navigation_path()
				get_viewport().set_input_as_handled()
				return

			if (
				key_event.keycode == KEY_M
				or key_event.physical_keycode == KEY_M
			):
				assign_debug_navigation_path_to_selected_citizen()
				get_viewport().set_input_as_handled()
				return

			var debug_resource := DebugPanel.get_stockpile_resource_for_key(key_event)

			if debug_resource != "":
				add_debug_resource_to_selected_stockpile(debug_resource, 10)
				get_viewport().set_input_as_handled()
				return

		var requested_view_mode: int = MapVisuals.get_view_mode_for_keycode(key_event.keycode)

		if requested_view_mode != MapVisuals.INVALID_VIEW_MODE:
			set_city_view_mode(requested_view_mode)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		if (
			event.pressed
			and event.button_index == MOUSE_BUTTON_RIGHT
			and is_city_player_command_tool_active()
		):
			settlement_ui_controller.deactivate_command_tool()
			get_viewport().set_input_as_handled()
			return

		if (
			event.pressed
			and event.button_index == MOUSE_BUTTON_RIGHT
			and settlement_command_controller.menu_open
		):
			settlement_ui_controller.close_command_menu()
			get_viewport().set_input_as_handled()
			return

		if event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			if is_road_placement_active:
				cancel_road_placement()
				settlement_ui_controller.close_build_menu()
				get_viewport().set_input_as_handled()
				return

			if has_active_city_object_placement():
				cancel_active_city_object_placement()
				settlement_ui_controller.close_all_object_menus()
				get_viewport().set_input_as_handled()
				return

			if selected_city_construction_site_id > 0:
				clear_selected_city_entity()
				get_viewport().set_input_as_handled()
				return

			if settlement_ui_controller.map_menu_open:
				settlement_ui_controller.close_map_menu()
				get_viewport().set_input_as_handled()
				return

			if settlement_ui_controller.is_build_menu_open():
				settlement_ui_controller.close_build_menu()
				get_viewport().set_input_as_handled()
				return

			if settlement_ui_controller.has_open_object_menu():
				settlement_ui_controller.close_all_object_menus()
				get_viewport().set_input_as_handled()
				return

			var cleared_any_selection := false

			if has_selected_city_entity():
				clear_selected_city_entity()
				cleared_any_selection = true

			if (
				WorldData.debug_mode_enabled
				and has_debug_selected_city_tile()
			):
				clear_debug_selected_city_tile()
				cleared_any_selection = true

			if cleared_any_selection:
				get_viewport().set_input_as_handled()
				return

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if (
			event.button_index == MOUSE_BUTTON_LEFT
			and is_city_player_command_tool_active()
		):
			if event.pressed:
				start_city_player_command_drag(
					event.position,
					settlement_command_controller.is_cancel_mode_active
				)
			else:
				finish_city_player_command_drag(event.position)

			get_viewport().set_input_as_handled()
			return

		if event.button_index == MOUSE_BUTTON_LEFT:
			if has_active_city_object_placement() and event.pressed:
				confirm_active_city_object_placement()
				get_viewport().set_input_as_handled()
				return

			if is_road_placement_active:
				if event.pressed:
					handle_road_left_mouse_pressed()
				else:
					handle_road_left_mouse_released()

				get_viewport().set_input_as_handled()
				return

			if event.pressed:
				start_object_selection_drag(event.position)
			else:
				finish_object_selection_drag(event.position)

			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion:
		if settlement_command_controller.is_dragging:
			update_city_player_command_drag(event.position)
			get_viewport().set_input_as_handled()
			return

		if is_object_selection_dragging:
			update_object_selection_drag(event.position)
			get_viewport().set_input_as_handled()
			return

#endregion

#region Simulation clock and debug input helpers

func connect_simulation_clock_signals() -> void:
	var time_changed_callable := Callable(
		self,
		"on_simulation_time_changed"
	)

	if not SimulationClock.time_changed.is_connected(time_changed_callable):
		SimulationClock.time_changed.connect(time_changed_callable)


func on_simulation_time_changed(
	_day: int,
	_hour: int,
	_minute: int
) -> void:
	if bound_city_state == null:
		return

	if not session_view_active:
		city_citizen_movement_presentation.consume_committed_tick(
			SimulationClock.tick_index,
			false
		)
		return

	city_information_ui.refresh_time()

	var movement_visual_changed := (
		city_citizen_movement_presentation.consume_committed_tick(
			SimulationClock.tick_index,
			true
		)
	)

	if movement_visual_changed:
		queue_city_citizen_layer_redraw()

	city_debug_presentation.request_refresh()


func add_debug_resource_to_selected_stockpile(
	resource: String,
	amount_delta: int
) -> void:
	var result := (
		city_debug_presentation
		.execute_add_resource_to_selected_public_storage(
			city_presentation_binding,
			selected_city_object_id,
			resource,
			amount_delta
		)
	)
	print(str(result.get("message", "Debug storage add blocked.")))
	if not bool(result.get("success", false)):
		return

	settlement_ui_controller.update_resource_bar_values()
	update_selected_entity_panel()
	update_debug_panel_text()
#endregion

#region City generation


func install_session_prepared_city_map_textures() -> void:
	if city_world == null or city_texture_cache == null:
		return

	var prepared_atlas = session_prepared_city_payload.get("map_atlas")

	if not prepared_atlas is Dictionary:
		return

	if not city_texture_cache.install_prepared_atlas(
		city_world,
		prepared_atlas
	):
		push_error(
			"Prepared city atlas was invalid; rebuilding synchronously."
		)

#endregion

#region Camera

func create_city_camera() -> void:
	if city_world == null:
		return

	camera = StrategyCamera2D.new()
	camera.max_zoom = 80.0
	camera.zoom_speed = 0.10

	add_child(camera)
	_configure_city_camera_for_bound_settlement()
	camera.make_current()

#endregion

#region Settlement UI facade and interaction input

func create_city_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 100
	add_child(ui_layer)

	ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(ui_root)

	create_city_information_panel()
	if not settlement_ui_controller.setup(
		ui_root,
		settlement_placement_controller,
		settlement_selection_controller,
		settlement_command_controller,
		{
			"is_map_mode_ready": Callable(
				self,
				"_is_bound_settlement_map_mode_ready"
			),
			"apply_map_mode": Callable(
				self,
				"_apply_bound_settlement_map_mode"
			),
			"back": Callable(self, "_on_settlement_back_requested"),
			"present_ui_change": Callable(
				self,
				"_on_settlement_ui_change"
			),
		}
	):
		push_error("Failed to set up settlement UI chrome.")
		return
	if settlement_entity_panel_presentation.get_parent() == null:
		add_child(settlement_entity_panel_presentation)
	if not settlement_entity_panel_presentation.setup(ui_root):
		push_error("Failed to set up settlement entity panel presentation.")
	settlement_selection_controller.create_selection_box_visual(ui_root)
	settlement_command_controller.create_drag_selection_box_visual(ui_root)
	if not settlement_ui_controller.create_overlay_chrome():
		push_error("Failed to set up settlement UI overlay chrome.")
	settlement_command_controller.create_cancel_cursor_visual(ui_root)

	get_viewport().size_changed.connect(update_city_ui_layout)
	update_city_ui_layout()
	settlement_ui_controller.refresh_all()


func create_city_information_panel() -> void:
	city_information_ui.setup(ui_root)


func is_city_player_command_mode_active() -> bool:
	return settlement_command_controller.is_command_mode_active()


func is_city_player_command_tool_active() -> bool:
	return settlement_command_controller.is_tool_active()


func _is_bound_settlement_map_mode_ready(mode: int) -> bool:
	return (
		city_presentation_binding != null
		and city_presentation_binding.is_valid()
		and city_texture_cache != null
		and city_texture_cache.is_mode_ready(
			city_presentation_binding.world,
			mode
		)
	)


func _apply_bound_settlement_map_mode(mode: int) -> void:
	if mode != settlement_ui_controller.view_mode:
		return
	print("Settlement map mode: ", MapVisuals.get_view_mode_name(mode))
	apply_cached_city_map_mode_texture()
	refresh_city_natural_feature_instance_visibility()


func _on_settlement_ui_change(
	change_kind: String,
	payload: Variant = null
) -> void:
	match change_kind:
		"selection_transition":
			if payload is Dictionary:
				_apply_city_selection_transition(payload)
		"command_cancel_activated":
			settlement_command_controller.update_cancel_cursor_visual(
				get_viewport().get_mouse_position()
			)
		"workplace_and_interaction_redraw":
			active_workplace_preview_refresh_pending = false
			queue_city_active_workplace_preview_layer_redraw()
			queue_city_interaction_layer_redraw()
		"interaction_redraw":
			queue_city_interaction_layer_redraw()


func _on_settlement_back_requested() -> void:
	_store_bound_city_camera_state()
	var session := get_game_session_controller()
	if session == null or not session.has_method("show_world_view"):
		push_error(
			"Settlement-to-world switching requires the persistent GameSession."
		)
		return
	session.call("show_world_view")

func _exit_tree() -> void:
	if city_texture_cache != null:
		city_texture_cache.dispose()

func set_city_view_mode(mode: int) -> void:
	settlement_ui_controller.set_view_mode(mode)


func update_city_ui_layout() -> void:
	if ui_root == null:
		return
	var viewport_size := get_viewport_rect().size
	settlement_ui_controller.layout(viewport_size)
	city_information_ui.layout()
	settlement_entity_panel_presentation.layout(
		viewport_size,
		city_information_ui.get_reserved_bottom_y()
	)


func cancel_active_city_object_placement() -> void:
	var object_type := (
		settlement_ui_controller.cancel_active_object_placement()
	)
	active_workplace_preview_refresh_pending = false
	if object_type != "":
		print("Settlement object placement canceled: ", object_type)

func update_construction_site_info_panel_screen_position() -> void:
	settlement_entity_panel_presentation.update_construction_site_info_panel_screen_position()


func hide_workplace_details_ui() -> void:
	settlement_entity_panel_presentation.hide_workplace_details_ui()


func hide_construction_site_info_panel() -> void:
	settlement_entity_panel_presentation.hide_construction_site_info_panel()


func update_selected_entity_panel() -> void:
	var selection_kind := selected_city_entity_kind
	var selection_id := selected_city_entity_id
	var selection_is_valid := (
		settlement_entity_panel_presentation.update_selected_entity_panel(
			selection_kind,
			selection_id
		)
	)
	if (
		not selection_is_valid
		and selection_kind != CITY_SELECTION_KIND_NONE
		and selected_city_entity_kind == selection_kind
		and selected_city_entity_id == selection_id
	):
		clear_selected_city_entity()


func _hide_selected_city_object_panel() -> void:
	settlement_entity_panel_presentation.hide_selected_entity_panels()


func start_city_player_command_drag(
	screen_position: Vector2,
	removing: bool,
	world_position_override: Variant = null
) -> void:
	var pointer_world_position := get_global_mouse_position()
	if world_position_override is Vector2:
		pointer_world_position = world_position_override
	if settlement_command_controller.begin_drag(
		screen_position,
		pointer_world_position,
		removing
	):
		queue_city_interaction_layer_redraw()


func update_city_player_command_drag(
	screen_position: Vector2,
	world_position_override: Variant = null
) -> void:
	var pointer_world_position := get_global_mouse_position()
	if world_position_override is Vector2:
		pointer_world_position = world_position_override
	if settlement_command_controller.update_drag(
		screen_position,
		pointer_world_position
	):
		queue_city_interaction_layer_redraw()


func finish_city_player_command_drag(
	screen_position: Vector2,
	world_position_override: Variant = null
) -> void:
	var pointer_world_position := get_global_mouse_position()
	if world_position_override is Vector2:
		pointer_world_position = world_position_override
	settlement_command_controller.finish_drag(
		screen_position,
		pointer_world_position
	)
	queue_city_interaction_layer_redraw()


func cancel_city_player_command_drag() -> void:
	settlement_command_controller.cancel_drag()
	queue_city_interaction_layer_redraw()

func start_road_placement() -> void:
	if not settlement_ui_controller.start_road_placement():
		return
	settlement_ui_controller.update_road_cursor_position(
		get_viewport().get_mouse_position()
	)
	print(
		"Road placement started. Drag a selection box, then left-click again "
		+ "to confirm."
	)


func cancel_road_placement() -> void:
	if settlement_ui_controller.cancel_road_placement():
		print("Road placement canceled.")

func confirm_active_city_object_placement() -> void:
	var commit := settlement_placement_controller.commit_active_object_placement(
		get_city_tile_under_mouse()
	)
	var status := str(commit.get("status", ""))
	var object_type := str(commit.get("object_type", ""))
	if status == SettlementPlacementControllerScript.COMMIT_STATUS_INVALID_POINTER:
		print("Cannot place object: invalid mouse position.")
		return
	if status == SettlementPlacementControllerScript.COMMIT_STATUS_UNAVAILABLE:
		print("Cannot place object: unavailable for this settlement.")
		settlement_ui_controller.set_object_option_selected(object_type, false)
		active_workplace_preview_refresh_pending = false
		settlement_ui_controller.update_object_button_states()
		queue_city_active_workplace_preview_layer_redraw()
		queue_city_interaction_layer_redraw()
		return
	if status == SettlementPlacementControllerScript.COMMIT_STATUS_INVALID_LOCATION:
		print("Cannot place object here.")
		return
	if status != SettlementPlacementControllerScript.COMMIT_STATUS_COMMITTED:
		if status != SettlementPlacementControllerScript.COMMIT_STATUS_INVALID_BINDING:
			print("Could not place object here.")
		return

	var uses_construction := bool(commit.get("uses_construction", false))
	var placement_result: Dictionary = commit.get("placement_result", {})
	if bool(commit.get("placement_cleared", false)):
		settlement_ui_controller.set_object_option_selected(object_type, false)
		active_workplace_preview_refresh_pending = false
		queue_city_active_workplace_preview_layer_redraw()

	settlement_ui_controller.update_object_button_states()
	settlement_ui_controller.update_build_button_state()
	update_debug_panel_text()
	if not uses_construction:
		city_information_ui.refresh_all()

	if uses_construction:
		print("Queued construction blueprint: ", placement_result)
	else:
		print("Placed city object: ", placement_result)

	queue_city_background_layer_redraw()
	queue_city_interaction_layer_redraw()



func start_object_selection_drag(screen_position: Vector2) -> void:
	if settlement_selection_controller.begin_selection_drag(
		screen_position,
		get_global_mouse_position()
	):
		queue_city_interaction_layer_redraw()

func update_object_selection_drag(screen_position: Vector2) -> void:
	if settlement_selection_controller.update_selection_drag(
		screen_position,
		get_global_mouse_position()
	):
		queue_city_interaction_layer_redraw()

func finish_object_selection_drag(screen_position: Vector2) -> void:
	var result := settlement_selection_controller.finish_selection_drag(
		screen_position,
		get_global_mouse_position(),
		city_citizen_movement_presentation
	)
	if not bool(result.get("completed", false)):
		return
	_apply_city_selection_transition(result)
	if (
		bool(result.get("was_click", false))
		and bool(result.get("empty_target", false))
		and WorldData.debug_mode_enabled
	):
		set_debug_selected_city_tile(
			result.get("tile_position", Vector2i(-1, -1))
		)
	queue_city_interaction_layer_redraw()

func has_selected_city_entity() -> bool:
	return settlement_selection_controller.has_selected_settlement_entity()

func has_debug_selected_city_tile() -> bool:
	return city_debug_presentation.has_selected_tile()


func set_debug_selected_city_tile(
	tile_position: Vector2i
) -> void:
	if not WorldData.debug_mode_enabled:
		return
	if (
		city_world == null
		or not city_world.is_in_bounds(tile_position.x, tile_position.y)
	):
		return

	if has_selected_city_entity():
		clear_selected_city_entity()
	if not city_debug_presentation.set_selected_tile(tile_position):
		return
	update_debug_panel_text()
	queue_city_background_layer_redraw()
	queue_city_interaction_layer_redraw()


func clear_debug_selected_city_tile() -> void:
	if not city_debug_presentation.clear_selected_tile():
		return
	update_debug_panel_text()
	queue_city_background_layer_redraw()
	queue_city_interaction_layer_redraw()

func set_selected_city_object(
	object_id: int
) -> void:
	_apply_city_selection_transition(
		settlement_selection_controller.set_selected_settlement_object(
			object_id
		)
	)


func set_selected_city_construction_site(
	site_id: int
) -> void:
	_apply_city_selection_transition(
		settlement_selection_controller.set_selected_settlement_construction_site(
			site_id
		)
	)


func clear_selected_city_entity() -> void:
	_apply_city_selection_transition(
		settlement_selection_controller.clear_selected_settlement_entity()
	)


func _apply_city_selection_transition(transition: Dictionary) -> void:
	var previous_kind := str(transition.get(
		"previous_kind",
		CITY_SELECTION_KIND_NONE
	))
	var current_kind := str(transition.get(
		"current_kind",
		CITY_SELECTION_KIND_NONE
	))
	var changed := bool(transition.get("changed", false))
	if (
		current_kind != CITY_SELECTION_KIND_NONE
		and WorldData.debug_mode_enabled
		and has_debug_selected_city_tile()
	):
		clear_debug_selected_city_tile()

	if not changed:
		update_selected_entity_panel()
		return
	if (
		current_kind == CITY_SELECTION_KIND_NONE
		and WorldData.debug_mode_enabled
		and has_debug_selected_city_tile()
	):
		clear_debug_navigation_result()
	if current_kind != CITY_SELECTION_KIND_NONE:
		refresh_selected_workplace_zone_cache()
	update_selected_entity_panel()
	update_debug_panel_text()
	queue_city_selection_visual_change(previous_kind, current_kind)


func queue_city_selection_visual_change(
	previous_selection_kind: String,
	current_selection_kind: String
) -> void:
	# Object selection owns a background workplace-zone overlay. Citizen
	# selection lives with the moving citizen geometry so its outline is rebuilt
	# from the same interpolated position as the marker.
	if (
		previous_selection_kind == CITY_SELECTION_KIND_OBJECT
		or current_selection_kind == CITY_SELECTION_KIND_OBJECT
	):
		queue_city_background_layer_redraw()

	if (
		previous_selection_kind == CITY_SELECTION_KIND_CITIZEN
		or current_selection_kind == CITY_SELECTION_KIND_CITIZEN
	):
		queue_city_citizen_layer_redraw()

	# Selection also changes whether the generic hovered-tile outline is shown.
	queue_city_interaction_layer_redraw()


func is_city_object_selectable(city_object: Dictionary) -> bool:
	return settlement_selection_controller.is_settlement_object_selectable(
		city_object
	)


func is_city_construction_site_selectable(
	construction_site: Dictionary
) -> bool:
	return (
		settlement_selection_controller
		.is_settlement_construction_site_selectable(construction_site)
	)

func get_city_object_by_id(object_id) -> Dictionary:
	return settlement_selection_controller.get_settlement_object_by_id(
		object_id
	)

func get_city_object_world_rect(city_object: Dictionary) -> Rect2:
	return settlement_selection_controller.get_settlement_object_world_rect(
		city_object
	)

func handle_road_left_mouse_pressed() -> void:
	var action := (
		settlement_placement_controller.handle_road_left_mouse_pressed(
			get_city_tile_from_mouse()
		)
	)
	if action == "confirm":
		confirm_road_preview()
	elif action == "drag_started":
		queue_city_interaction_layer_redraw()

func handle_road_left_mouse_released() -> void:
	if not settlement_placement_controller.handle_road_left_mouse_released():
		return
	print("Road preview ready. Left-click again to confirm, or right-click to cancel.")

func start_road_drag_selection() -> void:
	if settlement_placement_controller.start_road_drag_selection(
		get_city_tile_from_mouse()
	):
		queue_city_interaction_layer_redraw()

func update_road_drag_selection() -> void:
	if settlement_placement_controller.update_road_drag_selection(
		get_city_tile_from_mouse()
	):
		queue_city_interaction_layer_redraw()

func rebuild_road_preview_rectangle(start_tile: Vector2i, end_tile: Vector2i) -> void:
	settlement_placement_controller.rebuild_road_preview_rectangle(
		start_tile,
		end_tile
	)

func get_city_tile_from_mouse() -> Vector2i:
	if city_world == null:
		return Vector2i(-1, -1)

	var mouse_world_position: Vector2 = get_global_mouse_position()

	var tile_position := Vector2i(
		int(floor(mouse_world_position.x / float(city_tile_size))),
		int(floor(mouse_world_position.y / float(city_tile_size)))
	)

	if tile_position.x < 0 or tile_position.y < 0:
		return Vector2i(-1, -1)

	if tile_position.x >= city_world.width or tile_position.y >= city_world.height:
		return Vector2i(-1, -1)

	return tile_position

func confirm_road_preview() -> void:
	var commit := settlement_placement_controller.confirm_road_preview()
	var status := str(commit.get("status", ""))
	if status == SettlementPlacementControllerScript.COMMIT_STATUS_EMPTY_PREVIEW:
		print("No road tiles selected.")
		return
	if status == SettlementPlacementControllerScript.COMMIT_STATUS_UNAVAILABLE:
		print("Road placement is unavailable for this settlement.")
		cancel_road_placement()
		settlement_ui_controller.update_build_button_state()
		return
	if status != SettlementPlacementControllerScript.COMMIT_STATUS_COMMITTED:
		if status == SettlementPlacementControllerScript.COMMIT_STATUS_FAILED:
			print("No valid road tiles could be placed.")
			queue_city_interaction_layer_redraw()
		return

	var placed_tile_count := int(commit.get("placed_tile_count", 0))
	if placed_tile_count <= 0:
		print("No valid road tiles could be placed.")
		queue_city_interaction_layer_redraw()
		return

	print(
		"Queued ",
		placed_tile_count,
		" independent road-tile blueprints."
	)

	settlement_ui_controller.show_active_road_chrome()
	settlement_ui_controller.update_road_cursor_position(
		get_viewport().get_mouse_position()
	)

	queue_city_background_layer_redraw()
	queue_city_interaction_layer_redraw()
#endregion

#region Map texture cache

func setup_city_texture_cache() -> void:
	city_texture_cache.setup_standard_map_visuals({
		"owner": self,
		"label": "Settlement",
		"biome_resource_blend": 0.45,
		"has_valid_saved_cache_provider": Callable(
			self,
			"has_valid_saved_city_map_texture_cache"
		),
		"saved_cache_getter": Callable(
			self,
			"get_saved_city_map_texture_cache"
		),
		"saved_cache_storer": Callable(
			self,
			"store_saved_city_map_texture_cache"
		),
	})


func has_valid_saved_city_map_texture_cache(source_world: WorldData) -> bool:
	return MapTextureCacheStateScript.has_valid_city_cache(source_world, city_seed)


func get_saved_city_map_texture_cache() -> Dictionary:
	return MapTextureCacheStateScript.get_city_cache()


func store_saved_city_map_texture_cache(source_world: WorldData, texture_cache: Dictionary) -> void:
	MapTextureCacheStateScript.store_city_cache(source_world, city_seed, texture_cache)

func rebuild_city_terrain_texture() -> void:
	if city_texture_cache == null:
		setup_city_texture_cache()

	city_map_texture_cache_reused_on_entry = (
		has_valid_saved_city_map_texture_cache(city_world)
	)
	city_terrain_texture = city_texture_cache.rebuild(
		city_world,
		settlement_ui_controller.view_mode
	)
	refresh_city_terrain_sprite()


func apply_cached_city_map_mode_texture() -> void:
	if city_texture_cache == null:
		setup_city_texture_cache()

	city_terrain_texture = city_texture_cache.get_texture_for_mode(
		city_world,
		settlement_ui_controller.view_mode
	)
	refresh_city_terrain_sprite()


func create_city_terrain_sprite() -> void:
	city_terrain_sprite = Sprite2D.new()
	city_terrain_sprite.name = "CityTerrainSprite"
	city_terrain_sprite.centered = false
	city_terrain_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	city_terrain_sprite.z_index = -100
	add_child(city_terrain_sprite)


func refresh_city_terrain_sprite() -> void:
	if city_terrain_sprite == null:
		return

	city_terrain_sprite.texture = city_terrain_texture
	city_terrain_sprite.scale = Vector2.ONE * float(city_tile_size)
	city_terrain_sprite.visible = city_terrain_texture != null


#endregion

#region Rendering and tile drawing

func setup_city_natural_feature_rendering() -> void:
	if settlement_natural_feature_presenter.get_parent() == null:
		settlement_natural_feature_presenter.name = (
			"SettlementNaturalFeaturePresenter"
		)
		add_child(settlement_natural_feature_presenter)
	elif settlement_natural_feature_presenter.get_parent() != self:
		push_error(
			"Settlement natural-feature presenter already has another owner."
		)
		return

	if (
		city_presentation_binding == null
		or not settlement_natural_feature_presenter.initialize_presentation(
			city_presentation_binding.generation,
			city_tile_size,
			settlement_ui_controller.view_mode,
			session_prepared_city_payload
		)
	):
		push_error(
			"Could not initialize the bound settlement natural features."
		)
		return

	if city_world != null:
		city_presentation_invalidation_tracker.observed_city_tile_data_version = (
			city_world.tile_data_version
		)
		city_presentation_invalidation_tracker.observed_city_surface_feature_change_version = (
			city_world.city_surface_feature_change_version
		)
		city_world.consume_city_surface_feature_changes()


func store_city_natural_feature_cache() -> void:
	if city_presentation_binding == null:
		return
	settlement_natural_feature_presenter.store_cache(
		city_presentation_binding.generation
	)


func refresh_city_natural_feature_instance_visibility() -> void:
	if city_presentation_binding == null:
		return
	settlement_natural_feature_presenter.set_view_mode(
		city_presentation_binding.generation,
		settlement_ui_controller.view_mode
	)


func rebuild_city_natural_feature_multimeshes() -> void:
	if (
		city_presentation_binding == null
		or not settlement_natural_feature_presenter.rebuild(
			city_presentation_binding.generation,
			session_prepared_city_payload
		)
	):
		push_error(
			"Could not rebuild the bound settlement natural features."
		)


func apply_city_surface_feature_changes(
	changes: Array[Dictionary]
) -> bool:
	return (
		city_presentation_binding != null
		and settlement_natural_feature_presenter.apply_surface_feature_changes(
			city_presentation_binding.generation,
			changes
		)
	)


func should_draw_city_trees() -> bool:
	return (
		city_presentation_binding != null
		and settlement_natural_feature_presenter.should_draw_trees(
			city_presentation_binding.generation
		)
	)


func create_city_render_layers() -> void:
	city_active_workplace_preview_render_layer = CityRenderLayerScript.new()
	city_active_workplace_preview_render_layer.name = (
		"CityActiveWorkplacePreviewRenderLayer"
	)
	city_active_workplace_preview_render_layer.setup(
		Callable(self, "draw_city_active_workplace_preview_layer"),
		"active_workplace_preview",
		Callable(self, "_on_city_render_layer_drawn")
	)
	# Active workplace zones sit above terrain and rocks, but below completed
	# objects and construction blueprints. Keeping them in their own retained
	# layer prevents cursor-following previews from rebuilding static geometry.
	city_active_workplace_preview_render_layer.z_index = -1
	add_child(city_active_workplace_preview_render_layer)

	city_background_render_layer = CityRenderLayerScript.new()
	city_background_render_layer.name = "CityBackgroundRenderLayer"
	city_background_render_layer.setup(
		Callable(self, "draw_city_background_layer"),
		"background",
		Callable(self, "_on_city_render_layer_drawn")
	)
	city_background_render_layer.z_index = 0
	add_child(city_background_render_layer)

	city_citizen_render_layer = CityRenderLayerScript.new()
	city_citizen_render_layer.name = "CityCitizenRenderLayer"
	city_citizen_render_layer.setup(
		Callable(self, "draw_city_citizen_layer"),
		"citizen",
		Callable(self, "_on_city_render_layer_drawn")
	)
	city_citizen_render_layer.z_index = 10
	add_child(city_citizen_render_layer)

	city_interaction_render_layer = CityRenderLayerScript.new()
	city_interaction_render_layer.name = "CityInteractionRenderLayer"
	city_interaction_render_layer.setup(
		Callable(self, "draw_city_interaction_layer"),
		"interaction",
		Callable(self, "_on_city_render_layer_drawn")
	)
	city_interaction_render_layer.z_index = 20
	add_child(city_interaction_render_layer)


func queue_city_active_workplace_preview_layer_redraw() -> void:
	if not session_view_active:
		return
	if city_active_workplace_preview_render_layer != null:
		city_active_workplace_preview_render_layer.request_redraw()


func queue_city_background_layer_redraw() -> void:
	if not session_view_active:
		return
	if city_background_render_layer != null:
		city_background_render_layer.request_redraw()


func queue_city_citizen_layer_redraw() -> void:
	if not session_view_active:
		return
	if city_citizen_render_layer != null:
		city_citizen_render_layer.request_redraw()


func queue_city_interaction_layer_redraw() -> void:
	if not session_view_active:
		return
	if city_interaction_render_layer != null:
		city_interaction_render_layer.request_redraw()


func queue_all_city_render_layers_redraw() -> void:
	queue_city_active_workplace_preview_layer_redraw()
	queue_city_background_layer_redraw()
	queue_city_citizen_layer_redraw()
	queue_city_interaction_layer_redraw()


func _on_city_render_layer_drawn(
	render_layer: CityRenderLayer,
	duration_usec: int
) -> void:
	city_presentation_draw_count += 1
	city_presentation_last_draw_duration_usec = duration_usec
	city_presentation_total_draw_duration_usec += duration_usec
	city_presentation_last_draw_layer = render_layer.layer_name


func draw_city_active_workplace_preview_layer(
	draw_target: CanvasItem
) -> void:
	if city_world == null:
		return

	draw_active_workplace_zone_background(draw_target)


func draw_city_background_layer(draw_target: CanvasItem) -> void:
	if city_world == null:
		return

	# CityTerrainSprite and natural-feature MultiMeshInstance2D nodes retain the
	# static map geometry. This layer redraws only versioned objects and overlays.
	draw_selected_workplace_zone_background(draw_target)
	settlement_infrastructure_presenter.draw_completed_infrastructure(
		draw_target
	)
	city_debug_presentation.draw_background(draw_target)
	settlement_infrastructure_presenter.draw_ground_piles(draw_target)


func draw_city_citizen_layer(draw_target: CanvasItem) -> void:
	if city_world == null:
		return

	city_citizen_movement_presentation.draw_citizens(draw_target)
	draw_selected_city_citizen_highlight(draw_target)


func draw_city_interaction_layer(draw_target: CanvasItem) -> void:
	if city_world == null:
		return

	settlement_command_controller.draw_overlay(
		draw_target,
		hovered_city_tile,
		settlement_natural_feature_presenter.white_texture,
		settlement_natural_feature_presenter.tree_multimesh,
		settlement_natural_feature_presenter.rock_multimesh
	)
	city_debug_presentation.draw_selected_tile_highlight(draw_target)
	draw_selected_city_object_highlight(draw_target)
	draw_selected_city_construction_site_highlight(draw_target)
	city_debug_presentation.draw_city_object_names(draw_target)
	var placement_preview := get_active_city_object_placement_preview()
	settlement_placement_controller.draw_active_object_placement_preview(
		draw_target,
		get_city_tile_under_mouse(),
		workplace_zone_overlay_cache.has_cached_zone(
			placement_preview,
			true,
			city_world
		),
		Callable(
			settlement_infrastructure_presenter,
			"draw_settlement_object_visual"
		)
	)
	draw_hovered_city_tile_highlight(draw_target)
	settlement_placement_controller.draw_road_preview(draw_target)

func draw_selected_workplace_zone_background(
	draw_target: CanvasItem
) -> void:
	if selected_city_object_id == null:
		return

	if int(selected_city_object_id) < 0:
		return

	var city_object: Dictionary = get_city_object_by_id(
		selected_city_object_id
	)

	if not is_city_object_selectable(city_object):
		return

	draw_selected_workplace_resource_zone(
		city_object,
		draw_target
	)


func draw_active_workplace_zone_background(
	draw_target: CanvasItem
) -> void:
	var preview_object := (
		get_active_city_object_placement_preview()
	)

	if preview_object.is_empty():
		return

	draw_workplace_resource_zone_preview(
		preview_object,
		draw_target
	)


func start_city_object_placement(
	object_type: String,
	size_tiles: Vector2i,
	object_owner: String = "player",
	repeat_after_place: bool = false
) -> void:
	if not settlement_placement_controller.start_object_placement(
		object_type,
		size_tiles,
		object_owner,
		repeat_after_place
	):
		return
	active_workplace_preview_refresh_pending = (
		active_city_object_placement_uses_environmental_source()
	)
	queue_city_active_workplace_preview_layer_redraw()
	queue_city_interaction_layer_redraw()

func clear_city_object_placement() -> void:
	settlement_placement_controller.clear_object_placement()
	active_workplace_preview_refresh_pending = false
	queue_city_active_workplace_preview_layer_redraw()
	queue_city_interaction_layer_redraw()


func has_active_city_object_placement() -> bool:
	return settlement_placement_controller.has_active_object_placement()


func active_city_object_placement_uses_environmental_source() -> bool:
	return (
		settlement_placement_controller
		.active_object_placement_uses_environmental_source()
	)


func is_uncommitted_city_placement_preview_active() -> bool:
	return settlement_placement_controller.is_uncommitted_placement_preview_active()


#region Workplace zone painting and cache

func get_active_city_object_placement_preview() -> Dictionary:
	return (
		settlement_placement_controller.get_active_object_placement_preview(
			get_city_tile_under_mouse()
		)
	)

func refresh_active_workplace_zone_preview_cache() -> void:
	if not has_active_city_object_placement():
		return

	var preview_object := (
		get_active_city_object_placement_preview()
	)

	if preview_object.is_empty():
		return

	workplace_zone_overlay_cache.prepare({
		"city_object": preview_object,
		"preview_mode": true,
		"city_world": city_world,
		"city_tile_size": city_tile_size,
	})


func refresh_selected_workplace_zone_cache() -> void:
	if selected_city_object_id < 0:
		return

	var city_object := (
		settlement_selection_controller.get_settlement_object_by_id(
			selected_city_object_id
		)
	)

	if not is_city_object_selectable(city_object):
		return

	workplace_zone_overlay_cache.prepare({
		"city_object": city_object,
		"preview_mode": false,
		"city_world": city_world,
		"city_tile_size": city_tile_size,
	})


func draw_workplace_resource_zone_preview(
	preview_object: Dictionary,
	draw_target: CanvasItem
) -> bool:
	return workplace_zone_overlay_cache.draw_cached({
		"city_object": preview_object,
		"preview_mode": true,
		"city_world": city_world,
		"draw_target": draw_target,
	})


func draw_selected_workplace_resource_zone(
	city_object: Dictionary,
	draw_target: CanvasItem
) -> bool:
	return workplace_zone_overlay_cache.draw_cached({
		"city_object": city_object,
		"preview_mode": false,
		"city_world": city_world,
		"draw_target": draw_target,
	})
#endregion

func draw_selected_city_citizen_highlight(
	draw_target: CanvasItem
) -> void:
	settlement_selection_controller.draw_selected_settlement_citizen_highlight(
		draw_target,
		get_viewport(),
		city_citizen_movement_presentation
	)


func draw_selected_city_object_highlight(
	draw_target: CanvasItem
) -> void:
	settlement_selection_controller.draw_selected_settlement_object_highlight(
		draw_target,
		get_viewport()
	)

func draw_selected_city_construction_site_highlight(
	draw_target: CanvasItem
) -> void:
	settlement_selection_controller.draw_selected_settlement_construction_site_highlight(
		draw_target,
		get_viewport()
	)


func get_city_hover_highlight_tiles(
	tile_position: Vector2i
) -> Array[Vector2i]:
	return settlement_selection_controller.get_hover_highlight_tiles(
		tile_position,
		is_road_placement_active
	)


func draw_hovered_city_tile_highlight(
	draw_target: CanvasItem
) -> void:
	settlement_selection_controller.draw_hovered_settlement_tile_highlight(
		draw_target,
		{
			"has_active_object_placement": has_active_city_object_placement(),
			"is_player_command_mode_active": is_city_player_command_mode_active(),
			"debug_mode_enabled": WorldData.debug_mode_enabled,
			"debug_selected_tile": city_debug_presentation.selected_tile,
			"is_road_placement_active": is_road_placement_active,
		}
	)



func get_city_tile_under_mouse() -> Vector2i:
	return settlement_selection_controller.world_position_to_settlement_tile(
		get_global_mouse_position()
	)


#endregion

#region Debug panel and navigation orchestration

func update_debug_panel_text() -> void:
	city_debug_presentation.refresh(
		_get_city_debug_presentation_values()
	)


func create_debug_panel() -> void:
	if not city_debug_presentation.configure_ui(self, city_tile_size):
		push_error("City debug presentation UI configuration failed.")


func clear_debug_navigation_result() -> void:
	city_debug_presentation.clear_navigation_result()


func request_debug_navigation_path() -> void:
	city_debug_presentation.request_navigation(
		selected_city_citizen_id,
		hovered_city_tile
	)
	update_debug_panel_text()
	queue_city_background_layer_redraw()
	queue_city_interaction_layer_redraw()


func assign_debug_navigation_path_to_selected_citizen() -> void:
	var result := (
		city_debug_presentation
		.execute_assign_navigation_path_to_selected_citizen(
			city_presentation_binding,
			selected_city_citizen_id
		)
	)
	print(str(result.get("message", "Movement rejected.")))
	if not bool(result.get("success", false)):
		return

	city_citizen_movement_presentation.track_mover(
		selected_city_citizen_id
	)

	update_selected_entity_panel()
	update_debug_panel_text()

func get_citizen_debug_list_text() -> String:
	return city_debug_presentation.citizen_debug_panel.get_debug_list_text()

func toggle_debug_mode() -> void:
	var is_enabled := city_debug_presentation.toggle_enabled()
	queue_city_background_layer_redraw()
	queue_city_interaction_layer_redraw()
	if is_enabled:
		print("Debug mode: ON")
	else:
		print("Debug mode: OFF")


func _get_city_debug_presentation_values() -> Dictionary:
	return {
		"settlement_context": bound_settlement_context,
		"city_world": city_world,
		"city_seed": city_seed,
		"city_view_name": MapVisuals.get_view_mode_name(
			settlement_ui_controller.view_mode
		),
		"hovered_city_tile": hovered_city_tile,
		"selected_city_entity_kind": selected_city_entity_kind,
		"selected_city_entity_id": selected_city_entity_id,
		"selected_city_object_id": selected_city_object_id,
	}


#endregion
