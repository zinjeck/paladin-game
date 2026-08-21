extends Node

const CITY_SCENE := preload("res://scenes/CityScreen.tscn")
const CityStateValidatorScript = preload(
	"res://scripts/city/simulation/CityStateValidator.gd"
)
const CityWorldGeneratorScript = preload(
	"res://scripts/city/generation/CityWorldGenerator.gd"
)
const CityConstructionSystemScript = preload(
	"res://scripts/city/simulation/systems/CityConstructionSystem.gd"
)
const CityNavigationSystemScript = preload(
	"res://scripts/city/simulation/systems/CityNavigationSystem.gd"
)
const SettlementNaturalFeaturePresenterScript = preload(
	"res://scripts/map/visuals/SettlementNaturalFeaturePresenter.gd"
)
const SettlementPresentationBindingScript = preload(
	"res://scripts/settlements/presentation/SettlementPresentationBinding.gd"
)
const CityPresentationBindingScript = preload(
	"res://scripts/city/rendering/CityPresentationBinding.gd"
)
const TEST_CITY_NAME := "Smoke Test City"
const TEST_CULTURE_NAME := "Smoke Test Culture"

var failure_count: int = 0
var active_workplace_preview_draw_count: int = 0
var background_draw_count: int = 0
var citizen_draw_count: int = 0
var interaction_draw_count: int = 0


func _ready() -> void:
	await _run_smoke_test()

	if failure_count > 0:
		push_error(
			"City renderer refactor smoke test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City renderer refactor smoke test passed.")
	get_tree().quit(0)


func _run_smoke_test() -> void:
	_prepare_dev_city_region()

	var renderer := CITY_SCENE.instantiate() as CityRenderer
	_expect(renderer != null, "City scene must instantiate a CityRenderer.")

	if renderer == null:
		return

	SimulationClock.set_simulation_paused(true)
	var binding := (
		CityRendererBindingSupport.prepare_player_capital_renderer(renderer)
	)
	_expect(
		not binding.is_empty(),
		"The smoke-test renderer must receive an explicit capital binding before _ready()."
	)
	if binding.is_empty():
		renderer.free()
		return

	add_child(renderer)
	await get_tree().process_frame
	await get_tree().process_frame

	_expect(renderer.city_world != null, "City world must be generated.")
	_expect(
		renderer.city_active_workplace_preview_render_layer != null,
		"Active workplace preview render layer must exist."
	)
	_expect(
		renderer.city_background_render_layer != null,
		"Background render layer must exist."
	)
	_expect(
		renderer.city_citizen_render_layer != null,
		"Citizen render layer must exist."
	)
	_expect(
		renderer.city_interaction_render_layer != null,
		"Interaction render layer must exist."
	)
	_expect(
		renderer.settlement_infrastructure_presenter != null
		and (
			renderer.settlement_infrastructure_presenter
			.is_bound_to_settlement_presentation(
				renderer.get_settlement_presentation_binding()
			)
		),
		"Infrastructure drawing must be owned by the exact settlement binding."
	)

	_test_city_map_texture_cache(renderer)
	_test_city_information_panel_initial(renderer)
	_test_road_hover_highlight(renderer)
	_test_settlement_natural_feature_presenter_binding(renderer)
	_test_city_natural_features(renderer)
	_test_ground_pile_coalescing(renderer)
	await _test_focused_layer_invalidation(renderer)
	_test_resource_catalog_and_bulk_totals()
	_place_and_validate_city_fixture(renderer)
	await _test_city_information_panel_live_data(renderer)
	_test_universal_construction_core(renderer)

	renderer.queue_all_city_render_layers_redraw()
	await get_tree().process_frame
	await get_tree().process_frame

	var validation := CityStateValidatorScript.validate_for_settlement(
		renderer.bound_settlement_context,
		true,
		false
	)
	_expect(
		bool(validation.get("valid", false)),
		"City state validator must remain valid after the fixture."
	)

	if not bool(validation.get("valid", false)):
		for error in validation.get("errors", []):
			push_error(str(error))

	# Several fixtures deliberately edit authoritative tile data. The complete
	# atomic cache must already represent that latest version before re-entry.
	renderer.settlement_ui_controller.update_map_mode_button_visuals()
	_expect(
		renderer.has_valid_saved_city_map_texture_cache(renderer.city_world),
		"The latest tile-data version must finish with a complete saved map cache."
	)

	var cached_tree_multimesh_id: int = (
		renderer.settlement_natural_feature_presenter.tree_multimesh.get_instance_id()
		if renderer.settlement_natural_feature_presenter.tree_multimesh != null
		else 0
	)
	var cached_rock_multimesh_id: int = (
		renderer.settlement_natural_feature_presenter.rock_multimesh.get_instance_id()
		if renderer.settlement_natural_feature_presenter.rock_multimesh != null
		else 0
	)
	renderer.queue_free()
	await get_tree().process_frame

	var reloaded_renderer := CITY_SCENE.instantiate() as CityRenderer
	var reload_binding := CityRendererBindingSupport.configure_existing_renderer(
		reloaded_renderer,
		int(binding["settlement_context"].settlement_id)
	)
	_expect(
		not reload_binding.is_empty(),
		"City re-entry must explicitly bind the retained settlement before _ready()."
	)
	if reload_binding.is_empty():
		reloaded_renderer.free()
		WorldData.reset_runtime_session_state()
		return
	add_child(reloaded_renderer)
	SimulationClock.set_simulation_paused(true)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(
		reloaded_renderer.city_natural_feature_cache_reused_on_entry
		and reloaded_renderer.settlement_natural_feature_presenter.tree_multimesh != null
		and reloaded_renderer.settlement_natural_feature_presenter.rock_multimesh != null
		and reloaded_renderer.settlement_natural_feature_presenter.tree_multimesh.get_instance_id()
		== cached_tree_multimesh_id
		and reloaded_renderer.settlement_natural_feature_presenter.rock_multimesh.get_instance_id()
		== cached_rock_multimesh_id,
		"City re-entry must reuse the natural-feature MultiMeshes instead of rescanning the full map."
	)
	_expect(
		reloaded_renderer.city_map_texture_cache_reused_on_entry
		and reloaded_renderer.has_valid_saved_city_map_texture_cache(
			reloaded_renderer.city_world
		),
		"City re-entry must reuse the completed map texture cache."
	)
	reloaded_renderer.queue_free()
	await get_tree().process_frame
	WorldData.reset_runtime_session_state()

	# No deferred map-generation work may remain after the renderer is freed.
	await get_tree().process_frame


func _test_city_map_texture_cache(renderer: CityRenderer) -> void:
	var view_modes: Array[int] = MapVisuals.get_all_view_modes()
	var original_view_mode: int = renderer.settlement_ui_controller.view_mode
	_expect(
		renderer.city_texture_cache.is_mode_ready(
			renderer.city_world,
			original_view_mode
		)
		and renderer.city_terrain_texture != null,
		"The visible city map mode must be ready as soon as the scene becomes interactive."
	)
	_expect(
		renderer.city_terrain_sprite != null
		and renderer.city_terrain_sprite.texture
		== renderer.city_terrain_texture,
		"The static city terrain must be retained by a Sprite2D."
	)
	_expect(
		renderer.city_texture_cache.mode_textures.size()
		== view_modes.size(),
		"Every city map mode must be ready in the same atomic preparation pass."
	)

	renderer.settlement_ui_controller.update_map_mode_button_visuals()
	_expect(
		renderer.has_valid_saved_city_map_texture_cache(
			renderer.city_world
		),
		"Atomic city map preparation must persist the complete mode set."
	)

	var texture_instance_ids: Dictionary = {}

	for mode in view_modes:
		var raw_texture = renderer.city_texture_cache.mode_textures.get(
			mode
		)
		_expect(
			raw_texture is ImageTexture,
			"Every city map mode must have a ready independent ImageTexture."
		)

		if not raw_texture is ImageTexture:
			continue

		var texture := raw_texture as ImageTexture
		var texture_instance_id := texture.get_instance_id()
		_expect(
			not texture_instance_ids.has(texture_instance_id),
			"Each city map mode must own a distinct GPU texture resource."
		)
		texture_instance_ids[texture_instance_id] = true
		_expect(
			texture.get_width() == renderer.city_world.width
			and texture.get_height() == renderer.city_world.height,
			"Each city map texture must match the source map dimensions."
		)
		renderer.set_city_view_mode(mode)
		_expect(
			renderer.city_terrain_texture == texture
			and renderer.city_terrain_sprite != null
			and renderer.city_terrain_sprite.texture == texture,
			"Switching city map modes must only swap the retained texture."
		)

		var sample_tile_position := Vector2i(
			int(renderer.city_world.width / 2),
			int(renderer.city_world.height / 2)
		)
		var source_tile := renderer.city_world.get_tile(
			sample_tile_position.x,
			sample_tile_position.y
		)
		var expected_color := MapVisuals.get_tile_color_for_mode(
			source_tile,
			mode,
			0.45
		)
		var actual_color := texture.get_image().get_pixelv(
			sample_tile_position
		)
		_expect(
			_colors_match_rgba8(actual_color, expected_color),
			"Batched city map colors must match the single-mode color contract."
		)

	renderer.set_city_view_mode(original_view_mode)


func _colors_match_rgba8(a: Color, b: Color) -> bool:
	var tolerance := 1.0 / 255.0 + 0.0001
	return (
		absf(a.r - b.r) <= tolerance
		and absf(a.g - b.g) <= tolerance
		and absf(a.b - b.b) <= tolerance
		and absf(a.a - b.a) <= tolerance
	)


func _test_road_hover_highlight(renderer: CityRenderer) -> void:
	var original_road_active := renderer.is_road_placement_active
	var original_hovered_tile := renderer.hovered_city_tile
	var test_tile := Vector2i(0, 0)

	renderer.is_road_placement_active = true
	renderer.hovered_city_tile = test_tile

	var highlight_tiles := renderer.get_city_hover_highlight_tiles(test_tile)
	_expect(
		highlight_tiles == [test_tile],
		"Road placement must retain an exact one-tile hover highlight."
	)

	renderer.is_road_placement_active = original_road_active
	renderer.hovered_city_tile = original_hovered_tile


