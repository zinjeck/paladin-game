extends Node2D
class_name CityRenderer

# File responsibility: City-scene input, UI coordination, render-layer orchestration,
# and high-level drawing. Specialized caches and diagnostic text live with their
# dedicated presentation owners.

const MapTextureCacheStateScript = preload(
	"res://scripts/map/visuals/MapTextureCacheState.gd"
)
const MapCameraSessionStateScript = preload(
	"res://scripts/map/MapCameraSessionState.gd"
)
const CityStateValidator = preload(
	"res://scripts/city/simulation/CityStateValidator.gd"
)
const CityNavigationSystemScript = preload(
	"res://scripts/city/simulation/systems/CityNavigationSystem.gd"
)
const CityCitizenMovementPresentationScript = preload(
	"res://scripts/citizens/rendering/CityCitizenMovementPresentation.gd"
)
const CitizenDebugPanelScript = preload(
	"res://scripts/ui/debug/CitizenDebugPanel.gd"
)
const CityInformationPanelScript = preload(
	"res://scripts/ui/city/CityInformationPanel.gd"
)
const CityDebugPresentationScript = preload(
	"res://scripts/city/rendering/CityDebugPresentation.gd"
)
const CityRenderLayerScript = preload(
	"res://scripts/city/rendering/CityRenderLayer.gd"
)
const CityWorkplaceZoneOverlayCacheScript = preload(
	"res://scripts/city/rendering/CityWorkplaceZoneOverlayCache.gd"
)
const CityWorldGeneratorScript = preload(
	"res://scripts/city/generation/CityWorldGenerator.gd"
)
const CityConstructionSystemScript = preload(
	"res://scripts/city/simulation/systems/CityConstructionSystem.gd"
)
const CityWorkSystemScript = preload(
	"res://scripts/city/simulation/systems/CityWorkSystem.gd"
)
@export_file("*.tscn") var world_scene_path: String = ""
@export var local_tiles_per_world_tile: int = 64
@export var city_tile_size: int = 2

var city_world: WorldData
var city_seed: int = 0
var camera: Camera2D
var observed_city_camera_zoom: Vector2 = Vector2.ZERO
var ui_layer: CanvasLayer
var ui_root: Control
var city_information_ui = CityInformationPanelScript.new()

var back_button: Button
var resource_bar: Control
var resource_boxes: Array[Panel] = []
var city_view_mode: int = MapVisuals.ViewMode.BIOME
var city_maps_button: Button
var city_map_mode_buttons: Array[Button] = []
var city_map_menu_open: bool = false
var resource_icons: Array[ColorRect] = []
var resource_amount_labels: Array[Label] = []
var build_option_button: Button
var build_option_icon: Panel
var city_terrain_texture: ImageTexture
var city_texture_cache := MapTextureCache.new()
var city_initialization_duration_usec: int = 0
var city_generation_duration_usec: int = 0
var city_map_texture_setup_duration_usec: int = 0
var city_natural_feature_setup_duration_usec: int = 0
var city_map_texture_cache_reused_on_entry: bool = false
var city_natural_feature_cache_reused_on_entry: bool = false
var city_background_render_layer: CityRenderLayer
var city_citizen_render_layer: CityRenderLayer
var city_interaction_render_layer: CityRenderLayer
var debug_panel_ui: DebugPanel
var debug_refresh_pending: bool = false
var debug_panel_position: Vector2 = Vector2.ZERO
var debug_panel_padding: Vector2 = Vector2(12.0, 10.0)
var debug_panel_min_size: Vector2 = Vector2(430.0, 170.0)
var debug_navigation_path: Array = []
var debug_navigation_status: String = (
	CityNavigationSystemScript.PATH_STATUS_NOT_REQUESTED
)
var debug_navigation_start_tile: Vector2i = (
	WorldData.INVALID_CITY_TILE_POSITION
)
var debug_navigation_destination_tile: Vector2i = (
	WorldData.INVALID_CITY_TILE_POSITION
)
var debug_navigation_candidate_count: int = 0
var debug_navigation_expanded_nodes: int = 0
var debug_navigation_path_cost: int = 0
var debug_navigation_duration_usec: int = 0
var debug_selected_city_tile: Vector2i = (
	WorldData.INVALID_CITY_TILE_POSITION
)
var citizen_debug_ui = CitizenDebugPanelScript.new()
const DEFAULT_CITY_OBJECT_FRAME_COLOR: Color = Color(0.32, 0.30, 0.24, 0.95)
const DEFAULT_CITY_OBJECT_FILL_COLOR: Color = Color(0.86, 0.84, 0.76, 0.55)
const DEFAULT_CITY_OBJECT_FRAME_THICKNESS: float = 0.35
var is_road_placement_active: bool = false
var is_road_dragging: bool = false
var road_preview_tiles: Array = []
var road_preview_lookup: Dictionary = {}
var bottom_button_one: Button
var bottom_button_two: Button
var bottom_button_three: Button
var bottom_button_four: Button
var bottom_button_five: Button
var bottom_button_six: Button
var city_command_cancel_task_button: Button
var city_command_chop_trees_button: Button
var city_command_collect_rocks_button: Button
var city_command_cancel_cursor_icon: Label
var city_command_menu_open: bool = false
var is_city_player_command_cancel_mode_active: bool = false
var active_city_player_command_type: String = (
	WorldData.CITY_PLAYER_COMMAND_TYPE_NONE
)
var is_city_player_command_dragging: bool = false
var city_player_command_drag_removing: bool = false
var city_player_command_drag_start_screen: Vector2 = Vector2.ZERO
var city_player_command_drag_current_screen: Vector2 = Vector2.ZERO
var city_player_command_drag_start_world: Vector2 = Vector2.ZERO
var city_player_command_drag_current_world: Vector2 = Vector2.ZERO
var city_player_command_drag_preview_tiles: Array[Vector2i] = []
var city_player_command_selection_box_panel: Panel
var road_drag_start_tile: Vector2i = Vector2i(-1, -1)
var road_drag_current_tile: Vector2i = Vector2i(-1, -1)
var city_object_option_buttons: Dictionary = {}
var city_object_option_icons: Dictionary = {}
var road_cursor_icon: Panel
var hovered_city_tile: Vector2i = Vector2i(-1, -1)
const CITY_SELECTION_KIND_NONE := "none"
const CITY_SELECTION_KIND_OBJECT := "object"
const CITY_SELECTION_KIND_CITIZEN := "citizen"
const CITY_SELECTION_KIND_CONSTRUCTION_SITE := "construction_site"

var selected_city_entity_kind: String = (
	CITY_SELECTION_KIND_NONE
)
var selected_city_entity_id: int = -1

# Compatibility view for existing object-only systems.
# This is derived state, not a second selection owner.
var selected_city_object_id: int:
	get:
		if (
			selected_city_entity_kind
			== CITY_SELECTION_KIND_OBJECT
		):
			return selected_city_entity_id

		return -1

var selected_city_citizen_id: int:
	get:
		if (
			selected_city_entity_kind
			== CITY_SELECTION_KIND_CITIZEN
		):
			return selected_city_entity_id

		return -1

var selected_city_construction_site_id: int:
	get:
		if (
			selected_city_entity_kind
			== CITY_SELECTION_KIND_CONSTRUCTION_SITE
		):
			return selected_city_entity_id

		return -1

var observed_city_object_version: int = -1
var observed_city_container_version: int = -1
var observed_city_public_storage_version: int = -1
var observed_city_citizen_version: int = -1
var observed_city_citizen_spatial_version: int = -1
var observed_city_citizen_movement_version: int = -1
var synchronized_city_citizen_movement_version: int = -1
var observed_city_citizen_task_version: int = -1
var observed_city_ground_pile_version: int = -1
var observed_city_player_command_version: int = -1
var observed_city_haul_reservation_version: int = -1
var observed_city_construction_version: int = -1
var city_citizen_movement_presentation = (
	CityCitizenMovementPresentationScript.new()
)
var city_citizen_draw_buffer: Array[Dictionary] = []
var city_citizen_rect_draw_buffer: Array[Rect2] = []
var city_natural_feature_white_texture: ImageTexture
var city_tree_mesh: ArrayMesh
var city_rock_mesh: ArrayMesh
static var shared_city_natural_feature_white_texture: ImageTexture
static var shared_city_tree_mesh: ArrayMesh
static var shared_city_rock_mesh: ArrayMesh
static var cached_city_natural_feature_source_instance_id: int = 0
static var cached_city_natural_feature_tile_data_version: int = -1
static var cached_city_natural_feature_change_version: int = -1
static var cached_city_natural_feature_seed: int = 0
static var cached_city_natural_feature_tile_size: int = 0
static var cached_city_tree_multimesh: MultiMesh
static var cached_city_rock_multimesh: MultiMesh
static var cached_city_tree_index_by_tile: Dictionary = {}
static var cached_city_tree_tile_by_index: Array[Vector2i] = []
static var cached_city_rock_index_by_tile: Dictionary = {}
static var cached_city_rock_tile_by_index: Array[Vector2i] = []
var city_tree_multimesh: MultiMesh
var city_rock_multimesh: MultiMesh
var city_tree_multimesh_index_by_tile: Dictionary = {}
var city_tree_multimesh_tile_by_index: Array[Vector2i] = []
var city_rock_multimesh_index_by_tile: Dictionary = {}
var city_rock_multimesh_tile_by_index: Array[Vector2i] = []
var observed_city_assignment_version: int = -1
var observed_city_workplace_version: int = -1
var observed_city_tile_data_version: int = -1
var observed_city_surface_feature_change_version: int = -1
var workplace_zone_overlay_cache = (
	CityWorkplaceZoneOverlayCacheScript.new()
)
var active_city_object_placement: Dictionary = {}
var object_info_panel: Panel
var object_info_title_label: Label
var object_info_body_label: Label
var object_info_storage_title_label: Label
var object_info_storage_icons: Array[ColorRect] = []
var object_info_storage_amount_labels: Array[Label] = []
var workplace_details_button: Button
var workplace_details_panel: Panel
var workplace_details_title_label: Label
var workplace_details_body_label: Label
var workplace_details_open: bool = false
var workplace_details_object_id: int = -1
var workplace_details_button_body_line_count: int = 0
var construction_site_info_panel: Panel
var construction_site_info_title_label: Label
var construction_site_info_body_label: Label
var object_selection_box_panel: Panel
var is_object_selection_dragging: bool = false
var object_selection_drag_start_screen: Vector2 = Vector2.ZERO
var object_selection_drag_current_screen: Vector2 = Vector2.ZERO
var object_selection_drag_start_world: Vector2 = Vector2.ZERO
var object_selection_drag_current_world: Vector2 = Vector2.ZERO
const DEBUG_CITY_OBJECT_NAME_TARGET_FONT_SIZE: int = 11
const DEBUG_CITY_OBJECT_NAME_MIN_FONT_SIZE: int = 6
const DEBUG_CITY_OBJECT_NAME_TEXT_COLOR: Color = Color(0.82, 0.94, 1.0, 1.0)
const DEBUG_CITY_OBJECT_NAME_SHADOW_COLOR: Color = Color(0.0, 0.0, 0.0, 0.85)
const DEBUG_CITY_OBJECT_NAME_BACKGROUND_COLOR: Color = Color(0.0, 0.0, 0.0, 0.55)
const DEBUG_CITY_OBJECT_NAME_PADDING: Vector2 = Vector2(4.0, 2.0)
const DEBUG_CITY_OBJECT_NAME_MAX_WIDTH_RATIO: float = 0.82
const DEBUG_CITY_OBJECT_NAME_MAX_HEIGHT_RATIO: float = 0.45
const OBJECT_SELECTION_DRAG_THRESHOLD_PIXELS: float = 4.0
const CONSTRUCTION_SITE_INFO_PANEL_WIDTH: float = 252.0
const CONSTRUCTION_SITE_INFO_PANEL_HEADER_HEIGHT: float = 60.0
const CONSTRUCTION_SITE_INFO_PANEL_RESOURCE_ROW_HEIGHT: float = 26.0
const CONSTRUCTION_SITE_INFO_PANEL_BOTTOM_PADDING: float = 14.0
const CONSTRUCTION_SITE_INFO_PANEL_SIDE_GAP: float = 10.0
const SELECTED_OBJECT_BORDER_TILE_FRACTION: float = 0.02
const CURSOR_LOOK_FILL_COLOR: Color = Color(1.0, 1.0, 1.0, 0.08)
const CURSOR_LOOK_BORDER_COLOR: Color = Color(1.0, 1.0, 1.0, 0.58)
const CURSOR_LOOK_GRID_COLOR: Color = Color(1.0, 1.0, 1.0, 0.22)
const SELECTED_OBJECT_HIGHLIGHT_COLOR: Color = Color(0.0, 0.85, 1.0, 1.0)
const CITY_CITIZEN_MARKER_COLOR: Color = (
	Color(0.824, 0.706, 0.549, 1.0)
)
const CITY_CITIZEN_MARKER_TILE_SCALE: float = 0.5
const CITY_HAUL_CARGO_MARKER_CITIZEN_SCALE: float = 0.5
const CITY_GROUND_PILE_MARKER_TILE_SCALE: float = 0.16
const CITY_CONSTRUCTION_CLEARING_COLOR := Color(1.0, 0.48, 0.08, 0.9)
const CITY_CONSTRUCTION_GATHERING_COLOR := Color(0.12, 0.78, 1.0, 0.9)
const CITY_CONSTRUCTION_LABOR_COLOR := Color(0.25, 1.0, 0.48, 0.9)
const CITY_CONSTRUCTION_BLUEPRINT_FILL := Color(0.2, 0.65, 1.0, 0.18)
const CITY_PLAYER_COMMAND_DARKEN_COLOR := Color(0.0, 0.0, 0.0, 0.72)
const CITY_PLAYER_COMMAND_HIGHLIGHT_FILL := Color(1.0, 0.78, 0.12, 0.28)
const CITY_PLAYER_COMMAND_HIGHLIGHT_BORDER := Color(1.0, 0.88, 0.28, 0.95)
const CITY_PLAYER_COMMAND_CLAIMED_BORDER := Color(0.2, 1.0, 0.65, 1.0)
const CITY_PLAYER_COMMAND_PREVIEW_FILL := Color(0.0, 0.85, 1.0, 0.24)
const CITY_PLAYER_COMMAND_PREVIEW_BORDER := Color(0.2, 0.95, 1.0, 0.95)
const CITY_PLAYER_COMMAND_REMOVE_PREVIEW_FILL := Color(1.0, 0.16, 0.16, 0.24)
const CITY_PLAYER_COMMAND_REMOVE_PREVIEW_BORDER := Color(1.0, 0.3, 0.3, 0.95)
const CITY_TREE_CANOPY_TILE_SCALE: float = 1.30
const CITY_TREE_MIN_SCALE_VARIATION: float = 0.92
const CITY_TREE_MAX_SCALE_VARIATION: float = 1.08
const CITY_TREE_DARK_COLOR := Color(0.12, 0.43, 0.16, 1.0)
const CITY_TREE_LIGHT_COLOR := Color(0.30, 0.66, 0.28, 1.0)
const CITY_TAIGA_TREE_DARK_COLOR := Color(0.12, 0.29, 0.24, 1.0)
const CITY_TAIGA_TREE_LIGHT_COLOR := Color(0.29, 0.47, 0.36, 1.0)
const CITY_JUNGLE_TREE_DARK_COLOR := Color(0.055, 0.27, 0.10, 1.0)
const CITY_JUNGLE_TREE_LIGHT_COLOR := Color(0.16, 0.49, 0.18, 1.0)
const CITY_ROCK_MARKER_TILE_SCALE: float = 0.28
const CITY_ROCK_MAX_CENTER_OFFSET_TILES: float = 0.30
const CITY_TREE_ROTATION_SALT: int = 401
const CITY_TREE_SCALE_SALT: int = 409
const CITY_TREE_COLOR_SALT: int = 419
const CITY_ROCK_OFFSET_X_SALT: int = 431
const CITY_ROCK_OFFSET_Y_SALT: int = 433
const DEBUG_NAVIGATION_PATH_FILL_COLOR: Color = (
	Color(1.0, 0.82, 0.0, 0.34)
)
const DEBUG_NAVIGATION_PATH_LINE_COLOR: Color = (
	Color(1.0, 0.95, 0.20, 0.92)
)
const DEBUG_SELECTED_TILE_HIGHLIGHT_COLOR: Color = (
	Color(0.0, 1.0, 1.0, 1.0)
)

#region Lifecycle and input

func _ready() -> void:
	var initialization_start_usec := Time.get_ticks_usec()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	RenderingServer.set_default_clear_color(Color.BLACK)

	setup_city_texture_cache()
	var generation_start_usec := Time.get_ticks_usec()
	generate_city_world()
	city_generation_duration_usec = (
		Time.get_ticks_usec() - generation_start_usec
	)
	clear_invalid_old_city_foundation_state()
	ensure_city_foundation_object_exists()
	WorldData.ensure_city_citizen_spatial_state(
		city_world
	)
	WorldData.ensure_city_citizen_demographic_state()
	WorldData.ensure_city_citizen_need_state()
	WorldData.ensure_city_citizen_task_state()
	WorldData.ensure_city_citizen_movement_state()
	city_citizen_movement_presentation.initialize()
	synchronized_city_citizen_movement_version = (
		WorldData.city_citizen_movement_version
	)
	# The presentation initialized from current authority. Discard any movement
	# trace left by simulation ticks that ran while this renderer was inactive.
	WorldData.clear_city_citizen_movement_visual_events()
	var natural_feature_start_usec := Time.get_ticks_usec()
	setup_city_natural_feature_rendering()
	city_natural_feature_setup_duration_usec = (
		Time.get_ticks_usec() - natural_feature_start_usec
	)
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
	SimulationClock.resume_simulation()
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


func _process(delta: float) -> void:
	_process_texture_cache_and_camera()
	var city_hover_tile_changed := _update_city_hover_state()
	_update_active_city_interaction_state()
	var change_flags := _collect_city_change_flags()
	_synchronize_city_citizen_movement(change_flags)

	if city_citizen_movement_presentation.update(delta):
		queue_city_citizen_layer_redraw()

	_apply_city_change_refreshes(
		change_flags,
		city_hover_tile_changed
	)


func _process_texture_cache_and_camera() -> void:
	if city_texture_cache != null:
		var warmup_was_running := city_texture_cache.warmup_running
		city_texture_cache.process_warmup()

		if warmup_was_running and not city_texture_cache.warmup_running:
			update_city_map_mode_button_visuals()

	if (
		camera != null
		and camera.zoom != observed_city_camera_zoom
	):
		observed_city_camera_zoom = camera.zoom
		queue_city_citizen_layer_redraw()
		queue_city_interaction_layer_redraw()


func _update_city_hover_state() -> bool:
	var current_hovered_tile := get_city_tile_under_mouse()
	var city_hover_tile_changed := (
		current_hovered_tile != hovered_city_tile
	)

	if not city_hover_tile_changed:
		return false

	hovered_city_tile = current_hovered_tile
	update_debug_panel_text()

	var hover_visual_can_change := (
		not has_selected_city_entity()
		or has_active_city_object_placement()
		or is_road_placement_active
		or is_road_dragging
		or is_object_selection_dragging
		or is_city_player_command_tool_active()
		or is_city_player_command_dragging
	)

	if hover_visual_can_change:
		queue_city_interaction_layer_redraw()

	return true


func _update_active_city_interaction_state() -> void:
	if is_road_placement_active:
		update_road_cursor_icon_position()

	if is_city_player_command_cancel_mode_active:
		update_city_player_command_cancel_cursor_icon_position()

	if is_road_dragging:
		update_road_drag_selection()

	if selected_city_construction_site_id > 0:
		update_construction_site_info_panel_screen_position()


func _collect_city_change_flags() -> Dictionary:
	var change_flags := {
		"city_objects_changed": false,
		"city_containers_changed": false,
		"public_storage_changed": false,
		"city_citizens_changed": false,
		"city_citizen_spatial_changed": false,
		"city_citizen_movement_changed": false,
		"city_citizen_task_changed": false,
		"city_ground_piles_changed": false,
		"city_player_commands_changed": false,
		"city_haul_reservations_changed": false,
		"city_construction_changed": false,
		"city_assignments_changed": false,
		"city_workplaces_changed": false,
		"city_tile_data_changed": false,
		"city_surface_features_changed": false,
	}

	_collect_city_world_change_flags(change_flags)
	_collect_world_data_change_flags(change_flags)
	return change_flags


func _collect_city_world_change_flags(
	change_flags: Dictionary
) -> void:
	if city_world == null:
		return

	if observed_city_tile_data_version != city_world.tile_data_version:
		observed_city_tile_data_version = city_world.tile_data_version
		change_flags["city_tile_data_changed"] = true
		workplace_zone_overlay_cache.invalidate_all()
		rebuild_city_natural_feature_multimeshes()
		observed_city_surface_feature_change_version = (
			city_world.city_surface_feature_change_version
		)
		city_world.consume_city_surface_feature_changes()
		return

	if (
		observed_city_surface_feature_change_version
		== city_world.city_surface_feature_change_version
	):
		return

	observed_city_surface_feature_change_version = (
		city_world.city_surface_feature_change_version
	)
	var surface_feature_changes := (
		city_world.consume_city_surface_feature_changes()
	)

	if surface_feature_changes.is_empty():
		return

	change_flags["city_surface_features_changed"] = true

	if not apply_city_surface_feature_changes(surface_feature_changes):
		rebuild_city_natural_feature_multimeshes()
	else:
		store_city_natural_feature_cache()


func _collect_world_data_change_flags(
	change_flags: Dictionary
) -> void:
	if observed_city_object_version != WorldData.city_object_version:
		observed_city_object_version = WorldData.city_object_version
		change_flags["city_objects_changed"] = true

	if observed_city_container_version != WorldData.city_container_version:
		observed_city_container_version = WorldData.city_container_version
		change_flags["city_containers_changed"] = true

	if (
		observed_city_public_storage_version
		!= WorldData.city_public_storage_version
	):
		observed_city_public_storage_version = (
			WorldData.city_public_storage_version
		)
		change_flags["public_storage_changed"] = true

	if observed_city_citizen_version != WorldData.city_citizen_version:
		observed_city_citizen_version = WorldData.city_citizen_version
		change_flags["city_citizens_changed"] = true

	if (
		observed_city_citizen_spatial_version
		!= WorldData.city_citizen_spatial_version
	):
		observed_city_citizen_spatial_version = (
			WorldData.city_citizen_spatial_version
		)
		change_flags["city_citizen_spatial_changed"] = true

	if (
		observed_city_citizen_movement_version
		!= WorldData.city_citizen_movement_version
	):
		observed_city_citizen_movement_version = (
			WorldData.city_citizen_movement_version
		)
		change_flags["city_citizen_movement_changed"] = true

	if (
		observed_city_citizen_task_version
		!= WorldData.city_citizen_task_version
	):
		observed_city_citizen_task_version = (
			WorldData.city_citizen_task_version
		)
		change_flags["city_citizen_task_changed"] = true

	if (
		observed_city_ground_pile_version
		!= WorldData.city_ground_pile_version
	):
		observed_city_ground_pile_version = (
			WorldData.city_ground_pile_version
		)
		change_flags["city_ground_piles_changed"] = true

	if (
		observed_city_player_command_version
		!= WorldData.city_player_command_version
	):
		observed_city_player_command_version = (
			WorldData.city_player_command_version
		)
		change_flags["city_player_commands_changed"] = true

	if (
		observed_city_haul_reservation_version
		!= WorldData.city_haul_reservation_version
	):
		observed_city_haul_reservation_version = (
			WorldData.city_haul_reservation_version
		)
		change_flags["city_haul_reservations_changed"] = true

	if (
		observed_city_construction_version
		!= WorldData.city_construction_version
	):
		observed_city_construction_version = (
			WorldData.city_construction_version
		)
		change_flags["city_construction_changed"] = true

	if (
		observed_city_assignment_version
		!= WorldData.city_assignment_version
	):
		observed_city_assignment_version = (
			WorldData.city_assignment_version
		)
		change_flags["city_assignments_changed"] = true

	if (
		observed_city_workplace_version
		!= WorldData.city_workplace_version
	):
		observed_city_workplace_version = (
			WorldData.city_workplace_version
		)
		change_flags["city_workplaces_changed"] = true


func _synchronize_city_citizen_movement(
	change_flags: Dictionary
) -> void:
	var movement_changed := bool(
		change_flags.get("city_citizen_movement_changed", false)
	)

	if movement_changed:
		if (
			synchronized_city_citizen_movement_version
			!= observed_city_citizen_movement_version
		):
			# Movement snapshots include partial progress even when the citizen
			# has not completed its current cardinal or diagonal tile step.
			city_citizen_movement_presentation.synchronize(true)
			city_citizen_movement_presentation.refresh_mover_tracking()
			synchronized_city_citizen_movement_version = (
				observed_city_citizen_movement_version
			)
		return

	if (
		bool(change_flags.get("city_citizens_changed", false))
		or bool(
			change_flags.get(
				"city_citizen_spatial_changed",
				false
			)
		)
	):
		# Non-movement position edits are teleports. Refresh any tracked mover
		# without animating from a stale tile.
		city_citizen_movement_presentation.synchronize(false)


