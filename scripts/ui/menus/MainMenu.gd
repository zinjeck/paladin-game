extends Control

@export_file("*.tscn") var world_scene_path: String = "res://scenes/WorldScene.tscn"
@export_file("*.tscn") var city_scene_path: String = "res://scenes/CityScreen.tscn"

var background: ColorRect
var title_label: Label
var button_container: VBoxContainer
var play_button: Button
var exit_button: Button
var dev_city_button: Button

func _ready() -> void:
	create_background()
	create_title()
	create_buttons()


func create_background() -> void:
	background = ColorRect.new()
	background.color = Color(0.015, 0.035, 0.11, 1.0)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE

	background.anchor_left = 0.0
	background.anchor_top = 0.0
	background.anchor_right = 1.0
	background.anchor_bottom = 1.0
	background.offset_left = 0.0
	background.offset_top = 0.0
	background.offset_right = 0.0
	background.offset_bottom = 0.0

	add_child(background)

func create_title() -> void:
	title_label = Label.new()
	title_label.text = "PALADIN"

	title_label.anchor_left = 0.0
	title_label.anchor_top = 0.0
	title_label.anchor_right = 1.0
	title_label.anchor_bottom = 0.0

	title_label.offset_left = 0.0
	title_label.offset_top = 95.0
	title_label.offset_right = 0.0
	title_label.offset_bottom = 190.0

	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	title_label.add_theme_color_override("font_color", Color.WHITE)
	title_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.75))
	title_label.add_theme_constant_override("shadow_offset_x", 3)
	title_label.add_theme_constant_override("shadow_offset_y", 3)
	title_label.add_theme_font_size_override("font_size", 72)

	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	add_child(title_label)

func create_buttons() -> void:
	button_container = VBoxContainer.new()
	button_container.custom_minimum_size = Vector2(220.0, 110.0)
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	button_container.add_theme_constant_override("separation", 16)

	button_container.anchor_left = 0.5
	button_container.anchor_top = 0.5
	button_container.anchor_right = 0.5
	button_container.anchor_bottom = 0.5

	button_container.offset_left = -110.0
	button_container.offset_top = -55.0
	button_container.offset_right = 110.0
	button_container.offset_bottom = 55.0

	add_child(button_container)

	play_button = create_menu_button("Play")
	dev_city_button = create_menu_button("Dev City")
	exit_button = create_menu_button("Exit")

	button_container.add_child(play_button)

	if OS.is_debug_build():
		button_container.add_child(dev_city_button)

	button_container.add_child(exit_button)

	play_button.pressed.connect(on_play_pressed)
	dev_city_button.pressed.connect(on_dev_city_pressed)
	exit_button.pressed.connect(on_exit_pressed)

func on_dev_city_pressed() -> void:
	DevCityLauncher.launch_dev_city(
		get_tree(),
		city_scene_path,
		"res://scenes/MainMenu.tscn"
	)

func create_menu_button(button_text: String) -> Button:
	var button: Button = Button.new()
	button.text = button_text
	button.custom_minimum_size = Vector2(220.0, 44.0)
	button.focus_mode = Control.FOCUS_NONE

	var normal_style: StyleBoxFlat = StyleBoxFlat.new()
	normal_style.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	normal_style.border_color = Color(1.0, 1.0, 1.0, 1.0)
	normal_style.set_corner_radius_all(6)

	var hover_style: StyleBoxFlat = StyleBoxFlat.new()
	hover_style.bg_color = Color(0.78, 0.88, 1.0, 1.0)
	hover_style.border_color = Color(1.0, 1.0, 1.0, 1.0)
	hover_style.set_corner_radius_all(6)

	var pressed_style: StyleBoxFlat = StyleBoxFlat.new()
	pressed_style.bg_color = Color(0.55, 0.70, 0.95, 1.0)
	pressed_style.border_color = Color(1.0, 1.0, 1.0, 1.0)
	pressed_style.set_corner_radius_all(6)

	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.add_theme_color_override("font_color", Color(0.02, 0.04, 0.12, 1.0))
	button.add_theme_color_override("font_hover_color", Color(0.02, 0.04, 0.12, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.02, 0.04, 0.12, 1.0))
	button.add_theme_font_size_override("font_size", 20)

	return button


func on_play_pressed() -> void:
	if world_scene_path.is_empty():
		push_error("World scene path is empty.")
		return

	var error: Error = get_tree().change_scene_to_file(world_scene_path)

	if error != OK:
		push_error("Could not load world scene: " + world_scene_path)


func on_exit_pressed() -> void:
	get_tree().quit()