func _test_city_information_panel_initial(
	renderer: CityRenderer
) -> void:
	var city_ui = renderer.city_information_ui

	_expect(
		city_ui != null and city_ui.panel != null,
		"City information panel must exist."
	)

	if city_ui == null or city_ui.panel == null:
		return

	_expect(
		city_ui.panel.get_parent() == renderer.ui_root,
		"City information panel must live in the screen-space UI root."
	)
	_expect(
		city_ui.panel.position.is_equal_approx(
			city_ui.PANEL_POSITION
		)
		and city_ui.panel.position.is_zero_approx(),
		"City information panel must attach to the exact upper-left corner."
	)
	_expect(
		city_ui.panel.size.x > city_ui.panel.size.y,
		"City information panel must be rectangular and wider than tall."
	)
	_expect(
		city_ui.city_name_label.text == TEST_CITY_NAME,
		"City information panel must show the committed city name."
	)
	_expect(
		city_ui.date_time_label.text
		== SimulationClock.get_time_display_text(),
		"City information panel must show the current day and time."
	)
	_expect(
		city_ui.season_label.text.is_empty(),
		"City information panel season cell must remain blank."
	)
	_expect(
		city_ui.hunger_label.text == "Hun"
		and city_ui.happiness_label.text == "Hap",
		"City information panel must use the Hun and Hap labels."
	)
	_expect(
		city_ui.population_button.text == "Pop\n0"
		and city_ui.jobs_button.text == "Jobs"
		and city_ui.reserved_button.text.is_empty(),
		"City information buttons must begin with the requested text."
	)
	_expect(
		is_zero_approx(city_ui.hunger_bar.value)
		and is_zero_approx(city_ui.happiness_bar.value),
		"An empty city must show fully depleted need meters."
	)
	_expect(
		not city_ui.hunger_label.visible
		and not city_ui.happiness_label.visible
		and not city_ui.hunger_bar.visible
		and not city_ui.happiness_bar.visible,
		"Hun and Hap readouts must stay hidden until the City Keep is placed."
	)
	_expect(
		city_ui.hunger_bar.size.y <= 4.0
		and city_ui.happiness_bar.size.y <= 4.0,
		"Hun and Hap meters must remain slim strips."
	)
	_expect(
		city_ui.population_button.position.x
		== city_ui.jobs_button.position.x
		and city_ui.jobs_button.position.x
		== city_ui.reserved_button.position.x
		and city_ui.population_button.position.y
		< city_ui.jobs_button.position.y
		and city_ui.jobs_button.position.y
		< city_ui.reserved_button.position.y,
		"City information buttons must form one right-side stack."
	)
	_expect(
		city_ui.date_time_label.get_parent().position.y
		== city_ui.season_label.get_parent().position.y
		and city_ui.hunger_label.get_parent().position.y
		== city_ui.happiness_label.get_parent().position.y,
		"Date/season and Hun/Hap must each share a row."
	)
	_expect(
		city_ui.panel.mouse_filter == Control.MOUSE_FILTER_STOP
		and city_ui.population_button.mouse_filter
		== Control.MOUSE_FILTER_STOP
		and city_ui.jobs_button.mouse_filter
		== Control.MOUSE_FILTER_STOP
		and city_ui.reserved_button.mouse_filter
		== Control.MOUSE_FILTER_STOP,
		"Panel surfaces must block map clicks underneath them."
	)
	_expect(
		city_ui.city_name_label.mouse_filter
		== Control.MOUSE_FILTER_IGNORE
		and city_ui.date_time_label.mouse_filter
		== Control.MOUSE_FILTER_IGNORE
		and city_ui.season_label.mouse_filter
		== Control.MOUSE_FILTER_IGNORE
		and city_ui.hunger_bar.mouse_filter
		== Control.MOUSE_FILTER_IGNORE
		and city_ui.happiness_bar.mouse_filter
		== Control.MOUSE_FILTER_IGNORE,
		"City information text and meters must not consume input."
	)
	_expect(
		city_ui.population_button.pressed.get_connections().is_empty()
		and city_ui.jobs_button.pressed.get_connections().is_empty()
		and city_ui.reserved_button.pressed.get_connections().is_empty(),
		"City information buttons must remain inert in this pass."
	)

	var panel_style := (
		city_ui.panel.get_theme_stylebox("panel") as StyleBoxFlat
	)
	_expect(
		panel_style != null
		and is_equal_approx(panel_style.bg_color.r, panel_style.bg_color.g)
		and is_equal_approx(panel_style.bg_color.g, panel_style.bg_color.b),
		"City information panel must use a neutral grey fill."
	)
	_expect(
		city_ui.hunger_bar.background_color.r
		> city_ui.hunger_bar.background_color.g
		and city_ui.hunger_bar.fill_color.g
		> city_ui.hunger_bar.fill_color.r,
		"Need meters must expose a red remainder and green filled segment."
	)

	var original_world_minutes := SimulationClock.absolute_world_minutes
	SimulationClock.absolute_world_minutes = 2 * 24 * 60 + 9 * 60 + 7
	SimulationClock.emit_time_changed()
	_expect(
		city_ui.date_time_label.text == "Day 3, 09:07",
		"Clock signals must refresh the city information date immediately."
	)
	SimulationClock.absolute_world_minutes = original_world_minutes
	SimulationClock.emit_time_changed()

	var panel_position_before: Vector2 = city_ui.panel.position
	var panel_size_before: Vector2 = city_ui.panel.size
	var original_zoom := renderer.camera.zoom
	renderer.camera.zoom = original_zoom * 0.75
	renderer.update_city_ui_layout()
	_expect(
		city_ui.panel.position.is_equal_approx(panel_position_before)
		and city_ui.panel.size.is_equal_approx(panel_size_before),
		"Camera zoom must not move or scale the city information panel."
	)
	renderer.camera.zoom = original_zoom
	renderer.update_city_ui_layout()
	_expect(
		renderer.settlement_entity_panel_presentation.object_info_panel.position.y + 0.01
		>= city_ui.get_reserved_bottom_y(),
		"Object details must lay out below the fixed city information panel; "
		+ "got y=" + str(
			renderer.settlement_entity_panel_presentation.object_info_panel.position.y
		)
		+ " below reserved y=" + str(city_ui.get_reserved_bottom_y()) + "."
	)


func _test_city_information_panel_live_data(
	renderer: CityRenderer
) -> void:
	var city_ui = renderer.city_information_ui
	var city_state := _get_registered_renderer_city_state(renderer)
	_expect(
		city_state != null,
		"The live-data fixture must retain its registered settlement state."
	)
	if city_state == null:
		return
	var citizen_count := (
		CityCitizenRegistrySystem.get_city_population_count_for_city_state(
			city_state
		)
	)

	_expect(
		city_ui.population_button.text == "Pop\n" + str(citizen_count),
		"Founding must refresh the population button immediately."
	)
	_expect(
		city_ui.hunger_label.visible
		and city_ui.happiness_label.visible
		and city_ui.hunger_bar.visible
		and city_ui.happiness_bar.visible,
		"Founding must reveal both citizen-need readouts immediately."
	)
	_expect(
		is_equal_approx(city_ui.hunger_bar.value, 100.0)
		and is_equal_approx(city_ui.happiness_bar.value, 70.0),
		"Founders' average hunger and happiness must appear in the meters."
	)

	if citizen_count <= 0:
		return

	var first_citizen: Dictionary = (
		city_state.citizen_registry_state.citizens[0]
	)
	var first_citizen_id := int(first_citizen.get("id", -1))
	var original_hunger := int(first_citizen.get("hunger", 100))
	var original_hunger_remainder := int(
		first_citizen.get("hunger_decay_remainder", 0)
	)
	var original_happiness := int(first_citizen.get("happiness", 70))
	var original_hunger_total := 0.0
	var original_happiness_total := 0.0

	for raw_citizen in city_state.citizen_registry_state.citizens:
		var citizen: Dictionary = raw_citizen
		original_hunger_total += float(citizen.get("hunger", 100))
		original_happiness_total += float(
			citizen.get("happiness", 70)
		)

	_expect(
		CitizenNeedsSystem.set_city_citizen_happiness_for_city_state(
			city_state,
			first_citizen_id,
			30
		),
		"Need-meter fixture must update the first citizen's happiness."
	)
	_expect(
		CitizenNeedsSystem.set_city_citizen_hunger_state_for_city_state(
			city_state,
			first_citizen_id,
			40,
			original_hunger_remainder
		),
		"Need-meter fixture must update the first citizen's hunger."
	)
	await get_tree().process_frame

	var expected_hunger := (
		original_hunger_total - float(original_hunger) + 40.0
	) / float(citizen_count)
	var expected_happiness := (
		original_happiness_total - float(original_happiness) + 30.0
	) / float(citizen_count)
	_expect(
		is_equal_approx(city_ui.hunger_bar.value, expected_hunger)
		and is_equal_approx(
			city_ui.happiness_bar.value,
			expected_happiness
		),
		"Citizen version changes must refresh both average need meters."
	)

	CitizenNeedsSystem.set_city_citizen_happiness_for_city_state(
		city_state,
		first_citizen_id,
		original_happiness
	)
	CitizenNeedsSystem.set_city_citizen_hunger_state_for_city_state(
		city_state,
		first_citizen_id,
		original_hunger,
		original_hunger_remainder
	)
	await get_tree().process_frame


func _test_focused_layer_invalidation(
	renderer: CityRenderer
) -> void:
	renderer.city_active_workplace_preview_render_layer.draw.connect(
		_on_active_workplace_preview_layer_draw
	)
	renderer.city_background_render_layer.draw.connect(
		_on_background_layer_draw
	)
	renderer.city_citizen_render_layer.draw.connect(
		_on_citizen_layer_draw
	)
	renderer.city_interaction_render_layer.draw.connect(
		_on_interaction_layer_draw
	)

	renderer.queue_all_city_render_layers_redraw()
	await get_tree().process_frame
	await get_tree().process_frame

	# Isolate the explicit invalidation from hover/version work performed by the
	# renderer's regular process loop.
	renderer.set_process(false)
	var active_preview_before := active_workplace_preview_draw_count
	var background_before := background_draw_count
	var citizen_before := citizen_draw_count
	var interaction_before := interaction_draw_count

	renderer.queue_city_citizen_layer_redraw()
	renderer.queue_city_citizen_layer_redraw()
	await get_tree().process_frame
	await get_tree().process_frame

	_expect(
		citizen_draw_count == citizen_before + 1,
		"Repeated same-frame invalidation must coalesce into one citizen redraw."
	)
	_expect(
		active_workplace_preview_draw_count == active_preview_before,
		"Citizen-only invalidation must not redraw the placement preview."
	)
	_expect(
		background_draw_count == background_before,
		"Citizen-only invalidation must not redraw the static city."
	)
	_expect(
		interaction_draw_count == interaction_before,
		"Citizen-only invalidation must not redraw interaction overlays."
	)

	background_before = background_draw_count
	citizen_before = citizen_draw_count
	interaction_before = interaction_draw_count
	renderer.queue_city_selection_visual_change(
		renderer.CITY_SELECTION_KIND_NONE,
		renderer.CITY_SELECTION_KIND_CITIZEN
	)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(
		background_draw_count == background_before
		and citizen_draw_count == citizen_before + 1
		and interaction_draw_count == interaction_before + 1,
		"Citizen selection must redraw its moving marker layer and hover overlay."
	)

	background_before = background_draw_count
	citizen_before = citizen_draw_count
	interaction_before = interaction_draw_count
	renderer.queue_city_selection_visual_change(
		renderer.CITY_SELECTION_KIND_CITIZEN,
		renderer.CITY_SELECTION_KIND_OBJECT
	)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(
		background_draw_count == background_before + 1
		and citizen_draw_count == citizen_before + 1
		and interaction_draw_count == interaction_before + 1,
		"Leaving citizen selection must clear its moving-layer outline while object selection redraws its zone and interaction layers."
	)

	await _test_active_workplace_preview_invalidation(renderer)
	renderer.set_process(true)