func _apply_city_change_refreshes(
	change_flags: Dictionary,
	city_hover_tile_changed: bool
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

	if (
		has_active_city_object_placement()
		and (
			city_hover_tile_changed
			or city_tile_data_changed
		)
	):
		refresh_active_workplace_zone_preview_cache()
		queue_city_background_layer_redraw()

	if (
		has_selected_city_entity()
		and (
			city_objects_changed
			or city_tile_data_changed
		)
	):
		refresh_selected_workplace_zone_cache()

	if city_containers_changed or public_storage_changed:
		update_resource_bar_values()

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
		debug_refresh_pending
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
		debug_refresh_pending = false

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
			if city_command_menu_open:
				close_city_player_command_menu()
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

			var debug_resource := get_debug_stockpile_resource_for_key(key_event)

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
			deactivate_city_player_command_tool()
			get_viewport().set_input_as_handled()
			return

		if (
			event.pressed
			and event.button_index == MOUSE_BUTTON_RIGHT
			and city_command_menu_open
		):
			close_city_player_command_menu()
			get_viewport().set_input_as_handled()
			return

		if event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			if is_road_placement_active:
				cancel_road_placement()
				close_build_menu()
				get_viewport().set_input_as_handled()
				return

			if has_active_city_object_placement():
				cancel_active_city_object_placement()
				close_all_city_object_menus()
				get_viewport().set_input_as_handled()
				return

			if selected_city_construction_site_id > 0:
				clear_selected_city_entity()
				get_viewport().set_input_as_handled()
				return

			if city_map_menu_open:
				close_city_map_menu()
				get_viewport().set_input_as_handled()
				return

			if build_option_button != null and build_option_button.visible:
				close_build_menu()
				get_viewport().set_input_as_handled()
				return

			if has_open_city_object_menu():
				close_all_city_object_menus()
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
					is_city_player_command_cancel_mode_active
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
		if is_city_player_command_dragging:
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
	city_information_ui.refresh_time()

	var movement_visual_changed := (
		city_citizen_movement_presentation.synchronize_committed_tick(
			WorldData.take_city_citizen_movement_visual_events(
				SimulationClock.tick_index
			)
		)
	)

	# This post-tick synchronization also captures work, haul, and return-home
	# routes assigned after the movement system, before another batched tick can
	# advance or complete them.
	city_citizen_movement_presentation.synchronize(true)
	city_citizen_movement_presentation.refresh_mover_tracking()
	synchronized_city_citizen_movement_version = (
		WorldData.city_citizen_movement_version
	)

	if movement_visual_changed:
		queue_city_citizen_layer_redraw()

	# Coalesce the clock update with version-driven debug refreshes in _process.
	# This prevents the full validator/debug provider from running twice for
	# one simulation tick.
	debug_refresh_pending = true

func get_debug_stockpile_resource_for_key(key_event: InputEventKey) -> String:
	if key_event.keycode == KEY_H or key_event.physical_keycode == KEY_H:
		return WorldData.RESOURCE_FISH

	if key_event.keycode == KEY_J or key_event.physical_keycode == KEY_J:
		return WorldData.RESOURCE_COAL

	if key_event.keycode == KEY_K or key_event.physical_keycode == KEY_K:
		return WorldData.RESOURCE_IRON

	if key_event.keycode == KEY_L or key_event.physical_keycode == KEY_L:
		return WorldData.RESOURCE_GOLD

	return ""


func add_debug_resource_to_selected_stockpile(resource: String, amount_delta: int) -> void:
	if not WorldData.debug_mode_enabled:
		return

	if selected_city_object_id < 0:
		print("Debug storage add blocked: select a public storage object first.")
		return

	var city_object := get_city_object_by_id(selected_city_object_id)

	if city_object.is_empty():
		print("Debug storage add blocked: selected object not found.")
		return

	if not WorldData.city_object_counts_as_public_city_storage(city_object):
		print("Debug storage add blocked: selected object is not public city storage.")
		return

	if not WorldData.can_city_object_store_resource(city_object, resource):
		print("Debug storage add blocked: selected storage cannot store resource: ", resource)
		return

	var accepted_amount := WorldData.add_resource_to_city_object_storage(
		selected_city_object_id,
		resource,
		amount_delta
	)

	if accepted_amount <= 0:
		print("Debug storage add blocked: selected storage is full for resource: ", resource)
		return

	update_resource_bar_values()
	update_selected_entity_panel()
	update_debug_panel_text()

	print(
		"Debug added +",
		accepted_amount,
		" ",
		resource,
		" to public storage object #",
		selected_city_object_id
	)

#endregion

#region City generation

func generate_city_world() -> void:
	if WorldData.has_active_city_save():
		city_world = WorldData.official_city_world
		city_seed = WorldData.official_city_seed
		print("Loaded existing city world.")
		return

	if not WorldData.has_city_start_region():
		push_error("No selected world region was stored before entering the city screen.")
		return

	city_seed = CityWorldGeneratorScript.calculate_city_seed()

	var city_world_generator = CityWorldGeneratorScript.new()
	city_world = city_world_generator.generate_city_world(
		local_tiles_per_world_tile,
		city_seed
	)

	WorldData.store_city_world_save(city_world, city_seed)
	print("Stored official city world.")

#endregion

#region Camera

func create_city_camera() -> void:
	if city_world == null:
		return

	camera = StrategyCamera2D.new()
	camera.max_zoom = 80.0
	camera.zoom_speed = 0.10

	add_child(camera)

	camera.configure_for_map(
		city_world.width,
		city_world.height,
		city_tile_size,
		not MapCameraSessionStateScript.has_city_camera_state
	)

	if MapCameraSessionStateScript.has_city_camera_state:
		camera.position = MapCameraSessionStateScript.city_camera_position
		camera.zoom = MapCameraSessionStateScript.city_camera_zoom
		camera.clamp_camera_to_map_bounds()

	camera.make_current()
	observed_city_camera_zoom = camera.zoom

func store_current_city_camera_state() -> void:
	if camera == null:
		return

	MapCameraSessionStateScript.store_city_camera(
		camera.position,
		camera.zoom
	)

#endregion

#region General UI, resource bar, map modes, and object panels

func create_city_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 100
	add_child(ui_layer)

	ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(ui_root)

	create_city_information_panel()
	create_bottom_city_buttons()
	create_city_object_option_button(WorldData.CITY_OBJECT_CITY_CENTER)
	create_build_option_button()
	create_city_object_option_button(WorldData.CITY_OBJECT_HOUSE)
	create_city_object_option_button(WorldData.CITY_OBJECT_STOCKPILE)
	create_city_object_option_button(WorldData.CITY_OBJECT_FISHING_GROUNDS)
	create_city_player_command_menu()
	create_resource_bar()
	create_city_maps_menu()
	create_object_info_panel()
	create_construction_site_info_panel()
	create_object_selection_box_visual()
	create_city_player_command_selection_box_visual()
	create_back_button()
	create_road_cursor_icon()
	create_city_player_command_cancel_cursor_icon()

	get_viewport().size_changed.connect(update_city_ui_layout)
	update_city_ui_layout()
	update_resource_bar_values()
	update_city_object_button_states()
	update_build_button_state()


func create_city_information_panel() -> void:
	city_information_ui.setup(ui_root)


func create_road_cursor_icon() -> void:
	road_cursor_icon = Panel.new()
	road_cursor_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	road_cursor_icon.visible = false

	var visual_style := get_city_object_visual_style(
		WorldData.CITY_OBJECT_ROAD
	)
	var road_style := create_flat_ui_style(
		visual_style.get("fill_color", Color(0.56, 0.25, 0.10, 0.96)),
		visual_style.get("frame_color", Color(0.29, 0.11, 0.045, 1.0)),
		1
	)

	road_cursor_icon.add_theme_stylebox_override("panel", road_style)
	ui_root.add_child(road_cursor_icon)

func update_road_cursor_icon_position() -> void:
	if road_cursor_icon == null:
		return

	var icon_size := Vector2(12.0, 12.0)
	var mouse_position := get_viewport().get_mouse_position()

	road_cursor_icon.size = icon_size
	road_cursor_icon.position = mouse_position + Vector2(10.0, 10.0)
	road_cursor_icon.move_to_front()


func create_city_player_command_cancel_cursor_icon() -> void:
	city_command_cancel_cursor_icon = Label.new()
	city_command_cancel_cursor_icon.text = "X"
	city_command_cancel_cursor_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	city_command_cancel_cursor_icon.visible = false
	city_command_cancel_cursor_icon.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	city_command_cancel_cursor_icon.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)
	city_command_cancel_cursor_icon.add_theme_font_size_override(
		"font_size",
		18
	)
	city_command_cancel_cursor_icon.add_theme_color_override(
		"font_color",
		Color(1.0, 0.12, 0.12, 1.0)
	)
	city_command_cancel_cursor_icon.add_theme_color_override(
		"font_outline_color",
		Color(0.15, 0.0, 0.0, 1.0)
	)
	city_command_cancel_cursor_icon.add_theme_constant_override(
		"outline_size",
		2
	)
	ui_root.add_child(city_command_cancel_cursor_icon)


func update_city_player_command_cancel_cursor_icon_position() -> void:
	if city_command_cancel_cursor_icon == null:
		return

	var icon_size := Vector2(18.0, 18.0)
	var mouse_position := get_viewport().get_mouse_position()

	city_command_cancel_cursor_icon.size = icon_size
	city_command_cancel_cursor_icon.position = (
		mouse_position + Vector2(10.0, 8.0)
	)
	city_command_cancel_cursor_icon.move_to_front()

func set_road_option_selected(is_selected: bool) -> void:
	if build_option_icon == null:
		return

	var visual_style := get_city_object_visual_style(
		WorldData.CITY_OBJECT_ROAD
	)
	var fill_color: Color = visual_style.get(
		"fill_color",
		Color(0.56, 0.25, 0.10, 0.96)
	)
	var border_color: Color = visual_style.get(
		"frame_color",
		Color(0.29, 0.11, 0.045, 1.0)
	)

	if is_selected:
		fill_color = fill_color.darkened(0.22)
		border_color = Color(0.95, 0.95, 0.95, 1.0)

	var icon_style := create_flat_ui_style(
		fill_color,
		border_color,
		1
	)

	build_option_icon.add_theme_stylebox_override("panel", icon_style)

func update_build_button_state() -> void:
	var can_build := WorldData.can_build_in_city()

	if bottom_button_two != null:
		bottom_button_two.disabled = not can_build
		bottom_button_two.text = "2"

	if build_option_button != null:
		build_option_button.disabled = not can_build

		if not can_build:
			build_option_button.visible = false


func is_placing_city_object_type(object_type: String) -> bool:
	if not has_active_city_object_placement():
		return false

	return str(active_city_object_placement.get("type", "")) == object_type

func create_bottom_city_buttons() -> void:
	bottom_button_one = Button.new()
	bottom_button_one.text = "1"
	bottom_button_one.focus_mode = Control.FOCUS_NONE
	bottom_button_one.custom_minimum_size = Vector2(58.0, 58.0)
	bottom_button_one.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(bottom_button_one)
	bottom_button_one.pressed.connect(on_city_object_menu_button_pressed.bind(WorldData.CITY_OBJECT_CITY_CENTER))

	bottom_button_two = Button.new()
	bottom_button_two.text = "2"
	bottom_button_two.focus_mode = Control.FOCUS_NONE
	bottom_button_two.custom_minimum_size = Vector2(58.0, 58.0)
	bottom_button_two.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(bottom_button_two)
	bottom_button_two.pressed.connect(on_build_menu_button_pressed)

	bottom_button_three = Button.new()
	bottom_button_three.text = "3"
	bottom_button_three.focus_mode = Control.FOCUS_NONE
	bottom_button_three.custom_minimum_size = Vector2(58.0, 58.0)
	bottom_button_three.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(bottom_button_three)
	bottom_button_three.pressed.connect(on_city_object_menu_button_pressed.bind(WorldData.CITY_OBJECT_HOUSE))

	bottom_button_four = Button.new()
	bottom_button_four.text = "4"
	bottom_button_four.focus_mode = Control.FOCUS_NONE
	bottom_button_four.custom_minimum_size = Vector2(58.0, 58.0)
	bottom_button_four.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(bottom_button_four)
	bottom_button_four.pressed.connect(on_city_object_menu_button_pressed.bind(WorldData.CITY_OBJECT_STOCKPILE))

	bottom_button_five = Button.new()
	bottom_button_five.text = "5"
	bottom_button_five.focus_mode = Control.FOCUS_NONE
	bottom_button_five.custom_minimum_size = Vector2(58.0, 58.0)
	bottom_button_five.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(bottom_button_five)
	bottom_button_five.pressed.connect(on_city_object_menu_button_pressed.bind(WorldData.CITY_OBJECT_FISHING_GROUNDS))

	bottom_button_six = Button.new()
	bottom_button_six.text = "6"
	bottom_button_six.focus_mode = Control.FOCUS_NONE
	bottom_button_six.custom_minimum_size = Vector2(58.0, 58.0)
	bottom_button_six.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(bottom_button_six)
	bottom_button_six.pressed.connect(on_city_player_command_menu_button_pressed)


func create_city_player_command_menu() -> void:
	city_command_cancel_task_button = Button.new()
	city_command_cancel_task_button.text = "Cancel\nTask"
	city_command_cancel_task_button.focus_mode = Control.FOCUS_NONE
	city_command_cancel_task_button.toggle_mode = true
	city_command_cancel_task_button.custom_minimum_size = Vector2(58.0, 58.0)
	city_command_cancel_task_button.add_theme_font_size_override(
		"font_size",
		12
	)
	city_command_cancel_task_button.mouse_filter = Control.MOUSE_FILTER_STOP
	city_command_cancel_task_button.visible = false
	ui_root.add_child(city_command_cancel_task_button)
	city_command_cancel_task_button.pressed.connect(
		on_city_player_command_cancel_task_pressed
	)

	city_command_chop_trees_button = Button.new()
	city_command_chop_trees_button.text = "Chop\nTrees"
	city_command_chop_trees_button.focus_mode = Control.FOCUS_NONE
	city_command_chop_trees_button.toggle_mode = true
	city_command_chop_trees_button.custom_minimum_size = Vector2(58.0, 58.0)
	city_command_chop_trees_button.add_theme_font_size_override("font_size", 12)
	city_command_chop_trees_button.mouse_filter = Control.MOUSE_FILTER_STOP
	city_command_chop_trees_button.visible = false
	ui_root.add_child(city_command_chop_trees_button)
	city_command_chop_trees_button.pressed.connect(
		on_city_player_command_option_pressed.bind(
			WorldData.CITY_PLAYER_COMMAND_TYPE_CHOP_TREE
		)
	)

	city_command_collect_rocks_button = Button.new()
	city_command_collect_rocks_button.text = "Collect\nRocks"
	city_command_collect_rocks_button.focus_mode = Control.FOCUS_NONE
	city_command_collect_rocks_button.toggle_mode = true
	city_command_collect_rocks_button.custom_minimum_size = Vector2(58.0, 58.0)
	city_command_collect_rocks_button.add_theme_font_size_override("font_size", 12)
	city_command_collect_rocks_button.mouse_filter = Control.MOUSE_FILTER_STOP
	city_command_collect_rocks_button.visible = false
	ui_root.add_child(city_command_collect_rocks_button)
	city_command_collect_rocks_button.pressed.connect(
		on_city_player_command_option_pressed.bind(
			WorldData.CITY_PLAYER_COMMAND_TYPE_COLLECT_ROCK
		)
	)

	update_city_player_command_button_visuals()


func on_city_player_command_menu_button_pressed() -> void:
	if not WorldData.player_city_founded:
		return

	if city_command_menu_open:
		close_city_player_command_menu()
		return

	close_city_map_menu()
	close_build_menu()
	close_all_city_object_menus()
	cancel_active_city_object_placement()
	cancel_road_placement()
	clear_selected_city_entity()

	city_command_menu_open = true
	city_command_cancel_task_button.visible = true
	city_command_chop_trees_button.visible = true
	city_command_collect_rocks_button.visible = true
	layout_city_player_command_menu(get_viewport_rect().size)
	city_command_cancel_task_button.move_to_front()
	city_command_chop_trees_button.move_to_front()
	city_command_collect_rocks_button.move_to_front()
	update_city_player_command_button_visuals()


func on_city_player_command_option_pressed(command_type: String) -> void:
	if not WorldData.is_valid_city_player_command_type(command_type):
		return

	is_city_player_command_cancel_mode_active = false

	if city_command_cancel_cursor_icon != null:
		city_command_cancel_cursor_icon.visible = false

	if active_city_player_command_type == command_type:
		active_city_player_command_type = WorldData.CITY_PLAYER_COMMAND_TYPE_NONE
	else:
		active_city_player_command_type = command_type

	cancel_city_player_command_drag()
	clear_selected_city_entity()
	update_city_player_command_button_visuals()
	queue_city_interaction_layer_redraw()


func on_city_player_command_cancel_task_pressed() -> void:
	active_city_player_command_type = WorldData.CITY_PLAYER_COMMAND_TYPE_NONE
	is_city_player_command_cancel_mode_active = (
		not is_city_player_command_cancel_mode_active
	)
	cancel_city_player_command_drag()
	clear_selected_city_entity()

	if city_command_cancel_cursor_icon != null:
		city_command_cancel_cursor_icon.visible = (
			is_city_player_command_cancel_mode_active
		)

	if is_city_player_command_cancel_mode_active:
		update_city_player_command_cancel_cursor_icon_position()

	update_city_player_command_button_visuals()
	queue_city_interaction_layer_redraw()


func deactivate_city_player_command_tool() -> void:
	active_city_player_command_type = WorldData.CITY_PLAYER_COMMAND_TYPE_NONE
	is_city_player_command_cancel_mode_active = false
	cancel_city_player_command_drag()

	if city_command_cancel_cursor_icon != null:
		city_command_cancel_cursor_icon.visible = false

	update_city_player_command_button_visuals()
	queue_city_interaction_layer_redraw()


func close_city_player_command_menu() -> void:
	city_command_menu_open = false
	deactivate_city_player_command_tool()

	if city_command_cancel_task_button != null:
		city_command_cancel_task_button.visible = false

	if city_command_chop_trees_button != null:
		city_command_chop_trees_button.visible = false

	if city_command_collect_rocks_button != null:
		city_command_collect_rocks_button.visible = false

func is_city_player_command_mode_active() -> bool:
	return WorldData.is_valid_city_player_command_type(
		active_city_player_command_type
	)


func is_city_player_command_tool_active() -> bool:
	return (
		is_city_player_command_mode_active()
		or is_city_player_command_cancel_mode_active
	)


func update_city_player_command_button_visuals() -> void:
	if city_command_cancel_task_button != null:
		city_command_cancel_task_button.set_pressed_no_signal(
			is_city_player_command_cancel_mode_active
		)

	if city_command_chop_trees_button != null:
		city_command_chop_trees_button.set_pressed_no_signal(
			active_city_player_command_type
			== WorldData.CITY_PLAYER_COMMAND_TYPE_CHOP_TREE
		)

	if city_command_collect_rocks_button != null:
		city_command_collect_rocks_button.set_pressed_no_signal(
			active_city_player_command_type
			== WorldData.CITY_PLAYER_COMMAND_TYPE_COLLECT_ROCK
		)


func layout_city_player_command_menu(viewport_size: Vector2) -> void:
	if (
		bottom_button_six == null
		or city_command_cancel_task_button == null
		or city_command_chop_trees_button == null
		or city_command_collect_rocks_button == null
	):
		return

	var button_size := Vector2(58.0, 58.0)
	var gap := 6.0
	var centered_x := (
		bottom_button_six.position.x
		+ bottom_button_six.size.x * 0.5
		- button_size.x * 0.5
	)
	var chop_y := bottom_button_six.position.y - button_size.y - gap

	city_command_chop_trees_button.position = Vector2(centered_x, chop_y)
	city_command_chop_trees_button.size = button_size
	city_command_collect_rocks_button.position = Vector2(
		centered_x,
		chop_y - button_size.y - gap
	)
	city_command_collect_rocks_button.size = button_size
	city_command_cancel_task_button.position = Vector2(
		centered_x,
		chop_y - (button_size.y + gap) * 2.0
	)
	city_command_cancel_task_button.size = button_size

func create_city_object_option_button(object_type: String) -> void:
	var definition := WorldData.get_city_object_definition(object_type)

	if definition.is_empty():
		push_error("Missing city object definition for: " + object_type)
		return

	var option_button := Button.new()
	option_button.text = ""
	option_button.focus_mode = Control.FOCUS_NONE
	option_button.custom_minimum_size = Vector2(58.0, 58.0)
	option_button.mouse_filter = Control.MOUSE_FILTER_STOP
	option_button.visible = false

	ui_root.add_child(option_button)
	option_button.pressed.connect(on_city_object_option_button_pressed.bind(object_type))

	var icon := Panel.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var visual_style := WorldData.get_city_object_visual_style_for_type(object_type)

	var icon_style := create_flat_ui_style(
		Color(
			float(visual_style["fill_color"].r),
			float(visual_style["fill_color"].g),
			float(visual_style["fill_color"].b),
			1.0
		),
		Color(
			float(visual_style["frame_color"].r),
			float(visual_style["frame_color"].g),
			float(visual_style["frame_color"].b),
			1.0
		),
		1
	)

	icon.add_theme_stylebox_override("panel", icon_style)
	option_button.add_child(icon)

	city_object_option_buttons[object_type] = option_button
	city_object_option_icons[object_type] = icon

func get_bottom_button_for_slot(button_slot: int) -> Button:
	match button_slot:
		1:
			return bottom_button_one
		2:
			return bottom_button_two
		3:
			return bottom_button_three
		4:
			return bottom_button_four
		5:
			return bottom_button_five
		6:
			return bottom_button_six

	return null

func layout_city_object_option_button(object_type: String, _viewport_size: Vector2) -> void:
	if not city_object_option_buttons.has(object_type):
		return

	var definition := WorldData.get_city_object_definition(object_type)

	if definition.is_empty():
		return

	var button_slot: int = int(definition.get("button_slot", 0))
	var bottom_button := get_bottom_button_for_slot(button_slot)

	if bottom_button == null:
		return

	var option_button: Button = city_object_option_buttons[object_type]
	var button_size := 58.0
	var gap := 6.0

	option_button.position = Vector2(
		bottom_button.position.x,
		bottom_button.position.y - button_size - gap
	)

	option_button.size = Vector2(button_size, button_size)

	if city_object_option_icons.has(object_type):
		var icon: Panel = city_object_option_icons[object_type]
		var size_tiles: Vector2i = definition["size"]
		var largest_side: float = float(max(size_tiles.x, size_tiles.y))
		var max_icon_size := 30.0

		var icon_size := Vector2(
			float(size_tiles.x) / largest_side * max_icon_size,
			float(size_tiles.y) / largest_side * max_icon_size
		)

		icon.position = (Vector2(button_size, button_size) - icon_size) * 0.5
		icon.size = icon_size


func layout_all_city_object_option_buttons(viewport_size: Vector2) -> void:
	for object_type in city_object_option_buttons.keys():
		layout_city_object_option_button(str(object_type), viewport_size)

func create_back_button() -> void:
	back_button = Button.new()
	back_button.text = "Back"
	back_button.focus_mode = Control.FOCUS_NONE
	back_button.custom_minimum_size = Vector2(68.0, 50.0)
	back_button.mouse_filter = Control.MOUSE_FILTER_STOP

	var normal_style := create_flat_ui_style(
		Color(0.85, 0.05, 0.03, 0.95),
		Color(0.35, 0.00, 0.00, 1.0),
		2
	)

	var hover_style := create_flat_ui_style(
		Color(1.0, 0.10, 0.08, 0.95),
		Color(0.45, 0.00, 0.00, 1.0),
		2
	)

	var pressed_style := create_flat_ui_style(
		Color(0.60, 0.02, 0.02, 0.95),
		Color(0.20, 0.00, 0.00, 1.0),
		2
	)

	back_button.add_theme_stylebox_override("normal", normal_style)
	back_button.add_theme_stylebox_override("hover", hover_style)
	back_button.add_theme_stylebox_override("pressed", pressed_style)
	back_button.add_theme_color_override("font_color", Color.WHITE)
	back_button.add_theme_color_override("font_hover_color", Color.WHITE)
	back_button.add_theme_color_override("font_pressed_color", Color.WHITE)

	ui_root.add_child(back_button)

	back_button.pressed.connect(on_back_button_pressed)

