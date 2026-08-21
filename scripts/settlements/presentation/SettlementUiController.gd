extends RefCounted
class_name SettlementUiController

# Owns the reusable settlement-view UI chrome. The controller is bound to one
# exact presentation identity and reads eligibility/resource values only from
# that binding. Gameplay actions use the three explicitly typed controllers;
# only map-mode, navigation, and presentation notifications cross through four
# narrow Callables. This component never receives the scene facade.

const SettlementCommandControllerScript = preload(
	"res://scripts/settlements/presentation/SettlementCommandController.gd"
)
const SettlementPlacementControllerScript = preload(
	"res://scripts/settlements/presentation/SettlementPlacementController.gd"
)
const SettlementSelectionControllerScript = preload(
	"res://scripts/settlements/presentation/SettlementSelectionController.gd"
)
const SettlementPresentationBindingScript = preload(
	"res://scripts/settlements/presentation/SettlementPresentationBinding.gd"
)

const BOTTOM_BUTTON_SIZE := Vector2(58.0, 58.0)
const OPTION_BUTTON_GAP: float = 6.0
const MAP_BUTTON_SIZE := Vector2(52.0, 52.0)
const RESOURCE_BOX_SIZE := Vector2(52.0, 50.0)
const BACK_BUTTON_SIZE := Vector2(68.0, 50.0)

const REQUIRED_ACTIONS: Array[String] = [
	"is_map_mode_ready",
	"apply_map_mode",
	"back",
	"present_ui_change",
]

var presentation_binding: SettlementPresentationBindingScript
var highest_accepted_binding_generation: int = 0
var ui_parent: Control
var actions: Dictionary = {}
var placement_controller: SettlementPlacementControllerScript
var selection_controller: SettlementSelectionControllerScript
var command_controller: SettlementCommandControllerScript
var primary_chrome_created: bool = false
var overlay_chrome_created: bool = false
var last_viewport_size: Vector2 = Vector2.ZERO

var view_mode: int = MapVisuals.ViewMode.BIOME
var map_menu_open: bool = false

var back_button: Button
var resource_bar: Control
var resource_boxes: Array[Panel] = []
var resource_icons: Array[ColorRect] = []
var resource_amount_labels: Array[Label] = []
var maps_button: Button
var map_mode_buttons: Array[Button] = []
var build_option_button: Button
var build_option_icon: Panel
var bottom_buttons: Array[Button] = []
var command_cancel_task_button: Button
var command_chop_trees_button: Button
var command_collect_rocks_button: Button
var object_option_buttons: Dictionary = {}
var object_option_icons: Dictionary = {}
var road_cursor_icon: Panel


func can_bind_settlement_presentation(
	binding: SettlementPresentationBindingScript
) -> bool:
	if (
		binding == null
		or not binding.is_valid()
		or not binding.supports_backend_capability(
			SettlementPresentationBindingScript.CAPABILITY_CITY_DETAIL
		)
	):
		return false
	if binding.generation > highest_accepted_binding_generation:
		return true
	return (
		binding.generation == highest_accepted_binding_generation
		and is_bound_to_settlement_presentation(binding)
	)


func bind_settlement_presentation(
	binding: SettlementPresentationBindingScript
) -> bool:
	if not can_bind_settlement_presentation(binding):
		return false
	if is_bound_to_settlement_presentation(binding):
		return true

	presentation_binding = binding
	highest_accepted_binding_generation = binding.generation
	_reset_visible_chrome_without_actions()
	if primary_chrome_created:
		refresh_all()
	return true


func is_bound_to_settlement_presentation(
	binding: SettlementPresentationBindingScript
) -> bool:
	return (
		binding != null
		and presentation_binding != null
		and presentation_binding.matches_binding(binding)
		and binding.generation == highest_accepted_binding_generation
	)


func reset_presentation() -> void:
	presentation_binding = null
	_reset_visible_chrome_without_actions()
	# Preserve the high-water mark. A delayed older binding must never revive
	# menu state after this presentation has already left its settlement.