func _test_active_workplace_preview_invalidation(
	renderer: CityRenderer
) -> void:
	var camera_process_was_enabled := renderer.camera.is_processing()
	renderer.camera.set_process(false)
	renderer._process_texture_cache_and_camera()
	await get_tree().process_frame
	await get_tree().process_frame
	var background_before := background_draw_count
	var active_preview_before := active_workplace_preview_draw_count
	var interaction_before := interaction_draw_count

	renderer.start_city_object_placement(
		CityObjectCatalog.CITY_OBJECT_HOUSE,
		Vector2i(3, 3)
	)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(
		not renderer.active_city_object_placement_uses_environmental_source()
		and not renderer.active_workplace_preview_refresh_pending,
		"Non-environmental placement must not schedule workplace-zone cache work."
	)
	_expect(
		background_draw_count == background_before
		and active_workplace_preview_draw_count == active_preview_before + 1
		and interaction_draw_count == interaction_before + 1,
		"Starting a placement must refresh only its retained preview and interaction layers."
	)

	renderer.clear_city_object_placement()
	await get_tree().process_frame
	await get_tree().process_frame

	renderer.start_city_object_placement(
		CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS,
		Vector2i(3, 3)
	)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(
		renderer.active_city_object_placement_uses_environmental_source()
		and renderer.active_workplace_preview_refresh_pending,
		"Environmental placement must defer its zone cache until hover is stable."
	)

	background_before = background_draw_count
	active_preview_before = active_workplace_preview_draw_count
	interaction_before = interaction_draw_count
	# Model two consecutive edge-scroll frames. Both invalidations must coalesce,
	# clear any stale retained zone, and leave texture preparation pending.
	renderer._apply_city_change_refreshes({}, true)
	renderer.queue_city_interaction_layer_redraw()
	renderer._apply_city_change_refreshes({}, true)
	renderer.queue_city_interaction_layer_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(
		renderer.active_workplace_preview_refresh_pending,
		"Moving hover must not rebuild an environmental preview cache."
	)
	_expect(
		background_draw_count == background_before
		and active_workplace_preview_draw_count == active_preview_before + 1
		and interaction_draw_count == interaction_before + 1,
		"Moving placement hover must never redraw static background geometry."
	)

	background_before = background_draw_count
	active_preview_before = active_workplace_preview_draw_count
	var original_camera_position := renderer.camera.position
	renderer.camera.position += Vector2(0.25, 0.0)
	var camera_transform_changed := (
		renderer._process_texture_cache_and_camera()
	)
	renderer._apply_city_change_refreshes(
		{},
		false,
		camera_transform_changed
	)
	await get_tree().process_frame
	await get_tree().process_frame
	var moving_camera_preview := (
		renderer.get_active_city_object_placement_preview()
	)
	_expect(
		camera_transform_changed
		and renderer.active_workplace_preview_refresh_pending
		and not renderer.workplace_zone_overlay_cache.has_cached_zone(
			moving_camera_preview,
			true,
			renderer.city_world
		),
		"Camera motion with an unchanged hovered tile must keep environmental preview preparation deferred."
	)
	_expect(
		background_draw_count == background_before
		and active_workplace_preview_draw_count == active_preview_before + 1,
		"Camera motion must clear only the retained workplace preview layer."
	)

	background_before = background_draw_count
	active_preview_before = active_workplace_preview_draw_count
	camera_transform_changed = renderer._process_texture_cache_and_camera()
	renderer._apply_city_change_refreshes(
		{},
		false,
		camera_transform_changed
	)
	await get_tree().process_frame
	await get_tree().process_frame
	var fishing_preview := renderer.get_active_city_object_placement_preview()
	_expect(
		not renderer.active_workplace_preview_refresh_pending
		and not fishing_preview.is_empty()
		and renderer.workplace_zone_overlay_cache.has_cached_zone(
			fishing_preview,
			true,
			renderer.city_world
		),
		"One stable-hover frame must prepare the environmental preview exactly once."
	)
	_expect(
		background_draw_count == background_before
		and active_workplace_preview_draw_count == active_preview_before + 1,
		"Preparing a stable workplace preview must not redraw static background geometry."
	)

	background_before = background_draw_count
	active_preview_before = active_workplace_preview_draw_count
	interaction_before = interaction_draw_count
	renderer.clear_city_object_placement()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(
		not renderer.has_active_city_object_placement()
		and background_draw_count == background_before
		and active_workplace_preview_draw_count == active_preview_before + 1
		and interaction_draw_count == interaction_before + 1,
		"Clearing placement must erase its retained preview without touching the static background."
	)
	renderer.camera.position = original_camera_position
	renderer._process_texture_cache_and_camera()
	renderer.camera.set_process(camera_process_was_enabled)


func _on_active_workplace_preview_layer_draw() -> void:
	active_workplace_preview_draw_count += 1


func _on_background_layer_draw() -> void:
	background_draw_count += 1


func _on_citizen_layer_draw() -> void:
	citizen_draw_count += 1


func _on_interaction_layer_draw() -> void:
	interaction_draw_count += 1


func _test_city_natural_features(
	renderer: CityRenderer
) -> void:
	var city_state := _get_registered_renderer_city_state(renderer)
	_expect(
		city_state != null,
		"Natural-feature coverage requires the registered renderer state."
	)
	if city_state == null:
		return
	var tree_count := 0
	var rock_count := 0
	var first_tree_tile := Vector2i(-1, -1)
	var first_rock_tile := Vector2i(-1, -1)
	var generated_tree_tiles: Array[Vector2i] = []
	var generated_rock_tiles: Array[Vector2i] = []

	for y in range(renderer.city_world.height):
		var row: Array = renderer.city_world.tiles[y]

		for x in range(renderer.city_world.width):
			var tile: Dictionary = row[x]
			var surface_feature := (
				WorldData.get_city_surface_feature(tile)
			)

			if (
				surface_feature
				== WorldData.CITY_SURFACE_FEATURE_TREE
			):
				tree_count += 1
				generated_tree_tiles.append(Vector2i(x, y))

				if first_tree_tile == Vector2i(-1, -1):
					first_tree_tile = Vector2i(x, y)

				_expect(
					str(tile.get("terrain", ""))
					== WorldData.TERRAIN_LAND,
					"Trees must generate only on walkable land terrain."
				)
				_expect(
					not [
						WorldData.BIOME_MOUNTAIN,
						WorldData.BIOME_OCEAN,
						WorldData.BIOME_RIVER,
					].has(str(tile.get("biome", ""))),
					"Mountains and water biomes must contain no trees."
				)
				continue

			if (
				surface_feature
				== WorldData.CITY_SURFACE_FEATURE_ROCK
			):
				rock_count += 1
				generated_rock_tiles.append(Vector2i(x, y))

				if first_rock_tile == Vector2i(-1, -1):
					first_rock_tile = Vector2i(x, y)

				_expect(
					str(tile.get("terrain", ""))
					== WorldData.TERRAIN_LAND,
					"Rocks must generate only where citizens can reach them."
				)

	_expect(tree_count > 0, "The dev city must generate trees.")
	_expect(
		renderer.settlement_natural_feature_presenter.tree_multimesh != null
		and renderer.settlement_natural_feature_presenter.tree_multimesh.instance_count
		== tree_count,
		"Tree MultiMesh count must match generated tree tiles."
	)
	_expect(
		renderer.settlement_natural_feature_presenter.rock_multimesh != null
		and renderer.settlement_natural_feature_presenter.rock_multimesh.instance_count
		== rock_count,
		"Rock MultiMesh count must match generated rock tiles."
	)
	_expect(
		renderer.settlement_natural_feature_presenter.tree_multimesh_instance != null
		and renderer.settlement_natural_feature_presenter.tree_multimesh_instance.multimesh
		== renderer.settlement_natural_feature_presenter.tree_multimesh
		and renderer.settlement_natural_feature_presenter.rock_multimesh_instance != null
		and renderer.settlement_natural_feature_presenter.rock_multimesh_instance.multimesh
		== renderer.settlement_natural_feature_presenter.rock_multimesh,
		"Natural features must be retained by MultiMeshInstance2D nodes."
	)

	if first_tree_tile != Vector2i(-1, -1):
		_expect(
			CityNavigationSystem.is_city_tile_walkable_for_citizen_for_city_state(
				city_state,
				renderer.city_world,
				first_tree_tile
			),
			"Citizens must be able to walk beneath tree canopies."
		)
		_expect(
			not CityLogisticsSystem.can_city_ground_pile_exist_at_tile_for_city_state(
				city_state,
				renderer.city_world,
				first_tree_tile
			),
			"Ground piles must remain excluded from tree tiles."
		)

		var tree_multimesh_before: MultiMesh = (
			renderer.settlement_natural_feature_presenter.tree_multimesh
		)
		var tile_data_version_before_harvest := (
			renderer.city_world.tile_data_version
		)
		var prepared_payload_before_harvest := (
			renderer.session_prepared_city_payload.duplicate(true)
		)
		renderer.session_prepared_city_payload.merge({
			"city_world": renderer.city_world,
			"tree_tiles": generated_tree_tiles.duplicate(),
			"rock_tiles": generated_rock_tiles.duplicate(),
			"feature_tile_data_version": (
				renderer.city_world.tile_data_version
			),
			"city_surface_feature_change_version": (
				renderer.city_world.city_surface_feature_change_version
			),
		}, true)
		_expect(
			renderer.city_world.remove_tile_surface_feature(
				first_tree_tile,
				WorldData.CITY_SURFACE_FEATURE_TREE
			),
			"A harvested tree must mutate through the WorldData owner API."
		)
		var feature_changes := (
			renderer.city_world.consume_city_surface_feature_changes()
		)

		_expect(
			renderer.apply_city_surface_feature_changes(feature_changes),
			"A harvested tree must update its existing MultiMesh in place."
		)
		_expect(
			renderer.settlement_natural_feature_presenter.tree_multimesh
			== tree_multimesh_before,
			"Tree harvesting must not rebuild the full tree MultiMesh."
		)
		_expect(
			renderer.settlement_natural_feature_presenter.tree_multimesh.visible_instance_count
			== tree_count - 1,
			"Harvesting one tree must hide exactly one tree instance."
		)
		_expect(
			renderer.city_world.tile_data_version
			== tile_data_version_before_harvest,
			"Harvesting a tree must not invalidate broad tile data."
		)
		var bound_context: SettlementSimulationContext = (
			renderer.get_bound_settlement_context()
		)
		_expect(
			bound_context != null
			and renderer.validate_city_presentation_binding(bound_context)
			and renderer.rebind_city_presentation(bound_context),
			(
				"Incremental feature compaction must preserve same-target "
				+ "validation and re-entry."
			)
		)

		# A full rebuild must not trust the stale session-prepared feature lists
		# that predate the focused owner mutation.
		renderer.rebuild_city_natural_feature_multimeshes()
		_expect(
			renderer.settlement_natural_feature_presenter.tree_multimesh != null
			and renderer.settlement_natural_feature_presenter.tree_multimesh.instance_count
			== tree_count - 1
			and WorldData.get_city_surface_feature(
				renderer.city_world.get_tile(
					first_tree_tile.x,
					first_tree_tile.y
				)
			) == WorldData.CITY_SURFACE_FEATURE_NONE,
			"A full natural-feature rebuild must not resurrect a removed tree from stale prepared data."
		)
		renderer.session_prepared_city_payload = (
			prepared_payload_before_harvest
		)

		# Restore the fixture through the same owner boundary after the focused
		# incremental-removal and full-rebuild checks.
		_expect(
			renderer.city_world.set_tile_surface_feature(
				first_tree_tile,
				WorldData.CITY_SURFACE_FEATURE_TREE
			),
			"The natural-feature fixture must restore its tree through WorldData."
		)
		renderer.city_world.consume_city_surface_feature_changes()
		renderer.rebuild_city_natural_feature_multimeshes()
		renderer.city_presentation_invalidation_tracker.observed_city_surface_feature_change_version = (
			renderer.city_world.city_surface_feature_change_version
		)

		# Hidden detailed simulation can advance focused world versions while the
		# renderer process is disabled. Same-target re-entry must reconcile them
		# before exact validation instead of rejecting its own retained state.
		renderer.set_session_view_active(false)
		_expect(
			renderer.city_world.remove_tile_surface_feature(
				first_tree_tile,
				WorldData.CITY_SURFACE_FEATURE_TREE
			),
			"The hidden re-entry fixture must remove one tree through WorldData."
		)
		var hidden_bound_context: SettlementSimulationContext = (
			renderer.get_bound_settlement_context()
		)
		_expect(
			hidden_bound_context != null
			and renderer.rebind_city_presentation(hidden_bound_context)
			and renderer.validate_city_presentation_binding(
				hidden_bound_context
			)
			and not renderer.session_view_active
			and renderer.settlement_natural_feature_presenter.tree_index_by_tile.size()
			== tree_count - 1
			and renderer.settlement_natural_feature_presenter.tree_multimesh.visible_instance_count
			== tree_count - 1,
			(
				"Same-target re-entry must reconcile hidden natural-feature "
				+ "changes before exact validation."
			)
		)
		renderer.set_session_view_active(true)
		_expect(
			renderer.city_world.set_tile_surface_feature(
				first_tree_tile,
				WorldData.CITY_SURFACE_FEATURE_TREE
			),
			"The hidden re-entry fixture must restore its tree through WorldData."
		)
		renderer.rebuild_city_natural_feature_multimeshes()
		renderer.city_world.consume_city_surface_feature_changes()
		renderer.city_presentation_invalidation_tracker.observed_city_surface_feature_change_version = (
			renderer.city_world.city_surface_feature_change_version
		)

	if first_rock_tile != Vector2i(-1, -1):
		_expect(
			CityNavigationSystem.is_city_tile_walkable_for_citizen_for_city_state(
				city_state,
				renderer.city_world,
				first_rock_tile
			),
			"A rock tile must remain walkable."
		)

	_expect(
		WorldData.get_city_surface_feature_resource_type(
			WorldData.CITY_SURFACE_FEATURE_TREE
		)
		== WorldData.RESOURCE_LUMBER,
		"Trees must map to lumber for future foraging."
	)
	_expect(
		WorldData.get_city_surface_feature_resource_type(
			WorldData.CITY_SURFACE_FEATURE_ROCK
		)
		== WorldData.RESOURCE_STONE,
		"Rocks must map to stone for future foraging."
	)

	var previous_view_mode: int = renderer.settlement_ui_controller.view_mode
	renderer.set_city_view_mode(MapVisuals.ViewMode.RESOURCES)
	_expect(
		not renderer.should_draw_city_trees()
		and not renderer.settlement_natural_feature_presenter.tree_multimesh_instance.visible,
		"Trees must be hidden without redrawing citizens in Resources mode."
	)
	renderer.set_city_view_mode(MapVisuals.ViewMode.BIOME)
	_expect(
		renderer.should_draw_city_trees()
		and renderer.settlement_natural_feature_presenter.tree_multimesh_instance.visible,
		"Trees must remain retained and visible outside Resources mode."
	)
	renderer.set_city_view_mode(previous_view_mode)

	_test_city_keep_accepts_tree_covered_access(city_state)


