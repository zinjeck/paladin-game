extends RefCounted
class_name CityInformationPanel

const SettlementPresentationBindingScript = preload(
	"res://scripts/settlements/presentation/SettlementPresentationBinding.gd"
)

# File responsibility: the fixed city-summary panel's presentation, layout,
# and read-only projection of city identity, time, population, and citizen needs.

class SlimNeedMeter:
	extends Control

	var value: float = 0.0:
		set(new_value):
			var clamped_value := clampf(new_value, 0.0, 100.0)

			if is_equal_approx(value, clamped_value):
				return

			value = clamped_value
			queue_redraw()

	var background_color: Color
	var fill_color: Color
	var border_color: Color


	func setup(
		new_background_color: Color,
		new_fill_color: Color,
		new_border_color: Color
	) -> void:
		background_color = new_background_color
		fill_color = new_fill_color
		border_color = new_border_color
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		# The meter is custom-drawn from its current Control bounds, so a real
		# geometry change must invalidate it. Value changes are separately guarded
		# above and do not redraw when the clamped visual value is unchanged.
		resized.connect(queue_redraw)


	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return

		var border_width := minf(1.0, size.y * 0.5)
		var inner_rect := Rect2(
			Vector2(border_width, border_width),
			Vector2(
				maxf(size.x - border_width * 2.0, 0.0),
				maxf(size.y - border_width * 2.0, 0.0)
			)
		)

		if inner_rect.size.x > 0.0 and inner_rect.size.y > 0.0:
			# Red and green occupy the exact same inner track. Drawing the red
			# remainder inside the border first prevents it from appearing thicker
			# than the green fill as the value depletes.
			draw_rect(inner_rect, background_color, true)
			var fill_rect := inner_rect
			fill_rect.size.x *= value / 100.0

			if fill_rect.size.x > 0.0:
				draw_rect(fill_rect, fill_color, true)

		draw_rect(
			Rect2(Vector2.ZERO, size),
			border_color,
			false,
			border_width
		)


const PANEL_POSITION := Vector2.ZERO
const PANEL_SIZE := Vector2(432.0, 144.0)
const MAIN_AREA_WIDTH: float = 348.0
const INFORMATION_CELL_WIDTH: float = MAIN_AREA_WIDTH / 2.0
const ACTION_BUTTON_WIDTH: float = PANEL_SIZE.x - MAIN_AREA_WIDTH
const ROW_HEIGHT: float = PANEL_SIZE.y / 3.0
const METER_POSITION := Vector2(44.0, 22.0)
const METER_SIZE := Vector2(120.0, 4.0)
const OBJECT_PANEL_GAP: float = 8.0

const PANEL_FILL_COLOR := Color(0.31, 0.31, 0.31, 0.97)
const CELL_FILL_COLOR := Color(0.40, 0.40, 0.40, 0.97)
const BUTTON_FILL_COLOR := Color(0.37, 0.37, 0.37, 0.98)
const BORDER_COLOR := Color(0.15, 0.15, 0.15, 1.0)
const TEXT_COLOR := Color(0.95, 0.95, 0.95, 1.0)
const METER_GREEN_COLOR := Color(0.12, 0.68, 0.20, 1.0)
const METER_RED_COLOR := Color(0.72, 0.14, 0.11, 1.0)

var panel: Panel
var city_name_label: Label
var date_time_label: Label
var season_label: Label
var hunger_label: Label
var happiness_label: Label
var hunger_bar: SlimNeedMeter
var happiness_bar: SlimNeedMeter
var population_button: Button
var jobs_button: Button
var reserved_button: Button
var presentation_binding: SettlementPresentationBindingScript
var highest_accepted_binding_generation: int = 0


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

	presentation_binding = binding
	highest_accepted_binding_generation = maxi(
		highest_accepted_binding_generation,
		binding.generation
	)
	if panel != null:
		refresh_all()
	return true


func bind_city_presentation(
	binding: SettlementPresentationBindingScript
) -> bool:
	return bind_settlement_presentation(binding)


func is_bound_to_settlement_presentation(
	binding: SettlementPresentationBindingScript
) -> bool:
	return (
		presentation_binding != null
		and presentation_binding.matches_binding(binding)
	)


func is_bound_to_city_presentation(
	binding: SettlementPresentationBindingScript
) -> bool:
	return is_bound_to_settlement_presentation(binding)


func reset_presentation() -> void:
	presentation_binding = null


