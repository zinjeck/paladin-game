extends Node

const WORLD_SCENE := preload("res://scenes/WorldScene.tscn")
const WORLD_RENDERER_SCRIPT := preload(
	"res://scripts/world/rendering/WorldRenderer.gd"
)
const TEST_WORLD_SIZE := Vector2i(32, 32)
const TEST_WORLD_SEED: int = 58_031
const TEST_REGION_CENTER := Vector2i(12, 12)
const TEST_CITY_NAME := "Asterfall"
const TEST_CULTURE_NAME := "Valen"

static var expected_region_top_left := Vector2i(-1, -1)
static var expected_region_center := Vector2i(-1, -1)
static var expected_world_texture_instance_ids: Dictionary = {}

var failure_count: int = 0
var city_view_request_count: int = 0


func _ready() -> void:
	await _run_world_founding_flow_test()
	_finish_test()


func show_city_view(_request: Dictionary = {}) -> void:
	city_view_request_count += 1


func _finish_test() -> void:
	WorldData.reset_runtime_session_state()
	expected_region_top_left = Vector2i(-1, -1)
	expected_region_center = Vector2i(-1, -1)
	expected_world_texture_instance_ids.clear()

	if failure_count > 0:
		push_error(
			"World founding flow test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("World founding flow test passed.")
	get_tree().quit(0)


func _run_world_founding_flow_test() -> void:
	WorldData.reset_runtime_session_state()
	SimulationClock.suspend_simulation()

	var world_scene := WORLD_SCENE.instantiate()
	add_child(world_scene)
	await get_tree().process_frame

	var renderer = world_scene.get_node_or_null("WorldRenderer")
	var camera := world_scene.get_node_or_null("Camera2D") as Camera2D

	_expect(renderer != null, "WorldScene must contain WorldRenderer.")
	_expect(camera != null, "WorldScene must contain Camera2D.")

	if renderer == null or camera == null:
		world_scene.queue_free()
		await get_tree().process_frame
		return

	var test_world := _make_test_world()
	renderer.world = test_world
	renderer.world_start_background.visible = false
	renderer.select_region_button.visible = true
	renderer.rebuild_world_map_textures()
	_test_world_map_cache(renderer, test_world, false)

	_expect(renderer.play_button.disabled, "Play must start disabled.")
	renderer.on_select_region_button_pressed()
	renderer.hovered_tile = TEST_REGION_CENTER

	var camera_process_before_panel := camera.is_processing()
	var camera_input_before_panel := camera.is_processing_input()
	renderer.handle_left_mouse_click()
	await get_tree().process_frame

	_expect(renderer.has_selected_region(), "A valid region must be selected.")
	_expect(renderer.founding_panel_open, "Selecting a region must open the panel.")
	_expect(
		renderer.founding_modal_overlay.visible,
		"The founding modal overlay must be visible."
	)
	_expect(renderer.play_button.disabled, "Play must remain disabled while the panel is open.")
	_expect(
		renderer.founding_panel_save_button.disabled,
		"Save must be disabled while both names are blank."
	)
	_expect(
		renderer.founding_city_name_line_edit.max_length
		== WorldData.MAX_FOUNDING_NAME_LENGTH
		and renderer.founding_culture_name_line_edit.max_length
		== WorldData.MAX_FOUNDING_NAME_LENGTH,
		"Both founding inputs must enforce the shared 40-character maximum."
	)
	_expect(
		renderer.founding_modal_overlay.mouse_filter
		== Control.MOUSE_FILTER_STOP
		and renderer.founding_panel.mouse_filter
		== Control.MOUSE_FILTER_STOP
		and renderer.founding_city_name_line_edit.mouse_filter
		== Control.MOUSE_FILTER_STOP
		and renderer.founding_culture_name_line_edit.mouse_filter
		== Control.MOUSE_FILTER_STOP
		and renderer.city_name_world_label.mouse_filter
		== Control.MOUSE_FILTER_IGNORE,
		"The modal and fields must consume mouse input while the map label ignores it."
	)
	_expect(
		not camera.is_processing()
		and not camera.is_processing_input(),
		"The modal must block camera polling and discrete input."
	)
	_expect(
		renderer.founding_ui_layer.layer
		> renderer.debug_panel_ui.canvas_layer.layer,
		"The founding modal must render above the debug panel."
	)
	_expect(
		renderer.founding_panel.size.y >= 490.0,
		"The founding panel must remain vertically roomy."
	)

	var reserved_space := renderer.founding_panel.find_child(
		"ReservedCultureCustomizationSpace",
		true,
		false
	) as Control
	_expect(
		reserved_space != null
		and reserved_space.custom_minimum_size.y >= 250.0,
		"The panel must preserve a large empty culture-customization area."
	)
	_expect(
		renderer.founding_panel_back_button.position.x
		< renderer.founding_panel_save_button.position.x,
		"Back and Save must occupy opposite sides of the bottom row."
	)

	renderer.founding_city_name_line_edit.text = TEST_CITY_NAME
	renderer.founding_culture_name_line_edit.text = ""
	renderer.on_founding_name_text_changed("")
	_expect(
		renderer.founding_panel_save_button.disabled,
		"Save must remain disabled with only a city name."
	)
	renderer.founding_city_name_line_edit.text = ""
	renderer.founding_culture_name_line_edit.text = TEST_CULTURE_NAME
	renderer.on_founding_name_text_changed("")
	_expect(
		renderer.founding_panel_save_button.disabled,
		"Save must remain disabled with only a culture name."
	)
	renderer.founding_city_name_line_edit.text = "   "
	renderer.on_founding_name_text_changed("")
	_expect(
		renderer.founding_panel_save_button.disabled,
		"Whitespace-only names must not enable Save."
	)

	renderer.founding_city_name_line_edit.text = "  " + TEST_CITY_NAME + "  "
	renderer.founding_culture_name_line_edit.text = "  " + TEST_CULTURE_NAME + "  "
	renderer.on_founding_name_text_changed("")
	_expect(
		not renderer.founding_panel_save_button.disabled,
		"Save must enable when both trimmed names are nonblank."
	)
	renderer.on_founding_panel_save_button_pressed()

	_expect(not renderer.founding_panel_open, "Save must close the panel.")
	_expect(
		camera.is_processing() == camera_process_before_panel
		and camera.is_processing_input() == camera_input_before_panel,
		"Closing the modal must restore prior camera processing state."
	)
	_expect(
		renderer.saved_city_name == TEST_CITY_NAME
		and renderer.saved_culture_name == TEST_CULTURE_NAME,
		"Save must trim and retain both provisional names."
	)
	_expect(not renderer.play_button.disabled, "Saved valid identity must enable Play.")
	_expect(
		renderer.city_name_world_label.visible
		and renderer.city_name_world_label.text == TEST_CITY_NAME,
		"The saved city name must appear above the selected region."
	)
	var selected_region_rect: Rect2 = renderer.get_region_rect(
		renderer.selected_region_top_left
	)
	var displayed_label_size: Vector2 = (
		renderer.city_name_world_label.size
		* renderer.city_name_world_label.scale
	)
	var expected_label_gap: float = (
		renderer.city_name_world_label_screen_gap
		/ maxf(camera.zoom.y, 0.001)
	)
	_expect(
		is_equal_approx(
			renderer.city_name_world_label.position.x
			+ displayed_label_size.x * 0.5,
			selected_region_rect.get_center().x
		)
		and is_equal_approx(
			renderer.city_name_world_label.position.y
			+ displayed_label_size.y
			+ expected_label_gap,
			selected_region_rect.position.y
		),
		"The city label must be centered immediately above the selected region."
	)

	var original_zoom := camera.zoom
	camera.zoom = Vector2(2.0, 2.0)
	renderer.update_city_name_world_label_transform()
	_expect(
		is_equal_approx(renderer.city_name_world_label.scale.x, 0.5)
		and is_equal_approx(renderer.city_name_world_label.scale.y, 0.5),
		"The city label must inverse-scale with camera zoom for readability."
	)
	camera.zoom = original_zoom
	renderer.update_city_name_world_label_transform()

	renderer.open_founding_panel()
	_expect(
		renderer.founding_city_name_line_edit.text == TEST_CITY_NAME
		and renderer.founding_culture_name_line_edit.text == TEST_CULTURE_NAME,
		"Reopening a saved region must prefill both names."
	)
	_expect(
		renderer.play_button.disabled,
		"Play must be disabled while editing a saved identity."
	)
	renderer.handle_right_mouse_click()
	_expect(
		renderer.has_selected_region(),
		"World right-click handling must not clear a region while the panel is open."
	)
	var revised_city_name := TEST_CITY_NAME + " Revised"
	renderer.founding_city_name_line_edit.text = revised_city_name
	renderer.on_founding_name_text_changed("")
	renderer.on_founding_panel_save_button_pressed()
	_expect(
		renderer.saved_city_name == revised_city_name
		and renderer.city_name_world_label.text == revised_city_name
		and not renderer.play_button.disabled,
		"Resaving edits must update the provisional identity and world label."
	)
	renderer.open_founding_panel()
	renderer.on_founding_panel_back_button_pressed()
	_expect(
		not renderer.has_selected_region()
		and not renderer.has_provisional_founding_identity
		and renderer.play_button.disabled
		and not renderer.city_name_world_label.visible
		and renderer.region_cursor_state
		== WORLD_RENDERER_SCRIPT.RegionCursorState.REGION_PLACE
		and renderer.region_cursor_line.visible,
		"Panel Back must clear the complete provisional selection and identity."
	)

	_select_and_save(renderer, "Rightclick City", "Rightclick Culture")
	renderer.handle_right_mouse_click()
	_expect(
		not renderer.has_selected_region()
		and renderer.play_button.disabled
		and not renderer.city_name_world_label.visible
		and renderer.region_cursor_state
		== WORLD_RENDERER_SCRIPT.RegionCursorState.REGION_PLACE
		and renderer.region_cursor_line.visible,
		"World right-click after Save must restore region-placement state."
	)
	renderer.handle_right_mouse_click()
	_expect(
		renderer.region_cursor_state
		== WORLD_RENDERER_SCRIPT.RegionCursorState.SINGLE_TILE
		and not renderer.region_cursor_line.visible,
		"A second world right-click must exit region-placement mode."
	)

	_select_and_save(renderer, TEST_CITY_NAME, TEST_CULTURE_NAME)
	expected_region_top_left = renderer.selected_region_top_left
	expected_region_center = renderer.selected_region_center
	renderer.on_play_button_pressed()

	_expect(
		city_view_request_count == 1,
		"Play must request the retained city view from the session host."
	)
	_expect(
		WorldData.has_active_world_save()
		and WorldData.get_official_city_name() == TEST_CITY_NAME
		and WorldData.get_official_founding_culture_name()
		== TEST_CULTURE_NAME,
		"The Play handler must commit both saved names before transitioning."
	)
	_expect(
		WorldData.get_culture_snapshot().size() == 1,
		"The Play commit must create exactly one culture record."
	)

	await _run_locked_world_reload_test()


func _run_locked_world_reload_test() -> void:
	_expect(
		WorldData.has_active_world_save()
		and WorldData.official_selected_region_top_left
		== expected_region_top_left
		and WorldData.official_selected_region_center
		== expected_region_center,
		"Play must transition only after the selected region is committed."
	)
	_expect(
		WorldData.get_official_city_name() == TEST_CITY_NAME
		and WorldData.get_official_founding_culture_name()
		== TEST_CULTURE_NAME
		and WorldData.get_culture_snapshot().size() == 1,
		"The transitioned scene must retain exactly one official founding identity."
	)

	var reloaded_world_scene := WORLD_SCENE.instantiate()
	add_child(reloaded_world_scene)
	await get_tree().process_frame
	var reloaded_renderer = reloaded_world_scene.get_node_or_null("WorldRenderer")

	_expect(reloaded_renderer != null, "The locked WorldScene must reload.")

	if reloaded_renderer != null:
		_test_world_map_cache(
			reloaded_renderer,
			WorldData.official_world,
			true
		)
		_expect(
			reloaded_renderer.selected_region_top_left
			== expected_region_top_left
			and reloaded_renderer.city_name_world_label.visible
			and reloaded_renderer.city_name_world_label.text
			== TEST_CITY_NAME,
			"Locked-world reload must restore the region and official city label."
		)
		_expect(
			reloaded_renderer.generate_world_button.disabled
			and reloaded_renderer.select_region_button.disabled
			and reloaded_renderer.play_button.text == "City",
			"Locked-world reload must restore the locked controls."
		)
		reloaded_renderer.handle_right_mouse_click()
		_expect(
			reloaded_renderer.has_selected_region(),
			"Right-click must not clear a committed region."
		)

	reloaded_world_scene.queue_free()
	await get_tree().process_frame


func _test_world_map_cache(
	renderer,
	source_world: WorldData,
	expect_saved_texture_reuse: bool
) -> void:
	var view_modes: Array[int] = renderer.get_all_world_view_modes()
	var original_view_mode := int(renderer.view_mode)
	_expect(
		renderer.world_texture_cache.is_mode_ready(
			source_world,
			original_view_mode
		)
		and renderer.world_map_texture != null,
		"The visible world map mode must be available before interaction."
	)

	_expect(
		renderer.world_texture_cache.mode_textures.size()
		== view_modes.size()
		and renderer.has_valid_saved_world_map_texture_cache(source_world),
		"World map preparation must atomically publish and persist every mode."
	)

	var texture_instance_ids: Dictionary = {}

	for mode in view_modes:
		var raw_texture = renderer.world_texture_cache.mode_textures.get(
			mode
		)
		_expect(
			raw_texture is ImageTexture,
			"Every world map mode must have a ready independent ImageTexture."
		)

		if not raw_texture is ImageTexture:
			continue

		var texture := raw_texture as ImageTexture
		var texture_instance_id := texture.get_instance_id()
		_expect(
			not texture_instance_ids.has(texture_instance_id),
			"Each world map mode must own a distinct GPU texture resource."
		)
		texture_instance_ids[texture_instance_id] = true
		_expect(
			texture.get_width() == source_world.width
			and texture.get_height() == source_world.height,
			"Each world map texture must match the source map dimensions."
		)

		if expect_saved_texture_reuse:
			_expect(
				int(expected_world_texture_instance_ids.get(mode, -1))
				== texture_instance_id,
				"Locked-world re-entry must reuse each completed map texture."
			)
		else:
			expected_world_texture_instance_ids[mode] = texture_instance_id

		renderer.set_world_view_mode(mode)
		_expect(
			renderer.world_map_texture == texture,
			"Switching world map modes must be a cache-only texture lookup."
		)

		var texture_image := texture.get_image()
		var sample_tile_position := Vector2i(
			int(source_world.width / 2),
			int(source_world.height / 2)
		)
		var source_tile := source_world.get_tile(
			sample_tile_position.x,
			sample_tile_position.y
		)
		var expected_color: Color = renderer.get_tile_color_for_mode(
			source_tile,
			mode
		)
		var actual_color := texture_image.get_pixelv(
			sample_tile_position
		)
		_expect(
			_colors_match_rgba8(actual_color, expected_color),
			"Batched world map colors must match the single-mode color contract."
		)

	renderer.set_world_view_mode(original_view_mode)


func _colors_match_rgba8(a: Color, b: Color) -> bool:
	var tolerance := 1.0 / 255.0 + 0.0001
	return (
		absf(a.r - b.r) <= tolerance
		and absf(a.g - b.g) <= tolerance
		and absf(a.b - b.b) <= tolerance
		and absf(a.a - b.a) <= tolerance
	)


func _select_and_save(renderer, city_name: String, culture_name: String) -> void:
	renderer.on_select_region_button_pressed()
	renderer.hovered_tile = TEST_REGION_CENTER
	renderer.handle_left_mouse_click()
	renderer.founding_city_name_line_edit.text = city_name
	renderer.founding_culture_name_line_edit.text = culture_name
	renderer.on_founding_name_text_changed("")
	renderer.on_founding_panel_save_button_pressed()


func _make_test_world() -> WorldData:
	var test_world := WorldData.new()
	test_world.setup(TEST_WORLD_SIZE.x, TEST_WORLD_SIZE.y, TEST_WORLD_SEED)

	for y in range(test_world.height):
		for x in range(test_world.width):
			var tile := test_world.get_tile(x, y)
			tile["terrain"] = WorldData.TERRAIN_LAND
			tile["biome"] = WorldData.BIOME_PLAIN
			tile["is_land"] = true

	test_world.mark_tile_data_changed()
	return test_world


func _expect(condition: bool, failure_message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error("World founding flow test: " + failure_message)