func _test_settlement_natural_feature_presenter_binding(
	renderer: CityRenderer
) -> void:
	var presenter = (
		renderer.settlement_natural_feature_presenter
	)
	var current_binding: CityPresentationBindingScript = (
		renderer.get_city_presentation_binding()
	)
	var binding_generation := current_binding.generation
	_expect(
		presenter != null
		and presenter.get_parent() == renderer
		and presenter.is_bound_to_settlement_presentation(
			current_binding
		)
		and presenter.tree_multimesh_instance != null
		and presenter.rock_multimesh_instance != null
		and presenter.tree_multimesh_instance.get_parent() == presenter
		and presenter.rock_multimesh_instance.get_parent() == presenter,
		"The settlement presenter must physically own retained natural-feature state and nodes."
	)

	var missing_capability_binding := SettlementPresentationBindingScript.new()
	var missing_capability_bound := missing_capability_binding.rebind(
		renderer.bound_settlement_context,
		binding_generation + 1
	)
	_expect(
		missing_capability_bound
		and not presenter.bind_settlement_presentation(
			missing_capability_binding
		)
		and presenter.is_bound_to_settlement_presentation(
			current_binding
		),
		"The natural-feature owner must reject a registered identity that lacks exact world and seed capabilities."
	)

	var isolated_presenter = SettlementNaturalFeaturePresenterScript.new()
	var isolated_binding := CityPresentationBindingScript.new()
	var isolated_stale_binding := CityPresentationBindingScript.new()
	var isolated_newer_binding := CityPresentationBindingScript.new()
	var isolated_bindings_valid := (
		isolated_binding.rebind(renderer.bound_settlement_context, 5)
		and isolated_stale_binding.rebind(
			renderer.bound_settlement_context,
			4
		)
		and isolated_newer_binding.rebind(
			renderer.bound_settlement_context,
			6
		)
	)
	var retained_tree_multimesh := MultiMesh.new()
	_expect(
		isolated_bindings_valid
		and isolated_presenter.bind_settlement_presentation(isolated_binding)
		and not isolated_presenter.bind_settlement_presentation(
			isolated_stale_binding
		)
		and isolated_presenter.accepts_generation(5),
		"The settlement presenter must reject stale registered bindings transactionally."
	)
	isolated_presenter.tree_multimesh = retained_tree_multimesh
	isolated_presenter.tree_index_by_tile[Vector2i(1, 1)] = 0
	_expect(
		isolated_presenter.bind_settlement_presentation(
			isolated_newer_binding
		)
		and is_same(
			isolated_presenter.tree_multimesh,
			retained_tree_multimesh
		)
		and isolated_presenter.tree_index_by_tile.has(Vector2i(1, 1)),
		"A fresh token for the exact same settlement source must preserve retained features."
	)
	isolated_presenter.free()


func _test_city_keep_accepts_tree_covered_access(
	city_state: CitySettlementSimulationState
) -> void:
	var keep_size := CityObjectCatalog.get_city_object_size_for_type(
		CityObjectCatalog.CITY_OBJECT_CITY_CENTER
	)
	var test_world := WorldData.new()
	test_world.setup(
		keep_size.x + 2,
		keep_size.y + 2,
		9091
	)
	var keep_top_left := Vector2i.ONE
	for y in range(test_world.height):
		for x in range(test_world.width):
			var tile_position := Vector2i(x, y)
			test_world.set_tile_terrain(
				tile_position,
				WorldData.TERRAIN_LAND
			)

			if (
				x == 0
				or y == 0
				or x == test_world.width - 1
				or y == test_world.height - 1
			):
				test_world.set_tile_surface_feature(
					tile_position,
					WorldData.CITY_SURFACE_FEATURE_TREE
				)

	var original_city_world: WorldData = city_state.city_world
	city_state.city_world = test_world
	var can_place_keep := (
		CityObjectSystem.can_place_city_object_for_city_state(
			city_state,
			test_world,
			keep_top_left,
			keep_size,
			CityObjectCatalog.CITY_OBJECT_CITY_CENTER
		)
	)
	city_state.city_world = original_city_world
	_expect(
		can_place_keep,
		"A City Keep must accept tree-covered access tiles."
	)


func _prepare_dev_city_region() -> void:
	DevCityLauncher.reset_dev_city_state()

	var generator := WorldGenerator.new()
	var dev_world := generator.generate_world(
		DevCityLauncher.DEV_WORLD_SEED
	)
	var region_top_left := DevCityLauncher.find_good_dev_region(
		dev_world,
		DevCityLauncher.DEV_REGION_SIZE
	)
	var region_center := region_top_left + Vector2i(
		int(DevCityLauncher.DEV_REGION_SIZE / 2),
		int(DevCityLauncher.DEV_REGION_SIZE / 2)
	)

	_expect(
		region_top_left != Vector2i(-1, -1),
		"Dev city region must be found."
	)

	SimulationClock.start_new_game()
	var world_lock_succeeded := WorldData.lock_world_save({
		"source_world": dev_world,
		"region_top_left": region_top_left,
		"region_center": region_center,
		"region_size": DevCityLauncher.DEV_REGION_SIZE,
		"world_scene_path": "res://scenes/MainMenu.tscn",
		"city_scene_path": "res://scenes/CityScreen.tscn",
		"city_name": TEST_CITY_NAME,
		"culture_name": TEST_CULTURE_NAME,
	})
	_expect(
		world_lock_succeeded,
		"The smoke-test world and founding identity must lock."
	)


func _test_resource_catalog_and_bulk_totals() -> void:
	var expected_resources: Array[String] = [
		WorldData.RESOURCE_FISH,
		WorldData.RESOURCE_MEAT,
		WorldData.RESOURCE_LUMBER,
		WorldData.RESOURCE_STONE,
		WorldData.RESOURCE_COAL,
		WorldData.RESOURCE_IRON,
		WorldData.RESOURCE_GOLD,
	]

	_expect(
		CityResourceCatalog.get_city_resource_types() == expected_resources,
		"Resource catalog order must remain stable."
	)
	_expect(
		CityResourceCatalog.is_city_resource_type(WorldData.RESOURCE_MEAT),
		"Meat must be a valid city resource."
	)
	_expect(
		not CityResourceCatalog.is_city_resource_type("invalid_resource"),
		"Unknown resource IDs must remain invalid."
	)
	_expect(
		CityResourceCatalog.get_city_food_hunger_restore(
			WorldData.RESOURCE_MEAT
		)
		== 20,
		"Meat nutrition must remain 20."
	)

	var fishery_definition := CityObjectCatalog.get_city_object_definition(
		CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS
	)
	var fishery_source_policy: Dictionary = (
		fishery_definition.get("resource_source_policy", {})
	)
	_expect(
		int(fishery_source_policy.get("reach_tiles", 0)) == 8,
		"Fishing Grounds reach must remain eight tiles."
	)
	_expect(
		int(
			fishery_source_policy.get(
				"source_density_for_full_productivity_basis_points",
				0
			)
		)
		== 1_000,
		"Fishing Grounds full productivity must require 10% fish density."
	)
	var fishery_recipe: Dictionary = fishery_definition.get(
		"production_recipe",
		{}
	)
	_expect(
		int(fishery_recipe.get("work_units_per_batch", 0)) == 120_000,
		"Fishing Grounds must require two worker-hours per fish."
	)


	var house_definition := CityObjectCatalog.get_city_object_definition(
		CityObjectCatalog.CITY_OBJECT_HOUSE
	)
	var house_container_policy: Dictionary = house_definition.get(
		"container_access_policy",
		{}
	)
	_expect(
		not bool(
			house_container_policy.get(
				CityObjectCatalog.CONTAINER_ACCESS_COUNTS_TOWARD_CITY_OWNED_TOTALS,
				true
			)
		),
		"Private house storage must not count as secured city resources."
	)

	var city_generator := CityWorldGeneratorScript.new()
	for biome in [
		WorldData.BIOME_PLAIN,
		WorldData.BIOME_FOREST,
		WorldData.BIOME_TAIGA,
		WorldData.BIOME_JUNGLE,
		WorldData.BIOME_TUNDRA,
		WorldData.BIOME_DESERT,
	]:
		_expect(
			city_generator.get_sparse_rock_base_spawn_chance(biome) > 0.0,
			"Every non-hill land biome must retain sparse rock generation."
		)
		_expect(
			city_generator.get_rock_cluster_spawn_chance(biome) > 0.0,
			"Every land biome must support local rock clusters."
		)

	_expect(
		city_generator.get_rock_cluster_spawn_chance(
			WorldData.BIOME_HILLS
		)
		> city_generator.get_rock_cluster_spawn_chance(
			WorldData.BIOME_PLAIN
		),
		"Hill rock clusters must remain denser than plain clusters."
	)