func create_resource_bar() -> void:
	resource_bar = Control.new()
	resource_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(resource_bar)

	resource_boxes.clear()
	resource_icons.clear()
	resource_amount_labels.clear()

	var resource_order := get_city_resource_order()

	for i in range(resource_order.size()):
		var resource: String = resource_order[i]

		var box := Panel.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var box_style := create_flat_ui_style(
			Color(0.08, 0.08, 0.08, 0.82),
			Color(0.85, 0.85, 0.85, 0.95),
			1
		)

		box.add_theme_stylebox_override("panel", box_style)
		resource_bar.add_child(box)
		resource_boxes.append(box)

		var icon := ColorRect.new()
		icon.color = get_resource_color(resource)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(icon)
		resource_icons.append(icon)

		var amount_label := Label.new()
		amount_label.text = "0"
		amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		amount_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		amount_label.add_theme_color_override("font_color", Color.WHITE)
		amount_label.add_theme_font_size_override("font_size", 12)
		box.add_child(amount_label)
		resource_amount_labels.append(amount_label)

func get_city_resource_order() -> Array[String]:
	return WorldData.get_city_resource_types()

func update_resource_bar_values() -> void:
	var resource_order := get_city_resource_order()
	var owned_resource_amounts := (
		WorldData.get_total_owned_city_resource_amounts()
	)

	for i in range(resource_amount_labels.size()):
		if i >= resource_order.size():
			continue

		var resource: String = resource_order[i]
		var amount := maxi(
			int(owned_resource_amounts.get(resource, 0)),
			0
		)

		resource_amount_labels[i].text = str(amount)

func create_city_maps_menu() -> void:
	city_maps_button = Button.new()
	city_maps_button.text = "Maps"
	city_maps_button.focus_mode = Control.FOCUS_NONE
	city_maps_button.mouse_filter = Control.MOUSE_FILTER_STOP
	city_maps_button.custom_minimum_size = Vector2(52.0, 52.0)

	ui_root.add_child(city_maps_button)
	city_maps_button.pressed.connect(on_city_maps_button_pressed)

	city_map_mode_buttons.clear()

	for i in range(MapVisuals.get_all_view_modes().size()):
		var mode_button := Button.new()
		mode_button.text = str(i + 1)
		mode_button.focus_mode = Control.FOCUS_NONE
		mode_button.mouse_filter = Control.MOUSE_FILTER_STOP
		mode_button.custom_minimum_size = Vector2(52.0, 52.0)
		mode_button.visible = false
		mode_button.tooltip_text = get_city_map_mode_name(get_city_map_mode_for_index(i))

		ui_root.add_child(mode_button)
		city_map_mode_buttons.append(mode_button)

		mode_button.pressed.connect(
			on_city_map_mode_button_pressed.bind(get_city_map_mode_for_index(i))
		)

	update_city_maps_button_visual()
	update_city_map_mode_button_visuals()


func layout_city_maps_menu(viewport_size: Vector2) -> void:
	if city_maps_button == null:
		return

	var button_size := 52.0
	var resource_box_width := 52.0
	var resource_box_height := 50.0
	var resource_order := get_city_resource_order()
	var resource_count := maxi(resource_order.size(), 1)
	var gold_index := resource_order.find(WorldData.RESOURCE_GOLD)

	if gold_index < 0:
		gold_index = resource_count - 1

	var resource_bar_x := viewport_size.x - resource_box_width * float(resource_count)
	var gold_box_x := resource_bar_x + float(gold_index) * resource_box_width
	var gold_box_y := 0.0

	city_maps_button.position = Vector2(gold_box_x, gold_box_y + resource_box_height)
	city_maps_button.size = Vector2(button_size, button_size)

	var popup_x := city_maps_button.position.x + button_size
	var popup_y := city_maps_button.position.y

	var popup_width := button_size * float(city_map_mode_buttons.size())

	if popup_x + popup_width > viewport_size.x:
		popup_x = city_maps_button.position.x - popup_width

	for i in range(city_map_mode_buttons.size()):
		var mode_button := city_map_mode_buttons[i]
		mode_button.position = Vector2(popup_x + float(i) * button_size, popup_y)
		mode_button.size = Vector2(button_size, button_size)

	city_maps_button.move_to_front()

	if city_map_menu_open:
		for mode_button in city_map_mode_buttons:
			mode_button.move_to_front()


func on_city_maps_button_pressed() -> void:
	if not city_map_menu_open:
		close_city_player_command_menu()

	set_city_map_menu_open(not city_map_menu_open)


func set_city_map_menu_open(is_open: bool) -> void:
	city_map_menu_open = is_open

	for mode_button in city_map_mode_buttons:
		mode_button.visible = city_map_menu_open

	update_city_maps_button_visual()
	update_city_map_mode_button_visuals()
	layout_city_maps_menu(get_viewport_rect().size)


func close_city_map_menu() -> void:
	if not city_map_menu_open:
		return

	set_city_map_menu_open(false)


func update_city_maps_button_visual() -> void:
	if city_maps_button == null:
		return

	if city_map_menu_open:
		city_maps_button.text = "Close"
		apply_square_button_style(
			city_maps_button,
			Color(0.75, 0.04, 0.03, 0.96),
			Color(0.25, 0.0, 0.0, 1.0),
			Color.WHITE
		)
	else:
		city_maps_button.text = "Maps"
		apply_square_button_style(
			city_maps_button,
			Color(0.55, 0.38, 0.14, 0.96),
			Color(0.24, 0.15, 0.04, 1.0),
			Color.WHITE
		)


func update_city_map_mode_button_visuals() -> void:
	for i in range(city_map_mode_buttons.size()):
		var mode_button := city_map_mode_buttons[i]
		var mode := get_city_map_mode_for_index(i)
		var mode_is_ready := (
			city_texture_cache != null
			and city_texture_cache.is_mode_ready(city_world, mode)
		)
		mode_button.disabled = not mode_is_ready

		if mode == city_view_mode:
			apply_square_button_style(
				mode_button,
				Color(0.0, 0.85, 1.0, 0.95),
				Color(0.0, 0.22, 0.32, 1.0),
				Color.BLACK
			)
		else:
			apply_square_button_style(
				mode_button,
				Color(0.08, 0.08, 0.08, 0.90),
				Color(0.85, 0.85, 0.85, 0.85),
				Color.WHITE
			)


func apply_square_button_style(
	button: Button,
	fill_color: Color,
	border_color: Color,
	font_color: Color
) -> void:
	var normal_style := create_flat_ui_style(fill_color, border_color, 1)
	var hover_style := create_flat_ui_style(fill_color.lightened(0.15), border_color.lightened(0.15), 1)
	var pressed_style := create_flat_ui_style(fill_color.darkened(0.18), border_color, 1)

	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.add_theme_stylebox_override("focus", normal_style)

	button.add_theme_color_override("font_color", font_color)
	button.add_theme_color_override("font_hover_color", font_color)
	button.add_theme_color_override("font_pressed_color", font_color)
	button.add_theme_font_size_override("font_size", 14)

func _exit_tree() -> void:
	if city_texture_cache != null:
		city_texture_cache.dispose()

func on_city_map_mode_button_pressed(mode: int) -> void:
	set_city_view_mode(mode)


func set_city_view_mode(mode: int) -> void:
	if city_view_mode == mode:
		return
	if (
		city_texture_cache == null
		or not city_texture_cache.is_mode_ready(city_world, mode)
	):
		return

	close_city_player_command_menu()

	city_view_mode = mode

	print("City map mode: ", get_city_map_mode_name(city_view_mode))

	apply_cached_city_map_mode_texture()

	update_city_map_mode_button_visuals()
	queue_city_background_layer_redraw()
	queue_city_citizen_layer_redraw()

func get_city_map_mode_for_index(index: int) -> int:
	return MapVisuals.get_view_mode_for_index(index)


func get_city_map_mode_name(mode: int) -> String:
	return MapVisuals.get_view_mode_name(mode)


func get_all_city_view_modes() -> Array[int]:
	return MapVisuals.get_all_view_modes()

func create_flat_ui_style(fill_color: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()

	style.bg_color = fill_color
	style.border_color = border_color
	style.border_width_left = border_width
	style.border_width_right = border_width
	style.border_width_top = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0

	return style

func update_city_ui_layout() -> void:
	if ui_root == null:
		return

	var viewport_size: Vector2 = get_viewport_rect().size

	layout_bottom_buttons(viewport_size)
	layout_city_player_command_menu(viewport_size)
	layout_all_city_object_option_buttons(viewport_size)
	layout_build_option_button(viewport_size)
	layout_resource_bar(viewport_size)
	city_information_ui.layout()
	layout_object_info_panel(viewport_size)
	update_construction_site_info_panel_screen_position()
	layout_city_maps_menu(viewport_size)
	layout_back_button(viewport_size)
func close_city_object_menu(object_type: String) -> void:
	if city_object_option_buttons.has(object_type):
		var option_button: Button = city_object_option_buttons[object_type]
		option_button.visible = false


func close_all_city_object_menus() -> void:
	for object_type in city_object_option_buttons.keys():
		close_city_object_menu(str(object_type))


func has_open_city_object_menu() -> bool:
	for object_type in city_object_option_buttons.keys():
		var option_button: Button = city_object_option_buttons[object_type]

		if option_button.visible:
			return true

	return false


func on_city_object_menu_button_pressed(object_type: String) -> void:
	if not WorldData.can_use_city_object_definition(object_type):
		print("City object menu blocked: ", object_type)
		update_city_object_button_states()
		return

	if not city_object_option_buttons.has(object_type):
		return

	close_city_map_menu()
	close_build_menu()
	close_city_player_command_menu()
	cancel_road_placement()

	var option_button: Button = city_object_option_buttons[object_type]
	var should_open := not option_button.visible

	close_all_city_object_menus()

	if not should_open:
		cancel_active_city_object_placement()
		return

	cancel_active_city_object_placement()

	option_button.visible = true
	layout_city_object_option_button(object_type, get_viewport_rect().size)
	option_button.move_to_front()

	update_city_object_button_states()

func on_city_object_option_button_pressed(object_type: String) -> void:
	if not WorldData.can_use_city_object_definition(object_type):
		print("City object placement blocked: ", object_type)
		update_city_object_button_states()
		return

	if is_placing_city_object_type(object_type):
		cancel_active_city_object_placement()
	else:
		start_city_object_placement_from_definition(object_type)

func start_city_object_placement_from_definition(object_type: String) -> void:
	var definition := WorldData.get_city_object_definition(object_type)

	if definition.is_empty():
		push_error("Cannot start placement. Missing city object definition: " + object_type)
		return

	if not WorldData.can_use_city_object_definition(object_type):
		print("Cannot place locked city object: ", object_type)
		update_city_object_button_states()
		return

	close_build_menu()
	close_city_player_command_menu()
	cancel_road_placement()

	var size_tiles: Vector2i = definition["size"]
	var repeat_after_place: bool = bool(definition.get("repeat_after_place", false))

	start_city_object_placement(
		object_type,
		size_tiles,
		"player",
		repeat_after_place
	)

	set_city_object_option_selected(object_type, true)
	queue_city_background_layer_redraw()
	queue_city_interaction_layer_redraw()

	print("City object placement started: ", object_type)


func cancel_active_city_object_placement() -> void:
	if not has_active_city_object_placement():
		return

	var object_type: String = str(active_city_object_placement.get("type", ""))

	clear_city_object_placement()

	if object_type != "":
		set_city_object_option_selected(object_type, false)

	queue_city_background_layer_redraw()
	queue_city_interaction_layer_redraw()

	print("City object placement canceled: ", object_type)


func set_city_object_option_selected(object_type: String, is_selected: bool) -> void:
	if not city_object_option_icons.has(object_type):
		return

	var icon: Panel = city_object_option_icons[object_type]
	var visual_style := WorldData.get_city_object_visual_style_for_type(object_type)

	var fill_color: Color = visual_style["fill_color"]
	var border_color: Color = visual_style["frame_color"]

	fill_color = Color(fill_color.r, fill_color.g, fill_color.b, 1.0)
	border_color = Color(border_color.r, border_color.g, border_color.b, 1.0)

	if is_selected:
		border_color = Color(0.0, 0.85, 1.0, 1.0)

	var icon_style := create_flat_ui_style(
		fill_color,
		border_color,
		1
	)

	icon.add_theme_stylebox_override("panel", icon_style)

func update_city_object_button_states() -> void:
	var city_object_main_buttons := {
		WorldData.CITY_OBJECT_CITY_CENTER: bottom_button_one,
		WorldData.CITY_OBJECT_HOUSE: bottom_button_three,
		WorldData.CITY_OBJECT_STOCKPILE: bottom_button_four,
		WorldData.CITY_OBJECT_FISHING_GROUNDS: bottom_button_five
	}

	for object_type in city_object_main_buttons.keys():
		var object_type_string := str(object_type)
		var definition := WorldData.get_city_object_definition(object_type_string)
		var main_button: Button = city_object_main_buttons[object_type_string]

		if definition.is_empty() or main_button == null:
			continue

		main_button.disabled = not WorldData.can_use_city_object_definition(object_type_string)
		main_button.text = str(int(definition.get("button_slot", 0)))

	if bottom_button_six != null:
		bottom_button_six.disabled = not WorldData.player_city_founded
		bottom_button_six.text = "6"

	for object_type in city_object_option_buttons.keys():
		var object_type_string := str(object_type)
		var option_button: Button = city_object_option_buttons[object_type_string]
		var can_use := WorldData.can_use_city_object_definition(object_type_string)

		option_button.disabled = not can_use

		if not can_use:
			option_button.visible = false
			set_city_object_option_selected(object_type_string, false)

func create_object_info_panel() -> void:
	object_info_panel = Panel.new()
	object_info_panel.visible = false
	object_info_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var panel_style := create_flat_ui_style(
		Color(0.16, 0.16, 0.16, 0.94),
		Color(0.42, 0.42, 0.42, 1.0),
		1
	)

	object_info_panel.add_theme_stylebox_override("panel", panel_style)
	ui_root.add_child(object_info_panel)

	object_info_title_label = Label.new()
	object_info_title_label.text = "City Keep"
	object_info_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	object_info_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	object_info_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	object_info_title_label.add_theme_color_override("font_color", Color(0.88, 0.96, 1.0, 1.0))
	object_info_title_label.add_theme_font_size_override("font_size", 18)
	object_info_panel.add_child(object_info_title_label)

	object_info_body_label = Label.new()
	object_info_body_label.text = ""
	object_info_body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	object_info_body_label.add_theme_color_override("font_color", Color(0.82, 0.82, 0.82, 1.0))
	object_info_body_label.add_theme_font_size_override("font_size", 13)
	object_info_panel.add_child(object_info_body_label)
	create_object_info_storage_rows()
	create_workplace_details_ui()


func create_construction_site_info_panel() -> void:
	construction_site_info_panel = Panel.new()
	construction_site_info_panel.visible = false
	construction_site_info_panel.mouse_filter = (
		Control.MOUSE_FILTER_STOP
	)

	var panel_style := create_flat_ui_style(
		Color(0.16, 0.16, 0.16, 0.94),
		Color(0.42, 0.42, 0.42, 1.0),
		1
	)

	construction_site_info_panel.add_theme_stylebox_override(
		"panel",
		panel_style
	)
	ui_root.add_child(construction_site_info_panel)

	construction_site_info_title_label = Label.new()
	construction_site_info_title_label.text = (
		"Construction Progress: 0%"
	)
	construction_site_info_title_label.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	construction_site_info_title_label.add_theme_color_override(
		"font_color",
		Color(0.88, 0.96, 1.0, 1.0)
	)
	construction_site_info_title_label.add_theme_font_size_override(
		"font_size",
		16
	)
	construction_site_info_panel.add_child(
		construction_site_info_title_label
	)

	construction_site_info_body_label = Label.new()
	construction_site_info_body_label.text = ""
	construction_site_info_body_label.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	construction_site_info_body_label.add_theme_color_override(
		"font_color",
		Color(0.82, 0.82, 0.82, 1.0)
	)
	construction_site_info_body_label.add_theme_font_size_override(
		"font_size",
		14
	)
	construction_site_info_body_label.add_theme_constant_override(
		"line_spacing",
		4
	)
	construction_site_info_panel.add_child(
		construction_site_info_body_label
	)

func create_object_info_storage_rows() -> void:
	object_info_storage_title_label = Label.new()
	object_info_storage_title_label.text = "Storage"
	object_info_storage_title_label.visible = false
	object_info_storage_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	object_info_storage_title_label.add_theme_color_override("font_color", Color(0.88, 0.96, 1.0, 1.0))
	object_info_storage_title_label.add_theme_font_size_override("font_size", 15)
	object_info_panel.add_child(object_info_storage_title_label)

	object_info_storage_icons.clear()
	object_info_storage_amount_labels.clear()

	for i in range(
		maxi(
			WorldData.get_city_resource_types().size(),
			1
		)
	):
		var icon := ColorRect.new()
		icon.visible = false
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		object_info_panel.add_child(icon)
		object_info_storage_icons.append(icon)

		var amount_label := Label.new()
		amount_label.visible = false
		amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		amount_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92, 1.0))
		amount_label.add_theme_font_size_override("font_size", 13)
		object_info_panel.add_child(amount_label)
		object_info_storage_amount_labels.append(amount_label)


func create_workplace_details_ui() -> void:
	workplace_details_button = Button.new()
	workplace_details_button.text = "Workplace Details"
	workplace_details_button.visible = false
	workplace_details_button.focus_mode = Control.FOCUS_NONE
	workplace_details_button.mouse_filter = (
		Control.MOUSE_FILTER_STOP
	)
	object_info_panel.add_child(workplace_details_button)
	workplace_details_button.pressed.connect(
		on_workplace_details_button_pressed
	)

	workplace_details_panel = Panel.new()
	workplace_details_panel.visible = false
	workplace_details_panel.mouse_filter = (
		Control.MOUSE_FILTER_STOP
	)

	var panel_style := create_flat_ui_style(
		Color(0.16, 0.16, 0.16, 0.94),
		Color(0.42, 0.42, 0.42, 1.0),
		1
	)

	workplace_details_panel.add_theme_stylebox_override(
		"panel",
		panel_style
	)
	ui_root.add_child(workplace_details_panel)

	workplace_details_title_label = Label.new()
	workplace_details_title_label.text = "Workplace Details"
	workplace_details_title_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	workplace_details_title_label.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)
	workplace_details_title_label.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	workplace_details_title_label.add_theme_color_override(
		"font_color",
		Color(0.88, 0.96, 1.0, 1.0)
	)
	workplace_details_title_label.add_theme_font_size_override(
		"font_size",
		18
	)
	workplace_details_panel.add_child(
		workplace_details_title_label
	)

	workplace_details_body_label = Label.new()
	workplace_details_body_label.text = ""
	workplace_details_body_label.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	workplace_details_body_label.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
	)
	workplace_details_body_label.add_theme_color_override(
		"font_color",
		Color(0.82, 0.82, 0.82, 1.0)
	)
	workplace_details_body_label.add_theme_font_size_override(
		"font_size",
		13
	)
	workplace_details_panel.add_child(
		workplace_details_body_label
	)


func layout_object_info_panel(viewport_size: Vector2) -> void:
	if object_info_panel == null:
		return

	var panel_width := 240.0
	var desired_panel_y := maxf(
		viewport_size.y * 0.10,
		city_information_ui.get_reserved_bottom_y()
	)
	var panel_y := maxf(desired_panel_y, 0.0)
	var panel_height := minf(
		600.0,
		maxf(viewport_size.y - panel_y, 0.0)
	)

	object_info_panel.size = Vector2(
		panel_width,
		panel_height
	)
	# Apply position after size because Control minimum-size growth can otherwise
	# shift the panel back over the persistent city summary.
	object_info_panel.position = Vector2(
		0.0,
		panel_y
	)

	if object_info_title_label != null:
		object_info_title_label.position = Vector2(0.0, 10.0)
		object_info_title_label.size = Vector2(
			panel_width,
			32.0
		)

	if object_info_body_label != null:
		object_info_body_label.position = Vector2(14.0, 56.0)
		object_info_body_label.size = Vector2(
			panel_width - 28.0,
			370.0
		)

	layout_workplace_details_button(
		workplace_details_button_body_line_count
	)
	layout_workplace_details_panel(viewport_size)
	layout_object_info_storage_rows(panel_width)


func layout_workplace_details_button(
	body_line_count: int
) -> void:
	if workplace_details_button == null:
		return

	var body_start_y := 56.0
	var body_line_height := 21.0
	var button_gap := 6.0
	var button_y := (
		body_start_y
		+ float(body_line_count) * body_line_height
		+ button_gap
	)

	workplace_details_button.position = Vector2(
		14.0,
		button_y
	)
	workplace_details_button.size = Vector2(
		object_info_panel.size.x - 28.0,
		30.0
	)


func layout_workplace_details_panel(
	_viewport_size: Vector2
) -> void:
	if workplace_details_panel == null:
		return

	var panel_gap := 8.0
	var panel_width := 320.0
	var panel_height := object_info_panel.size.y

	workplace_details_panel.size = Vector2(
		panel_width,
		panel_height
	)
	workplace_details_panel.position = Vector2(
		object_info_panel.position.x
			+ object_info_panel.size.x
			+ panel_gap,
		object_info_panel.position.y
	)

	if workplace_details_title_label != null:
		workplace_details_title_label.position = Vector2(
			0.0,
			10.0
		)
		workplace_details_title_label.size = Vector2(
			panel_width,
			32.0
		)

	if workplace_details_body_label != null:
		workplace_details_body_label.position = Vector2(
			14.0,
			56.0
		)
		workplace_details_body_label.size = Vector2(
			panel_width - 28.0,
			panel_height - 70.0
		)


func layout_construction_site_info_panel_content(
	resource_row_count: int
) -> void:
	if construction_site_info_panel == null:
		return

	var safe_row_count := maxi(resource_row_count, 1)
	var panel_height := (
		CONSTRUCTION_SITE_INFO_PANEL_HEADER_HEIGHT
		+ float(safe_row_count)
		* CONSTRUCTION_SITE_INFO_PANEL_RESOURCE_ROW_HEIGHT
		+ CONSTRUCTION_SITE_INFO_PANEL_BOTTOM_PADDING
	)

	construction_site_info_panel.size = Vector2(
		CONSTRUCTION_SITE_INFO_PANEL_WIDTH,
		panel_height
	)

	if construction_site_info_title_label != null:
		construction_site_info_title_label.position = Vector2(
			12.0,
			8.0
		)
		construction_site_info_title_label.size = Vector2(
			CONSTRUCTION_SITE_INFO_PANEL_WIDTH - 24.0,
			32.0
		)

	if construction_site_info_body_label != null:
		construction_site_info_body_label.position = Vector2(
			20.0,
			CONSTRUCTION_SITE_INFO_PANEL_HEADER_HEIGHT
		)
		construction_site_info_body_label.size = Vector2(
			CONSTRUCTION_SITE_INFO_PANEL_WIDTH - 40.0,
			float(safe_row_count)
			* CONSTRUCTION_SITE_INFO_PANEL_RESOURCE_ROW_HEIGHT
		)


func update_construction_site_info_panel_screen_position() -> void:
	if (
		construction_site_info_panel == null
		or not construction_site_info_panel.visible
		or selected_city_construction_site_id <= 0
	):
		return

	var site := WorldData.get_city_construction_site_by_id(
		selected_city_construction_site_id
	)

	if site.is_empty():
		return

	var site_world_rect := get_city_construction_site_world_rect(site)

	if (
		site_world_rect.size.x <= 0.0
		or site_world_rect.size.y <= 0.0
	):
		return

	# Keep the panel truly attached to the site's right side. It is allowed to
	# travel off-screen with the site instead of turning into an edge-clamped HUD.
	var canvas_transform := get_global_transform_with_canvas()
	var right_middle_screen := canvas_transform * Vector2(
		site_world_rect.end.x,
		site_world_rect.position.y
		+ site_world_rect.size.y * 0.5
	)
	var panel_size := construction_site_info_panel.size
	construction_site_info_panel.position = Vector2(
		right_middle_screen.x
		+ CONSTRUCTION_SITE_INFO_PANEL_SIDE_GAP,
		right_middle_screen.y - panel_size.y
	)