func setup(
	parent: Control,
	settlement_placement_controller: SettlementPlacementControllerScript,
	settlement_selection_controller: SettlementSelectionControllerScript,
	settlement_command_controller: SettlementCommandControllerScript,
	action_callbacks: Dictionary
) -> bool:
	if primary_chrome_created:
		return (
			parent == ui_parent
			and is_same(
				settlement_placement_controller,
				placement_controller
			)
			and is_same(
				settlement_selection_controller,
				selection_controller
			)
			and is_same(
				settlement_command_controller,
				command_controller
			)
			and _actions_are_valid(action_callbacks)
		)
	if (
		parent == null
		or presentation_binding == null
		or not presentation_binding.is_valid()
		or settlement_placement_controller == null
		or settlement_selection_controller == null
		or settlement_command_controller == null
		or not settlement_placement_controller.is_bound_to_settlement_presentation(
			presentation_binding
		)
		or not settlement_selection_controller.is_bound_to_settlement_presentation(
			presentation_binding
		)
		or not settlement_command_controller.is_bound_to_settlement_presentation(
			presentation_binding
		)
		or not _actions_are_valid(action_callbacks)
	):
		return false

	ui_parent = parent
	placement_controller = settlement_placement_controller
	selection_controller = settlement_selection_controller
	command_controller = settlement_command_controller
	actions = action_callbacks.duplicate()
	_create_bottom_buttons()
	_create_object_option_button(CityObjectCatalog.CITY_OBJECT_CITY_CENTER)
	_create_build_option_button()
	_create_object_option_button(CityObjectCatalog.CITY_OBJECT_HOUSE)
	_create_object_option_button(CityObjectCatalog.CITY_OBJECT_STOCKPILE)
	_create_object_option_button(
		CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS
	)
	_create_command_menu()
	_create_resource_bar()
	_create_maps_menu()
	primary_chrome_created = true
	refresh_all()
	return true


func create_overlay_chrome() -> bool:
	if overlay_chrome_created:
		return true
	if not primary_chrome_created or ui_parent == null:
		return false
	_create_back_button()
	_create_road_cursor_icon()
	overlay_chrome_created = true
	return true


func is_interaction_state_clear() -> bool:
	return (
		not map_menu_open
		and not is_build_menu_open()
		and not has_open_object_menu()
		and (
			command_cancel_task_button == null
			or not command_cancel_task_button.visible
		)
		and (
			command_chop_trees_button == null
			or not command_chop_trees_button.visible
		)
		and (
			command_collect_rocks_button == null
			or not command_collect_rocks_button.visible
		)
		and (road_cursor_icon == null or not road_cursor_icon.visible)
	)


func refresh_all() -> void:
	update_resource_bar_values()
	update_build_button_state()
	update_object_button_states()
	update_command_button_visuals()
	update_map_mode_button_visuals()


func get_resource_order() -> Array[String]:
	return CityResourceCatalog.get_city_resource_types()


func update_resource_bar_values() -> void:
	var settlement_state := _get_bound_settlement_state()
	if settlement_state == null:
		return
	var resource_order := get_resource_order()
	var owned_resource_amounts := (
		CityResourceAccountingSystem
		.get_total_owned_city_resource_amounts_for_city_state(
			settlement_state
		)
	)
	for index in range(resource_amount_labels.size()):
		if index >= resource_order.size():
			continue
		var resource: String = resource_order[index]
		resource_amount_labels[index].text = str(
			maxi(int(owned_resource_amounts.get(resource, 0)), 0)
		)


func update_build_button_state() -> void:
	var settlement_state := _get_bound_settlement_state()
	var can_build := (
		settlement_state != null
		and settlement_state.can_build_city_objects()
	)
	var build_button := get_bottom_button_for_slot(2)
	if build_button != null:
		build_button.disabled = not can_build
		build_button.text = "2"
	if build_option_button != null:
		build_option_button.disabled = not can_build
		if not can_build:
			build_option_button.visible = false


func update_object_button_states() -> void:
	var settlement_state := _get_bound_settlement_state()
	var main_button_types := {
		CityObjectCatalog.CITY_OBJECT_CITY_CENTER: 1,
		CityObjectCatalog.CITY_OBJECT_HOUSE: 3,
		CityObjectCatalog.CITY_OBJECT_STOCKPILE: 4,
		CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS: 5,
	}
	for raw_object_type in main_button_types.keys():
		var object_type := str(raw_object_type)
		var definition := (
			CityObjectCatalog.get_city_object_definition(object_type)
		)
		var main_button := get_bottom_button_for_slot(
			int(main_button_types[raw_object_type])
		)
		if definition.is_empty() or main_button == null:
			continue
		main_button.disabled = not _can_use_object_type(
			settlement_state,
			object_type
		)
		main_button.text = str(int(definition.get("button_slot", 0)))

	var command_button := get_bottom_button_for_slot(6)
	if command_button != null:
		command_button.disabled = (
			settlement_state == null
			or not settlement_state.is_city_founded()
		)
		command_button.text = "6"

	for raw_object_type in object_option_buttons.keys():
		var object_type := str(raw_object_type)
		var option_button: Button = object_option_buttons[object_type]
		var can_use := _can_use_object_type(settlement_state, object_type)
		option_button.disabled = not can_use
		if not can_use:
			option_button.visible = false
			set_object_option_selected(object_type, false)