func _test_ground_pile_coalescing(
	renderer: CityRenderer
) -> void:
	var city_state := _get_registered_renderer_city_state(renderer)
	_expect(
		city_state != null,
		"Ground-pile coverage requires the registered renderer state."
	)
	if city_state == null:
		return
	var test_tiles := _find_ground_pile_test_pair(
		city_state,
		renderer.city_world
	)

	_expect(
		test_tiles.size() == 2,
		"The dev city must expose two nearby ground-pile tiles."
	)

	if test_tiles.size() != 2:
		return

	var anchor_tile: Vector2i = test_tiles[0]
	var overflow_tile: Vector2i = test_tiles[1]
	var first_amount := CityLogisticsSystem.CITY_GROUND_PILE_CAPACITY - 2

	_expect(
		CityLogisticsSystem.CITY_GROUND_PILE_MERGE_RADIUS_TILES == 2,
		"Ground-pile coalescing radius must remain exactly two tiles."
	)
	var anchor_add_result := (
		CityLogisticsSystem.add_resource_to_city_ground_piles_with_result_for_city_state(
			city_state,
			{
				"tile_position": anchor_tile,
				"resource": WorldData.RESOURCE_LUMBER,
				"amount_delta": first_amount,
			}
		)
	)
	_expect(
		int(anchor_add_result.get("added_amount", 0)) == first_amount,
		"The anchor ground pile must accept its initial lumber."
	)
	var overflow_add_result := (
		CityLogisticsSystem.add_resource_to_city_ground_piles_with_result_for_city_state(
			city_state,
			{
				"tile_position": overflow_tile,
				"resource": WorldData.RESOURCE_LUMBER,
				"amount_delta": 4,
			}
		)
	)
	_expect(
		int(overflow_add_result.get("added_amount", 0)) == 4,
		"A nearby lumber drop must be accepted atomically."
	)

	var lumber_piles: Array = []

	for raw_ground_pile in (
		CityLogisticsSystem.get_city_ground_pile_snapshot_for_city_state(
			city_state
		)
	):
		if not raw_ground_pile is Dictionary:
			continue

		var ground_pile: Dictionary = raw_ground_pile

		if str(
			ground_pile.get(
				"resource_type",
				WorldData.RESOURCE_NONE
			)
		) == WorldData.RESOURCE_LUMBER:
			lumber_piles.append(ground_pile)

	_expect(
		lumber_piles.size() == 2,
		"A full coalesced pile must leave one overflow pile at the new drop tile."
	)

	var found_full_anchor := false
	var found_origin_overflow := false

	for raw_ground_pile in lumber_piles:
		var ground_pile: Dictionary = raw_ground_pile
		var pile_tile: Vector2i = ground_pile.get(
			"tile_position",
			CityCitizens.INVALID_CITY_TILE_POSITION
		)
		var pile_amount := int(ground_pile.get("amount", 0))

		if (
			pile_tile == anchor_tile
			and pile_amount == CityLogisticsSystem.CITY_GROUND_PILE_CAPACITY
		):
			found_full_anchor = true
		elif pile_tile == overflow_tile and pile_amount == 2:
			found_origin_overflow = true

	_expect(
		found_full_anchor,
		"Nearby lumber must fill the original pile only to capacity."
	)
	_expect(
		found_origin_overflow,
		"Overflow lumber must remain where the new resource was collected."
	)

	for raw_ground_pile in lumber_piles:
		var ground_pile: Dictionary = raw_ground_pile
		var amount := int(ground_pile.get("amount", 0))

		_expect(
			CityLogisticsSystem.remove_resource_from_city_ground_pile_for_city_state(
				city_state,
				int(ground_pile.get("id", -1)),
				WorldData.RESOURCE_LUMBER,
				amount
			) == amount,
			"Ground-pile fixture cleanup must remove every test unit."
		)


func _find_ground_pile_test_pair(
	city_state: CitySettlementSimulationState,
	city_world: WorldData
) -> Array:
	if city_state == null or city_world == null:
		return []

	for y in range(city_world.height):
		for x in range(city_world.width):
			var anchor_tile := Vector2i(x, y)

			if not CityLogisticsSystem.can_city_ground_pile_exist_at_tile_for_city_state(
				city_state,
				city_world,
				anchor_tile
			):
				continue

			for offset_y in range(-2, 3):
				for offset_x in range(-2, 3):
					if offset_x == 0 and offset_y == 0:
						continue

					var candidate_tile := (
						anchor_tile
						+ Vector2i(offset_x, offset_y)
					)

					if (
						CityLogisticsSystem.get_city_ground_pile_tile_distance_squared(
							anchor_tile,
							candidate_tile
						)
						> 4
					):
						continue

					if CityLogisticsSystem.can_city_ground_pile_exist_at_tile_for_city_state(
						city_state,
						city_world,
						candidate_tile
					):
						return [anchor_tile, candidate_tile]

	return []


func _place_and_validate_city_fixture(
	renderer: CityRenderer
) -> void:
	var city_state := _get_registered_renderer_city_state(renderer)
	_expect(
		city_state != null,
		"Immediate-placement coverage requires the registered renderer state."
	)
	if city_state == null:
		return
	var keep_size := CityObjectCatalog.get_city_object_size_for_type(
		CityObjectCatalog.CITY_OBJECT_CITY_CENTER
	)
	var keep_top_left := _find_placeable_rectangle(
		city_state,
		renderer.city_world,
		keep_size,
		CityObjectCatalog.CITY_OBJECT_CITY_CENTER
	)

	_expect(
		keep_top_left != Vector2i(-1, -1),
		"A placeable City Keep footprint must exist."
	)

	if keep_top_left == Vector2i(-1, -1):
		return

	var keep_footprint := (
		CityObjectSystem.make_rectangle_city_object_footprint_tiles(
			keep_top_left,
			keep_size
		)
	)
	_normalize_surface_feature_fixture(
		renderer.city_world,
		keep_footprint
	)
	var tree_test_tile := keep_top_left
	var rock_test_tile := keep_top_left + Vector2i(1, 0)
	_expect(
		renderer.city_world.set_tile_surface_feature(
			tree_test_tile,
			WorldData.CITY_SURFACE_FEATURE_TREE
		)
		and renderer.city_world.set_tile_surface_feature(
			rock_test_tile,
			WorldData.CITY_SURFACE_FEATURE_ROCK
		),
		"The immediate-placement fixture must publish tree and rock features through WorldData."
	)
	renderer.rebuild_city_natural_feature_multimeshes()
	renderer.city_presentation_invalidation_tracker.observed_city_surface_feature_change_version = (
		renderer.city_world.city_surface_feature_change_version
	)
	renderer.city_world.consume_city_surface_feature_changes()
	renderer.city_world.mark_tile_data_changed()
	var tile_data_version_before_placement := (
		renderer.city_world.tile_data_version
	)
	var surface_feature_version_before_placement := (
		renderer.city_world.city_surface_feature_change_version
	)

	_expect(
		CityObjectSystem.can_place_city_object_for_city_state(
			city_state,
			renderer.city_world,
			keep_top_left,
			keep_size,
			CityObjectCatalog.CITY_OBJECT_CITY_CENTER
		),
		"Surface features must not invalidate building placement."
	)

	_expect(
		WorldPoliticalState.synchronize_foundation_with_world_data(),
		"The atomic foundation fixture must establish its target capital context."
	)
	city_state = WorldPoliticalState.get_city_simulation_state(
		renderer.bound_settlement_context.settlement_id
	)
	_expect(
		city_state is CitySettlementSimulationState,
		"Immediate placement must resolve a target settlement state."
	)
	if not city_state is CitySettlementSimulationState:
		return

	var object_count_before_failure: int = city_state.object_state.objects.size()
	var next_object_id_before_failure: int = (
		city_state.object_state.next_object_id
	)
	var runtime_before_failure: Dictionary = (
		city_state.city_runtime_data.duplicate(true)
	)
	var citizen_count_before_failure: int = (
		city_state.citizen_registry_state.citizens.size()
	)
	var population_marker_before_failure: bool = (
		city_state.citizen_registry_state.starting_population_initialized
	)
	var valid_city_seed: int = renderer.city_seed
	var failed_keep_values := {
		"object_type": CityObjectCatalog.CITY_OBJECT_CITY_CENTER,
		"top_left": keep_top_left,
		"size_tiles": keep_size,
		"object_owner": "player",
		"settlement_world": renderer.city_world,
	}

	# A zero seed is rejected by the local foundation transaction after the Keep
	# has registered. The object owner must roll that exact object back before a
	# retry; presentation never owns either side of this transaction.
	renderer.city_seed = 0
	failed_keep_values["settlement_seed"] = renderer.city_seed
	var failed_keep := (
		CityObjectSystem.place_immediate_settlement_object_for_context(
			renderer.bound_settlement_context,
			failed_keep_values
		)
	)
	renderer.city_seed = valid_city_seed
	failed_keep_values["settlement_seed"] = renderer.city_seed
	var state_after_failure = (
		WorldPoliticalState.get_city_simulation_state(
			renderer.bound_settlement_context.settlement_id
		)
	)
	_expect(
		failed_keep.is_empty(),
		"A rejected foundation transaction must report placement failure."
	)
	_expect(
		state_after_failure is CitySettlementSimulationState
		and state_after_failure.object_state.objects.size()
		== object_count_before_failure
		and state_after_failure.object_state.next_object_id
		== next_object_id_before_failure,
		"Rejected foundation placement must leave no Keep and must restore its object ID."
	)
	_expect(
		state_after_failure is CitySettlementSimulationState
		and state_after_failure.city_runtime_data == runtime_before_failure
		and state_after_failure.citizen_registry_state.citizens.size()
		== citizen_count_before_failure
		and state_after_failure.citizen_registry_state.starting_population_initialized
		== population_marker_before_failure,
		"Rejected foundation placement must leave no runtime or starting-population residue."
	)
	var failed_footprint_is_clear := true
	if state_after_failure is CitySettlementSimulationState:
		for raw_tile in keep_footprint:
			if (
				raw_tile is Vector2i
				and CityObjectSystem.get_city_object_id_at_tile_for_city_state(
					state_after_failure,
					raw_tile
				) > 0
			):
				failed_footprint_is_clear = false
				break
	_expect(
		failed_footprint_is_clear,
		"Rejected foundation placement must release every occupied Keep tile."
	)
	_expect(
		WorldData.get_city_surface_feature(
			renderer.city_world.get_tile(tree_test_tile.x, tree_test_tile.y)
		) == WorldData.CITY_SURFACE_FEATURE_TREE
		and WorldData.get_city_surface_feature(
			renderer.city_world.get_tile(rock_test_tile.x, rock_test_tile.y)
		) == WorldData.CITY_SURFACE_FEATURE_ROCK
		and renderer.city_world.city_surface_feature_change_version
		== surface_feature_version_before_placement,
		"Rejected foundation placement must not clear local surface features."
	)

	city_state = WorldPoliticalState.get_city_simulation_state(
		renderer.bound_settlement_context.settlement_id
	)
	var keep := CityObjectSystem.place_immediate_settlement_object_for_context(
		renderer.bound_settlement_context,
		failed_keep_values
	)
	renderer.city_information_ui.refresh_all()
	_expect(
		int(keep.get("id", -1)) == next_object_id_before_failure,
		"A successful foundation retry must reuse the rolled-back object ID."
	)

	_expect(
		WorldData.get_city_surface_feature(
			renderer.city_world.get_tile(
				tree_test_tile.x,
				tree_test_tile.y
			)
		)
		== WorldData.CITY_SURFACE_FEATURE_NONE,
		"Placed buildings must remove covered trees."
	)
	_expect(
		WorldData.get_city_surface_feature(
			renderer.city_world.get_tile(
				rock_test_tile.x,
				rock_test_tile.y
			)
		)
		== WorldData.CITY_SURFACE_FEATURE_NONE,
		"Placed buildings must remove covered rocks."
	)
	_expect(
		renderer.city_world.tile_data_version
		== tile_data_version_before_placement,
		"Placement must not invalidate broad city tile data."
	)
	_expect(
		renderer.city_world.city_surface_feature_change_version
		== surface_feature_version_before_placement + 2,
		"Placement must publish one incremental change per removed feature."
	)

	var primary_culture_id := int(
		city_state.city_runtime_data.get(
			"primary_culture_id",
			WorldData.INVALID_CULTURE_ID
		)
	)
	_expect(
		str(city_state.city_runtime_data.get("name", ""))
		== TEST_CITY_NAME,
		"City Keep placement must use the committed official city name."
	)
	_expect(
		primary_culture_id
		== WorldData.get_official_founding_culture_id()
		and WorldData.get_culture_name_by_id(primary_culture_id)
		== TEST_CULTURE_NAME,
		"The founded city's primary culture must resolve to the committed culture."
	)

	_expect(
		CityCitizenRegistrySystem.get_city_population_count_for_city_state(
			city_state
		)
		== CityCitizenRegistrySystem.STARTING_CITY_POPULATION,
		"Founding must still create the starting population."
	)

	var all_founders_share_primary_culture := true

	for raw_citizen in city_state.citizen_registry_state.citizens:
		if (
			not raw_citizen is Dictionary
			or raw_citizen.get("culture_id") != primary_culture_id
		):
			all_founders_share_primary_culture = false
			break

	_expect(
		all_founders_share_primary_culture,
		"Every starting citizen must reference the city's primary culture."
	)

	var keep_id := int(keep.get("id", -1))
	var before_totals := (
		CityResourceAccountingSystem
			.get_total_owned_city_resource_amounts_for_city_state(city_state)
	)
	_expect(
		int(before_totals.get(WorldData.RESOURCE_FISH, 0))
		== 0,
		"Fixture must begin without fish."
	)

	var accepted_fish := (
		CityResourceContainerSystem
			.add_resource_to_city_object_storage_for_city_state(
				city_state,
				keep_id,
				WorldData.RESOURCE_FISH,
				3
			)
	)
	_expect(accepted_fish == 3, "Keep must accept three fish.")
	_expect(
		int(
			CityResourceAccountingSystem
				.get_total_owned_city_resource_amounts_for_city_state(city_state)
				.get(WorldData.RESOURCE_FISH, 0)
		)
		== 3,
		"Bulk owned-resource cache must invalidate after storage changes."
	)


	var first_citizen: Dictionary = city_state.citizen_registry_state.citizens[0]
	var first_citizen_id := int(first_citizen.get("id", -1))
	var removed_fish := (
		CityResourceContainerSystem
			.remove_resource_from_city_object_storage_for_city_state(
				city_state,
				keep_id,
				WorldData.RESOURCE_FISH,
				1
			)
	)
	var carried_fish := (
		CityCitizenInventorySystem
			.set_city_citizen_haul_cargo_for_city_state(
				city_state,
				first_citizen_id,
				WorldData.RESOURCE_FISH,
				removed_fish
			)
	)
	_expect(
		removed_fish == 1 and carried_fish == 1,
		"Fixture haul pickup must succeed."
	)
	_expect(
		int(
			CityResourceAccountingSystem
				.get_total_owned_city_resource_amounts_for_city_state(city_state)
				.get(WorldData.RESOURCE_FISH, 0)
		)
		== 2,
		"In-transit citizen cargo must not count as secured city resources."
	)
	_expect(
		CityResourceAccountingSystem
			.get_total_physical_city_resource_amount_for_city_state(
				city_state,
				WorldData.RESOURCE_FISH
			)
		== 3,
		"Resource conservation must still include in-transit cargo."
	)
	CityCitizenInventorySystem.set_city_citizen_haul_cargo_for_city_state(
		city_state,
		first_citizen_id,
		WorldData.RESOURCE_NONE,
		0
	)
	CityResourceContainerSystem.add_resource_to_city_object_storage_for_city_state(
		city_state,
		keep_id,
		WorldData.RESOURCE_FISH,
		1
	)

	var mixed_cargo := CityCitizens.make_city_citizen_haul_cargo({
		"resources": {
			WorldData.RESOURCE_LUMBER: 4,
			WorldData.RESOURCE_STONE: 4,
			WorldData.RESOURCE_FISH: 2,
		},
	})
	_expect(
		int(mixed_cargo.get("amount", 0)) == 10,
		"Mixed haul cargo must sum every resource amount."
	)
	var mixed_resources: Dictionary = mixed_cargo.get("resources", {})
	_expect(
		int(mixed_resources.get(WorldData.RESOURCE_LUMBER, 0)) == 4
		and int(mixed_resources.get(WorldData.RESOURCE_STONE, 0)) == 4
		and int(mixed_resources.get(WorldData.RESOURCE_FISH, 0)) == 2,
		"Mixed haul cargo must preserve its 4 + 4 + 2 manifest."
	)
	_expect(
		CityCitizenInventorySystem.set_city_citizen_haul_cargo_resources_for_city_state(
			city_state,
			first_citizen_id,
			mixed_cargo.get("resources", {})
		) == 10,
		"A citizen with capacity ten must accept a full mixed load."
	)
	_expect(
		CityCitizenInventorySystem.get_city_citizen_haul_cargo_resource_amount_for_city_state(
			city_state,
			first_citizen_id,
			WorldData.RESOURCE_STONE
		) == 4,
		"Mixed cargo lookup must return the requested resource amount."
	)
	CityCitizenInventorySystem.set_city_citizen_haul_cargo_resources_for_city_state(
		city_state,
		first_citizen_id,
		{}
	)

	var chained_haul := CityCitizens.make_city_citizen_haul({
		"allow_ground_pile_pickup_chaining": true,
		"pickup_stop_count": 3,
	})
	_expect(
		bool(
			chained_haul.get(
				"allow_ground_pile_pickup_chaining",
				false
			)
		)
		and int(chained_haul.get("pickup_stop_count", 0)) == 3,
		"Haul state must preserve multi-stop ground-pile routing."
	)

	var first_access_tiles := CityNavigationSystem.get_city_object_access_tiles_for_city_state(
		city_state,
		renderer.city_world,
		keep
	)
	var second_access_tiles := CityNavigationSystem.get_city_object_access_tiles_for_city_state(
		city_state,
		renderer.city_world,
		keep
	)
	_expect(
		not first_access_tiles.is_empty(),
		"Keep must expose citizen access tiles."
	)
	_expect(
		first_access_tiles == second_access_tiles,
		"Cached access tiles must preserve deterministic results."
	)

	if not first_access_tiles.is_empty():
		first_access_tiles.clear()
		_expect(
			not CityNavigationSystem.get_city_object_access_tiles_for_city_state(
				city_state,
				renderer.city_world,
				keep
			).is_empty(),
			"Access-tile callers must not mutate the cached array."
		)