func get_city_construction_site_world_rect(
	site: Dictionary
) -> Rect2:
	var footprint_tiles = site.get("footprint_tiles", [])

	if not footprint_tiles is Array or footprint_tiles.is_empty():
		return Rect2()

	var minimum_tile := Vector2i(
		2147483647,
		2147483647
	)
	var maximum_tile := Vector2i(
		-2147483648,
		-2147483648
	)
	var found_tile := false

	for raw_tile in footprint_tiles:
		if not raw_tile is Vector2i:
			continue

		var tile_position: Vector2i = raw_tile
		minimum_tile.x = mini(minimum_tile.x, tile_position.x)
		minimum_tile.y = mini(minimum_tile.y, tile_position.y)
		maximum_tile.x = maxi(maximum_tile.x, tile_position.x)
		maximum_tile.y = maxi(maximum_tile.y, tile_position.y)
		found_tile = true

	if not found_tile:
		return Rect2()

	return Rect2(
		Vector2(
			float(minimum_tile.x * city_tile_size),
			float(minimum_tile.y * city_tile_size)
		),
		Vector2(
			float(
				(maximum_tile.x - minimum_tile.x + 1)
				* city_tile_size
			),
			float(
				(maximum_tile.y - minimum_tile.y + 1)
				* city_tile_size
			)
		)
	)

func layout_object_info_storage_rows(panel_width: float) -> void:
	if object_info_storage_title_label != null:
		object_info_storage_title_label.position = Vector2(14.0, 436.0)
		object_info_storage_title_label.size = Vector2(panel_width - 28.0, 24.0)

	var row_start_y := 468.0
	var row_height := 28.0
	var icon_size := 16.0

	for i in range(object_info_storage_icons.size()):
		var row_y := row_start_y + float(i) * row_height

		var icon := object_info_storage_icons[i]
		icon.position = Vector2(18.0, row_y + 4.0)
		icon.size = Vector2(icon_size, icon_size)

		if i < object_info_storage_amount_labels.size():
			var amount_label := object_info_storage_amount_labels[i]
			amount_label.position = Vector2(44.0, row_y)
			amount_label.size = Vector2(panel_width - 58.0, row_height)

func get_container_type_display_name(container_type: String) -> String:
	match container_type:
		WorldData.CONTAINER_TYPE_PUBLIC_CITY_STORAGE:
			return "Public city storage"
		WorldData.CONTAINER_TYPE_PRIVATE_HOME_STORAGE:
			return "Private home storage"
		WorldData.CONTAINER_TYPE_WORKPLACE_STORAGE:
			return "Workplace output buffer"
		WorldData.CONTAINER_TYPE_PERSONAL_INVENTORY:
			return "Personal inventory"
		WorldData.CONTAINER_TYPE_GROUND_PILE:
			return "Ground pile"
		_:
			return "None"


func get_storage_panel_title_for_object(city_object: Dictionary) -> String:
	var container_type := WorldData.get_city_object_container_type(city_object)

	match container_type:
		WorldData.CONTAINER_TYPE_PUBLIC_CITY_STORAGE:
			return "Public Storage"
		WorldData.CONTAINER_TYPE_PRIVATE_HOME_STORAGE:
			return "Private Storage"
		WorldData.CONTAINER_TYPE_WORKPLACE_STORAGE:
			return "Workplace Output Buffer"
		WorldData.CONTAINER_TYPE_PERSONAL_INVENTORY:
			return "Personal Inventory"
		WorldData.CONTAINER_TYPE_GROUND_PILE:
			return "Ground Pile"
		_:
			return "Storage"

func get_workplace_production_status_display_name(
	production_status: String
) -> String:
	match production_status:
		WorldData.WORKPLACE_PRODUCTION_STATUS_WORKING:
			return "Working"
		WorldData.WORKPLACE_PRODUCTION_STATUS_IDLE_NO_WORKERS:
			return "Idle - No Workers Present"
		WorldData.WORKPLACE_PRODUCTION_STATUS_BLOCKED_OUTPUT_FULL:
			return "Blocked - Output Storage Full"
		WorldData.WORKPLACE_PRODUCTION_STATUS_BLOCKED_MISSING_INPUT:
			return "Blocked - Missing Input"
		WorldData.WORKPLACE_PRODUCTION_STATUS_BLOCKED_NO_RESOURCE_SOURCE:
			return "Blocked - No Resource Source"
		WorldData.WORKPLACE_PRODUCTION_STATUS_INACTIVE:
			return "Inactive"
		_:
			return production_status.capitalize()


func format_compact_production_number(value: float) -> String:
	var nearest_integer := int(round(value))

	if is_equal_approx(value, float(nearest_integer)):
		return str(nearest_integer)

	return "%.2f" % value

func update_selected_city_citizen_panel() -> void:
	if object_info_panel == null:
		return

	hide_workplace_details_ui()

	var citizen := (
		WorldData.get_city_citizen_by_id(
			selected_city_citizen_id
		)
	)

	if citizen.is_empty():
		object_info_panel.visible = false
		hide_object_info_storage_display()
		return

	object_info_panel.visible = true
	hide_object_info_storage_display()

	var citizen_id := int(
		citizen.get("id", -1)
	)
	var citizen_name := str(
		citizen.get(
			"name",
			"Citizen " + str(citizen_id)
		)
	)
	var raw_position = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var position_text := "invalid"

	if raw_position is Vector2i:
		position_text = (
			str(raw_position.x)
			+ ", "
			+ str(raw_position.y)
		)

	var state_text := str(
		citizen.get("state", "unknown")
	).capitalize()
	var task_text := CitizenDebugPanelScript.get_task_text(citizen)
	var task_target_text := "none"
	var raw_current_task = citizen.get("current_task", {})

	if raw_current_task is Dictionary:
		var raw_task_target_tile = raw_current_task.get(
			"target_tile",
			WorldData.INVALID_CITY_TILE_POSITION
		)

		if (
			raw_task_target_tile is Vector2i
			and raw_task_target_tile
			!= WorldData.INVALID_CITY_TILE_POSITION
		):
			task_target_text = str(raw_task_target_tile)
	object_info_title_label.text = citizen_name
	var movement_state_text := str(
		citizen.get(
			"movement_state",
			WorldData.CITY_CITIZEN_MOVEMENT_STATE_IDLE
		)
	)

	var movement_text := movement_state_text.capitalize()

	if (
		movement_state_text
		== WorldData.CITY_CITIZEN_MOVEMENT_STATE_MOVING
	):
		movement_text += (
			" -> "
			+ str(
				citizen.get(
					"movement_destination_tile",
					WorldData.INVALID_CITY_TILE_POSITION
				)
			)
		)

	var body_lines := [
		"Citizen #" + str(citizen_id),
		"Sex: "
			+ WorldData.get_city_citizen_sex_display_name(
				str(citizen.get("sex", ""))
			),
		"Position: " + position_text,
		"State: " + state_text,
		"Task: " + task_text,
		"Activity tile: " + task_target_text,
		"Movement: " + movement_text,
		"Hunger: "
			+ str(WorldData.get_city_citizen_hunger(citizen_id))
			+ " / "
			+ str(WorldData.MAX_CITIZEN_HUNGER),
		"Personal food: "
			+ str(
				WorldData.get_food_nutrition_in_resource_container(
					WorldData.get_city_citizen_inventory(citizen_id)
				)
			)
			+ " nutrition",
		"Home: "
			+ CitizenDebugPanelScript.get_home_text(
				citizen
			),
		"Workplace: "
			+ CitizenDebugPanelScript.get_job_text(
				citizen
			)
	]
	body_lines.append_array(
		get_citizen_haul_status_lines(citizen)
	)
	var body_text := ""

	for line_index in range(body_lines.size()):
		if line_index > 0:
			body_text += "\n"

		body_text += str(
			body_lines[line_index]
		)

	object_info_body_label.text = body_text
	update_citizen_inventory_display(citizen)


func get_citizen_haul_status_lines(
	citizen: Dictionary
) -> Array:
	var citizen_id := int(citizen.get("id", -1))

	if not WorldData.city_citizen_is_hauling(citizen_id):
		return ["Hauling: No"]

	var haul := WorldData.get_city_citizen_current_haul(citizen_id)
	var cargo_resources := (
		WorldData.get_city_citizen_haul_cargo_resources(citizen_id)
	)
	var resource := str(
		haul.get("resource_type", WorldData.RESOURCE_NONE)
	)

	if resource == WorldData.RESOURCE_NONE and not cargo_resources.is_empty():
		var cargo_resource_names: Array = cargo_resources.keys()
		cargo_resource_names.sort()
		resource = str(cargo_resource_names[0])

	var cargo_amount := (
		WorldData.get_city_citizen_haul_cargo_amount(citizen_id)
	)
	var carry_capacity := maxi(
		int(citizen.get("carry_capacity", 0)),
		0
	)
	var personal_inventory_used := (
		WorldData.get_city_citizen_inventory_used_capacity(citizen_id)
	)
	var haul_capacity := maxi(
		carry_capacity - personal_inventory_used,
		0
	)
	var haul_phase := str(
		haul.get(
			"phase",
			WorldData.CITY_CITIZEN_HAUL_PHASE_NONE
		)
	).replace("_", " ").capitalize()
	var lines: Array = [
		"Hauling: Yes",
		"Current pickup: " + resource.capitalize(),
		"Cargo contents: "
			+ get_city_resource_manifest_display_text(cargo_resources),
		"Cargo total: "
			+ str(cargo_amount)
			+ " / "
			+ str(haul_capacity)
			+ " (shared carry "
			+ str(personal_inventory_used + cargo_amount)
			+ " / "
			+ str(carry_capacity)
			+ ")",
		"Haul source: "
			+ get_haul_endpoint_display_text(haul.get("source", {})),
		"Haul destination: "
			+ get_haul_endpoint_display_text(haul.get("destination", {})),
		"Pickup stops: "
			+ str(maxi(int(haul.get("pickup_stop_count", 0)), 0)),
		"Haul phase: " + haul_phase,
	]
	var reservation_id := int(
		haul.get(
			"reservation_id",
			WorldData.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
		)
	)

	if reservation_id > 0:
		var reservation := WorldData.get_city_haul_reservation(
			reservation_id
		)

		if not reservation.is_empty():
			var reserved_resources := (
				WorldData.get_city_haul_reservation_destination_resources(
					reservation_id
				)
			)
			lines.append(
				"Reservation #"
				+ str(reservation_id)
				+ ": source "
				+ str(
					maxi(
						int(
							reservation.get(
								"source_reserved_amount",
								0
							)
						),
						0
					)
				)
				+ ", destination "
				+ str(
					maxi(
						int(
							reservation.get(
								"destination_reserved_amount",
								0
							)
						),
						0
					)
				)
				+ " ["
				+ get_city_resource_manifest_display_text(
					reserved_resources
				)
				+ "]"
			)

	return lines


func get_city_resource_manifest_display_text(
	resources: Dictionary
) -> String:
	return CitizenDebugPanelScript.format_resource_manifest(
		resources
	)

func get_haul_endpoint_display_text(raw_endpoint) -> String:
	return CitizenDebugPanelScript.format_haul_endpoint(
		raw_endpoint
	)

func update_citizen_inventory_display(
	citizen: Dictionary
) -> void:
	var raw_inventory = citizen.get("inventory", {})

	if not raw_inventory is Dictionary:
		hide_object_info_storage_display()
		return

	var inventory: Dictionary = raw_inventory
	var present_resources := (
		WorldData.get_resource_container_present_resources(
			inventory
		)
	)
	var used_capacity := (
		WorldData.get_resource_container_total_amount(
			inventory
		)
	)
	var carry_capacity := maxi(
		int(citizen.get("carry_capacity", 0)),
		0
	)
	var citizen_id := int(citizen.get("id", -1))
	var haul_cargo_amount := (
		WorldData.get_city_citizen_haul_cargo_amount(
			citizen_id
		)
	)

	if object_info_storage_title_label != null:
		var inventory_title := (
			"Personal Inventory ("
				+ str(used_capacity)
				+ " / "
				+ str(carry_capacity)
				+ ")"
		)

		if haul_cargo_amount > 0:
			inventory_title += (
				" | Total Carried "
				+ str(used_capacity + haul_cargo_amount)
				+ " / "
				+ str(carry_capacity)
			)

		object_info_storage_title_label.text = inventory_title

		object_info_storage_title_label.visible = true

	for i in range(object_info_storage_icons.size()):
		if i >= present_resources.size():
			object_info_storage_icons[i].visible = false

			if i < object_info_storage_amount_labels.size():
				object_info_storage_amount_labels[i].visible = false

			continue

		var resource: String = present_resources[i]
		var amount := (
			WorldData.get_resource_container_resource_amount(
				inventory,
				resource
			)
		)
		var icon := object_info_storage_icons[i]
		icon.visible = true
		icon.color = get_resource_color(resource)

		if i < object_info_storage_amount_labels.size():
			var amount_label := object_info_storage_amount_labels[i]
			amount_label.visible = true
			amount_label.text = (
				resource.capitalize()
					+ ": "
					+ str(amount)
			)


func get_object_info_lines_text(lines: Array) -> String:
	var result := ""

	for line_index in range(lines.size()):
		if line_index > 0:
			result += "\n"

		result += str(lines[line_index])

	return result


func hide_workplace_details_ui() -> void:
	workplace_details_open = false
	workplace_details_object_id = -1
	workplace_details_button_body_line_count = 0

	if workplace_details_button != null:
		workplace_details_button.visible = false
		workplace_details_button.text = "Workplace Details"

	if workplace_details_panel != null:
		workplace_details_panel.visible = false


func update_workplace_details_ui(
	city_object: Dictionary,
	main_body_line_count: int,
	detail_lines: Array
) -> void:
	var object_id := int(city_object.get("id", -1))

	if workplace_details_object_id != object_id:
		workplace_details_open = false
		workplace_details_object_id = object_id

	workplace_details_button_body_line_count = (
		main_body_line_count
	)

	if workplace_details_button != null:
		workplace_details_button.visible = true

		if workplace_details_open:
			workplace_details_button.text = (
				"Hide Workplace Details"
			)
		else:
			workplace_details_button.text = (
				"Workplace Details"
			)

		layout_workplace_details_button(
			workplace_details_button_body_line_count
		)

	if workplace_details_title_label != null:
		workplace_details_title_label.text = (
			get_city_object_display_name(city_object)
				+ " Details"
		)

	if workplace_details_body_label != null:
		workplace_details_body_label.text = (
			get_object_info_lines_text(detail_lines)
		)

	if workplace_details_panel != null:
		workplace_details_panel.visible = (
			workplace_details_open
		)

		if workplace_details_open:
			workplace_details_panel.move_to_front()


func on_workplace_details_button_pressed() -> void:
	var city_object := get_city_object_by_id(
		selected_city_object_id
	)

	if (
		city_object.is_empty()
		or not WorldData.city_object_is_workplace(
			city_object
		)
	):
		hide_workplace_details_ui()
		return

	workplace_details_open = not workplace_details_open
	update_selected_entity_panel()


func hide_construction_site_info_panel() -> void:
	if construction_site_info_panel != null:
		construction_site_info_panel.visible = false


func update_selected_city_construction_site_panel() -> void:
	object_info_panel.visible = false
	hide_object_info_storage_display()
	hide_workplace_details_ui()

	var site := WorldData.get_city_construction_site_by_id(
		selected_city_construction_site_id
	)

	if not is_city_construction_site_selectable(site):
		hide_construction_site_info_panel()
		clear_selected_city_entity()
		return

	var progress_summary := (
		CityConstructionSystemScript
		.get_city_construction_site_progress_summary(
			selected_city_construction_site_id
		)
	)

	if progress_summary.is_empty():
		hide_construction_site_info_panel()
		clear_selected_city_entity()
		return

	construction_site_info_title_label.text = (
		"Construction Progress: "
		+ str(
			int(progress_summary.get("progress_percent", 0))
		)
		+ "%"
	)

	var resource_lines: Array[String] = []
	var phase := str(site.get("phase", "unknown"))
	resource_lines.append("Phase: " + phase.capitalize())
	resource_lines.append(
		"Labor: "
		+ str(maxi(int(site.get("completed_labor_minutes", 0)), 0))
		+ "/"
		+ str(maxi(int(site.get("required_labor_minutes", 0)), 0))
		+ " minutes"
	)
	var material_line_start_index := resource_lines.size()
	var material_recipe = site.get("material_recipe", {})

	if material_recipe is Dictionary:
		for resource in WorldData.get_city_resource_types():
			var required_amount := maxi(
				int(material_recipe.get(resource, 0)),
				0
			)

			if required_amount <= 0:
				continue

			var delivered_amount := mini(
				WorldData.get_city_construction_site_reserved_resource_amount(
					selected_city_construction_site_id,
					resource
				),
				required_amount
			)
			resource_lines.append(
				resource.capitalize()
				+ ": "
				+ str(delivered_amount)
				+ "/"
				+ str(required_amount)
			)

	if resource_lines.size() == material_line_start_index:
		resource_lines.append("Materials: none")

	construction_site_info_body_label.text = "\n".join(
		resource_lines
	)
	layout_construction_site_info_panel_content(
		resource_lines.size()
	)
	construction_site_info_panel.visible = true
	construction_site_info_panel.move_to_front()
	update_construction_site_info_panel_screen_position()

func update_selected_entity_panel() -> void:
	if object_info_panel == null:
		return

	if (
		selected_city_entity_kind
		== CITY_SELECTION_KIND_CONSTRUCTION_SITE
	):
		update_selected_city_construction_site_panel()
		return

	hide_construction_site_info_panel()

	if selected_city_entity_kind == CITY_SELECTION_KIND_CITIZEN:
		update_selected_city_citizen_panel()
		return

	if selected_city_object_id < 0:
		_hide_selected_city_object_panel()
		return

	var city_object: Dictionary = get_city_object_by_id(
		selected_city_object_id
	)

	if city_object.is_empty():
		_hide_selected_city_object_panel()
		return

	_update_selected_city_object_panel(city_object)


func _hide_selected_city_object_panel() -> void:
	object_info_panel.visible = false
	hide_object_info_storage_display()
	hide_workplace_details_ui()


func _update_selected_city_object_panel(
	city_object: Dictionary
) -> void:
	object_info_panel.visible = true

	var object_type: String = str(city_object["type"])

	if object_type == WorldData.CITY_OBJECT_CITY_CENTER:
		object_info_title_label.text = "City Keep"
	else:
		object_info_title_label.text = get_city_object_display_name(
			city_object
		)

	var body_lines: Array = [
		"Object: " + get_city_object_display_name(city_object)
	]
	var workplace_detail_lines: Array = []
	var is_workplace := WorldData.city_object_is_workplace(
		city_object
	)

	if object_type == WorldData.CITY_OBJECT_CITY_CENTER:
		_append_city_center_object_info(body_lines)
	elif object_type == WorldData.CITY_OBJECT_HOUSE:
		_append_house_object_info({
			"city_object": city_object,
			"body_lines": body_lines,
		})
	elif is_workplace:
		_append_workplace_object_info({
			"city_object": city_object,
			"body_lines": body_lines,
			"workplace_detail_lines": workplace_detail_lines,
		})

	var metadata_lines: Array = body_lines

	if is_workplace:
		metadata_lines = workplace_detail_lines

	_append_selected_object_metadata({
		"city_object": city_object,
		"metadata_lines": metadata_lines,
	})

	object_info_body_label.text = get_object_info_lines_text(
		body_lines
	)

	if is_workplace:
		update_workplace_details_ui(
			city_object,
			body_lines.size(),
			workplace_detail_lines
		)
	else:
		hide_workplace_details_ui()

	update_object_info_storage_display(city_object)


func _append_city_center_object_info(body_lines: Array) -> void:
	body_lines.append(
		"Population: "
		+ str(WorldData.get_city_population_count())
	)
	body_lines.append(
		"Male: "
		+ str(
			WorldData.get_city_citizen_count_by_sex(
				WorldData.CITY_CITIZEN_SEX_MALE
			)
		)
		+ " | Female: "
		+ str(
			WorldData.get_city_citizen_count_by_sex(
				WorldData.CITY_CITIZEN_SEX_FEMALE
			)
		)
	)
	body_lines.append(
		"Housed: "
		+ str(WorldData.get_city_housed_citizen_count())
		+ " / "
		+ str(WorldData.get_total_city_resident_capacity())
	)
	body_lines.append(
		"Unemployed: "
		+ str(WorldData.get_city_unemployed_citizen_count())
	)


func _append_house_object_info(values: Dictionary) -> void:
	var city_object: Dictionary = values.get("city_object", {})
	var body_lines: Array = values.get("body_lines", [])

	body_lines.append(
		"Residents: "
		+ str(WorldData.get_city_object_resident_count(city_object))
		+ " / "
		+ str(WorldData.get_city_object_resident_capacity(city_object))
	)
	var food_supply := CityResourceMatcher.get_city_home_food_supply_status(
		city_object
	)
	body_lines.append(
		"Food reserve: "
		+ str(int(food_supply.get("stored_nutrition", 0)))
		+ " / "
		+ str(int(food_supply.get("target_nutrition", 0)))
		+ " nutrition"
	)
	body_lines.append(
		"Incoming food: "
		+ str(int(food_supply.get("incoming_nutrition", 0)))
		+ " | Unfilled: "
		+ str(int(food_supply.get("unfulfilled_nutrition", 0)))
	)

	var resident_names := WorldData.get_city_object_resident_names(
		city_object
	)

	for resident_name in resident_names:
		body_lines.append("- " + str(resident_name))


func _append_workplace_object_info(values: Dictionary) -> void:
	var city_object: Dictionary = values.get("city_object", {})
	var body_lines: Array = values.get("body_lines", [])
	var workplace_detail_lines: Array = values.get(
		"workplace_detail_lines",
		[]
	)
	var production_status := WorldData.get_city_object_production_status(
		city_object
	)

	body_lines.append(
		"Status: "
		+ get_workplace_production_status_display_name(
			production_status
		)
	)
	body_lines.append(
		"Assigned: "
		+ str(WorldData.get_city_object_worker_count(city_object))
		+ " / "
		+ str(WorldData.get_city_object_worker_capacity(city_object))
	)
	body_lines.append(
		"Present: "
		+ str(
			WorldData.get_city_object_attending_worker_count(
				city_object
			)
		)
	)
	body_lines.append(
		"Productive: "
		+ str(
			WorldData.get_city_object_productive_worker_count(
				city_object
			)
		)
	)

	var worker_names := WorldData.get_city_object_worker_names(
		city_object
	)

	for worker_name in worker_names:
		body_lines.append("- " + str(worker_name))

	var output_resources := WorldData.get_city_object_output_resources(
		city_object
	)

	if not output_resources.is_empty():
		var output_names: Array[String] = []

		for output_resource in output_resources:
			output_names.append(output_resource.capitalize())

		workplace_detail_lines.append(
			"Output: " + ", ".join(output_names)
		)

	var production_recipe := WorldData.get_city_object_production_recipe(
		city_object
	)
	var work_units_per_batch := int(
		production_recipe.get("work_units_per_batch", 0)
	)
	var progress_work_units := (
		WorldData.get_city_object_production_progress_work_units(
			city_object
		)
	)

	if work_units_per_batch > 0:
		workplace_detail_lines.append(
			"Progress: "
			+ str(progress_work_units)
			+ " / "
			+ str(work_units_per_batch)
		)

	for output_resource in output_resources:
		var output_per_hour := (
			WorkplaceProductionSystem.get_estimated_output_per_hour(
				city_object,
				output_resource
			)
		)

		workplace_detail_lines.append(
			"Rate: "
			+ format_compact_production_number(output_per_hour)
			+ " "
			+ output_resource
			+ "/hour"
		)

	_append_workplace_resource_source_details({
		"city_object": city_object,
		"workplace_detail_lines": workplace_detail_lines,
	})

	var site_productivity_percentage := (
		float(
			WorkplaceProductionSystem.get_current_site_productivity_basis_points(
				city_object,
				city_world
			)
		)
		/ 100.0
	)
	workplace_detail_lines.append(
		"Site Productivity: "
		+ format_compact_production_number(
			site_productivity_percentage
		)
		+ "%"
	)


func _append_workplace_resource_source_details(
	values: Dictionary
) -> void:
	var city_object: Dictionary = values.get("city_object", {})
	var workplace_detail_lines: Array = values.get(
		"workplace_detail_lines",
		[]
	)
	var source_evaluation := (
		WorkplaceProductionSystem.get_resource_source_evaluation(
			city_object,
			city_world
		)
	)

	if not bool(
		source_evaluation.get("uses_environmental_source", false)
	):
		return

	var source_resource := str(
		source_evaluation.get(
			"resource_type",
			WorldData.RESOURCE_NONE
		)
	)
	var resource_tile_count := int(
		source_evaluation.get("resource_tile_count", 0)
	)
	var zone_tile_count := int(
		source_evaluation.get("zone_tile_count", 0)
	)
	var density_percentage := (
		float(source_evaluation.get("density_basis_points", 0))
		/ 100.0
	)
	var full_productivity_density_percentage := (
		float(
			source_evaluation.get(
				"source_density_for_full_productivity_basis_points",
				0
			)
		)
		/ 100.0
	)
	var reach_tiles := int(source_evaluation.get("reach_tiles", 0))

	workplace_detail_lines.append(
		source_resource.capitalize()
		+ " Source: "
		+ str(resource_tile_count)
		+ " / "
		+ str(zone_tile_count)
		+ " zone tiles"
	)
	workplace_detail_lines.append(
		"Density: "
		+ format_compact_production_number(density_percentage)
		+ "% | Full Density: "
		+ format_compact_production_number(
			full_productivity_density_percentage
		)
		+ "% | Reach: "
		+ str(reach_tiles)
	)