func setup(parent: Control) -> void:
	if parent == null:
		push_error("CityInformationPanel.setup requires a parent Control.")
		return
	if presentation_binding == null or not presentation_binding.is_valid():
		push_error(
			"CityInformationPanel.setup requires an explicit city presentation binding."
		)
		return

	panel = Panel.new()
	panel.name = "CityInformationPanel"
	panel.clip_contents = true
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override(
		"panel",
		_make_flat_style(PANEL_FILL_COLOR, BORDER_COLOR, 2)
	)
	parent.add_child(panel)

	var city_name_cell := _create_cell(
		"CityNameCell",
		Vector2.ZERO,
		Vector2(MAIN_AREA_WIDTH, ROW_HEIGHT)
	)
	city_name_label = _create_centered_label(
		city_name_cell,
		"CityNameLabel",
		18
	)
	city_name_label.clip_text = true
	city_name_label.text_overrun_behavior = (
		TextServer.OVERRUN_TRIM_ELLIPSIS
	)

	var date_time_cell := _create_cell(
		"DateTimeCell",
		Vector2(0.0, ROW_HEIGHT),
		Vector2(INFORMATION_CELL_WIDTH, ROW_HEIGHT)
	)
	date_time_label = _create_centered_label(
		date_time_cell,
		"DateTimeLabel",
		14
	)

	var season_cell := _create_cell(
		"SeasonCell",
		Vector2(INFORMATION_CELL_WIDTH, ROW_HEIGHT),
		Vector2(INFORMATION_CELL_WIDTH, ROW_HEIGHT)
	)
	season_label = _create_centered_label(
		season_cell,
		"SeasonLabel",
		14
	)

	var hunger_cell := _create_cell(
		"HungerCell",
		Vector2(0.0, ROW_HEIGHT * 2.0),
		Vector2(INFORMATION_CELL_WIDTH, ROW_HEIGHT)
	)
	hunger_label = _create_need_label(
		hunger_cell,
		"HungerLabel",
		"Hun"
	)
	hunger_bar = _create_need_bar(
		hunger_cell,
		"HungerBar"
	)

	var happiness_cell := _create_cell(
		"HappinessCell",
		Vector2(INFORMATION_CELL_WIDTH, ROW_HEIGHT * 2.0),
		Vector2(INFORMATION_CELL_WIDTH, ROW_HEIGHT)
	)
	happiness_label = _create_need_label(
		happiness_cell,
		"HappinessLabel",
		"Hap"
	)
	happiness_bar = _create_need_bar(
		happiness_cell,
		"HappinessBar"
	)

	population_button = _create_action_button(
		"PopulationButton",
		0,
		"Pop\n0"
	)
	jobs_button = _create_action_button(
		"JobsButton",
		1,
		"Jobs"
	)
	reserved_button = _create_action_button(
		"ReservedButton",
		2,
		""
	)

	layout()
	refresh_all()


func layout() -> void:
	if panel == null:
		return

	panel.position = PANEL_POSITION
	panel.size = PANEL_SIZE


func refresh_all() -> void:
	refresh_identity()
	refresh_time()
	refresh_citizen_data()


func refresh_identity() -> void:
	if city_name_label == null:
		return

	var city_name := ""
	if presentation_binding != null and presentation_binding.is_valid():
		var city_state := _get_bound_city_state()
		city_name = str(
			city_state.city_runtime_data.get(
				"name",
				""
			)
		).strip_edges()

		if city_name.is_empty():
			city_name = str(
				WorldPoliticalState.get_settlement(
					presentation_binding.settlement_id
				).get("name", "")
			).strip_edges()

		if (
			city_name.is_empty()
			and presentation_binding.settlement_id
			== WorldPoliticalState.get_player_capital_settlement_id()
			and WorldData.has_official_founding_identity()
		):
			city_name = WorldData.get_official_city_name().strip_edges()

	city_name_label.text = city_name
	city_name_label.tooltip_text = city_name

	if season_label != null:
		season_label.text = ""


func refresh_time() -> void:
	if date_time_label == null:
		return

	date_time_label.text = SimulationClock.get_time_display_text()