func _test_universal_construction_core(
	renderer: CityRenderer
) -> void:
	var city_state := _get_registered_renderer_city_state(renderer)
	_expect(
		city_state != null,
		"Construction coverage requires the registered renderer state."
	)
	if city_state == null:
		return
	_expect(
		not city_state.citizen_registry_state.citizens.is_empty(),
		"Construction coverage requires a starting citizen."
	)

	if city_state.citizen_registry_state.citizens.is_empty():
		return

	var citizen_id := int(
		city_state.citizen_registry_state.citizens[0].get("id", -1)
	)
	var keep_access_tiles: Array = []

	for raw_object in CityObjectSystem.get_city_objects_for_city_state(city_state):
		if (
			raw_object is Dictionary
			and str(raw_object.get("type", ""))
			== CityObjectCatalog.CITY_OBJECT_CITY_CENTER
		):
			keep_access_tiles = CityNavigationSystem.get_city_object_access_tiles_for_city_state(
				city_state,
				renderer.city_world,
				raw_object
			)
			break

	_expect(
		not keep_access_tiles.is_empty(),
		"Construction coverage requires reachable City Keep access."
	)

	if keep_access_tiles.is_empty():
		return

	var house_size := CityObjectCatalog.get_city_object_size_for_type(
		CityObjectCatalog.CITY_OBJECT_HOUSE
	)
	var house_top_left := _find_reachable_construction_rectangle(
		city_state,
		renderer.city_world,
		house_size,
		CityObjectCatalog.CITY_OBJECT_HOUSE,
		citizen_id,
		keep_access_tiles
	)

	_expect(
		house_top_left != CityCitizens.INVALID_CITY_TILE_POSITION,
		"A construction-enabled House footprint must exist."
	)

	if house_top_left == CityCitizens.INVALID_CITY_TILE_POSITION:
		return

	var house_footprint := (
		CityObjectSystem.make_rectangle_city_object_footprint_tiles(
			house_top_left,
			house_size
		)
	)
	_normalize_surface_feature_fixture(
		renderer.city_world,
		house_footprint
	)
	var tree_tile := house_top_left
	var rock_tile := house_top_left + Vector2i(1, 0)
	var cleanup_tile := house_top_left + Vector2i(2, 0)
	_expect(
		renderer.city_world.set_tile_surface_feature(
			tree_tile,
			WorldData.CITY_SURFACE_FEATURE_TREE
		)
		and renderer.city_world.set_tile_surface_feature(
			rock_tile,
			WorldData.CITY_SURFACE_FEATURE_ROCK
		),
		"The construction fixture must publish tree and rock features through WorldData."
	)
	renderer.city_world.remove_tile_surface_feature(cleanup_tile)
	renderer.rebuild_city_natural_feature_multimeshes()
	renderer.city_presentation_invalidation_tracker.observed_city_surface_feature_change_version = (
		renderer.city_world.city_surface_feature_change_version
	)
	renderer.city_world.consume_city_surface_feature_changes()

	var house_site := (
		CityConstructionSystemScript.create_rectangular_site_for_city_state(
			city_state,
			{
				"object_type": CityObjectCatalog.CITY_OBJECT_HOUSE,
				"top_left": house_top_left,
				"size_tiles": house_size,
				"object_owner": "player",
				"city_world": renderer.city_world,
			}
		)
	)
	var house_site_id := int(house_site.get("id", -1))

	_expect(house_site_id > 0, "House placement must create a blueprint.")

	if house_site_id <= 0:
		return

	var initial_progress := (
		CityConstructionSystemScript.get_city_construction_site_progress_summary_for_city_state(
			city_state,
			house_site_id
		)
	)
	_expect(
		int(initial_progress.get("progress_percent", -1)) == 0,
		"A newly placed obstructed blueprint must begin at zero percent."
	)
	_expect(
		float(
			initial_progress.get(
				"required_clearing_work_units",
				0.0
			)
		) > 0.0,
		"Construction progress must include required clearing work."
	)

	renderer.set_selected_city_construction_site(house_site_id)
	_expect(
		renderer.selected_city_construction_site_id == house_site_id
		and renderer.settlement_entity_panel_presentation.construction_site_info_panel.visible,
		"Selecting a blueprint must open its compact construction panel."
	)
	_expect(
		renderer.settlement_entity_panel_presentation.construction_site_info_title_label.text
		== "Construction Progress: 0%",
		"The construction panel must display the calculated percentage."
	)
	_expect(
		renderer.settlement_entity_panel_presentation.construction_site_info_body_label.text.contains(
			"Lumber: 0/8"
		)
		and renderer.settlement_entity_panel_presentation.construction_site_info_body_label.text.contains(
			"Stone: 0/4"
		),
		"The panel must list the blueprint's live data-driven recipe."
	)
	var panel_size_before_zoom := (
		renderer.settlement_entity_panel_presentation.construction_site_info_panel.size
	)
	var original_camera_zoom := renderer.camera.zoom
	renderer.camera.zoom = original_camera_zoom * 1.5
	renderer.update_construction_site_info_panel_screen_position()
	var panel_size_after_zoom := (
		renderer.settlement_entity_panel_presentation.construction_site_info_panel.size
	)
	_expect(
		is_equal_approx(
			panel_size_after_zoom.x,
			panel_size_before_zoom.x
		)
		and is_equal_approx(
			panel_size_after_zoom.y,
			panel_size_before_zoom.y
		),
		"Construction panel dimensions must remain screen-constant under zoom. "
			+ "Before: "
			+ str(panel_size_before_zoom)
			+ ", after: "
			+ str(panel_size_after_zoom)
	)
	renderer.camera.zoom = original_camera_zoom
	renderer.update_construction_site_info_panel_screen_position()

	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	renderer._input(right_click)
	_expect(
		renderer.selected_city_construction_site_id < 0
		and not renderer.settlement_entity_panel_presentation.construction_site_info_panel.visible,
		"Right-click must close the construction panel."
	)
	renderer.set_selected_city_construction_site(house_site_id)

	renderer.start_city_object_placement(
		CityObjectCatalog.CITY_OBJECT_HOUSE,
		house_size
	)
	_expect(
		renderer.is_uncommitted_city_placement_preview_active(),
		"A cursor-attached placement ghost must suppress the separate white hover outline."
	)
	renderer.clear_city_object_placement()
	_expect(
		not renderer.is_uncommitted_city_placement_preview_active(),
		"Committing or cancelling placement must restore ordinary world-object hovering."
	)

	for hover_tile in house_footprint:
		_expect(
			renderer.get_city_hover_highlight_tiles(hover_tile)
			== house_footprint,
			"Hovering any House blueprint tile must resolve its full footprint."
		)

	_expect(
		CityObjectSystem.get_city_object_at_tile_for_city_state(
			city_state,
			house_top_left
		).is_empty(),
		"A House blueprint must not be an operational city object."
	)
	_expect(
		str(house_site.get("phase", ""))
		== CityConstructionSystem.CITY_CONSTRUCTION_PHASE_CLEARING,
		"An obstructed House blueprint must begin in clearing."
	)

	var cleanup_add_result := (
		CityLogisticsSystem.add_resource_to_city_ground_piles_with_result_for_city_state(
			city_state,
			{
				"tile_position": cleanup_tile,
				"resource": WorldData.RESOURCE_COAL,
				"amount_delta": 1,
			}
		)
	)
	var cleanup_placements: Array = cleanup_add_result.get(
		"placements",
		[]
	)

	_expect(
		int(cleanup_add_result.get("added_amount", 0)) == 1,
		"An ordinary footprint pile must be creatable for cleanup coverage."
	)

	var cleanup_candidate := (
		CityConstructionSystemScript.get_best_assignable_player_work_for_citizen_for_city_state(
			city_state,
			citizen_id
		)
	)
	_expect(
		not cleanup_candidate.is_empty()
		and int(cleanup_candidate.get("construction_site_id", -1))
		== house_site_id,
		"Clearing must expose ordinary footprint-pile cleanup as player work."
	)

	for raw_placement in cleanup_placements:
		if not raw_placement is Dictionary:
			continue

		CityLogisticsSystem.remove_resource_from_city_ground_pile_for_city_state(
			city_state,
			int(raw_placement.get("ground_pile_id", -1)),
			WorldData.RESOURCE_COAL,
			int(raw_placement.get("amount", 0))
		)

	for clearing_tile in [tree_tile, rock_tile]:
		var command := CityWorkSystem.get_city_player_command_at_tile_for_city_state(
			city_state,
			clearing_tile
		)
		var command_id := int(command.get("id", -1))

		_expect(
			command_id > 0
			and int(command.get("construction_site_id", -1))
			== house_site_id,
			"Each obstruction must expose a site-owned clearing command."
		)

		if command_id <= 0:
			continue

		_expect(
			CityWorkSystem.claim_city_player_command_for_city_state(
				city_state,
				command_id,
				citizen_id
			),
			"The clearing command must be claimable."
		)
		_expect(
			CityWorkSystem.repair_stale_city_player_command_claims_for_city_state(
				city_state
			) == 1,
			"A claim without its matching citizen task must self-repair."
		)
		_expect(
			CityWorkSystem.claim_city_player_command_for_city_state(
				city_state,
				command_id,
				citizen_id
			),
			"A repaired clearing command must become claimable again."
		)
		_expect(
			CityWorkSystem.complete_city_player_command_for_city_state(
				city_state,
				command_id,
				citizen_id
			),
			"Clearing must create physical output atomically."
		)

	CityConstructionSystemScript.refresh_city_construction_site_for_city_state(
		city_state,
		house_site_id
	)
	house_site = CityConstructionSystem.get_city_construction_site_by_id_for_city_state(
		city_state,
		house_site_id
	)

	_expect(
		str(house_site.get("phase", ""))
		== CityConstructionSystem.CITY_CONSTRUCTION_PHASE_GATHERING,
		"A cleared but under-supplied House must enter gathering."
	)
	_expect(
		CityConstructionSystem.get_city_construction_site_reserved_resource_amount_for_city_state(
			city_state,
			house_site_id,
			WorldData.RESOURCE_LUMBER
		) == 4
		and CityConstructionSystem.get_city_construction_site_reserved_resource_amount_for_city_state(
			city_state,
			house_site_id,
			WorldData.RESOURCE_STONE
		) == 4,
		"Needed clearing output must become physical site-owned material."
	)

	var cleared_progress := (
		CityConstructionSystemScript.get_city_construction_site_progress_summary_for_city_state(
			city_state,
			house_site_id
		)
	)
	_expect(
		int(cleared_progress.get("progress_percent", 0)) > 0,
		"Clearing and reserved clearing output must advance total progress."
	)
	renderer.update_selected_entity_panel()
	_expect(
		renderer.settlement_entity_panel_presentation.construction_site_info_body_label.text.contains(
			"Lumber: 4/8"
		)
		and renderer.settlement_entity_panel_presentation.construction_site_info_body_label.text.contains(
			"Stone: 4/4"
		),
		"The open construction panel must live-update delivered materials."
	)

	for raw_ground_pile in (
		CityLogisticsSystem.get_city_ground_pile_snapshot_for_city_state(
			city_state
		)
	):
		if (
			not raw_ground_pile is Dictionary
			or CityLogisticsSystem.get_city_ground_pile_construction_site_id(
				raw_ground_pile
			) != house_site_id
		):
			continue

		var pile_endpoint := CityLogisticsSystem.make_city_ground_pile_haul_endpoint(
			int(raw_ground_pile.get("id", -1))
		)
		_expect(
			not CityLogisticsSystem.city_haul_endpoint_can_provide_resource_for_city_state(
				city_state,
				{
					"endpoint": pile_endpoint,
					"resource": str(raw_ground_pile.get("resource_type", "")),
					"withdrawal_purpose": CityObjectCatalog.CONTAINER_HAUL_PURPOSE_GROUND_PILE_CLEANUP,
					"require_unreserved_amount": true,
				}
			),
			"Ordinary hauling must ignore construction-reserved piles."
		)

	_expect(
		CityConstructionSystem.add_resource_to_city_construction_site_for_city_state(
			city_state,
			house_site_id,
			WorldData.RESOURCE_LUMBER,
			4
		) == 4,
		"Delivered construction material must become a physical site pile."
	)
	CityConstructionSystemScript.refresh_city_construction_site_for_city_state(
		city_state,
		house_site_id
	)
	house_site = CityConstructionSystem.get_city_construction_site_by_id_for_city_state(
		city_state,
		house_site_id
	)

	_expect(
		str(house_site.get("phase", ""))
		== CityConstructionSystem.CITY_CONSTRUCTION_PHASE_LABOR,
		"A fully supplied House must enter labor."
	)

	house_site["completed_labor_minutes"] = int(
		house_site.get("required_labor_minutes", 0)
	)
	CityConstructionSystem.update_city_construction_site_for_city_state(
		city_state,
		house_site
	)
	var completed_house := (
		CityConstructionSystemScript.complete_city_construction_site_for_city_state(
			city_state,
			house_site_id
		)
	)

	_expect(
		str(completed_house.get("type", ""))
		== CityObjectCatalog.CITY_OBJECT_HOUSE,
		"Completed labor must consume material and create the House."
	)
	renderer.update_selected_entity_panel()
	_expect(
		renderer.selected_city_construction_site_id < 0
		and not renderer.settlement_entity_panel_presentation.construction_site_info_panel.visible,
		"Completing a selected site must close its now-invalid panel."
	)

	for hover_tile in house_footprint:
		_expect(
			renderer.get_city_hover_highlight_tiles(hover_tile)
			== house_footprint,
			"Hovering any completed House tile must resolve its full footprint."
		)

	_expect(
		CityConstructionSystem.get_city_construction_site_by_id_for_city_state(
			city_state,
			house_site_id
		).is_empty(),
		"Completed construction must release its blueprint."
	)
	_expect(
		CityConstructionSystem.get_city_construction_site_reserved_resource_amount_for_city_state(
			city_state,
			house_site_id,
			WorldData.RESOURCE_LUMBER
		) == 0,
		"Completed construction must consume every reserved pile."
	)

	var road_tiles := _find_clear_road_construction_tiles(
		city_state,
		renderer.city_world,
		3
	)
	_expect(
		road_tiles.size() == 3,
		"Three clear road construction tiles must exist."
	)

	if road_tiles.size() != 3:
		return

	var road_sites := CityConstructionSystemScript.create_road_sites_for_city_state(
		city_state,
		road_tiles,
		"player",
		renderer.city_world
	)
	_expect(
		road_sites.size() == road_tiles.size(),
		"A painted road must become one independent construction site per tile."
	)

	if road_sites.size() != road_tiles.size():
		return

	var site_id_lookup: Dictionary = {}

	for site_index in range(road_sites.size()):
		var road_site: Dictionary = road_sites[site_index]
		var road_site_id := int(road_site.get("id", -1))
		var footprint_tiles = road_site.get("footprint_tiles", [])
		site_id_lookup[road_site_id] = true
		_expect(
			road_site_id > 0
			and footprint_tiles is Array
			and footprint_tiles.size() == 1
			and footprint_tiles[0] == road_tiles[site_index]
			and road_site.get("material_recipe", {}).is_empty()
			and int(road_site.get("required_labor_minutes", -1)) == 8
			and int(road_site.get("maximum_workers", -1)) == 1,
			"Each road tile must own a labor-only, one-worker, eight-minute blueprint."
		)
		_expect(
			renderer.is_city_construction_site_selectable(road_site),
			"Each road blueprint tile must expose its own progress selection."
		)

	_expect(
		site_id_lookup.size() == road_sites.size(),
		"Every painted road tile must receive a distinct construction-site ID."
	)

	var selected_road_site: Dictionary = road_sites[1]
	var selected_road_site_id := int(selected_road_site.get("id", -1))
	var selected_road_tile: Vector2i = road_tiles[1]
	var road_progress := (
		CityConstructionSystemScript.get_city_construction_site_progress_summary_for_city_state(
			city_state,
			selected_road_site_id
		)
	)
	_expect(
		is_zero_approx(
			float(
				road_progress.get(
					"required_clearing_work_units",
					-1.0
				)
			)
		)
		and int(road_progress.get("progress_percent", -1)) == 0,
		"An unobstructed road tile must begin at zero without phantom clearing work."
	)
	_expect(
		CityConstructionSystem.add_resource_to_city_construction_site_for_city_state(
			city_state,
			selected_road_site_id,
			WorldData.RESOURCE_STONE,
			1
		) == 0,
		"Road construction must reject materials because it is labor-only."
	)
	_expect(
		CityWorkSystem.get_cancel_preview_tiles_for_city_state(
			city_state,
			[selected_road_tile]
		)
		== [selected_road_tile],
		"Cancel Task must resolve only the road blueprint tile inside the box."
	)
	_expect(
		CityConstructionSystemScript.cancel_city_construction_site_for_city_state(
			city_state,
			selected_road_site_id
		),
		"Canceling one road tile must succeed independently."
	)
	_expect(
		CityConstructionSystem.get_city_construction_site_by_id_for_city_state(
			city_state,
			selected_road_site_id
		).is_empty()
		and not CityConstructionSystem.get_city_construction_site_by_id_for_city_state(
			city_state,
			int(road_sites[0].get("id", -1))
		).is_empty()
		and not CityConstructionSystem.get_city_construction_site_by_id_for_city_state(
			city_state,
			int(road_sites[2].get("id", -1))
		).is_empty(),
		"Canceling one road tile must leave the neighboring painted tiles intact."
	)

	var completed_site_id := int(road_sites[0].get("id", -1))
	var completed_site := CityConstructionSystem.get_city_construction_site_by_id_for_city_state(
		city_state,
		completed_site_id
	)
	completed_site["completed_labor_minutes"] = int(
		completed_site.get("required_labor_minutes", 0)
	)
	_expect(
		CityConstructionSystemScript.update_city_construction_site_for_city_state(
			city_state,
			completed_site
		),
		"The road completion fixture must store full tile labor."
	)
	var completed_road := (
		CityConstructionSystemScript.complete_city_construction_site_for_city_state(
			city_state,
			completed_site_id
		)
	)
	_expect(
		not completed_road.is_empty()
		and renderer.is_city_object_selectable(completed_road)
		and CityObjectSystem.get_city_object_footprint_tiles(
			completed_road
		) == [road_tiles[0]],
		"A completed road tile must become one selectable one-tile object."
	)
	_expect(
		CityNavigationSystem.get_city_citizen_movement_step_cost_for_city_state(
			city_state,
			road_tiles[0] + Vector2i.LEFT,
			road_tiles[0]
		) == CityCitizens.CITY_CITIZEN_ROAD_CARDINAL_MOVEMENT_COST,
		"Entering a completed road tile must cost half a normal cardinal step."
	)

	CityConstructionSystemScript.cancel_city_construction_site_for_city_state(
		city_state,
		int(road_sites[2].get("id", -1))
	)