func _append_selected_object_metadata(values: Dictionary) -> void:
	var city_object: Dictionary = values.get("city_object", {})
	var metadata_lines: Array = values.get("metadata_lines", [])
	var top_left: Vector2i = city_object.get(
		"top_left",
		Vector2i(-1, -1)
	)
	var size_tiles: Vector2i = city_object.get(
		"size",
		Vector2i.ZERO
	)

	if top_left == Vector2i(-1, -1) or size_tiles == Vector2i.ZERO:
		var footprint_tiles := WorldData.get_city_object_footprint_tiles(
			city_object
		)

		if not footprint_tiles.is_empty():
			var footprint_rect := get_city_tile_collection_world_rect(
				footprint_tiles
			)
			top_left = Vector2i(
				roundi(footprint_rect.position.x / float(city_tile_size)),
				roundi(footprint_rect.position.y / float(city_tile_size))
			)
			size_tiles = Vector2i(
				roundi(footprint_rect.size.x / float(city_tile_size)),
				roundi(footprint_rect.size.y / float(city_tile_size))
			)
	var container_type := WorldData.get_city_object_container_type(
		city_object
	)

	metadata_lines.append(
		"Owner: " + str(city_object.get("owner", "none"))
	)
	metadata_lines.append(
		"Container: " + get_container_type_display_name(container_type)
	)
	metadata_lines.append(
		"Position: "
		+ str(top_left.x)
		+ ", "
		+ str(top_left.y)
	)
	metadata_lines.append(
		"Size: "
		+ str(size_tiles.x)
		+ " x "
		+ str(size_tiles.y)
	)

func update_object_info_storage_display(
	city_object: Dictionary
) -> void:
	var allowed_resources := (
		WorldData.get_city_object_storage_resources(
			city_object
		)
	)

	if allowed_resources.is_empty():
		hide_object_info_storage_display()
		return

	var stored_resources := (
		WorldData.get_city_object_present_storage_resources(
			city_object
		)
	)
	var used_capacity := (
		WorldData.get_city_object_storage_used_capacity(
			city_object
		)
	)
	var total_capacity := (
		WorldData.get_city_object_storage_capacity(
			city_object
		)
	)

	if object_info_storage_title_label != null:
		object_info_storage_title_label.text = (
			get_storage_panel_title_for_object(city_object)
				+ " ("
				+ str(used_capacity)
				+ " / "
				+ str(total_capacity)
				+ ")"
		)
		object_info_storage_title_label.visible = true

	for i in range(object_info_storage_icons.size()):
		if i >= stored_resources.size():
			object_info_storage_icons[i].visible = false

			if i < object_info_storage_amount_labels.size():
				object_info_storage_amount_labels[i].visible = false

			continue

		var resource: String = stored_resources[i]
		var amount := (
			WorldData.get_city_object_stored_resource_amount(
				city_object,
				resource
			)
		)

		var icon := object_info_storage_icons[i]
		icon.visible = true
		icon.color = get_resource_color(resource)

		if i < object_info_storage_amount_labels.size():
			var amount_label := (
				object_info_storage_amount_labels[i]
			)
			amount_label.visible = true
			amount_label.text = (
				resource.capitalize()
					+ ": "
					+ str(amount)
			)

func hide_object_info_storage_display() -> void:
	if object_info_storage_title_label != null:
		object_info_storage_title_label.visible = false

	for icon in object_info_storage_icons:
		icon.visible = false

	for amount_label in object_info_storage_amount_labels:
		amount_label.visible = false

func create_object_selection_box_visual() -> void:
	object_selection_box_panel = Panel.new()
	object_selection_box_panel.visible = false
	object_selection_box_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var box_style := create_flat_ui_style(
		CURSOR_LOOK_FILL_COLOR,
		CURSOR_LOOK_BORDER_COLOR,
		1
	)

	object_selection_box_panel.add_theme_stylebox_override("panel", box_style)
	ui_root.add_child(object_selection_box_panel)


func update_object_selection_box_visual() -> void:
	if object_selection_box_panel == null:
		return

	var drag_distance: float = object_selection_drag_start_screen.distance_to(object_selection_drag_current_screen)

	if not is_object_selection_dragging or drag_distance < OBJECT_SELECTION_DRAG_THRESHOLD_PIXELS:
		object_selection_box_panel.visible = false
		return

	var min_x: float = minf(object_selection_drag_start_screen.x, object_selection_drag_current_screen.x)
	var min_y: float = minf(object_selection_drag_start_screen.y, object_selection_drag_current_screen.y)
	var max_x: float = maxf(object_selection_drag_start_screen.x, object_selection_drag_current_screen.x)
	var max_y: float = maxf(object_selection_drag_start_screen.y, object_selection_drag_current_screen.y)

	object_selection_box_panel.visible = true
	object_selection_box_panel.position = Vector2(min_x, min_y)
	object_selection_box_panel.size = Vector2(max_x - min_x, max_y - min_y)
	object_selection_box_panel.move_to_front()


func create_city_player_command_selection_box_visual() -> void:
	city_player_command_selection_box_panel = Panel.new()
	city_player_command_selection_box_panel.visible = false
	city_player_command_selection_box_panel.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	ui_root.add_child(city_player_command_selection_box_panel)


func update_city_player_command_selection_box_visual() -> void:
	if city_player_command_selection_box_panel == null:
		return

	var drag_distance := (
		city_player_command_drag_start_screen.distance_to(
			city_player_command_drag_current_screen
		)
	)

	if (
		not is_city_player_command_dragging
		or drag_distance < OBJECT_SELECTION_DRAG_THRESHOLD_PIXELS
	):
		city_player_command_selection_box_panel.visible = false
		return

	var fill_color := CITY_PLAYER_COMMAND_PREVIEW_FILL
	var border_color := CITY_PLAYER_COMMAND_PREVIEW_BORDER

	if city_player_command_drag_removing:
		fill_color = CITY_PLAYER_COMMAND_REMOVE_PREVIEW_FILL
		border_color = CITY_PLAYER_COMMAND_REMOVE_PREVIEW_BORDER

	city_player_command_selection_box_panel.add_theme_stylebox_override(
		"panel",
		create_flat_ui_style(fill_color, border_color, 1)
	)

	var min_x := minf(
		city_player_command_drag_start_screen.x,
		city_player_command_drag_current_screen.x
	)
	var min_y := minf(
		city_player_command_drag_start_screen.y,
		city_player_command_drag_current_screen.y
	)
	var max_x := maxf(
		city_player_command_drag_start_screen.x,
		city_player_command_drag_current_screen.x
	)
	var max_y := maxf(
		city_player_command_drag_start_screen.y,
		city_player_command_drag_current_screen.y
	)

	city_player_command_selection_box_panel.visible = true
	city_player_command_selection_box_panel.position = Vector2(min_x, min_y)
	city_player_command_selection_box_panel.size = Vector2(
		max_x - min_x,
		max_y - min_y
	)
	city_player_command_selection_box_panel.move_to_front()


func start_city_player_command_drag(
	screen_position: Vector2,
	removing: bool
) -> void:
	if not is_city_player_command_tool_active():
		return

	is_city_player_command_dragging = true
	city_player_command_drag_removing = removing
	city_player_command_drag_start_screen = screen_position
	city_player_command_drag_current_screen = screen_position
	city_player_command_drag_start_world = get_global_mouse_position()
	city_player_command_drag_current_world = (
		city_player_command_drag_start_world
	)
	refresh_city_player_command_drag_preview()
	update_city_player_command_selection_box_visual()
	queue_city_interaction_layer_redraw()


func update_city_player_command_drag(screen_position: Vector2) -> void:
	if not is_city_player_command_dragging:
		return

	city_player_command_drag_current_screen = screen_position
	city_player_command_drag_current_world = get_global_mouse_position()
	refresh_city_player_command_drag_preview()
	update_city_player_command_selection_box_visual()
	queue_city_interaction_layer_redraw()


func finish_city_player_command_drag(screen_position: Vector2) -> void:
	if not is_city_player_command_dragging:
		return

	city_player_command_drag_current_screen = screen_position
	city_player_command_drag_current_world = get_global_mouse_position()
	refresh_city_player_command_drag_preview()

	if city_player_command_drag_removing:
		CityWorkSystemScript.cancel_player_targets_at_tiles(
			city_player_command_drag_preview_tiles
		)
	else:
		CityWorkSystem.add_city_player_command_targets(
			active_city_player_command_type,
			city_player_command_drag_preview_tiles
		)

	cancel_city_player_command_drag()
	queue_city_interaction_layer_redraw()


func cancel_city_player_command_drag() -> void:
	is_city_player_command_dragging = false
	city_player_command_drag_removing = false
	city_player_command_drag_preview_tiles.clear()

	if city_player_command_selection_box_panel != null:
		city_player_command_selection_box_panel.visible = false

	queue_city_interaction_layer_redraw()


func refresh_city_player_command_drag_preview() -> void:
	city_player_command_drag_preview_tiles.clear()

	if not is_city_player_command_dragging or city_world == null:
		return

	var drag_tiles := get_city_tiles_in_player_command_drag_rect()

	if city_player_command_drag_removing:
		city_player_command_drag_preview_tiles = (
			CityWorkSystemScript.get_cancel_preview_tiles(drag_tiles)
		)
		return

	for tile_position in drag_tiles:
		if CityWorkSystem.can_designate_city_player_command_at_tile(
			active_city_player_command_type,
			tile_position
		):
			city_player_command_drag_preview_tiles.append(tile_position)


func get_city_tiles_in_player_command_drag_rect() -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	if city_world == null:
		return result

	var min_world_x := minf(
		city_player_command_drag_start_world.x,
		city_player_command_drag_current_world.x
	)
	var min_world_y := minf(
		city_player_command_drag_start_world.y,
		city_player_command_drag_current_world.y
	)
	var max_world_x := maxf(
		city_player_command_drag_start_world.x,
		city_player_command_drag_current_world.x
	)
	var max_world_y := maxf(
		city_player_command_drag_start_world.y,
		city_player_command_drag_current_world.y
	)
	var tile_size_float := float(city_tile_size)
	var world_width := float(city_world.width) * tile_size_float
	var world_height := float(city_world.height) * tile_size_float

	if (
		max_world_x < 0.0
		or max_world_y < 0.0
		or min_world_x >= world_width
		or min_world_y >= world_height
	):
		return result

	var min_tile_x := clampi(
		int(floor(min_world_x / tile_size_float)),
		0,
		city_world.width - 1
	)
	var min_tile_y := clampi(
		int(floor(min_world_y / tile_size_float)),
		0,
		city_world.height - 1
	)
	var max_tile_x := clampi(
		int(floor(max_world_x / tile_size_float)),
		0,
		city_world.width - 1
	)
	var max_tile_y := clampi(
		int(floor(max_world_y / tile_size_float)),
		0,
		city_world.height - 1
	)

	for tile_y in range(min_tile_y, max_tile_y + 1):
		for tile_x in range(min_tile_x, max_tile_x + 1):
			result.append(Vector2i(tile_x, tile_y))

	return result

func layout_bottom_buttons(viewport_size: Vector2) -> void:
	if (
		bottom_button_one == null
		or bottom_button_two == null
		or bottom_button_three == null
		or bottom_button_four == null
		or bottom_button_five == null
		or bottom_button_six == null
	):
		return

	var button_size := 58.0
	var gap := 0.0
	var total_width := button_size * 6.0 + gap * 5.0
	var start_x := viewport_size.x * 0.5 - total_width * 0.5
	var y := viewport_size.y - button_size
	var buttons: Array[Button] = [
		bottom_button_one,
		bottom_button_two,
		bottom_button_three,
		bottom_button_four,
		bottom_button_five,
		bottom_button_six,
	]

	for button_index in range(buttons.size()):
		var button := buttons[button_index]
		button.position = Vector2(
			start_x + (button_size + gap) * float(button_index),
			y
		)
		button.size = Vector2(button_size, button_size)

func layout_resource_bar(viewport_size: Vector2) -> void:
	if resource_bar == null:
		return

	var box_width := 52.0
	var box_height := 50.0
	var box_count := resource_boxes.size()
	var total_width := box_width * float(box_count)

	resource_bar.position = Vector2(viewport_size.x - total_width, 0.0)
	resource_bar.size = Vector2(total_width, box_height)

	for i in range(resource_boxes.size()):
		var box := resource_boxes[i]
		box.position = Vector2(float(i) * box_width, 0.0)
		box.size = Vector2(box_width, box_height)

		if i < resource_icons.size():
			var icon := resource_icons[i]
			icon.position = Vector2(box_width * 0.5 - 8.0, 7.0)
			icon.size = Vector2(16.0, 16.0)

		if i < resource_amount_labels.size():
			var label := resource_amount_labels[i]
			label.position = Vector2(0.0, 25.0)
			label.size = Vector2(box_width, 20.0)


func layout_back_button(viewport_size: Vector2) -> void:
	if back_button == null:
		return

	var button_size := Vector2(68.0, 50.0)

	back_button.position = Vector2(
		viewport_size.x - button_size.x - 12.0,
		viewport_size.y - button_size.y - 12.0
	)

	back_button.size = button_size

func on_back_button_pressed() -> void:
	store_current_city_camera_state()

	var return_path := WorldData.official_world_scene_path

	if return_path.is_empty():
		return_path = WorldData.city_return_world_scene_path

	if return_path.is_empty():
		return_path = world_scene_path

	if return_path.is_empty():
		push_error("World scene path is empty.")
		return

	var error: Error = get_tree().change_scene_to_file(return_path)

	if error != OK:
		push_error("Could not load world scene: " + return_path)

func get_city_tile_color(tile: Dictionary) -> Color:
	return get_city_tile_color_for_mode(tile, city_view_mode)


func get_city_tile_color_for_mode(tile: Dictionary, mode: int) -> Color:
	return MapVisuals.get_tile_color_for_mode(tile, mode, 0.45)


func populate_all_city_tile_colors(
	tile: Dictionary,
	output_colors: Array[Color]
) -> void:
	MapVisuals.populate_all_tile_colors(tile, output_colors, 0.45)


func get_biome_color(tile: Dictionary) -> Color:
	return MapVisuals.get_biome_color(tile)

func get_resource_color(resource: String) -> Color:
	return MapVisuals.get_resource_color(resource)

#endregion

#region Placement and selection input

func create_build_option_button() -> void:
	build_option_button = Button.new()
	build_option_button.text = ""
	build_option_button.focus_mode = Control.FOCUS_NONE
	build_option_button.custom_minimum_size = Vector2(58.0, 58.0)
	build_option_button.mouse_filter = Control.MOUSE_FILTER_STOP
	build_option_button.visible = false

	ui_root.add_child(build_option_button)
	build_option_button.pressed.connect(on_build_option_button_pressed)

	build_option_icon = Panel.new()
	build_option_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var visual_style := get_city_object_visual_style(
		WorldData.CITY_OBJECT_ROAD
	)
	var icon_style := create_flat_ui_style(
		visual_style.get("fill_color", Color(0.56, 0.25, 0.10, 0.96)),
		visual_style.get("frame_color", Color(0.29, 0.11, 0.045, 1.0)),
		1
	)

	build_option_icon.add_theme_stylebox_override("panel", icon_style)
	build_option_button.add_child(build_option_icon)

func layout_build_option_button(_viewport_size: Vector2) -> void:
	if build_option_button == null or bottom_button_two == null:
		return

	var button_size := 58.0
	var gap := 6.0

	build_option_button.position = Vector2(
		bottom_button_two.position.x,
		bottom_button_two.position.y - button_size - gap
	)

	build_option_button.size = Vector2(button_size, button_size)

	if build_option_icon != null:
		build_option_icon.position = Vector2(21.0, 21.0)
		build_option_icon.size = Vector2(16.0, 16.0)

func close_build_menu() -> void:
	if build_option_button != null:
		build_option_button.visible = false

func on_build_menu_button_pressed() -> void:
	if not WorldData.can_build_in_city():
		print("Build menu blocked: found a city first.")
		update_build_button_state()
		return

	if build_option_button == null:
		return

	close_city_map_menu()
	close_city_player_command_menu()

	var should_open := not build_option_button.visible

	close_all_city_object_menus()
	cancel_active_city_object_placement()

	if should_open:
		build_option_button.visible = true
		layout_build_option_button(get_viewport_rect().size)
		build_option_button.move_to_front()
	else:
		cancel_road_placement()
		build_option_button.visible = false

	update_build_button_state()

func on_build_option_button_pressed() -> void:
	if is_road_placement_active:
		cancel_road_placement()
	else:
		start_road_placement()

func start_road_placement() -> void:
	if not WorldData.can_build_in_city():
		print("Road placement blocked: found a city first.")
		update_build_button_state()
		return

	close_all_city_object_menus()
	close_city_player_command_menu()
	cancel_active_city_object_placement()

	is_road_placement_active = true
	is_road_dragging = false
	road_preview_tiles.clear()
	road_preview_lookup.clear()
	road_drag_start_tile = Vector2i(-1, -1)
	road_drag_current_tile = Vector2i(-1, -1)

	if road_cursor_icon != null:
		road_cursor_icon.visible = true
		update_road_cursor_icon_position()

	set_road_option_selected(true)

	update_build_button_state()
	queue_city_interaction_layer_redraw()

	print("Road placement started. Drag a selection box, then left-click again to confirm.")

func cancel_road_placement() -> void:
	if not is_road_placement_active and not is_road_dragging and road_preview_tiles.is_empty():
		return

	is_road_placement_active = false
	is_road_dragging = false
	road_preview_tiles.clear()
	road_preview_lookup.clear()
	road_drag_start_tile = Vector2i(-1, -1)
	road_drag_current_tile = Vector2i(-1, -1)

	if road_cursor_icon != null:
		road_cursor_icon.visible = false

	set_road_option_selected(false)

	queue_city_interaction_layer_redraw()

	print("Road placement canceled.")


func confirm_active_city_object_placement() -> void:
	if city_world == null:
		return

	var preview_object := get_active_city_object_placement_preview()

	if preview_object.is_empty():
		print("Cannot place object: invalid mouse position.")
		return

	var object_type: String = str(preview_object.get("type", ""))
	var top_left: Vector2i = preview_object["top_left"]
	var size_tiles: Vector2i = preview_object["size"]
	var object_owner: String = str(preview_object.get("owner", "player"))
	var repeat_after_place: bool = bool(active_city_object_placement.get("repeat_after_place", false))
	var uses_construction := (
		WorldData.city_object_type_uses_construction(object_type)
	)

	var can_place := WorldData.can_place_city_object(
		city_world,
		top_left,
		size_tiles,
		object_type
	)

	if uses_construction:
		can_place = WorldData.can_place_city_object_construction(
			city_world,
			top_left,
			size_tiles,
			object_type
		)

	if not can_place:
		print("Cannot place object here.")
		return

	var placement_result: Dictionary = {}

	if uses_construction:
		placement_result = CityConstructionSystemScript.create_rectangular_site({
			"object_type": object_type,
			"top_left": top_left,
			"size_tiles": size_tiles,
			"object_owner": object_owner,
			"city_world": city_world,
		})
	else:
		placement_result = WorldData.add_city_object({
			"object_type": object_type,
			"top_left": top_left,
			"size_tiles": size_tiles,
			"object_owner": object_owner,
			"city_world": city_world,
		})
		after_city_object_placed(placement_result)

	if placement_result.is_empty():
		print("Could not place object here.")
		return

	if not repeat_after_place:
		clear_city_object_placement()
		set_city_object_option_selected(object_type, false)

	update_city_object_button_states()
	update_build_button_state()
	update_debug_panel_text()

	if uses_construction:
		print("Queued construction blueprint: ", placement_result)
	else:
		print("Placed city object: ", placement_result)

	queue_city_background_layer_redraw()
	queue_city_interaction_layer_redraw()

func after_city_object_placed(city_object: Dictionary) -> void:
	if city_object.is_empty():
		return

	var object_type: String = str(city_object.get("type", ""))
	var definition := WorldData.get_city_object_definition(object_type)

	if definition.is_empty():
		return

	var placement_effect: String = str(definition.get("placement_effect", WorldData.CITY_OBJECT_PLACEMENT_EFFECT_NONE))

	match placement_effect:
		WorldData.CITY_OBJECT_PLACEMENT_EFFECT_FOUND_CITY:
			after_city_center_placed(city_object)

func after_city_center_placed(city_object: Dictionary) -> void:
	if WorldData.has_player_city():
		return

	var top_left: Vector2i = city_object.get("top_left", Vector2i(-1, -1))
	var size_tiles: Vector2i = city_object.get("size", Vector2i.ZERO)

	WorldData.found_player_city({
		"city_world_seed": city_seed,
		"city_map_size": Vector2i(
			city_world.width,
			city_world.height
		),
		"foundation_top_left": top_left,
		"foundation_size": size_tiles,
	})

	city_information_ui.refresh_all()
	update_city_object_button_states()
	update_build_button_state()

	print("Founded city at: ", top_left)
	print("City data: ", WorldData.player_city_data)

func start_object_selection_drag(screen_position: Vector2) -> void:
	is_object_selection_dragging = true

	object_selection_drag_start_screen = screen_position
	object_selection_drag_current_screen = screen_position

	object_selection_drag_start_world = get_global_mouse_position()
	object_selection_drag_current_world = object_selection_drag_start_world

	update_object_selection_box_visual()
	queue_city_interaction_layer_redraw()

func update_object_selection_drag(screen_position: Vector2) -> void:
	if not is_object_selection_dragging:
		return

	object_selection_drag_current_screen = screen_position
	object_selection_drag_current_world = get_global_mouse_position()

	update_object_selection_box_visual()
	queue_city_interaction_layer_redraw()

func finish_object_selection_drag(screen_position: Vector2) -> void:
	if not is_object_selection_dragging:
		return

	is_object_selection_dragging = false

	object_selection_drag_current_screen = screen_position
	object_selection_drag_current_world = get_global_mouse_position()

	if object_selection_box_panel != null:
		object_selection_box_panel.visible = false

	var drag_distance := object_selection_drag_start_screen.distance_to(object_selection_drag_current_screen)

	if drag_distance < OBJECT_SELECTION_DRAG_THRESHOLD_PIXELS:
		select_city_entity_under_mouse()
	else:
		select_city_object_in_drag_rect()

	queue_city_interaction_layer_redraw()

func get_selectable_city_citizen_ids_at_world_point(
	tile_position: Vector2i,
	world_position: Vector2
) -> Array:
	var selectable_citizen_ids := []
	var candidate_citizen_id_lookup: Dictionary = {}

	for raw_citizen_id in (
		WorldData.get_city_citizen_ids_at_tile(
			tile_position
		)
	):
		if typeof(raw_citizen_id) != TYPE_INT:
			continue

		candidate_citizen_id_lookup[raw_citizen_id] = true

	# Authoritative tile buckets remain the simulation truth. Citizens with
	# active cosmetic transitions are also considered so clicking follows the
	# marker that the player can actually see between tiles.
	for raw_citizen_id in (
		city_citizen_movement_presentation.get_transitioning_citizen_ids_snapshot()
	):
		if typeof(raw_citizen_id) != TYPE_INT:
			continue

		candidate_citizen_id_lookup[raw_citizen_id] = true

	var candidate_citizen_ids: Array = (
		candidate_citizen_id_lookup.keys()
	)
	candidate_citizen_ids.sort()

	for raw_citizen_id in candidate_citizen_ids:
		var citizen_id := int(raw_citizen_id)
		var citizen := (
			WorldData.get_city_citizen_by_id(
				citizen_id
			)
		)

		if citizen.is_empty():
			continue

		if not bool(citizen.get("alive", false)):
			continue

		var citizen_rect := (
			get_city_citizen_world_rect(
				citizen
			)
		)

		if not citizen_rect.has_point(
			world_position
		):
			continue

		selectable_citizen_ids.append(
			citizen_id
		)

	selectable_citizen_ids.sort()

	return selectable_citizen_ids