func set_object_option_selected(
	object_type: String,
	is_selected: bool
) -> void:
	if not object_option_icons.has(object_type):
		return
	var icon: Panel = object_option_icons[object_type]
	var visual_style := (
		CityObjectCatalog.get_city_object_visual_style_for_type(object_type)
	)
	var fill_color: Color = visual_style["fill_color"]
	var border_color: Color = visual_style["frame_color"]
	fill_color = Color(fill_color.r, fill_color.g, fill_color.b, 1.0)
	border_color = Color(
		border_color.r,
		border_color.g,
		border_color.b,
		1.0
	)
	if is_selected:
		border_color = Color(0.0, 0.85, 1.0, 1.0)
	icon.add_theme_stylebox_override(
		"panel",
		create_flat_style(fill_color, border_color, 1)
	)


func set_road_option_selected(is_selected: bool) -> void:
	if build_option_icon == null:
		return
	var visual_style := CityObjectCatalog.get_city_object_visual_style_for_type(
		CityObjectCatalog.CITY_OBJECT_ROAD
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
	build_option_icon.add_theme_stylebox_override(
		"panel",
		create_flat_style(fill_color, border_color, 1)
	)


func set_road_cursor_visible(is_visible: bool) -> void:
	if road_cursor_icon != null:
		road_cursor_icon.visible = is_visible


func show_active_road_chrome() -> void:
	if build_option_button != null:
		build_option_button.visible = true
	set_road_cursor_visible(true)
	set_road_option_selected(true)


func update_road_cursor_position(pointer_position: Vector2) -> void:
	if road_cursor_icon == null:
		return
	road_cursor_icon.size = Vector2(12.0, 12.0)
	road_cursor_icon.position = pointer_position + Vector2(10.0, 10.0)
	road_cursor_icon.move_to_front()


func close_map_menu() -> void:
	if map_menu_open:
		set_map_menu_open(false)


func set_map_menu_open(is_open: bool) -> void:
	map_menu_open = is_open
	for mode_button in map_mode_buttons:
		mode_button.visible = map_menu_open
	_update_maps_button_visual()
	update_map_mode_button_visuals()
	if last_viewport_size.x > 0.0 and last_viewport_size.y > 0.0:
		_layout_maps_menu(last_viewport_size)


func close_build_menu() -> void:
	if build_option_button != null:
		build_option_button.visible = false


func is_build_menu_open() -> bool:
	return build_option_button != null and build_option_button.visible


func close_object_menu(object_type: String) -> void:
	if object_option_buttons.has(object_type):
		var option_button: Button = object_option_buttons[object_type]
		option_button.visible = false


func close_all_object_menus() -> void:
	for raw_object_type in object_option_buttons.keys():
		close_object_menu(str(raw_object_type))


func has_open_object_menu() -> bool:
	for raw_object_type in object_option_buttons.keys():
		var option_button: Button = object_option_buttons[raw_object_type]
		if option_button.visible:
			return true
	return false


func close_command_menu(invoke_action: bool = true) -> void:
	if invoke_action and command_controller != null:
		command_controller.close_menu()
	_set_command_menu_buttons_visible(false)
	update_command_button_visuals()
	_publish_ui_change("interaction_redraw")


func update_command_button_visuals() -> void:
	if command_controller == null:
		return
	command_controller.update_command_button_visuals(
		command_cancel_task_button,
		command_chop_trees_button,
		command_collect_rocks_button
	)


func deactivate_command_tool() -> void:
	if command_controller == null:
		return
	command_controller.deactivate_tool()
	update_command_button_visuals()
	_publish_ui_change("interaction_redraw")


func cancel_active_object_placement() -> String:
	if placement_controller == null:
		return ""
	var object_type: String = (
		placement_controller.cancel_active_object_placement()
	)
	if object_type != "":
		set_object_option_selected(object_type, false)
	else:
		for raw_object_type in object_option_icons.keys():
			set_object_option_selected(str(raw_object_type), false)
	_publish_ui_change("workplace_and_interaction_redraw")
	return object_type


func start_object_placement_from_definition(object_type: String) -> bool:
	var settlement_state := _get_bound_settlement_state()
	var definition := CityObjectCatalog.get_city_object_definition(object_type)
	if (
		placement_controller == null
		or definition.is_empty()
		or not _can_use_object_type(settlement_state, object_type)
	):
		update_object_button_states()
		return false
	close_build_menu()
	close_command_menu()
	cancel_road_placement()
	if not placement_controller.start_object_placement(
		object_type,
		definition["size"],
		"player",
		bool(definition.get("repeat_after_place", false))
	):
		return false
	set_object_option_selected(object_type, true)
	_publish_ui_change("workplace_and_interaction_redraw")
	return true


func start_road_placement() -> bool:
	var settlement_state := _get_bound_settlement_state()
	if (
		placement_controller == null
		or settlement_state == null
		or not settlement_state.can_build_city_objects()
	):
		update_build_button_state()
		return false
	close_all_object_menus()
	close_command_menu()
	cancel_active_object_placement()
	if not placement_controller.start_road_placement():
		update_build_button_state()
		return false
	set_road_cursor_visible(true)
	set_road_option_selected(true)
	update_build_button_state()
	_publish_ui_change("interaction_redraw")
	return true


func cancel_road_placement() -> bool:
	if placement_controller == null:
		return false
	var had_interaction: bool = placement_controller.cancel_road_placement()
	set_road_cursor_visible(false)
	set_road_option_selected(false)
	_publish_ui_change("interaction_redraw")
	return had_interaction


func set_view_mode(mode: int) -> bool:
	if view_mode == mode:
		return false
	if not bool(_call_action("is_map_mode_ready", [mode])):
		push_error("Requested settlement map mode is missing from the atlas.")
		return false
	close_command_menu()
	view_mode = mode
	_call_action("apply_map_mode", [mode])
	update_map_mode_button_visuals()
	return true


func update_map_mode_button_visuals() -> void:
	for index in range(map_mode_buttons.size()):
		var mode_button := map_mode_buttons[index]
		var mode := MapVisuals.get_view_mode_for_index(index)
		var mode_is_ready := bool(
			_call_action("is_map_mode_ready", [mode])
		)
		mode_button.disabled = not mode_is_ready
		if mode == view_mode:
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


func layout(viewport_size: Vector2) -> void:
	last_viewport_size = viewport_size
	_layout_bottom_buttons(viewport_size)
	_layout_command_menu()
	_layout_all_object_option_buttons()
	_layout_build_option_button()
	_layout_resource_bar(viewport_size)
	_layout_maps_menu(viewport_size)
	_layout_back_button(viewport_size)


func get_bottom_button_for_slot(button_slot: int) -> Button:
	var index := button_slot - 1
	if index < 0 or index >= bottom_buttons.size():
		return null
	return bottom_buttons[index]


func _create_bottom_buttons() -> void:
	for slot in range(1, 7):
		var button := Button.new()
		button.text = str(slot)
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = BOTTOM_BUTTON_SIZE
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		ui_parent.add_child(button)
		bottom_buttons.append(button)

	get_bottom_button_for_slot(1).pressed.connect(
		_on_object_menu_button_pressed.bind(
			CityObjectCatalog.CITY_OBJECT_CITY_CENTER
		)
	)
	get_bottom_button_for_slot(2).pressed.connect(_on_build_menu_button_pressed)
	get_bottom_button_for_slot(3).pressed.connect(
		_on_object_menu_button_pressed.bind(CityObjectCatalog.CITY_OBJECT_HOUSE)
	)
	get_bottom_button_for_slot(4).pressed.connect(
		_on_object_menu_button_pressed.bind(
			CityObjectCatalog.CITY_OBJECT_STOCKPILE
		)
	)
	get_bottom_button_for_slot(5).pressed.connect(
		_on_object_menu_button_pressed.bind(
			CityObjectCatalog.CITY_OBJECT_FISHING_GROUNDS
		)
	)
	get_bottom_button_for_slot(6).pressed.connect(
		_on_command_menu_button_pressed
	)


func _create_object_option_button(object_type: String) -> void:
	var definition := CityObjectCatalog.get_city_object_definition(object_type)
	if definition.is_empty():
		push_error("Missing settlement object definition for: " + object_type)
		return
	var option_button := Button.new()
	option_button.text = ""
	option_button.focus_mode = Control.FOCUS_NONE
	option_button.custom_minimum_size = BOTTOM_BUTTON_SIZE
	option_button.mouse_filter = Control.MOUSE_FILTER_STOP
	option_button.visible = false
	ui_parent.add_child(option_button)
	option_button.pressed.connect(
		_on_object_option_button_pressed.bind(object_type)
	)

	var icon := Panel.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var visual_style := (
		CityObjectCatalog.get_city_object_visual_style_for_type(object_type)
	)
	var fill_color: Color = visual_style["fill_color"]
	var frame_color: Color = visual_style["frame_color"]
	icon.add_theme_stylebox_override(
		"panel",
		create_flat_style(
			Color(fill_color.r, fill_color.g, fill_color.b, 1.0),
			Color(frame_color.r, frame_color.g, frame_color.b, 1.0),
			1
		)
	)
	option_button.add_child(icon)
	object_option_buttons[object_type] = option_button
	object_option_icons[object_type] = icon


func _create_build_option_button() -> void:
	build_option_button = Button.new()
	build_option_button.text = ""
	build_option_button.focus_mode = Control.FOCUS_NONE
	build_option_button.custom_minimum_size = BOTTOM_BUTTON_SIZE
	build_option_button.mouse_filter = Control.MOUSE_FILTER_STOP
	build_option_button.visible = false
	ui_parent.add_child(build_option_button)
	build_option_button.pressed.connect(_on_build_option_button_pressed)

	build_option_icon = Panel.new()
	build_option_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_option_button.add_child(build_option_icon)
	set_road_option_selected(false)


func _create_command_menu() -> void:
	command_cancel_task_button = _create_command_button("Cancel\nTask")
	command_cancel_task_button.pressed.connect(
		_on_command_cancel_task_pressed
	)
	command_chop_trees_button = _create_command_button("Chop\nTrees")
	command_chop_trees_button.pressed.connect(
		_on_command_option_pressed.bind(
			SettlementCommandControllerScript.COMMAND_TYPE_CHOP_TREE
		)
	)
	command_collect_rocks_button = _create_command_button("Collect\nRocks")
	command_collect_rocks_button.pressed.connect(
		_on_command_option_pressed.bind(
			SettlementCommandControllerScript.COMMAND_TYPE_COLLECT_ROCK
		)
	)
	update_command_button_visuals()


func _create_command_button(label_text: String) -> Button:
	var button := Button.new()
	button.text = label_text
	button.focus_mode = Control.FOCUS_NONE
	button.toggle_mode = true
	button.custom_minimum_size = BOTTOM_BUTTON_SIZE
	button.add_theme_font_size_override("font_size", 12)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.visible = false
	ui_parent.add_child(button)
	return button


func _create_resource_bar() -> void:
	resource_bar = Control.new()
	resource_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_parent.add_child(resource_bar)
	for resource in get_resource_order():
		var box := Panel.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_stylebox_override(
			"panel",
			create_flat_style(
				Color(0.08, 0.08, 0.08, 0.82),
				Color(0.85, 0.85, 0.85, 0.95),
				1
			)
		)
		resource_bar.add_child(box)
		resource_boxes.append(box)

		var icon := ColorRect.new()
		icon.color = MapVisuals.get_resource_color(resource)
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


func _create_maps_menu() -> void:
	maps_button = Button.new()
	maps_button.text = "Maps"
	maps_button.focus_mode = Control.FOCUS_NONE
	maps_button.mouse_filter = Control.MOUSE_FILTER_STOP
	maps_button.custom_minimum_size = MAP_BUTTON_SIZE
	ui_parent.add_child(maps_button)
	maps_button.pressed.connect(_on_maps_button_pressed)
	for index in range(MapVisuals.get_all_view_modes().size()):
		var mode := MapVisuals.get_view_mode_for_index(index)
		var mode_button := Button.new()
		mode_button.text = str(index + 1)
		mode_button.focus_mode = Control.FOCUS_NONE
		mode_button.mouse_filter = Control.MOUSE_FILTER_STOP
		mode_button.custom_minimum_size = MAP_BUTTON_SIZE
		mode_button.visible = false
		mode_button.tooltip_text = MapVisuals.get_view_mode_name(mode)
		ui_parent.add_child(mode_button)
		map_mode_buttons.append(mode_button)
		mode_button.pressed.connect(_on_map_mode_button_pressed.bind(mode))
	_update_maps_button_visual()
	update_map_mode_button_visuals()


func _create_back_button() -> void:
	back_button = Button.new()
	back_button.text = "Back"
	back_button.focus_mode = Control.FOCUS_NONE
	back_button.custom_minimum_size = BACK_BUTTON_SIZE
	back_button.mouse_filter = Control.MOUSE_FILTER_STOP
	back_button.add_theme_stylebox_override(
		"normal",
		create_flat_style(
			Color(0.85, 0.05, 0.03, 0.95),
			Color(0.35, 0.00, 0.00, 1.0),
			2
		)
	)
	back_button.add_theme_stylebox_override(
		"hover",
		create_flat_style(
			Color(1.0, 0.10, 0.08, 0.95),
			Color(0.45, 0.00, 0.00, 1.0),
			2
		)
	)
	back_button.add_theme_stylebox_override(
		"pressed",
		create_flat_style(
			Color(0.60, 0.02, 0.02, 0.95),
			Color(0.20, 0.00, 0.00, 1.0),
			2
		)
	)
	back_button.add_theme_color_override("font_color", Color.WHITE)
	back_button.add_theme_color_override("font_hover_color", Color.WHITE)
	back_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	ui_parent.add_child(back_button)
	back_button.pressed.connect(_on_back_button_pressed)


func _create_road_cursor_icon() -> void:
	road_cursor_icon = Panel.new()
	road_cursor_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	road_cursor_icon.visible = false
	var visual_style := CityObjectCatalog.get_city_object_visual_style_for_type(
		CityObjectCatalog.CITY_OBJECT_ROAD
	)
	road_cursor_icon.add_theme_stylebox_override(
		"panel",
		create_flat_style(
			visual_style.get(
				"fill_color",
				Color(0.56, 0.25, 0.10, 0.96)
			),
			visual_style.get(
				"frame_color",
				Color(0.29, 0.11, 0.045, 1.0)
			),
			1
		)
	)
	ui_parent.add_child(road_cursor_icon)


func _on_object_menu_button_pressed(object_type: String) -> void:
	var settlement_state := _get_bound_settlement_state()
	if not _can_use_object_type(settlement_state, object_type):
		update_object_button_states()
		return
	if not object_option_buttons.has(object_type):
		return

	close_map_menu()
	close_build_menu()
	close_command_menu()
	cancel_road_placement()
	var option_button: Button = object_option_buttons[object_type]
	var should_open := not option_button.visible
	close_all_object_menus()
	cancel_active_object_placement()
	if should_open:
		option_button.visible = true
		_layout_object_option_button(object_type)
		option_button.move_to_front()
	update_object_button_states()


func _on_object_option_button_pressed(object_type: String) -> void:
	var settlement_state := _get_bound_settlement_state()
	if not _can_use_object_type(settlement_state, object_type):
		update_object_button_states()
		return
	if placement_controller.is_placing_object_type(object_type):
		cancel_active_object_placement()
	else:
		start_object_placement_from_definition(object_type)


func _on_build_menu_button_pressed() -> void:
	var settlement_state := _get_bound_settlement_state()
	if settlement_state == null or not settlement_state.can_build_city_objects():
		update_build_button_state()
		return
	if build_option_button == null:
		return
	close_map_menu()
	close_command_menu()
	var should_open := not build_option_button.visible
	close_all_object_menus()
	cancel_active_object_placement()
	if should_open:
		build_option_button.visible = true
		_layout_build_option_button()
		build_option_button.move_to_front()
	else:
		cancel_road_placement()
		build_option_button.visible = false
	update_build_button_state()


func _on_build_option_button_pressed() -> void:
	if placement_controller.is_road_placement_active:
		cancel_road_placement()
	else:
		start_road_placement()


func _on_command_menu_button_pressed() -> void:
	var settlement_state := _get_bound_settlement_state()
	if settlement_state == null or not settlement_state.is_city_founded():
		return
	if command_controller.menu_open:
		close_command_menu()
		return
	close_map_menu()
	close_build_menu()
	close_all_object_menus()
	cancel_active_object_placement()
	cancel_road_placement()
	var transition: Dictionary = selection_controller.clear_selected_settlement_entity()
	_publish_ui_change("selection_transition", transition)
	if not command_controller.open_menu():
		return
	_set_command_menu_buttons_visible(true)
	_layout_command_menu()
	command_cancel_task_button.move_to_front()
	command_chop_trees_button.move_to_front()
	command_collect_rocks_button.move_to_front()
	update_command_button_visuals()


func _on_command_option_pressed(command_type: String) -> void:
	if not command_controller.select_command_type(command_type):
		return
	var transition: Dictionary = selection_controller.clear_selected_settlement_entity()
	_publish_ui_change("selection_transition", transition)
	update_command_button_visuals()
	_publish_ui_change("interaction_redraw")


func _on_command_cancel_task_pressed() -> void:
	if not command_controller.toggle_cancel_mode():
		return
	var transition: Dictionary = selection_controller.clear_selected_settlement_entity()
	_publish_ui_change("selection_transition", transition)
	if command_controller.is_cancel_mode_active:
		_publish_ui_change("command_cancel_activated")
	update_command_button_visuals()
	_publish_ui_change("interaction_redraw")


func _on_maps_button_pressed() -> void:
	if not map_menu_open:
		close_command_menu()
		close_build_menu()
		close_all_object_menus()
		cancel_active_object_placement()
		cancel_road_placement()
	set_map_menu_open(not map_menu_open)


func _on_map_mode_button_pressed(mode: int) -> void:
	set_view_mode(mode)


func _on_back_button_pressed() -> void:
	_call_action("back")


func _layout_bottom_buttons(viewport_size: Vector2) -> void:
	if bottom_buttons.size() != 6:
		return
	var total_width := BOTTOM_BUTTON_SIZE.x * float(bottom_buttons.size())
	var start_x := viewport_size.x * 0.5 - total_width * 0.5
	var y := viewport_size.y - BOTTOM_BUTTON_SIZE.y
	for index in range(bottom_buttons.size()):
		var button := bottom_buttons[index]
		button.position = Vector2(
			start_x + BOTTOM_BUTTON_SIZE.x * float(index),
			y
		)
		button.size = BOTTOM_BUTTON_SIZE


func _layout_command_menu() -> void:
	var command_button := get_bottom_button_for_slot(6)
	if (
		command_button == null
		or command_cancel_task_button == null
		or command_chop_trees_button == null
		or command_collect_rocks_button == null
	):
		return
	var centered_x := (
		command_button.position.x
		+ command_button.size.x * 0.5
		- BOTTOM_BUTTON_SIZE.x * 0.5
	)
	var chop_y := (
		command_button.position.y
		- BOTTOM_BUTTON_SIZE.y
		- OPTION_BUTTON_GAP
	)
	command_chop_trees_button.position = Vector2(centered_x, chop_y)
	command_chop_trees_button.size = BOTTOM_BUTTON_SIZE
	command_collect_rocks_button.position = Vector2(
		centered_x,
		chop_y - BOTTOM_BUTTON_SIZE.y - OPTION_BUTTON_GAP
	)
	command_collect_rocks_button.size = BOTTOM_BUTTON_SIZE
	command_cancel_task_button.position = Vector2(
		centered_x,
		chop_y - (BOTTOM_BUTTON_SIZE.y + OPTION_BUTTON_GAP) * 2.0
	)
	command_cancel_task_button.size = BOTTOM_BUTTON_SIZE


func _layout_object_option_button(object_type: String) -> void:
	if not object_option_buttons.has(object_type):
		return
	var definition := CityObjectCatalog.get_city_object_definition(object_type)
	if definition.is_empty():
		return
	var bottom_button := get_bottom_button_for_slot(
		int(definition.get("button_slot", 0))
	)
	if bottom_button == null:
		return
	var option_button: Button = object_option_buttons[object_type]
	option_button.position = Vector2(
		bottom_button.position.x,
		bottom_button.position.y
		- BOTTOM_BUTTON_SIZE.y
		- OPTION_BUTTON_GAP
	)
	option_button.size = BOTTOM_BUTTON_SIZE
	if object_option_icons.has(object_type):
		var icon: Panel = object_option_icons[object_type]
		var size_tiles: Vector2i = definition["size"]
		var largest_side := float(max(size_tiles.x, size_tiles.y))
		var icon_size := Vector2(
			float(size_tiles.x) / largest_side * 30.0,
			float(size_tiles.y) / largest_side * 30.0
		)
		icon.position = (BOTTOM_BUTTON_SIZE - icon_size) * 0.5
		icon.size = icon_size


func _layout_all_object_option_buttons() -> void:
	for raw_object_type in object_option_buttons.keys():
		_layout_object_option_button(str(raw_object_type))


func _layout_build_option_button() -> void:
	var build_button := get_bottom_button_for_slot(2)
	if build_option_button == null or build_button == null:
		return
	build_option_button.position = Vector2(
		build_button.position.x,
		build_button.position.y
		- BOTTOM_BUTTON_SIZE.y
		- OPTION_BUTTON_GAP
	)
	build_option_button.size = BOTTOM_BUTTON_SIZE
	if build_option_icon != null:
		build_option_icon.position = Vector2(21.0, 21.0)
		build_option_icon.size = Vector2(16.0, 16.0)


func _layout_resource_bar(viewport_size: Vector2) -> void:
	if resource_bar == null:
		return
	var total_width := RESOURCE_BOX_SIZE.x * float(resource_boxes.size())
	resource_bar.position = Vector2(viewport_size.x - total_width, 0.0)
	resource_bar.size = Vector2(total_width, RESOURCE_BOX_SIZE.y)
	for index in range(resource_boxes.size()):
		var box := resource_boxes[index]
		box.position = Vector2(float(index) * RESOURCE_BOX_SIZE.x, 0.0)
		box.size = RESOURCE_BOX_SIZE
		if index < resource_icons.size():
			resource_icons[index].position = Vector2(
				RESOURCE_BOX_SIZE.x * 0.5 - 8.0,
				7.0
			)
			resource_icons[index].size = Vector2(16.0, 16.0)
		if index < resource_amount_labels.size():
			resource_amount_labels[index].position = Vector2(0.0, 25.0)
			resource_amount_labels[index].size = Vector2(
				RESOURCE_BOX_SIZE.x,
				20.0
			)


func _layout_maps_menu(viewport_size: Vector2) -> void:
	if maps_button == null:
		return
	var resource_order := get_resource_order()
	var resource_count := maxi(resource_order.size(), 1)
	var gold_index := resource_order.find(WorldData.RESOURCE_GOLD)
	if gold_index < 0:
		gold_index = resource_count - 1
	var resource_bar_x := (
		viewport_size.x - RESOURCE_BOX_SIZE.x * float(resource_count)
	)
	var gold_box_x := resource_bar_x + float(gold_index) * RESOURCE_BOX_SIZE.x
	maps_button.position = Vector2(gold_box_x, RESOURCE_BOX_SIZE.y)
	maps_button.size = MAP_BUTTON_SIZE
	var popup_x := maps_button.position.x + MAP_BUTTON_SIZE.x
	var popup_width := MAP_BUTTON_SIZE.x * float(map_mode_buttons.size())
	if popup_x + popup_width > viewport_size.x:
		popup_x = maps_button.position.x - popup_width
	for index in range(map_mode_buttons.size()):
		var mode_button := map_mode_buttons[index]
		mode_button.position = Vector2(
			popup_x + float(index) * MAP_BUTTON_SIZE.x,
			maps_button.position.y
		)
		mode_button.size = MAP_BUTTON_SIZE
	maps_button.move_to_front()
	if map_menu_open:
		for mode_button in map_mode_buttons:
			mode_button.move_to_front()


func _layout_back_button(viewport_size: Vector2) -> void:
	if back_button == null:
		return
	back_button.position = Vector2(
		viewport_size.x - BACK_BUTTON_SIZE.x - 12.0,
		viewport_size.y - BACK_BUTTON_SIZE.y - 12.0
	)
	back_button.size = BACK_BUTTON_SIZE


func _update_maps_button_visual() -> void:
	if maps_button == null:
		return
	if map_menu_open:
		maps_button.text = "Close"
		apply_square_button_style(
			maps_button,
			Color(0.75, 0.04, 0.03, 0.96),
			Color(0.25, 0.0, 0.0, 1.0),
			Color.WHITE
		)
	else:
		maps_button.text = "Maps"
		apply_square_button_style(
			maps_button,
			Color(0.55, 0.38, 0.14, 0.96),
			Color(0.24, 0.15, 0.04, 1.0),
			Color.WHITE
		)


func apply_square_button_style(
	button: Button,
	fill_color: Color,
	border_color: Color,
	font_color: Color
) -> void:
	var normal_style := create_flat_style(fill_color, border_color, 1)
	var hover_style := create_flat_style(
		fill_color.lightened(0.15),
		border_color.lightened(0.15),
		1
	)
	var pressed_style := create_flat_style(
		fill_color.darkened(0.18),
		border_color,
		1
	)
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.add_theme_stylebox_override("focus", normal_style)
	button.add_theme_color_override("font_color", font_color)
	button.add_theme_color_override("font_hover_color", font_color)
	button.add_theme_color_override("font_pressed_color", font_color)
	button.add_theme_font_size_override("font_size", 14)


func create_flat_style(
	fill_color: Color,
	border_color: Color,
	border_width: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.border_width_left = border_width
	style.border_width_right = border_width
	style.border_width_top = border_width
	style.border_width_bottom = border_width
	return style


func _set_command_menu_buttons_visible(is_visible: bool) -> void:
	if command_cancel_task_button != null:
		command_cancel_task_button.visible = is_visible
	if command_chop_trees_button != null:
		command_chop_trees_button.visible = is_visible
	if command_collect_rocks_button != null:
		command_collect_rocks_button.visible = is_visible


func _reset_visible_chrome_without_actions() -> void:
	map_menu_open = false
	for mode_button in map_mode_buttons:
		mode_button.visible = false
	close_build_menu()
	close_all_object_menus()
	_set_command_menu_buttons_visible(false)
	set_road_cursor_visible(false)
	for raw_object_type in object_option_icons.keys():
		set_object_option_selected(str(raw_object_type), false)
	set_road_option_selected(false)
	_update_maps_button_visual()


func _get_bound_settlement_state() -> CitySettlementSimulationState:
	if presentation_binding == null or not presentation_binding.is_valid():
		return null
	var capability_state = presentation_binding.get_backend_capability(
		SettlementPresentationBindingScript.CAPABILITY_CITY_DETAIL
	)
	return (
		capability_state
		if capability_state is CitySettlementSimulationState
		else null
	)


func _can_use_object_type(
	settlement_state: CitySettlementSimulationState,
	object_type: String
) -> bool:
	return (
		settlement_state != null
		and CityObjectSystem.can_use_city_object_definition_for_city_state(
			settlement_state,
			object_type
		)
	)


func _actions_are_valid(action_callbacks: Dictionary) -> bool:
	for action_name in REQUIRED_ACTIONS:
		var callback = action_callbacks.get(action_name)
		if not callback is Callable or not callback.is_valid():
			return false
	return true


func _call_action(action_name: String, arguments: Array = []) -> Variant:
	var callback = actions.get(action_name)
	if not callback is Callable or not callback.is_valid():
		return null
	return callback.callv(arguments)


func _publish_ui_change(
	change_kind: String,
	payload: Variant = null
) -> void:
	_call_action("present_ui_change", [change_kind, payload])