func _find_clear_road_construction_tiles(
	city_state: CitySettlementSimulationState,
	city_world: WorldData,
	required_count: int
) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []

	if city_state == null or city_world == null or required_count <= 0:
		return tiles

	for y in range(city_world.height):
		for x in range(city_world.width):
			var tile_position := Vector2i(x, y)

			if (
				CityConstructionSystem.can_place_city_road_tile_for_city_state(
					city_state,
					city_world,
					tile_position
				)
				and WorldData.get_city_surface_feature(
					city_world.get_tile(x, y)
				) == WorldData.CITY_SURFACE_FEATURE_NONE
				and not CityLogisticsSystem.has_city_ground_pile_at_tile_for_city_state(
					city_state,
					tile_position
				)
				and not CityCitizenSpatialSystem.has_living_city_citizen_at_tile_for_city_state(
					city_state,
					tile_position
				)
			):
				tiles.append(tile_position)

				if tiles.size() >= required_count:
					return tiles

	return tiles


func _find_reachable_construction_rectangle(
	city_state: CitySettlementSimulationState,
	city_world: WorldData,
	size_tiles: Vector2i,
	object_type: String,
	citizen_id: int,
	destination_access_tiles: Array
) -> Vector2i:
	if city_state == null or city_world == null or citizen_id <= 0:
		return CityCitizens.INVALID_CITY_TILE_POSITION

	var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id_for_city_state(
		city_state,
		citizen_id
	)
	var raw_citizen_tile = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if not raw_citizen_tile is Vector2i:
		return CityCitizens.INVALID_CITY_TILE_POSITION

	var citizen_tile: Vector2i = raw_citizen_tile
	var maximum_radius := maxi(city_world.width, city_world.height)
	var maximum_expanded_nodes := maxi(
		city_world.width * city_world.height,
		1
	)
	var keep_path := (
		CityNavigationSystemScript.find_path_to_any_city_tile_for_city_state(
			city_state,
			{
				"city_world": city_world,
				"start_tile": citizen_tile,
				"destination_tiles": destination_access_tiles,
				"max_expanded_nodes": maximum_expanded_nodes,
				"citizen_id": citizen_id,
				"heuristic_weight": 1,
			}
		)
	)

	if not bool(keep_path.get("success", false)):
		return CityCitizens.INVALID_CITY_TILE_POSITION

	for radius in range(maximum_radius + 1):
		for offset_y in range(-radius, radius + 1):
			for offset_x in range(-radius, radius + 1):
				if (
					radius > 0
					and maxi(absi(offset_x), absi(offset_y))
					!= radius
				):
					continue

				var top_left := (
					citizen_tile + Vector2i(offset_x, offset_y)
				)

				if (
					not city_world.is_in_bounds(top_left.x, top_left.y)
					or not city_world.is_in_bounds(
						top_left.x + size_tiles.x - 1,
						top_left.y + size_tiles.y - 1
					)
				):
					continue

				var footprint_tiles := (
					CityObjectSystem.make_rectangle_city_object_footprint_tiles(
						top_left,
						size_tiles
					)
				)
				var footprint_is_clear := true

				for raw_tile in footprint_tiles:
					if (
						raw_tile is Vector2i
						and (
							not CityObjectSystem.get_city_object_at_tile_for_city_state(
								city_state,
								raw_tile
							).is_empty()
							or not CityConstructionSystem.get_city_construction_site_at_tile_for_city_state(
								city_state,
								raw_tile
							).is_empty()
							or
							CityLogisticsSystem.has_city_ground_pile_at_tile_for_city_state(
								city_state,
								raw_tile
							)
							or CityCitizenSpatialSystem.has_living_city_citizen_at_tile_for_city_state(
								city_state,
								raw_tile
							)
						)
					):
						footprint_is_clear = false
						break

				if not footprint_is_clear:
					continue

				var cleanup_tile := (
					top_left + Vector2i(size_tiles.x - 1, 0)
				)
				var corridor_tiles := _make_cardinal_fixture_path(
					citizen_tile,
					cleanup_tile,
					true
				)

				if not _fixture_path_is_clear(city_state, corridor_tiles):
					corridor_tiles = _make_cardinal_fixture_path(
						citizen_tile,
						cleanup_tile,
						false
					)

				if not _fixture_path_is_clear(city_state, corridor_tiles):
					continue

				var fixture_tiles: Array = footprint_tiles.duplicate()

				for corridor_tile in corridor_tiles:
					if not fixture_tiles.has(corridor_tile):
						fixture_tiles.append(corridor_tile)

				for raw_fixture_tile in fixture_tiles:
					if not raw_fixture_tile is Vector2i:
						continue

					var fixture_tile: Vector2i = raw_fixture_tile
					city_world.set_tile_terrain(
						fixture_tile,
						WorldData.TERRAIN_LAND
					)
					city_world.remove_tile_surface_feature(fixture_tile)

				if not CityConstructionSystem.can_place_city_object_construction_for_city_state(
					city_state,
					city_world,
					top_left,
					size_tiles,
					object_type
				):
					continue

				var source_path := (
					CityNavigationSystemScript.find_path_to_any_city_tile_for_city_state(
						city_state,
						{
							"city_world": city_world,
							"start_tile": citizen_tile,
							"destination_tiles": [cleanup_tile],
							"max_expanded_nodes": maximum_expanded_nodes,
							"citizen_id": citizen_id,
							"heuristic_weight": 1,
						}
					)
				)

				if not bool(source_path.get("success", false)):
					continue

				var destination_path := (
					CityNavigationSystemScript.find_path_to_any_city_tile_for_city_state(
						city_state,
						{
							"city_world": city_world,
							"start_tile": cleanup_tile,
							"destination_tiles": destination_access_tiles,
							"max_expanded_nodes": maximum_expanded_nodes,
							"citizen_id": citizen_id,
							"heuristic_weight": 1,
						}
					)
				)

				if bool(destination_path.get("success", false)):
					return top_left

	return CityCitizens.INVALID_CITY_TILE_POSITION