func select_city_entity_under_mouse() -> void:
	var tile_position := get_city_tile_under_mouse()

	if tile_position == Vector2i(-1, -1):
		clear_selected_city_entity()
		return

	var mouse_world_position := (
		get_global_mouse_position()
	)
	var citizen_ids := (
		get_selectable_city_citizen_ids_at_world_point(
			tile_position,
			mouse_world_position
		)
	)

	if not citizen_ids.is_empty():
		var next_citizen_id := int(
			citizen_ids[0]
		)

		if (
			selected_city_entity_kind
			== CITY_SELECTION_KIND_CITIZEN
		):
			var current_index := citizen_ids.find(
				selected_city_entity_id
			)

			if current_index >= 0:
				var next_index := (
					(current_index + 1)
					% citizen_ids.size()
				)

				next_citizen_id = int(
					citizen_ids[next_index]
				)

		set_selected_city_citizen(
			next_citizen_id
		)
		return

	var construction_site := (
		CityConstructionSystem.get_city_construction_site_at_tile(
			tile_position
		)
	)

	if is_city_construction_site_selectable(construction_site):
		set_selected_city_construction_site(
			int(construction_site.get("id", -1))
		)
		return

	var city_object := (
		WorldData.get_city_object_at_tile(
			tile_position
		)
	)

	if not is_city_object_selectable(city_object):
		clear_selected_city_entity()

		if WorldData.debug_mode_enabled:
			set_debug_selected_city_tile(tile_position)

		return

	set_selected_city_object(
		int(city_object["id"])
	)


func select_city_object_in_drag_rect() -> void:
	var drag_rect := get_object_selection_world_rect()
	var best_object_id := -1
	var best_area := -1.0

	for city_object in WorldData.city_objects:
		if not is_city_object_selectable(city_object):
			continue

		var object_rect := get_city_object_world_rect(city_object)

		if not drag_rect.intersects(object_rect, true):
			continue

		var object_area := object_rect.size.x * object_rect.size.y

		if best_object_id == -1 or object_area > best_area:
			best_object_id = int(city_object["id"])
			best_area = object_area

	if best_object_id == -1:
		clear_selected_city_entity()
		return

	set_selected_city_object(best_object_id)


func get_object_selection_world_rect() -> Rect2:
	var min_x: float = minf(object_selection_drag_start_world.x, object_selection_drag_current_world.x)
	var min_y: float = minf(object_selection_drag_start_world.y, object_selection_drag_current_world.y)
	var max_x: float = maxf(object_selection_drag_start_world.x, object_selection_drag_current_world.x)
	var max_y: float = maxf(object_selection_drag_start_world.y, object_selection_drag_current_world.y)

	return Rect2(
		Vector2(min_x, min_y),
		Vector2(max_x - min_x, max_y - min_y)
	)

func has_selected_city_entity() -> bool:
	return (
		selected_city_entity_kind
		!= CITY_SELECTION_KIND_NONE
		and selected_city_entity_id >= 0
	)

func has_debug_selected_city_tile() -> bool:
	if city_world == null:
		return false

	if (
		debug_selected_city_tile
		== WorldData.INVALID_CITY_TILE_POSITION
	):
		return false

	return city_world.is_in_bounds(
		debug_selected_city_tile.x,
		debug_selected_city_tile.y
	)


func set_debug_selected_city_tile(
	tile_position: Vector2i
) -> void:
	if not WorldData.debug_mode_enabled:
		return

	if city_world == null:
		return

	if not city_world.is_in_bounds(
		tile_position.x,
		tile_position.y
	):
		return

	if has_selected_city_entity():
		clear_selected_city_entity()

	if debug_selected_city_tile == tile_position:
		return

	debug_selected_city_tile = tile_position
	clear_debug_navigation_result()
	update_debug_panel_text()
	queue_city_background_layer_redraw()
	queue_city_interaction_layer_redraw()


func clear_debug_selected_city_tile() -> void:
	if not has_debug_selected_city_tile():
		return

	debug_selected_city_tile = (
		WorldData.INVALID_CITY_TILE_POSITION
	)
	clear_debug_navigation_result()
	update_debug_panel_text()
	queue_city_background_layer_redraw()
	queue_city_interaction_layer_redraw()

func set_selected_city_entity(
	selection_kind: String,
	entity_id: int
) -> void:
	if entity_id < 0:
		clear_selected_city_entity()
		return

	if selection_kind == CITY_SELECTION_KIND_OBJECT:
		var city_object := (
			WorldData.get_city_object_by_id(
				entity_id
			)
		)

		if not is_city_object_selectable(
			city_object
		):
			clear_selected_city_entity()
			return
	elif selection_kind == CITY_SELECTION_KIND_CITIZEN:
		var citizen := (
			WorldData.get_city_citizen_by_id(
				entity_id
			)
		)

		if citizen.is_empty():
			clear_selected_city_entity()
			return

		if not bool(citizen.get("alive", false)):
			clear_selected_city_entity()
			return
	elif (
		selection_kind
		== CITY_SELECTION_KIND_CONSTRUCTION_SITE
	):
		var construction_site := (
			WorldData.get_city_construction_site_by_id(
				entity_id
			)
		)

		if not is_city_construction_site_selectable(
			construction_site
		):
			clear_selected_city_entity()
			return
	else:
		clear_selected_city_entity()
		return

	if (
		WorldData.debug_mode_enabled
		and has_debug_selected_city_tile()
	):
		clear_debug_selected_city_tile()

	if (
		selected_city_entity_kind == selection_kind
		and selected_city_entity_id == entity_id
	):
		update_selected_entity_panel()
		return

	selected_city_entity_kind = selection_kind
	selected_city_entity_id = entity_id

	refresh_selected_workplace_zone_cache()
	update_selected_entity_panel()
	update_debug_panel_text()
	queue_all_city_render_layers_redraw()


func set_selected_city_object(
	object_id: int
) -> void:
	set_selected_city_entity(
		CITY_SELECTION_KIND_OBJECT,
		object_id
	)


func set_selected_city_citizen(
	citizen_id: int
) -> void:
	set_selected_city_entity(
		CITY_SELECTION_KIND_CITIZEN,
		citizen_id
	)


func set_selected_city_construction_site(
	site_id: int
) -> void:
	set_selected_city_entity(
		CITY_SELECTION_KIND_CONSTRUCTION_SITE,
		site_id
	)


func clear_selected_city_entity() -> void:
	if not has_selected_city_entity():
		update_selected_entity_panel()
		return
	if (
		WorldData.debug_mode_enabled
		and has_debug_selected_city_tile()
	):
		clear_debug_navigation_result()
	selected_city_entity_kind = (
		CITY_SELECTION_KIND_NONE
	)
	selected_city_entity_id = -1

	update_selected_entity_panel()
	update_debug_panel_text()
	queue_all_city_render_layers_redraw()

func is_city_object_selectable(city_object: Dictionary) -> bool:
	return not city_object.is_empty()


func is_city_construction_site_selectable(
	construction_site: Dictionary
) -> bool:
	return not construction_site.is_empty()

func get_city_object_by_id(object_id) -> Dictionary:
	if object_id == null:
		return {}

	if typeof(object_id) != TYPE_INT:
		return {}

	var safe_object_id := int(object_id)

	if safe_object_id < 0:
		return {}

	return WorldData.get_city_object_by_id(safe_object_id)

func get_city_object_display_name(city_object: Dictionary) -> String:
	if city_object.is_empty():
		return "Unknown"

	var object_type: String = str(city_object.get("type", ""))

	return WorldData.get_city_object_display_name_for_type(object_type)

func get_city_object_world_rect(city_object: Dictionary) -> Rect2:
	if city_object.is_empty():
		return Rect2()

	if city_object.has("top_left") and city_object.has("size"):
		var top_left: Vector2i = city_object["top_left"]
		var size_tiles: Vector2i = city_object["size"]

		return Rect2(
			Vector2(
				float(top_left.x * city_tile_size),
				float(top_left.y * city_tile_size)
			),
			Vector2(
				float(size_tiles.x * city_tile_size),
				float(size_tiles.y * city_tile_size)
			)
		)

	return get_city_tile_collection_world_rect(
		WorldData.get_city_object_footprint_tiles(city_object)
	)


func get_city_tile_collection_world_rect(raw_tiles: Array) -> Rect2:
	var has_tile := false
	var minimum_tile := Vector2i.ZERO
	var maximum_tile := Vector2i.ZERO

	for raw_tile in raw_tiles:
		if not raw_tile is Vector2i:
			continue

		var tile_position: Vector2i = raw_tile

		if not has_tile:
			minimum_tile = tile_position
			maximum_tile = tile_position
			has_tile = true
			continue

		minimum_tile.x = mini(minimum_tile.x, tile_position.x)
		minimum_tile.y = mini(minimum_tile.y, tile_position.y)
		maximum_tile.x = maxi(maximum_tile.x, tile_position.x)
		maximum_tile.y = maxi(maximum_tile.y, tile_position.y)

	if not has_tile:
		return Rect2()

	return Rect2(
		Vector2(minimum_tile * city_tile_size),
		Vector2((maximum_tile - minimum_tile + Vector2i.ONE) * city_tile_size)
	)

func handle_road_left_mouse_pressed() -> void:
	if road_preview_tiles.size() > 0 and not is_road_dragging:
		confirm_road_preview()
		return

	start_road_drag_selection()

func handle_road_left_mouse_released() -> void:
	if not is_road_dragging:
		return

	is_road_dragging = false

	print("Road preview ready. Left-click again to confirm, or right-click to cancel.")

func start_road_drag_selection() -> void:
	var start_tile := get_city_tile_from_mouse()

	if start_tile == Vector2i(-1, -1):
		return

	is_road_dragging = true
	road_drag_start_tile = start_tile
	road_drag_current_tile = start_tile

	rebuild_road_preview_rectangle(road_drag_start_tile, road_drag_current_tile)

	queue_city_interaction_layer_redraw()

func update_road_drag_selection() -> void:
	if not is_road_dragging:
		return

	var current_tile := get_city_tile_from_mouse()

	if current_tile == Vector2i(-1, -1):
		return

	if current_tile == road_drag_current_tile:
		return

	road_drag_current_tile = current_tile

	rebuild_road_preview_rectangle(road_drag_start_tile, road_drag_current_tile)

	queue_city_interaction_layer_redraw()

func rebuild_road_preview_rectangle(start_tile: Vector2i, end_tile: Vector2i) -> void:
	road_preview_tiles.clear()
	road_preview_lookup.clear()

	if start_tile == Vector2i(-1, -1) or end_tile == Vector2i(-1, -1):
		return

	var min_x: int = min(start_tile.x, end_tile.x)
	var max_x: int = max(start_tile.x, end_tile.x)
	var min_y: int = min(start_tile.y, end_tile.y)
	var max_y: int = max(start_tile.y, end_tile.y)

	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var tile_position := Vector2i(x, y)

			if road_preview_lookup.has(tile_position):
				continue

			if not WorldData.can_place_city_road_tile(city_world, tile_position):
				continue

			road_preview_lookup[tile_position] = true
			road_preview_tiles.append(tile_position)

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
	if road_preview_tiles.is_empty():
		print("No road tiles selected.")
		return

	var construction_sites := CityConstructionSystemScript.create_road_sites(
		road_preview_tiles,
		"player",
		city_world
	)
	var placed_tile_count := construction_sites.size()

	if construction_sites.is_empty():
		print("No valid road tiles could be placed.")
		road_preview_tiles.clear()
		road_preview_lookup.clear()
		queue_city_interaction_layer_redraw()
		return

	print(
		"Queued ",
		placed_tile_count,
		" independent road-tile blueprints."
	)

	is_road_placement_active = true
	is_road_dragging = false
	road_preview_tiles.clear()
	road_preview_lookup.clear()
	road_drag_start_tile = Vector2i(-1, -1)
	road_drag_current_tile = Vector2i(-1, -1)

	if build_option_button != null:
		build_option_button.visible = true

	if road_cursor_icon != null:
		road_cursor_icon.visible = true
		update_road_cursor_icon_position()

	set_road_option_selected(true)

	queue_city_background_layer_redraw()
	queue_city_interaction_layer_redraw()

#endregion

#region Map texture cache