func refresh_citizen_data() -> void:
	var city_state := _get_bound_city_state()
	var city_is_founded: bool = (
		city_state != null and city_state.is_city_founded()
	)
	var citizen_count := (
		CityCitizenRegistrySystem.get_city_population_count_for_city_state(
			city_state
		)
		if city_state != null
		else 0
	)

	if population_button != null:
		population_button.text = "Pop\n" + str(citizen_count)

	if hunger_label != null:
		hunger_label.visible = city_is_founded
	if happiness_label != null:
		happiness_label.visible = city_is_founded
	if hunger_bar != null:
		hunger_bar.visible = city_is_founded
	if happiness_bar != null:
		happiness_bar.visible = city_is_founded

	var average_hunger := 0.0
	var average_happiness := 0.0
	if city_state != null and citizen_count > 0:
		var total_hunger := 0.0
		var total_happiness := 0.0
		for raw_citizen in city_state.citizen_registry_state.citizens:
			if not raw_citizen is Dictionary:
				continue
			var citizen_id := int(raw_citizen.get("id", -1))
			total_hunger += float(
				CitizenNeedsSystem.get_city_citizen_hunger_for_city_state(
					city_state,
					citizen_id
				)
			)
			total_happiness += float(
				CitizenNeedsSystem.get_city_citizen_happiness_for_city_state(
					city_state,
					citizen_id
				)
			)

		average_hunger = total_hunger / float(citizen_count)
		average_happiness = total_happiness / float(citizen_count)

	if hunger_bar != null:
		hunger_bar.value = average_hunger
	if happiness_bar != null:
		happiness_bar.value = average_happiness


func get_reserved_bottom_y() -> float:
	return PANEL_POSITION.y + PANEL_SIZE.y + OBJECT_PANEL_GAP


func _create_cell(
	cell_name: String,
	cell_position: Vector2,
	cell_size: Vector2
) -> Panel:
	var cell := Panel.new()
	cell.name = cell_name
	cell.position = cell_position
	cell.size = cell_size
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_theme_stylebox_override(
		"panel",
		_make_flat_style(CELL_FILL_COLOR, BORDER_COLOR, 1)
	)
	panel.add_child(cell)
	return cell


func _create_centered_label(
	parent: Control,
	label_name: String,
	font_size: int
) -> Label:
	var new_label := Label.new()
	new_label.name = label_name
	new_label.position = Vector2(8.0, 3.0)
	new_label.size = parent.size - Vector2(16.0, 6.0)
	new_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	new_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	new_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	new_label.add_theme_font_size_override("font_size", font_size)
	new_label.add_theme_color_override("font_color", TEXT_COLOR)
	parent.add_child(new_label)
	return new_label


func _create_need_label(
	parent: Control,
	label_name: String,
	label_text: String
) -> Label:
	var new_label := Label.new()
	new_label.name = label_name
	new_label.text = label_text
	new_label.position = Vector2(7.0, 6.0)
	new_label.size = Vector2(34.0, ROW_HEIGHT - 12.0)
	new_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	new_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	new_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	new_label.add_theme_font_size_override("font_size", 13)
	new_label.add_theme_color_override("font_color", TEXT_COLOR)
	parent.add_child(new_label)
	return new_label


func _create_need_bar(
	parent: Control,
	bar_name: String
) -> SlimNeedMeter:
	var bar := SlimNeedMeter.new()
	bar.name = bar_name
	bar.position = METER_POSITION
	bar.size = METER_SIZE
	bar.setup(
		METER_RED_COLOR,
		METER_GREEN_COLOR,
		BORDER_COLOR
	)
	parent.add_child(bar)
	return bar


func _create_action_button(
	button_name: String,
	row_index: int,
	button_text: String
) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = button_text
	button.position = Vector2(
		MAIN_AREA_WIDTH,
		ROW_HEIGHT * float(row_index)
	)
	button.size = Vector2(ACTION_BUTTON_WIDTH, ROW_HEIGHT)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", TEXT_COLOR)
	button.add_theme_stylebox_override(
		"normal",
		_make_flat_style(BUTTON_FILL_COLOR, BORDER_COLOR, 1)
	)
	button.add_theme_stylebox_override(
		"hover",
		_make_flat_style(
			BUTTON_FILL_COLOR.lightened(0.10),
			BORDER_COLOR,
			1
		)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_make_flat_style(
			BUTTON_FILL_COLOR.darkened(0.10),
			BORDER_COLOR,
			1
		)
	)
	panel.add_child(button)
	return button


func _get_bound_city_state() -> CitySettlementSimulationState:
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


func _make_flat_style(
	fill_color: Color,
	border_color: Color,
	border_width: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(0)
	return style