func _make_cardinal_fixture_path(
	start_tile: Vector2i,
	destination_tile: Vector2i,
	horizontal_first: bool
) -> Array[Vector2i]:
	var path: Array[Vector2i] = [start_tile]
	var current_tile := start_tile

	if horizontal_first:
		while current_tile.x != destination_tile.x:
			current_tile.x += (
				1 if destination_tile.x > current_tile.x else -1
			)
			path.append(current_tile)

		while current_tile.y != destination_tile.y:
			current_tile.y += (
				1 if destination_tile.y > current_tile.y else -1
			)
			path.append(current_tile)
	else:
		while current_tile.y != destination_tile.y:
			current_tile.y += (
				1 if destination_tile.y > current_tile.y else -1
			)
			path.append(current_tile)

		while current_tile.x != destination_tile.x:
			current_tile.x += (
				1 if destination_tile.x > current_tile.x else -1
			)
			path.append(current_tile)

	return path


func _fixture_path_is_clear(
	city_state: CitySettlementSimulationState,
	path_tiles: Array[Vector2i]
) -> bool:
	for path_index in range(1, path_tiles.size()):
		var tile_position := path_tiles[path_index]

		if (
			not CityObjectSystem.get_city_object_at_tile_for_city_state(
				city_state,
				tile_position
			).is_empty()
			or not CityConstructionSystem.get_city_construction_site_at_tile_for_city_state(
				city_state,
				tile_position
			).is_empty()
			or CityLogisticsSystem.has_city_ground_pile_at_tile_for_city_state(
				city_state,
				tile_position
			)
		):
			return false

	return true


func _normalize_surface_feature_fixture(
	city_world: WorldData,
	raw_tile_positions: Array
) -> void:
	if city_world == null:
		return

	for raw_tile in raw_tile_positions:
		if not raw_tile is Vector2i:
			continue

		var tile_position: Vector2i = raw_tile
		city_world.remove_tile_surface_feature(tile_position)


func _find_placeable_rectangle(
	city_state: CitySettlementSimulationState,
	city_world: WorldData,
	size_tiles: Vector2i,
	object_type: String = ""
) -> Vector2i:
	if city_state == null or city_world == null:
		return Vector2i(-1, -1)

	for y in range(city_world.height - size_tiles.y + 1):
		for x in range(city_world.width - size_tiles.x + 1):
			var top_left := Vector2i(x, y)

			if CityObjectSystem.can_place_city_object_for_city_state(
				city_state,
				city_world,
				top_left,
				size_tiles,
				object_type
			):
				return top_left

	return Vector2i(-1, -1)


func _get_registered_renderer_city_state(
	renderer: CityRenderer
) -> CitySettlementSimulationState:
	if renderer == null:
		return null
	var settlement_context := renderer.bound_settlement_context
	if (
		settlement_context == null
		or not WorldPoliticalState.is_registered_settlement_context(
			settlement_context
		)
	):
		return null
	return settlement_context.get_city_simulation_state()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error(message)