func setup_city_texture_cache() -> void:
	city_texture_cache.setup({
		"owner": self,
		"label": "City",
		"rows_per_frame": 16,
		"color_provider": Callable(
			self,
			"get_city_tile_color_for_mode"
		),
		"all_colors_provider": Callable(
			self,
			"populate_all_city_tile_colors"
		),
		"modes_provider": Callable(
			self,
			"get_all_city_view_modes"
		),
		"mode_name_provider": Callable(
			self,
			"get_city_map_mode_name"
		),
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
	city_terrain_texture = city_texture_cache.rebuild(city_world, city_view_mode)


func apply_cached_city_map_mode_texture() -> void:
	if city_texture_cache == null:
		setup_city_texture_cache()

	city_terrain_texture = city_texture_cache.get_texture_for_mode(city_world, city_view_mode)


#endregion

#region Rendering and tile drawing

func setup_city_natural_feature_rendering() -> void:
	if shared_city_natural_feature_white_texture == null:
		var white_image := Image.create(
			1,
			1,
			false,
			Image.FORMAT_RGBA8
		)
		white_image.fill(Color.WHITE)
		shared_city_natural_feature_white_texture = (
			ImageTexture.create_from_image(white_image)
		)

	if shared_city_tree_mesh == null:
		shared_city_tree_mesh = create_city_natural_feature_mesh(
			PackedVector2Array([
				Vector2(-0.18, -0.50),
				Vector2(0.10, -0.35),
				Vector2(0.48, -0.30),
				Vector2(0.24, 0.00),
				Vector2(0.50, 0.43),
				Vector2(0.10, 0.39),
				Vector2(-0.18, 0.50),
				Vector2(-0.30, 0.22),
				Vector2(-0.50, 0.00),
				Vector2(-0.25, -0.17),
			])
		)

	if shared_city_rock_mesh == null:
		shared_city_rock_mesh = create_city_natural_feature_mesh(
			PackedVector2Array([
				Vector2(-0.5, -0.5),
				Vector2(0.5, -0.5),
				Vector2(0.5, 0.5),
				Vector2(-0.5, 0.5),
			])
		)

	city_natural_feature_white_texture = (
		shared_city_natural_feature_white_texture
	)
	city_tree_mesh = shared_city_tree_mesh
	city_rock_mesh = shared_city_rock_mesh

	city_natural_feature_cache_reused_on_entry = (
		try_load_city_natural_feature_cache()
	)

	if not city_natural_feature_cache_reused_on_entry:
		rebuild_city_natural_feature_multimeshes()

	if city_world != null:
		observed_city_tile_data_version = (
			city_world.tile_data_version
		)
		observed_city_surface_feature_change_version = (
			city_world.city_surface_feature_change_version
		)
		city_world.consume_city_surface_feature_changes()


func try_load_city_natural_feature_cache() -> bool:
	if city_world == null:
		return false
	if (
		cached_city_natural_feature_source_instance_id
		!= city_world.get_instance_id()
		or cached_city_natural_feature_tile_data_version
		!= city_world.tile_data_version
		or cached_city_natural_feature_change_version
		!= city_world.city_surface_feature_change_version
		or cached_city_natural_feature_seed != city_seed
		or cached_city_natural_feature_tile_size != city_tile_size
		or cached_city_tree_multimesh == null
		or cached_city_rock_multimesh == null
	):
		return false

	city_tree_multimesh = cached_city_tree_multimesh
	city_rock_multimesh = cached_city_rock_multimesh
	city_tree_multimesh_index_by_tile = (
		cached_city_tree_index_by_tile
	)
	city_tree_multimesh_tile_by_index = (
		cached_city_tree_tile_by_index
	)
	city_rock_multimesh_index_by_tile = (
		cached_city_rock_index_by_tile
	)
	city_rock_multimesh_tile_by_index = (
		cached_city_rock_tile_by_index
	)
	return true


func store_city_natural_feature_cache() -> void:
	if city_world == null:
		return

	cached_city_natural_feature_source_instance_id = (
		city_world.get_instance_id()
	)
	cached_city_natural_feature_tile_data_version = (
		city_world.tile_data_version
	)
	cached_city_natural_feature_change_version = (
		city_world.city_surface_feature_change_version
	)
	cached_city_natural_feature_seed = city_seed
	cached_city_natural_feature_tile_size = city_tile_size
	cached_city_tree_multimesh = city_tree_multimesh
	cached_city_rock_multimesh = city_rock_multimesh
	cached_city_tree_index_by_tile = (
		city_tree_multimesh_index_by_tile
	)
	cached_city_tree_tile_by_index = (
		city_tree_multimesh_tile_by_index
	)
	cached_city_rock_index_by_tile = (
		city_rock_multimesh_index_by_tile
	)
	cached_city_rock_tile_by_index = (
		city_rock_multimesh_tile_by_index
	)


func create_city_natural_feature_mesh(
	points: PackedVector2Array
) -> ArrayMesh:
	var mesh := ArrayMesh.new()

	if points.size() < 3:
		return mesh

	var triangle_indices := Geometry2D.triangulate_polygon(
		points
	)

	if triangle_indices.is_empty():
		push_error(
			"Could not triangulate a city natural-feature polygon."
		)
		return mesh

	var vertices := PackedVector3Array()
	var vertex_colors := PackedColorArray()
	var texture_coordinates := PackedVector2Array()

	for point in points:
		vertices.append(Vector3(point.x, point.y, 0.0))
		vertex_colors.append(Color.WHITE)
		texture_coordinates.append(point + Vector2(0.5, 0.5))

	var surface_arrays: Array = []
	surface_arrays.resize(Mesh.ARRAY_MAX)
	surface_arrays[Mesh.ARRAY_VERTEX] = vertices
	surface_arrays[Mesh.ARRAY_COLOR] = vertex_colors
	surface_arrays[Mesh.ARRAY_TEX_UV] = texture_coordinates
	surface_arrays[Mesh.ARRAY_INDEX] = triangle_indices

	mesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES,
		surface_arrays
	)
	return mesh


func create_city_natural_feature_multimesh(
	mesh: Mesh,
	instance_count: int
) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = maxi(instance_count, 0)
	multimesh.visible_instance_count = maxi(instance_count, 0)
	return multimesh


func rebuild_city_natural_feature_multimeshes() -> void:
	city_tree_multimesh_index_by_tile.clear()
	city_tree_multimesh_tile_by_index.clear()
	city_rock_multimesh_index_by_tile.clear()
	city_rock_multimesh_tile_by_index.clear()

	if city_world == null:
		city_tree_multimesh = null
		city_rock_multimesh = null
		return

	# Collect feature positions while counting them. The previous implementation
	# traversed every city tile twice, which doubled a 331,776-tile scan during
	# every city-scene entry.
	var tree_tiles: Array[Vector2i] = []
	var rock_tiles: Array[Vector2i] = []

	for y in range(city_world.height):
		var row: Array = city_world.tiles[y]

		for x in range(city_world.width):
			match WorldData.get_city_surface_feature(row[x]):
				WorldData.CITY_SURFACE_FEATURE_TREE:
					tree_tiles.append(Vector2i(x, y))

				WorldData.CITY_SURFACE_FEATURE_ROCK:
					rock_tiles.append(Vector2i(x, y))

	city_tree_multimesh = create_city_natural_feature_multimesh(
		city_tree_mesh,
		tree_tiles.size()
	)
	city_rock_multimesh = create_city_natural_feature_multimesh(
		city_rock_mesh,
		rock_tiles.size()
	)

	var tile_size_float := float(city_tile_size)
	var rock_color := get_resource_color(WorldData.RESOURCE_STONE)

	for tree_index in range(tree_tiles.size()):
		var tree_tile := tree_tiles[tree_index]
		var tree_data: Dictionary = city_world.tiles[tree_tile.y][tree_tile.x]
		var tile_center := Vector2(
			(float(tree_tile.x) + 0.5) * tile_size_float,
			(float(tree_tile.y) + 0.5) * tile_size_float
		)
		var rotation_ratio := (
			CityWorldGeneratorScript.get_deterministic_tile_unit_value(
				city_seed,
				tree_tile.x,
				tree_tile.y,
				CITY_TREE_ROTATION_SALT
			)
		)
		var scale_ratio := (
			CityWorldGeneratorScript.get_deterministic_tile_unit_value(
				city_seed,
				tree_tile.x,
				tree_tile.y,
				CITY_TREE_SCALE_SALT
			)
		)
		var color_ratio := (
			CityWorldGeneratorScript.get_deterministic_tile_unit_value(
				city_seed,
				tree_tile.x,
				tree_tile.y,
				CITY_TREE_COLOR_SALT
			)
		)
		var canopy_scale := (
			tile_size_float
			* CITY_TREE_CANOPY_TILE_SCALE
			* lerpf(
				CITY_TREE_MIN_SCALE_VARIATION,
				CITY_TREE_MAX_SCALE_VARIATION,
				scale_ratio
			)
		)

		city_tree_multimesh.set_instance_transform_2d(
			tree_index,
			Transform2D(
				rotation_ratio * TAU,
				Vector2.ONE * canopy_scale,
				0.0,
				tile_center
			)
		)
		city_tree_multimesh.set_instance_color(
			tree_index,
			get_city_tree_canopy_color(tree_data, color_ratio)
		)
		city_tree_multimesh_index_by_tile[tree_tile] = tree_index
		city_tree_multimesh_tile_by_index.append(tree_tile)

	for rock_index in range(rock_tiles.size()):
		var rock_tile := rock_tiles[rock_index]
		var tile_center := Vector2(
			(float(rock_tile.x) + 0.5) * tile_size_float,
			(float(rock_tile.y) + 0.5) * tile_size_float
		)
		var offset_x_ratio := (
			CityWorldGeneratorScript.get_deterministic_tile_unit_value(
				city_seed,
				rock_tile.x,
				rock_tile.y,
				CITY_ROCK_OFFSET_X_SALT
			)
		)
		var offset_y_ratio := (
			CityWorldGeneratorScript.get_deterministic_tile_unit_value(
				city_seed,
				rock_tile.x,
				rock_tile.y,
				CITY_ROCK_OFFSET_Y_SALT
			)
		)
		var rock_offset := Vector2(
			lerpf(
				-CITY_ROCK_MAX_CENTER_OFFSET_TILES,
				CITY_ROCK_MAX_CENTER_OFFSET_TILES,
				offset_x_ratio
			),
			lerpf(
				-CITY_ROCK_MAX_CENTER_OFFSET_TILES,
				CITY_ROCK_MAX_CENTER_OFFSET_TILES,
				offset_y_ratio
			)
		) * tile_size_float
		var rock_scale := tile_size_float * CITY_ROCK_MARKER_TILE_SCALE

		city_rock_multimesh.set_instance_transform_2d(
			rock_index,
			Transform2D(
				0.0,
				Vector2.ONE * rock_scale,
				0.0,
				tile_center + rock_offset
			)
		)
		city_rock_multimesh.set_instance_color(rock_index, rock_color)
		city_rock_multimesh_index_by_tile[rock_tile] = rock_index
		city_rock_multimesh_tile_by_index.append(rock_tile)

	store_city_natural_feature_cache()


func get_city_tree_canopy_color(
	tile: Dictionary,
	color_ratio: float
) -> Color:
	var dark_color := CITY_TREE_DARK_COLOR
	var light_color := CITY_TREE_LIGHT_COLOR

	match str(tile.get("biome", "")):
		WorldData.BIOME_TAIGA:
			dark_color = CITY_TAIGA_TREE_DARK_COLOR
			light_color = CITY_TAIGA_TREE_LIGHT_COLOR

		WorldData.BIOME_JUNGLE:
			dark_color = CITY_JUNGLE_TREE_DARK_COLOR
			light_color = CITY_JUNGLE_TREE_LIGHT_COLOR

	return dark_color.lerp(light_color, color_ratio)


func apply_city_surface_feature_changes(
	changes: Array[Dictionary]
) -> bool:
	for change in changes:
		var raw_tile_position = change.get(
			"tile_position",
			WorldData.INVALID_CITY_TILE_POSITION
		)
		var previous_feature := str(
			change.get(
				"previous_feature",
				WorldData.CITY_SURFACE_FEATURE_NONE
			)
		)
		var current_feature := str(
			change.get(
				"current_feature",
				WorldData.CITY_SURFACE_FEATURE_NONE
			)
		)

		if (
			not raw_tile_position is Vector2i
			or current_feature
			!= WorldData.CITY_SURFACE_FEATURE_NONE
		):
			return false

		if not remove_city_natural_feature_multimesh_instance(
			previous_feature,
			raw_tile_position
		):
			return false

	return true


func remove_city_natural_feature_multimesh_instance(
	surface_feature: String,
	tile_position: Vector2i
) -> bool:
	var multimesh: MultiMesh
	var index_by_tile: Dictionary
	var tile_by_index: Array[Vector2i]

	match surface_feature:
		WorldData.CITY_SURFACE_FEATURE_TREE:
			multimesh = city_tree_multimesh
			index_by_tile = city_tree_multimesh_index_by_tile
			tile_by_index = city_tree_multimesh_tile_by_index

		WorldData.CITY_SURFACE_FEATURE_ROCK:
			multimesh = city_rock_multimesh
			index_by_tile = city_rock_multimesh_index_by_tile
			tile_by_index = city_rock_multimesh_tile_by_index

		_:
			return false

	if multimesh == null or not index_by_tile.has(tile_position):
		return false

	var removed_index := int(index_by_tile[tile_position])
	var last_index := tile_by_index.size() - 1

	if removed_index < 0 or removed_index > last_index:
		return false

	if removed_index != last_index:
		var last_tile := tile_by_index[last_index]
		multimesh.set_instance_transform_2d(
			removed_index,
			multimesh.get_instance_transform_2d(last_index)
		)
		multimesh.set_instance_color(
			removed_index,
			multimesh.get_instance_color(last_index)
		)
		index_by_tile[last_tile] = removed_index
		tile_by_index[removed_index] = last_tile

	index_by_tile.erase(tile_position)
	tile_by_index.pop_back()
	multimesh.visible_instance_count = tile_by_index.size()
	return true


func draw_city_rocks(draw_target: CanvasItem) -> void:
	if (
		city_rock_multimesh == null
		or city_rock_multimesh.instance_count <= 0
		or city_natural_feature_white_texture == null
	):
		return

	draw_target.draw_multimesh(
		city_rock_multimesh,
		city_natural_feature_white_texture
	)


func should_draw_city_trees() -> bool:
	return city_view_mode != MapVisuals.ViewMode.RESOURCES


func draw_city_trees(draw_target: CanvasItem) -> void:
	if not should_draw_city_trees():
		return

	if (
		city_tree_multimesh == null
		or city_tree_multimesh.instance_count <= 0
		or city_natural_feature_white_texture == null
	):
		return

	draw_target.draw_multimesh(
		city_tree_multimesh,
		city_natural_feature_white_texture
	)


func create_city_render_layers() -> void:
	city_background_render_layer = CityRenderLayerScript.new()
	city_background_render_layer.name = "CityBackgroundRenderLayer"
	city_background_render_layer.setup(
		Callable(self, "draw_city_background_layer")
	)
	add_child(city_background_render_layer)

	city_citizen_render_layer = CityRenderLayerScript.new()
	city_citizen_render_layer.name = "CityCitizenRenderLayer"
	city_citizen_render_layer.setup(
		Callable(self, "draw_city_citizen_layer")
	)
	add_child(city_citizen_render_layer)

	city_interaction_render_layer = CityRenderLayerScript.new()
	city_interaction_render_layer.name = "CityInteractionRenderLayer"
	city_interaction_render_layer.setup(
		Callable(self, "draw_city_interaction_layer")
	)
	add_child(city_interaction_render_layer)


func queue_city_background_layer_redraw() -> void:
	if city_background_render_layer != null:
		city_background_render_layer.queue_redraw()


func queue_city_citizen_layer_redraw() -> void:
	if city_citizen_render_layer != null:
		city_citizen_render_layer.queue_redraw()


func queue_city_interaction_layer_redraw() -> void:
	if city_interaction_render_layer != null:
		city_interaction_render_layer.queue_redraw()


func queue_all_city_render_layers_redraw() -> void:
	queue_city_background_layer_redraw()
	queue_city_citizen_layer_redraw()
	queue_city_interaction_layer_redraw()


func draw_city_background_layer(draw_target: CanvasItem) -> void:
	if city_world == null:
		return

	if city_terrain_texture != null:
		draw_target.draw_texture_rect(
			city_terrain_texture,
			Rect2(
				0.0,
				0.0,
				float(city_world.width * city_tile_size),
				float(city_world.height * city_tile_size)
			),
			false
		)

	draw_city_rocks(draw_target)
	draw_selected_workplace_zone_background(draw_target)
	draw_active_workplace_zone_background(draw_target)
	draw_city_objects(draw_target)
	draw_city_roads(draw_target)
	draw_city_construction_sites(draw_target)
	draw_debug_navigation_path(draw_target)
	draw_city_ground_piles(draw_target)


func draw_city_citizen_layer(draw_target: CanvasItem) -> void:
	if city_world == null:
		return

	draw_city_citizens(draw_target)
	draw_city_trees(draw_target)
	draw_selected_city_citizen_highlight(draw_target)


func draw_city_interaction_layer(draw_target: CanvasItem) -> void:
	if city_world == null:
		return

	draw_city_player_command_overlay(draw_target)
	draw_debug_selected_city_tile_highlight(draw_target)
	draw_selected_city_object_highlight(draw_target)
	draw_selected_city_construction_site_highlight(draw_target)
	draw_city_object_debug_names(draw_target)
	draw_active_city_object_placement_preview(draw_target)
	draw_hovered_city_tile_highlight(draw_target)
	draw_road_preview(draw_target)


func draw_city_player_command_overlay(draw_target: CanvasItem) -> void:
	if city_world == null:
		return

	if is_city_player_command_cancel_mode_active:
		# Every active natural-resource target remains visible while the
		# destructive tool is armed. Construction previews keep their normal
		# phase rendering underneath this interaction-layer overlay.
		for raw_command in CityWorkSystem.get_city_player_command_snapshot():
			if not raw_command is Dictionary:
				continue

			var raw_command_tile = raw_command.get(
				"tile_position",
				WorldData.INVALID_CITY_TILE_POSITION
			)

			if not raw_command_tile is Vector2i:
				continue

			var command_tile_rect := get_city_tile_world_rect(
				raw_command_tile
			)
			draw_target.draw_rect(
				command_tile_rect,
				CITY_PLAYER_COMMAND_REMOVE_PREVIEW_FILL,
				true
			)
			CityRenderLayerScript.draw_inner_box_border({
				"draw_target": draw_target,
				"rect": command_tile_rect,
				"border_color": CITY_PLAYER_COMMAND_REMOVE_PREVIEW_BORDER,
				"border_width": float(city_tile_size) * 0.08
			})

		var cancel_preview_tiles := city_player_command_drag_preview_tiles

		if not is_city_player_command_dragging:
			cancel_preview_tiles = (
				CityWorkSystemScript.get_cancel_preview_tiles(
					[hovered_city_tile]
				)
			)

		for tile_position in cancel_preview_tiles:
			var cancel_tile_rect := get_city_tile_world_rect(tile_position)
			draw_target.draw_rect(
				cancel_tile_rect,
				CITY_PLAYER_COMMAND_REMOVE_PREVIEW_FILL,
				true
			)
			CityRenderLayerScript.draw_inner_box_border({
				"draw_target": draw_target,
				"rect": cancel_tile_rect,
				"border_color": CITY_PLAYER_COMMAND_REMOVE_PREVIEW_BORDER,
				"border_width": float(city_tile_size) * 0.08
			})
		return

	if not is_city_player_command_mode_active():
		return

	var world_rect := Rect2(
		Vector2.ZERO,
		Vector2(
			float(city_world.width * city_tile_size),
			float(city_world.height * city_tile_size)
		)
	)
	draw_target.draw_rect(
		world_rect,
		CITY_PLAYER_COMMAND_DARKEN_COLOR,
		true
	)

	var command_snapshot := CityWorkSystem.get_city_player_command_snapshot()

	for raw_command in command_snapshot:
		if not raw_command is Dictionary:
			continue

		var command: Dictionary = raw_command

		if str(command.get("type", "")) != active_city_player_command_type:
			continue

		var raw_tile_position = command.get(
			"tile_position",
			WorldData.INVALID_CITY_TILE_POSITION
		)

		if not raw_tile_position is Vector2i:
			continue

		var tile_position: Vector2i = raw_tile_position
		var tile_rect := get_city_tile_world_rect(tile_position)
		draw_target.draw_rect(
			tile_rect,
			CITY_PLAYER_COMMAND_HIGHLIGHT_FILL,
			true
		)

	draw_active_city_player_command_features(draw_target)

	for raw_command in command_snapshot:
		if not raw_command is Dictionary:
			continue

		var command: Dictionary = raw_command

		if str(command.get("type", "")) != active_city_player_command_type:
			continue

		var raw_tile_position = command.get(
			"tile_position",
			WorldData.INVALID_CITY_TILE_POSITION
		)

		if not raw_tile_position is Vector2i:
			continue

		var border_color := CITY_PLAYER_COMMAND_HIGHLIGHT_BORDER

		if int(command.get("claimed_citizen_id", -1)) > 0:
			border_color = CITY_PLAYER_COMMAND_CLAIMED_BORDER

		CityRenderLayerScript.draw_inner_box_border({
			"draw_target": draw_target,
			"rect": get_city_tile_world_rect(raw_tile_position),
			"border_color": border_color,
			"border_width": float(city_tile_size) * 0.08
		})

	var preview_fill := CITY_PLAYER_COMMAND_PREVIEW_FILL
	var preview_border := CITY_PLAYER_COMMAND_PREVIEW_BORDER

	if city_player_command_drag_removing:
		preview_fill = CITY_PLAYER_COMMAND_REMOVE_PREVIEW_FILL
		preview_border = CITY_PLAYER_COMMAND_REMOVE_PREVIEW_BORDER

	for tile_position in city_player_command_drag_preview_tiles:
		var tile_rect := get_city_tile_world_rect(tile_position)
		draw_target.draw_rect(tile_rect, preview_fill, true)
		CityRenderLayerScript.draw_inner_box_border({
			"draw_target": draw_target,
			"rect": tile_rect,
			"border_color": preview_border,
			"border_width": float(city_tile_size) * 0.08
		})


func draw_active_city_player_command_features(
	draw_target: CanvasItem
) -> void:
	if city_natural_feature_white_texture == null:
		return

	if (
		active_city_player_command_type
		== WorldData.CITY_PLAYER_COMMAND_TYPE_CHOP_TREE
	):
		if (
			city_tree_multimesh != null
			and city_tree_multimesh.instance_count > 0
		):
			draw_target.draw_multimesh(
				city_tree_multimesh,
				city_natural_feature_white_texture
			)
	elif (
		active_city_player_command_type
		== WorldData.CITY_PLAYER_COMMAND_TYPE_COLLECT_ROCK
	):
		if (
			city_rock_multimesh != null
			and city_rock_multimesh.instance_count > 0
		):
			draw_target.draw_multimesh(
				city_rock_multimesh,
				city_natural_feature_white_texture
			)


func get_city_tile_world_rect(tile_position: Vector2i) -> Rect2:
	return Rect2(
		Vector2(
			float(tile_position.x * city_tile_size),
			float(tile_position.y * city_tile_size)
		),
		Vector2.ONE * float(city_tile_size)
	)


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

func get_city_citizen_world_rect(
	citizen: Dictionary
) -> Rect2:
	if citizen.is_empty():
		return Rect2()

	var raw_position = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if not raw_position is Vector2i:
		return Rect2()

	var city_tile_position: Vector2i = (
		raw_position
	)

	if city_world == null:
		return Rect2()

	if not city_world.is_in_bounds(
		city_tile_position.x,
		city_tile_position.y
	):
		return Rect2()

	var visual_tile_position: Vector2 = (
		city_citizen_movement_presentation.get_visual_tile_position(
			citizen
		)
	)

	var marker_side_length := (
		float(city_tile_size)
		* CITY_CITIZEN_MARKER_TILE_SCALE
	)
	var marker_size := Vector2(
		marker_side_length,
		marker_side_length
	)
	var tile_center := Vector2(
		(
			visual_tile_position.x
			+ 0.5
		)
		* float(city_tile_size),
		(
			visual_tile_position.y
			+ 0.5
		)
		* float(city_tile_size)
	)

	return Rect2(
		tile_center - marker_size * 0.5,
		marker_size
	)


func draw_city_citizens(draw_target: CanvasItem) -> void:
	if city_world == null:
		return

	city_citizen_draw_buffer.clear()
	city_citizen_rect_draw_buffer.clear()

	for raw_citizen in WorldData.city_citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen

		if not bool(citizen.get("alive", false)):
			continue

		var marker_rect := (
			get_city_citizen_world_rect(
				citizen
			)
		)

		if (
			marker_rect.size.x <= 0.0
			or marker_rect.size.y <= 0.0
		):
			continue

		draw_target.draw_rect(
			marker_rect,
			CITY_CITIZEN_MARKER_COLOR,
			true
		)

		city_citizen_draw_buffer.append(citizen)
		city_citizen_rect_draw_buffer.append(marker_rect)

	for citizen_index in range(
		city_citizen_draw_buffer.size()
	):
		draw_city_citizen_haul_cargo_marker(
			draw_target,
			city_citizen_draw_buffer[citizen_index],
			city_citizen_rect_draw_buffer[citizen_index]
		)


func draw_city_citizen_haul_cargo_marker(
	draw_target: CanvasItem,
	citizen: Dictionary,
	citizen_rect: Rect2
) -> void:
	var citizen_id := int(citizen.get("id", -1))
	var cargo_resources := (
		WorldData.get_city_citizen_haul_cargo_resources(citizen_id)
	)
	var cargo_amount := (
		WorldData.get_city_citizen_haul_cargo_amount(citizen_id)
	)

	if cargo_amount <= 0 or cargo_resources.is_empty():
		return

	var cargo_size := Vector2(
		citizen_rect.size.x * CITY_HAUL_CARGO_MARKER_CITIZEN_SCALE,
		citizen_rect.size.y * CITY_HAUL_CARGO_MARKER_CITIZEN_SCALE
	)
	var upper_right_corner := Vector2(
		citizen_rect.end.x,
		citizen_rect.position.y
	)
	var cargo_rect := Rect2(
		upper_right_corner - cargo_size * 0.5,
		cargo_size
	)
	var resource_names: Array = cargo_resources.keys()
	resource_names.sort()
	var drawn_amount := 0

	for raw_resource in resource_names:
		var resource := str(raw_resource)
		var resource_amount := maxi(
			int(cargo_resources.get(raw_resource, 0)),
			0
		)

		if resource_amount <= 0:
			continue

		var start_ratio := float(drawn_amount) / float(cargo_amount)
		drawn_amount += resource_amount
		var end_ratio := float(drawn_amount) / float(cargo_amount)
		var segment_rect := Rect2(
			Vector2(
				cargo_rect.position.x + cargo_rect.size.x * start_ratio,
				cargo_rect.position.y
			),
			Vector2(
				cargo_rect.size.x * (end_ratio - start_ratio),
				cargo_rect.size.y
			)
		)
		draw_target.draw_rect(
			segment_rect,
			get_resource_color(resource),
			true
		)


func draw_city_ground_piles(draw_target: CanvasItem) -> void:
	if city_world == null:
		return

	var ground_piles := WorldData.get_city_ground_pile_snapshot()
	var pile_count_by_tile: Dictionary = {}

	for raw_ground_pile in ground_piles:
		if not raw_ground_pile is Dictionary:
			continue

		var raw_tile_position = raw_ground_pile.get(
			"tile_position",
			WorldData.INVALID_CITY_TILE_POSITION
		)

		if not raw_tile_position is Vector2i:
			continue

		pile_count_by_tile[raw_tile_position] = (
			int(pile_count_by_tile.get(raw_tile_position, 0)) + 1
		)

	var next_slot_by_tile: Dictionary = {}
	var multiple_pile_offsets := [
		Vector2(-0.075, -0.075),
		Vector2(0.075, -0.075),
		Vector2(-0.075, 0.075),
		Vector2(0.075, 0.075),
	]

	for raw_ground_pile in ground_piles:
		if not raw_ground_pile is Dictionary:
			continue

		var ground_pile: Dictionary = raw_ground_pile
		var raw_tile_position = ground_pile.get(
			"tile_position",
			WorldData.INVALID_CITY_TILE_POSITION
		)
		var resource := str(
			ground_pile.get("resource_type", WorldData.RESOURCE_NONE)
		)

		if (
			not raw_tile_position is Vector2i
			or not WorldData.is_city_resource_type(resource)
		):
			continue

		var tile_position: Vector2i = raw_tile_position
		var pile_count := int(pile_count_by_tile.get(tile_position, 1))
		var slot_index := int(next_slot_by_tile.get(tile_position, 0))
		next_slot_by_tile[tile_position] = slot_index + 1
		var marker_scale := CITY_GROUND_PILE_MARKER_TILE_SCALE
		var center_offset := Vector2.ZERO

		if pile_count > 1:
			marker_scale = 0.11
			center_offset = multiple_pile_offsets[
				posmod(slot_index, multiple_pile_offsets.size())
			]

		var tile_center := Vector2(
			(float(tile_position.x) + 0.5) * float(city_tile_size),
			(float(tile_position.y) + 0.5) * float(city_tile_size)
		)
		tile_center += center_offset * float(city_tile_size)
		var marker_side := float(city_tile_size) * marker_scale
		var marker_rect := Rect2(
			tile_center - Vector2.ONE * marker_side * 0.5,
			Vector2.ONE * marker_side
		)

		draw_target.draw_rect(
			marker_rect,
			get_resource_color(resource),
			true
		)


func draw_debug_navigation_path(draw_target: CanvasItem) -> void:
	if not WorldData.debug_mode_enabled:
		return

	if debug_navigation_path.is_empty():
		return

	var path_points := PackedVector2Array()
	var tile_size_vector := Vector2(
		float(city_tile_size),
		float(city_tile_size)
	)

	for raw_path_tile in debug_navigation_path:
		if not raw_path_tile is Vector2i:
			continue

		var path_tile: Vector2i = raw_path_tile
		var tile_top_left := Vector2(
			float(path_tile.x * city_tile_size),
			float(path_tile.y * city_tile_size)
		)
		var tile_center := (
			tile_top_left
			+ tile_size_vector * 0.5
		)

		draw_target.draw_rect(
			Rect2(
				tile_top_left,
				tile_size_vector
			),
			DEBUG_NAVIGATION_PATH_FILL_COLOR,
			true
		)

		path_points.append(tile_center)

	if path_points.size() >= 2:
		draw_target.draw_polyline(
			path_points,
			DEBUG_NAVIGATION_PATH_LINE_COLOR,
			maxf(
				float(city_tile_size) * 0.18,
				0.25
			),
			false
		)

func draw_city_object_debug_names(
	draw_target: CanvasItem
) -> void:
	if not WorldData.debug_mode_enabled:
		return

	var font: Font = ThemeDB.fallback_font

	if font == null:
		return

	var pixels_per_world_unit := get_debug_pixels_per_world_unit()

	if pixels_per_world_unit <= 0.0:
		return

	var world_units_per_screen_pixel := 1.0 / pixels_per_world_unit

	for city_object in WorldData.city_objects:
		if city_object.is_empty():
			continue

		var object_type: String = str(city_object.get("type", ""))

		if object_type == WorldData.CITY_OBJECT_ROAD:
			continue

		var rect: Rect2 = get_city_object_world_rect(city_object)

		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue

		var object_name := get_city_object_display_name(city_object)

		if object_name == "":
			continue

		var label_center := get_city_object_debug_label_center(city_object, rect)
		var object_screen_size := rect.size * pixels_per_world_unit

		draw_centered_city_object_debug_name({
			"draw_target": draw_target,
			"label_center": label_center,
			"object_screen_size": object_screen_size,
			"object_name": object_name,
			"font": font,
			"world_units_per_screen_pixel": world_units_per_screen_pixel,
		})

func draw_centered_city_object_debug_name(
	values: Dictionary
) -> void:
	var draw_target: CanvasItem = values.get("draw_target")
	var label_center: Vector2 = values.get("label_center", Vector2.ZERO)
	var object_screen_size: Vector2 = values.get(
		"object_screen_size",
		Vector2.ZERO
	)
	var object_name := str(values.get("object_name", ""))
	var font: Font = values.get("font")
	var world_units_per_screen_pixel := float(
		values.get("world_units_per_screen_pixel", 1.0)
	)
	var font_size := get_debug_city_object_name_font_size(
		object_name,
		object_screen_size,
		font
	)

	if font_size < DEBUG_CITY_OBJECT_NAME_MIN_FONT_SIZE:
		return

	var text_size := font.get_string_size(
		object_name,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size
	)

	var ascent := font.get_ascent(font_size)
	var descent := font.get_descent(font_size)

	var background_rect := Rect2(
		-text_size * 0.5 - DEBUG_CITY_OBJECT_NAME_PADDING,
		text_size + DEBUG_CITY_OBJECT_NAME_PADDING * 2.0
	)

	var text_position := Vector2(
		-text_size.x * 0.5,
		(ascent - descent) * 0.5
	)

	draw_target.draw_set_transform(
		label_center,
		0.0,
		Vector2(world_units_per_screen_pixel, world_units_per_screen_pixel)
	)

	draw_target.draw_rect(
		background_rect,
		DEBUG_CITY_OBJECT_NAME_BACKGROUND_COLOR,
		true
	)

	draw_target.draw_string(
		font,
		text_position + Vector2(1.0, 1.0),
		object_name,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		DEBUG_CITY_OBJECT_NAME_SHADOW_COLOR
	)

	draw_target.draw_string(
		font,
		text_position,
		object_name,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		DEBUG_CITY_OBJECT_NAME_TEXT_COLOR
	)

	draw_target.draw_set_transform(
		Vector2.ZERO,
		0.0,
		Vector2.ONE
	)

func get_debug_pixels_per_world_unit() -> float:
	var canvas_transform := get_canvas_transform()
	var canvas_scale := canvas_transform.get_scale()

	var x_scale: float = abs(canvas_scale.x)
	var y_scale: float = abs(canvas_scale.y)

	if x_scale <= 0.0 or y_scale <= 0.0:
		return 1.0

	return (x_scale + y_scale) * 0.5


func get_debug_city_object_name_font_size(
	object_name: String,
	object_screen_size: Vector2,
	font: Font
) -> int:
	var target_font_size := DEBUG_CITY_OBJECT_NAME_TARGET_FONT_SIZE

	var text_size := font.get_string_size(
		object_name,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		target_font_size
	)

	var max_label_size := Vector2(
		object_screen_size.x * DEBUG_CITY_OBJECT_NAME_MAX_WIDTH_RATIO,
		object_screen_size.y * DEBUG_CITY_OBJECT_NAME_MAX_HEIGHT_RATIO
	)

	var padded_text_size := text_size + DEBUG_CITY_OBJECT_NAME_PADDING * 2.0

	if padded_text_size.x <= 0.0 or padded_text_size.y <= 0.0:
		return target_font_size

	var width_fit := max_label_size.x / padded_text_size.x
	var height_fit := max_label_size.y / padded_text_size.y
	var fit_scale: float = min(1.0, width_fit, height_fit)

	var fitted_font_size := int(floor(float(target_font_size) * fit_scale))

	if fitted_font_size < DEBUG_CITY_OBJECT_NAME_MIN_FONT_SIZE:
		return 0

	return fitted_font_size


func get_city_object_debug_label_center(city_object: Dictionary, fallback_rect: Rect2) -> Vector2:
	var footprint_tiles := get_city_object_debug_footprint_tiles(city_object)

	if not footprint_tiles.is_empty():
		var total := Vector2.ZERO
		var count := 0

		for tile_value in footprint_tiles:
			if tile_value is Vector2i:
				var tile: Vector2i = tile_value
				total += Vector2(
					(float(tile.x) + 0.5) * float(city_tile_size),
					(float(tile.y) + 0.5) * float(city_tile_size)
				)
				count += 1

		if count > 0:
			return total / float(count)

	return fallback_rect.position + fallback_rect.size * 0.5


func get_city_object_debug_footprint_tiles(city_object: Dictionary) -> Array:
	if city_object.has("footprint_tiles"):
		return city_object["footprint_tiles"]

	if city_object.has("tiles"):
		return city_object["tiles"]

	return []

func get_city_object_visual_style(object_type: String) -> Dictionary:
	return WorldData.get_city_object_visual_style_for_type(object_type)

func with_alpha_multiplier(color: Color, alpha_multiplier: float) -> Color:
	return Color(
		color.r,
		color.g,
		color.b,
		color.a * alpha_multiplier
	)


func draw_city_object_visual(
	draw_target: CanvasItem,
	city_object: Dictionary,
	alpha_multiplier: float = 1.0,
	is_valid_preview: bool = true
) -> void:
	if city_object.is_empty():
		return

	var object_type: String = str(city_object.get("type", ""))

	if object_type == WorldData.CITY_OBJECT_ROAD:
		return

	var rect: Rect2 = get_city_object_world_rect(city_object)

	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var style := get_city_object_visual_style(object_type)

	var frame_color: Color = style["frame_color"]
	var fill_color: Color = style["fill_color"]
	var frame_thickness: float = float(style["frame_thickness"])

	if not is_valid_preview:
		frame_color = Color(1.0, 0.0, 0.0, 0.95)
		fill_color = Color(1.0, 0.05, 0.05, 0.35)

	frame_color = with_alpha_multiplier(frame_color, alpha_multiplier)
	fill_color = with_alpha_multiplier(fill_color, alpha_multiplier)

	CityRenderLayerScript.draw_framed_rect({
		"draw_target": draw_target,
		"rect": rect,
		"frame_color": frame_color,
		"fill_color": fill_color,
		"frame_thickness": frame_thickness
	})


func draw_city_objects(draw_target: CanvasItem) -> void:
	for city_object in WorldData.city_objects:
		if city_object.is_empty():
			continue

		var object_type: String = str(city_object.get("type", ""))

		if object_type == WorldData.CITY_OBJECT_ROAD:
			continue

		draw_city_object_visual(
			draw_target,
			city_object,
			1.0,
			true
		)


func draw_city_construction_sites(draw_target: CanvasItem) -> void:
	for raw_site in CityConstructionSystem.get_city_construction_site_snapshot():
		if not raw_site is Dictionary:
			continue

		var site: Dictionary = raw_site
		var phase_color := _get_city_construction_phase_color(
			str(site.get("phase", ""))
		)
		var object_type := str(site.get("object_type", ""))
		var footprint_tiles = site.get("footprint_tiles", [])

		if not footprint_tiles is Array:
			continue

		if object_type != WorldData.CITY_OBJECT_ROAD:
			var preview_object := {
				"type": object_type,
				"top_left": site.get(
					"top_left",
					WorldData.INVALID_CITY_TILE_POSITION
				),
				"size": site.get("size", Vector2i.ZERO),
			}
			draw_city_object_visual(
				draw_target,
				preview_object,
				0.32,
				true
			)

		var blueprint_fill := CITY_CONSTRUCTION_BLUEPRINT_FILL

		if object_type == WorldData.CITY_OBJECT_ROAD:
			var road_style := get_city_object_visual_style(
				WorldData.CITY_OBJECT_ROAD
			)
			var road_fill: Color = road_style.get(
				"fill_color",
				Color(0.56, 0.25, 0.10, 0.96)
			)
			blueprint_fill = Color(
				road_fill.r,
				road_fill.g,
				road_fill.b,
				0.34
			)

		for raw_tile in footprint_tiles:
			if not raw_tile is Vector2i:
				continue

			var tile_rect := get_city_tile_world_rect(raw_tile)
			draw_target.draw_rect(
				tile_rect,
				blueprint_fill,
				true
			)
			CityRenderLayerScript.draw_inner_box_border({
				"draw_target": draw_target,
				"rect": tile_rect,
				"border_color": phase_color,
				"border_width": float(city_tile_size) * 0.06
			})


func _get_city_construction_phase_color(phase: String) -> Color:
	match phase:
		WorldData.CITY_CONSTRUCTION_PHASE_CLEARING:
			return CITY_CONSTRUCTION_CLEARING_COLOR

		WorldData.CITY_CONSTRUCTION_PHASE_GATHERING:
			return CITY_CONSTRUCTION_GATHERING_COLOR

		WorldData.CITY_CONSTRUCTION_PHASE_LABOR:
			return CITY_CONSTRUCTION_LABOR_COLOR

	return CURSOR_LOOK_BORDER_COLOR


func start_city_object_placement(
	object_type: String,
	size_tiles: Vector2i,
	object_owner: String = "player",
	repeat_after_place: bool = false
) -> void:
	active_city_object_placement = {
		"type": object_type,
		"size": size_tiles,
		"owner": object_owner,
		"repeat_after_place": repeat_after_place
	}
	refresh_active_workplace_zone_preview_cache()

func clear_city_object_placement() -> void:
	active_city_object_placement.clear()


func has_active_city_object_placement() -> bool:
	return not active_city_object_placement.is_empty()


func is_uncommitted_city_placement_preview_active() -> bool:
	return (
		has_active_city_object_placement()
		or is_road_placement_active
	)


#region Workplace zone painting and cache

func get_city_object_top_left_tile_from_mouse(size_tiles: Vector2i) -> Vector2i:
	if city_world == null:
		return Vector2i(-1, -1)

	if size_tiles.x <= 0 or size_tiles.y <= 0:
		return Vector2i(-1, -1)

	var center_tile := get_city_tile_under_mouse()

	if center_tile == Vector2i(-1, -1):
		return Vector2i(-1, -1)

	var top_left := Vector2i(
		center_tile.x - int(size_tiles.x / 2),
		center_tile.y - int(size_tiles.y / 2)
	)

	top_left.x = clamp(top_left.x, 0, city_world.width - size_tiles.x)
	top_left.y = clamp(top_left.y, 0, city_world.height - size_tiles.y)

	return top_left


func get_active_city_object_placement_preview() -> Dictionary:
	if not has_active_city_object_placement():
		return {}

	var size_tiles: Vector2i = active_city_object_placement.get("size", Vector2i.ZERO)
	var top_left := get_city_object_top_left_tile_from_mouse(size_tiles)

	if top_left == Vector2i(-1, -1):
		return {}

	return {
		"type": str(active_city_object_placement.get("type", "")),
		"top_left": top_left,
		"size": size_tiles,
		"owner": str(active_city_object_placement.get("owner", "player"))
	}

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

	var city_object := WorldData.get_city_object_by_id(
		selected_city_object_id
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

func draw_active_city_object_placement_preview(
	draw_target: CanvasItem
) -> void:
	var preview_object := (
		get_active_city_object_placement_preview()
	)

	if preview_object.is_empty():
		return

	var top_left: Vector2i = preview_object["top_left"]
	var size_tiles: Vector2i = preview_object["size"]
	var object_type := str(preview_object.get("type", ""))

	var can_place := WorldData.can_place_city_object(
		city_world,
		top_left,
		size_tiles,
		object_type
	)

	if WorldData.city_object_type_uses_construction(object_type):
		can_place = WorldData.can_place_city_object_construction(
			city_world,
			top_left,
			size_tiles,
			object_type
		)

	var has_workplace_zone := (
		workplace_zone_overlay_cache.has_cached_zone(
			preview_object,
			true,
			city_world
		)
	)

	if has_workplace_zone:
		# The zone was already drawn beneath the buildings.
		draw_city_object_visual(
			draw_target,
			preview_object,
			0.65,
			can_place
		)
		return

	draw_city_object_visual(
		draw_target,
		preview_object,
		0.45,
		can_place
	)

func draw_selected_city_citizen_highlight(
	draw_target: CanvasItem
) -> void:
	if selected_city_citizen_id < 0:
		return

	var citizen := (
		WorldData.get_city_citizen_by_id(
			selected_city_citizen_id
		)
	)

	if citizen.is_empty():
		return

	if not bool(citizen.get("alive", false)):
		return

	var marker_rect := (
		get_city_citizen_world_rect(
			citizen
		)
	)

	if (
		marker_rect.size.x <= 0.0
		or marker_rect.size.y <= 0.0
	):
		return

	CityRenderLayerScript.draw_screen_constant_inset_rect_border({
		"draw_target": draw_target,
		"rect": marker_rect,
		"border_color": SELECTED_OBJECT_HIGHLIGHT_COLOR,
		"inset_amount": 0.0,
		"border_width_pixels": 2.0,
		"viewport": get_viewport()
	})

func draw_debug_selected_city_tile_highlight(
	draw_target: CanvasItem
) -> void:
	if not WorldData.debug_mode_enabled:
		return

	if not has_debug_selected_city_tile():
		return

	var tile_rect := Rect2(
		Vector2(
			float(
				debug_selected_city_tile.x
				* city_tile_size
			),
			float(
				debug_selected_city_tile.y
				* city_tile_size
			)
		),
		Vector2(
			float(city_tile_size),
			float(city_tile_size)
		)
	)

	CityRenderLayerScript.draw_screen_constant_inset_rect_border({
		"draw_target": draw_target,
		"rect": tile_rect,
		"border_color": DEBUG_SELECTED_TILE_HIGHLIGHT_COLOR,
		"inset_amount": 0.0,
		"border_width_pixels": 2.0,
		"viewport": get_viewport()
	})

func draw_selected_city_object_highlight(
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

	var object_rect: Rect2 = get_city_object_world_rect(
		city_object
	)

	if (
		object_rect.size.x <= 0.0
		or object_rect.size.y <= 0.0
	):
		return

	CityRenderLayerScript.draw_screen_constant_inset_rect_border({
		"draw_target": draw_target,
		"rect": object_rect,
		"border_color": SELECTED_OBJECT_HIGHLIGHT_COLOR,
		"inset_amount": 0.0,
		"border_width_pixels": 2.0,
		"viewport": get_viewport()
	})

func draw_selected_city_construction_site_highlight(
	draw_target: CanvasItem
) -> void:
	if selected_city_construction_site_id <= 0:
		return

	var site := WorldData.get_city_construction_site_by_id(
		selected_city_construction_site_id
	)

	if not is_city_construction_site_selectable(site):
		return

	var site_rect := get_city_tile_collection_world_rect(
		site.get("footprint_tiles", [])
	)

	if site_rect.size.x <= 0.0 or site_rect.size.y <= 0.0:
		return

	CityRenderLayerScript.draw_screen_constant_inset_rect_border({
		"draw_target": draw_target,
		"rect": site_rect,
		"border_color": SELECTED_OBJECT_HIGHLIGHT_COLOR,
		"inset_amount": 0.0,
		"border_width_pixels": 2.0,
		"viewport": get_viewport()
	})


func draw_city_roads(draw_target: CanvasItem) -> void:
	var road_style := get_city_object_visual_style(
		WorldData.CITY_OBJECT_ROAD
	)
	var road_fill_color: Color = road_style.get(
		"fill_color",
		Color(0.56, 0.25, 0.10, 0.96)
	)

	for city_object in WorldData.city_objects:
		var object_type: String = str(city_object["type"])

		if object_type != WorldData.CITY_OBJECT_ROAD:
			continue

		if not city_object.has("tiles"):
			continue

		var road_tiles: Array = city_object["tiles"]

		for tile_position in road_tiles:
			if not tile_position is Vector2i:
				continue

			var rect := Rect2(
				float(tile_position.x * city_tile_size),
				float(tile_position.y * city_tile_size),
				float(city_tile_size),
				float(city_tile_size)
			)

			draw_target.draw_rect(
				rect,
				road_fill_color,
				true
			)

func draw_road_preview(draw_target: CanvasItem) -> void:
	if not is_road_placement_active:
		return

	if road_preview_tiles.is_empty():
		return

	var border_width: float = float(city_tile_size) * 0.06

	for tile_position in road_preview_tiles:
		if not tile_position is Vector2i:
			continue

		var rect := Rect2(
			float(tile_position.x * city_tile_size),
			float(tile_position.y * city_tile_size),
			float(city_tile_size),
			float(city_tile_size)
		)

		draw_target.draw_rect(
			rect,
			CURSOR_LOOK_FILL_COLOR,
			true
		)

		CityRenderLayerScript.draw_inner_box_border({
			"draw_target": draw_target,
			"rect": rect,
			"border_color": CURSOR_LOOK_BORDER_COLOR,
			"border_width": border_width
		})

func get_city_hover_highlight_tiles(
	tile_position: Vector2i
) -> Array[Vector2i]:
	var fallback_tiles: Array[Vector2i] = []

	if city_world == null:
		return fallback_tiles

	if not city_world.is_in_bounds(
		tile_position.x,
		tile_position.y
	):
		return fallback_tiles

	fallback_tiles.append(tile_position)

	# Construction sites take precedence over completed objects. This matters
	# for future expansion blueprints that may overlap their parent building.
	var construction_site := (
		CityConstructionSystem.get_city_construction_site_at_tile(
			tile_position
		)
	)

	if not construction_site.is_empty():
		if (
			str(construction_site.get("object_type", ""))
			== WorldData.CITY_OBJECT_ROAD
		):
			return fallback_tiles

		var construction_tiles := (
			normalize_city_hover_footprint_tiles(
				construction_site.get("footprint_tiles", [])
			)
		)

		if not construction_tiles.is_empty():
			return construction_tiles

	var city_object := WorldData.get_city_object_at_tile(
		tile_position
	)

	# Roads deliberately retain the original one-tile cursor behavior.
	if not is_city_object_selectable(city_object):
		return fallback_tiles

	var object_tiles := normalize_city_hover_footprint_tiles(
		WorldData.get_city_object_footprint_tiles(city_object)
	)

	if object_tiles.is_empty():
		return fallback_tiles

	return object_tiles


func normalize_city_hover_footprint_tiles(
	raw_tiles: Array
) -> Array[Vector2i]:
	var tile_lookup: Dictionary = {}

	for raw_tile in raw_tiles:
		if not raw_tile is Vector2i:
			continue

		var tile_position: Vector2i = raw_tile

		if city_world != null and not city_world.is_in_bounds(
			tile_position.x,
			tile_position.y
		):
			continue

		tile_lookup[tile_position] = true

	var footprint_tiles: Array[Vector2i] = []

	for raw_tile in tile_lookup.keys():
		if raw_tile is Vector2i:
			footprint_tiles.append(raw_tile)

	footprint_tiles.sort_custom(_sort_city_hover_tiles_y_then_x)
	return footprint_tiles


func _sort_city_hover_tiles_y_then_x(
	a: Vector2i,
	b: Vector2i
) -> bool:
	if a.y == b.y:
		return a.x < b.x

	return a.y < b.y


func draw_hovered_city_tile_highlight(
	draw_target: CanvasItem
) -> void:
	# A placement ghost is not yet a world entity. Its own validity preview is
	# the only cursor feedback until the player commits it.
	if is_uncommitted_city_placement_preview_active():
		return

	if is_city_player_command_mode_active():
		return

	if hovered_city_tile == Vector2i(-1, -1):
		return

	if (
		WorldData.debug_mode_enabled
		and has_debug_selected_city_tile()
		and hovered_city_tile
		== debug_selected_city_tile
	):
		return

	if is_object_selection_dragging:
		return

	if has_selected_city_entity():
		return

	var highlight_tiles := get_city_hover_highlight_tiles(
		hovered_city_tile
	)
	var border_width: float = float(city_tile_size) * 0.08

	CityRenderLayerScript.draw_tile_footprint_border({
		"draw_target": draw_target,
		"footprint_tiles": highlight_tiles,
		"border_color": CURSOR_LOOK_BORDER_COLOR,
		"border_width": border_width,
		"tile_size": city_tile_size
	})

func ensure_city_foundation_object_exists() -> void:
	if not WorldData.has_player_city_foundation():
		return

	if WorldData.has_city_object_type(WorldData.CITY_OBJECT_CITY_CENTER):
		return

	var top_left: Vector2i = WorldData.player_city_foundation_top_left
	var size_tiles: Vector2i = WorldData.player_city_foundation_size

	if not WorldData.can_place_city_object(
		city_world,
		top_left,
		size_tiles,
		WorldData.CITY_OBJECT_CITY_CENTER
	):
		print("Could not recover city foundation object.")
		return

	var foundation_object := WorldData.add_city_object({
		"object_type": WorldData.CITY_OBJECT_CITY_CENTER,
		"top_left": top_left,
		"size_tiles": size_tiles,
		"object_owner": "player",
		"city_world": city_world,
	})

	print("Recovered city foundation object: ", foundation_object)

func clear_invalid_old_city_foundation_state() -> void:
	if not WorldData.player_city_founded:
		return

	if WorldData.has_player_city_foundation():
		return

	print("Clearing old city-founded state with no placed foundation.")
	WorldData.reset_player_city_state()

func get_city_tile_under_mouse() -> Vector2i:
	if city_world == null:
		return Vector2i(-1, -1)

	var mouse_world_position: Vector2 = get_global_mouse_position()

	var tile_x := int(floor(mouse_world_position.x / float(city_tile_size)))
	var tile_y := int(floor(mouse_world_position.y / float(city_tile_size)))

	if tile_x < 0 or tile_y < 0 or tile_x >= city_world.width or tile_y >= city_world.height:
		return Vector2i(-1, -1)

	return Vector2i(tile_x, tile_y)


#endregion

#region Debug panel and navigation orchestration

func update_debug_panel_text() -> void:
	if debug_panel_ui == null:
		return

	debug_panel_ui.refresh()
	citizen_debug_ui.refresh()

func create_debug_panel() -> void:
	debug_panel_ui = DebugPanel.new()
	debug_panel_ui.setup({
		"parent": self,
		"canvas_layer_index": 120,
		"panel_position": debug_panel_position,
		"padding": debug_panel_padding,
		"minimum_size": debug_panel_min_size,
		"initial_text": "DEBUG INFO",
		"text_provider": Callable(
			self,
			"get_city_debug_panel_text"
		),
	})

	citizen_debug_ui.setup({
		"debug_panel": debug_panel_ui,
		"text_provider": Callable(
			self,
			"get_citizen_debug_list_text"
		),
	})

func get_first_living_debug_citizen() -> Dictionary:
	for raw_citizen in WorldData.city_citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen

		if not bool(citizen.get("alive", false)):
			continue

		var raw_position = citizen.get(
			"city_tile_position",
			WorldData.INVALID_CITY_TILE_POSITION
		)

		if not raw_position is Vector2i:
			continue

		return citizen

	return {}

func get_debug_navigation_source_citizen() -> Dictionary:
	if selected_city_citizen_id >= 0:
		var selected_citizen := (
			WorldData.get_city_citizen_by_id(
				selected_city_citizen_id
			)
		)

		if (
			not selected_citizen.is_empty()
			and bool(
				selected_citizen.get(
					"alive",
					false
				)
			)
		):
			return selected_citizen

	return get_first_living_debug_citizen()

func clear_debug_navigation_result() -> void:
	debug_navigation_path.clear()
	debug_navigation_status = (
		CityNavigationSystemScript
		.PATH_STATUS_NOT_REQUESTED
	)
	debug_navigation_start_tile = (
		WorldData.INVALID_CITY_TILE_POSITION
	)
	debug_navigation_destination_tile = (
		WorldData.INVALID_CITY_TILE_POSITION
	)
	debug_navigation_candidate_count = 0
	debug_navigation_expanded_nodes = 0
	debug_navigation_path_cost = 0
	debug_navigation_duration_usec = 0

func request_debug_navigation_path() -> void:
	clear_debug_navigation_result()

	if city_world == null:
		debug_navigation_status = (
			CityNavigationSystemScript
			.PATH_STATUS_INVALID_WORLD
		)
		update_debug_panel_text()
		queue_city_background_layer_redraw()
		queue_city_interaction_layer_redraw()
		return

	var citizen := (
		get_debug_navigation_source_citizen()
	)

	if citizen.is_empty():
		debug_navigation_status = (
			CityNavigationSystemScript
			.PATH_STATUS_INVALID_START
		)
		update_debug_panel_text()
		queue_city_background_layer_redraw()
		queue_city_interaction_layer_redraw()
		return

	var raw_start_tile = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if not raw_start_tile is Vector2i:
		debug_navigation_status = (
			CityNavigationSystemScript
			.PATH_STATUS_INVALID_START
		)
		update_debug_panel_text()
		queue_city_background_layer_redraw()
		queue_city_interaction_layer_redraw()
		return

	var start_tile: Vector2i = raw_start_tile
	var target_tile := hovered_city_tile
	if has_debug_selected_city_tile():
		target_tile = debug_selected_city_tile
	var destination_tiles := []

	if target_tile == Vector2i(-1, -1):
		debug_navigation_status = (
			CityNavigationSystemScript
			.PATH_STATUS_NO_DESTINATIONS
		)
		update_debug_panel_text()
		queue_city_background_layer_redraw()
		queue_city_interaction_layer_redraw()
		return

	var target_object := (
		WorldData.get_city_object_at_tile(
			target_tile
		)
	)

	if (
		not target_object.is_empty()
		and str(target_object.get("type", ""))
		!= WorldData.CITY_OBJECT_ROAD
	):
		destination_tiles = (
			WorldData.get_city_object_access_tiles(
				city_world,
				target_object
			)
		)
	else:
		destination_tiles.append(target_tile)

	var result := (
		CityNavigationSystemScript
		.find_path_to_any_city_tile({
			"city_world": city_world,
			"start_tile": start_tile,
			"destination_tiles": destination_tiles,
		})
	)

	debug_navigation_status = str(
		result.get(
			"status",
			CityNavigationSystemScript
			.PATH_STATUS_UNREACHABLE
		)
	)
	debug_navigation_start_tile = start_tile
	debug_navigation_destination_tile = result.get(
		"destination_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	debug_navigation_candidate_count = int(
		result.get(
			"destination_candidate_count",
			0
		)
	)
	debug_navigation_expanded_nodes = int(
		result.get(
			"expanded_node_count",
			0
		)
	)
	debug_navigation_path_cost = int(
		result.get("path_cost", 0)
	)
	debug_navigation_duration_usec = int(
		result.get("duration_usec", 0)
	)

	var raw_path = result.get("path", [])

	if raw_path is Array:
		for raw_path_tile in raw_path:
			if raw_path_tile is Vector2i:
				debug_navigation_path.append(
					raw_path_tile
				)

	print(
		"Navigation test: ",
		debug_navigation_status,
		" | Start: ",
		debug_navigation_start_tile,
		" | Destination: ",
		debug_navigation_destination_tile,
		" | Path cost: ",
		format_debug_navigation_path_cost(
			debug_navigation_path_cost
		),
		" | Expanded: ",
		debug_navigation_expanded_nodes,
		" | Time: ",
		debug_navigation_duration_usec,
		" usec"
	)

	update_debug_panel_text()
	queue_city_background_layer_redraw()
	queue_city_interaction_layer_redraw()

func assign_debug_navigation_path_to_selected_citizen() -> void:
	if selected_city_citizen_id < 0:
		print("Movement rejected: select a citizen first.")
		return

	if (
		debug_navigation_status
		!= CityNavigationSystemScript.PATH_STATUS_SUCCESS
		or debug_navigation_path.is_empty()
	):
		print("Movement rejected: press P to create a valid path.")
		return

	var citizen := WorldData.get_city_citizen_by_id(
		selected_city_citizen_id
	)

	if citizen.is_empty():
		print("Movement rejected: selected citizen is missing.")
		return

	if not bool(citizen.get("alive", false)):
		print("Movement rejected: selected citizen is not alive.")
		return

	var current_position = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if not current_position is Vector2i:
		print("Movement rejected: citizen position is invalid.")
		return

	if (
		debug_navigation_start_tile != current_position
		or debug_navigation_path[0] != current_position
	):
		print("Movement rejected: path is stale. Press P again.")
		return

	if not WorldData.assign_city_citizen_movement_order(
		selected_city_citizen_id,
		debug_navigation_path
	):
		print(
			"Movement rejected: authoritative path validation failed."
		)
		return

	city_citizen_movement_presentation.track_mover(
		selected_city_citizen_id
	)

	update_selected_entity_panel()
	update_debug_panel_text()

	CityStateValidator.validate(true, true)

	print(
		"Movement order assigned to citizen #",
		selected_city_citizen_id,
		" | Steps: ",
		maxi(debug_navigation_path.size() - 1, 0),
		" | Active movers: ",
		WorldData.city_active_mover_ids
	)

func get_navigation_debug_text() -> String:
	return CityDebugPresentationScript.get_navigation_text(
		_get_city_debug_presentation_values()
	)

func format_debug_navigation_path_cost(path_cost: int) -> String:
	return CityDebugPresentationScript.format_navigation_path_cost(
		path_cost
	)

func get_simulation_debug_text() -> String:
	return CityDebugPresentationScript.get_simulation_text(
		_get_city_debug_presentation_values()
	)

func get_citizen_debug_list_text() -> String:
	return CitizenDebugPanelScript.get_debug_list_text()

func toggle_debug_mode() -> void:
	if debug_panel_ui == null:
		return

	var is_enabled := debug_panel_ui.toggle_enabled()
	citizen_debug_ui.refresh()
	queue_all_city_render_layers_redraw()

	if is_enabled:
		CityStateValidator.validate(true, true)
		debug_panel_ui.refresh()
		print("Debug mode: ON")
	else:
		print("Debug mode: OFF")

func get_city_debug_panel_text() -> String:
	return CityDebugPresentationScript.get_panel_text(
		_get_city_debug_presentation_values()
	)


func _get_city_debug_presentation_values() -> Dictionary:
	return {
		"city_world": city_world,
		"city_seed": city_seed,
		"city_view_name": get_city_map_mode_name(city_view_mode),
		"hovered_city_tile": hovered_city_tile,
		"debug_selected_city_tile": debug_selected_city_tile,
		"has_debug_selected_city_tile": has_debug_selected_city_tile(),
		"selected_city_entity_kind": selected_city_entity_kind,
		"selected_city_entity_id": selected_city_entity_id,
		"selected_city_object_id": selected_city_object_id,
		"navigation_status": debug_navigation_status,
		"navigation_start_tile": debug_navigation_start_tile,
		"navigation_destination_tile": debug_navigation_destination_tile,
		"navigation_candidate_count": debug_navigation_candidate_count,
		"navigation_expanded_nodes": debug_navigation_expanded_nodes,
		"navigation_path_cost": debug_navigation_path_cost,
		"navigation_duration_usec": debug_navigation_duration_usec,
	}


#endregion
