extends Node2D
class_name CityObjectPanelAnchor

const SettlementPresentationBindingScript = preload(
	"res://scripts/settlements/presentation/SettlementPresentationBinding.gd"
)

# Owns the selected-settlement entity panels. The current detailed simulation
# backend is city-specific, but binding, reset, layout, and attachment are
# settlement-presentation responsibilities and do not depend on CityRenderer.

const SELECTION_KIND_NONE := "none"
const SELECTION_KIND_OBJECT := "object"
const SELECTION_KIND_CITIZEN := "citizen"
const SELECTION_KIND_CONSTRUCTION_SITE := "construction_site"

const PANEL_SIDE_GAP: float = 10.0
const WORKPLACE_DETAILS_GAP: float = 8.0
const VIEWPORT_MARGIN: float = 8.0
const CONSTRUCTION_PANEL_WIDTH: float = 252.0
const CONSTRUCTION_PANEL_HEADER_HEIGHT: float = 60.0
const CONSTRUCTION_PANEL_RESOURCE_ROW_HEIGHT: float = 26.0
const CONSTRUCTION_PANEL_BOTTOM_PADDING: float = 14.0

var presentation_binding: SettlementPresentationBindingScript
var highest_accepted_binding_generation: int = 0
var tile_size: int = 1
var citizen_text_presenter: CitizenDebugPanel

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

var selected_entity_kind: String = SELECTION_KIND_NONE
var selected_entity_id: int = -1
var was_world_attached: bool = false
var road_panel_suppressed: bool = false
var last_viewport_size: Vector2 = Vector2.ZERO
var last_reserved_bottom_y: float = 0.0


func can_bind_settlement_presentation(
	binding: SettlementPresentationBindingScript,
	new_tile_size: int
) -> bool:
	if (
		binding == null
		or not binding.is_valid()
		or not binding.supports_backend_capability(
			SettlementPresentationBindingScript.CAPABILITY_CITY_DETAIL
		)
		or new_tile_size <= 0
	):
		return false
	if is_bound_to_settlement_presentation(binding):
		return true
	return binding.generation > highest_accepted_binding_generation


func bind_settlement_presentation(
	binding: SettlementPresentationBindingScript,
	new_tile_size: int,
	new_citizen_text_presenter: CitizenDebugPanel = null
) -> bool:
	if not can_bind_settlement_presentation(binding, new_tile_size):
		return false
	if is_bound_to_settlement_presentation(binding):
		tile_size = new_tile_size
		citizen_text_presenter = new_citizen_text_presenter
		return true
	presentation_binding = binding
	highest_accepted_binding_generation = binding.generation
	tile_size = new_tile_size
	citizen_text_presenter = new_citizen_text_presenter
	reset_selection_presentation()
	return true


func bind_city_presentation(
	binding: SettlementPresentationBindingScript,
	new_tile_size: int,
	new_citizen_text_presenter: CitizenDebugPanel = null
) -> bool:
	return bind_settlement_presentation(
		binding,
		new_tile_size,
		new_citizen_text_presenter
	)


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
	citizen_text_presenter = null
	reset_selection_presentation()


func reset_selection_presentation() -> void:
	selected_entity_kind = SELECTION_KIND_NONE
	selected_entity_id = -1
	was_world_attached = false
	road_panel_suppressed = false
	hide_selected_entity_panels()


func setup(parent: Control) -> bool:
	if parent == null:
		return false
	if object_info_panel != null:
		return true
	_create_object_info_panel(parent)
	_create_construction_site_info_panel(parent)
	return true


func _process(_delta: float) -> void:
	synchronize()


func update_selected_entity_panel(
	selection_kind: String,
	selection_id: int
) -> bool:
	selected_entity_kind = selection_kind
	selected_entity_id = selection_id

	if object_info_panel == null or not _has_valid_binding():
		hide_selected_entity_panels()
		return selection_kind == SELECTION_KIND_NONE
	if selection_kind == SELECTION_KIND_CONSTRUCTION_SITE:
		return _update_selected_construction_site_panel(selection_id)

	hide_construction_site_info_panel()
	if selection_kind == SELECTION_KIND_CITIZEN:
		return _update_selected_citizen_panel(selection_id)
	if selection_kind != SELECTION_KIND_OBJECT or selection_id < 0:
		_hide_selected_object_panel()
		return selection_kind == SELECTION_KIND_NONE

	var city_object := _get_city_object_by_id(selection_id)
	if city_object.is_empty():
		_hide_selected_object_panel()
		return false
	_update_selected_object_panel(city_object)
	return true


func synchronize() -> void:
	if object_info_panel == null:
		return
	if selected_entity_kind == SELECTION_KIND_CONSTRUCTION_SITE:
		update_construction_site_info_panel_screen_position()
		return
	if selected_entity_kind != SELECTION_KIND_OBJECT or selected_entity_id < 0:
		_restore_hud_layout_if_needed()
		return

	var city_object := _get_city_object_by_id(selected_entity_id)
	if city_object.is_empty():
		_restore_hud_layout_if_needed()
		return
	if str(city_object.get("type", "")) == CityObjectCatalog.CITY_OBJECT_ROAD:
		_suppress_road_object_panels()
		return
	road_panel_suppressed = false
	_attach_panel_to_object(city_object)


func layout(viewport_size: Vector2, reserved_bottom_y: float) -> void:
	last_viewport_size = viewport_size
	last_reserved_bottom_y = maxf(reserved_bottom_y, 0.0)
	if object_info_panel == null:
		return

	var panel_width := 240.0
	var desired_panel_y := maxf(viewport_size.y * 0.10, last_reserved_bottom_y)
	var panel_y := maxf(desired_panel_y, 0.0)
	var panel_height := minf(600.0, maxf(viewport_size.y - panel_y, 0.0))
	object_info_panel.size = Vector2(panel_width, panel_height)
	object_info_panel.position = Vector2(0.0, panel_y)
	object_info_title_label.position = Vector2(0.0, 10.0)
	object_info_title_label.size = Vector2(panel_width, 32.0)
	object_info_body_label.position = Vector2(14.0, 56.0)
	object_info_body_label.size = Vector2(panel_width - 28.0, 370.0)
	_layout_workplace_details_button(workplace_details_button_body_line_count)
	_layout_workplace_details_panel()
	_layout_storage_rows(panel_width)


func hide_selected_entity_panels() -> void:
	_hide_selected_object_panel()
	hide_construction_site_info_panel()


func hide_workplace_details_ui() -> void:
	workplace_details_open = false
	workplace_details_object_id = -1
	workplace_details_button_body_line_count = 0
	if workplace_details_button != null:
		workplace_details_button.visible = false
		workplace_details_button.text = "Workplace Details"
	if workplace_details_panel != null:
		workplace_details_panel.visible = false


func hide_construction_site_info_panel() -> void:
	if construction_site_info_panel != null:
		construction_site_info_panel.visible = false


func update_construction_site_info_panel_screen_position() -> void:
	if (
		construction_site_info_panel == null
		or not construction_site_info_panel.visible
		or selected_entity_kind != SELECTION_KIND_CONSTRUCTION_SITE
		or selected_entity_id <= 0
	):
		return
	var site := CityConstructionSystem.get_city_construction_site_by_id_for_city_state(
		_get_bound_city_state(), selected_entity_id
	)
	if site.is_empty():
		return
	var site_world_rect := _get_construction_site_world_rect(site)
	if site_world_rect.size.x <= 0.0 or site_world_rect.size.y <= 0.0:
		return
	var canvas_transform := get_global_transform_with_canvas()
	var right_middle_screen := canvas_transform * Vector2(
		site_world_rect.end.x,
		site_world_rect.position.y + site_world_rect.size.y * 0.5
	)
	construction_site_info_panel.position = Vector2(
		right_middle_screen.x + PANEL_SIDE_GAP,
		right_middle_screen.y - construction_site_info_panel.size.y
	)


func _create_object_info_panel(parent: Control) -> void:
	object_info_panel = Panel.new()
	object_info_panel.visible = false
	object_info_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	object_info_panel.add_theme_stylebox_override(
		"panel", _create_flat_style(Color(0.16, 0.16, 0.16, 0.94), Color(0.42, 0.42, 0.42, 1.0))
	)
	parent.add_child(object_info_panel)
	object_info_title_label = Label.new()
	object_info_title_label.text = "Settlement Center"
	object_info_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	object_info_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	object_info_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	object_info_title_label.add_theme_color_override("font_color", Color(0.88, 0.96, 1.0, 1.0))
	object_info_title_label.add_theme_font_size_override("font_size", 18)
	object_info_panel.add_child(object_info_title_label)
	object_info_body_label = Label.new()
	object_info_body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	object_info_body_label.add_theme_color_override("font_color", Color(0.82, 0.82, 0.82, 1.0))
	object_info_body_label.add_theme_font_size_override("font_size", 13)
	object_info_panel.add_child(object_info_body_label)
	_create_storage_rows()
	_create_workplace_details_ui(parent)


func _create_storage_rows() -> void:
	object_info_storage_title_label = Label.new()
	object_info_storage_title_label.text = "Storage"
	object_info_storage_title_label.visible = false
	object_info_storage_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	object_info_storage_title_label.add_theme_color_override("font_color", Color(0.88, 0.96, 1.0, 1.0))
	object_info_storage_title_label.add_theme_font_size_override("font_size", 15)
	object_info_panel.add_child(object_info_storage_title_label)
	for _resource_index in range(maxi(CityResourceCatalog.get_city_resource_types().size(), 1)):
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


func _create_workplace_details_ui(parent: Control) -> void:
	workplace_details_button = Button.new()
	workplace_details_button.text = "Workplace Details"
	workplace_details_button.visible = false
	workplace_details_button.focus_mode = Control.FOCUS_NONE
	workplace_details_button.mouse_filter = Control.MOUSE_FILTER_STOP
	object_info_panel.add_child(workplace_details_button)
	workplace_details_button.pressed.connect(_on_workplace_details_pressed)
	workplace_details_panel = Panel.new()
	workplace_details_panel.visible = false
	workplace_details_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	workplace_details_panel.add_theme_stylebox_override(
		"panel", _create_flat_style(Color(0.16, 0.16, 0.16, 0.94), Color(0.42, 0.42, 0.42, 1.0))
	)
	parent.add_child(workplace_details_panel)
	workplace_details_title_label = Label.new()
	workplace_details_title_label.text = "Workplace Details"
	workplace_details_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	workplace_details_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	workplace_details_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	workplace_details_title_label.add_theme_color_override("font_color", Color(0.88, 0.96, 1.0, 1.0))
	workplace_details_title_label.add_theme_font_size_override("font_size", 18)
	workplace_details_panel.add_child(workplace_details_title_label)
	workplace_details_body_label = Label.new()
	workplace_details_body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	workplace_details_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	workplace_details_body_label.add_theme_color_override("font_color", Color(0.82, 0.82, 0.82, 1.0))
	workplace_details_body_label.add_theme_font_size_override("font_size", 13)
	workplace_details_panel.add_child(workplace_details_body_label)


func _create_construction_site_info_panel(parent: Control) -> void:
	construction_site_info_panel = Panel.new()
	construction_site_info_panel.visible = false
	construction_site_info_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	construction_site_info_panel.add_theme_stylebox_override(
		"panel", _create_flat_style(Color(0.16, 0.16, 0.16, 0.94), Color(0.42, 0.42, 0.42, 1.0))
	)
	parent.add_child(construction_site_info_panel)
	construction_site_info_title_label = Label.new()
	construction_site_info_title_label.text = "Construction Progress: 0%"
	construction_site_info_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	construction_site_info_title_label.add_theme_color_override("font_color", Color(0.88, 0.96, 1.0, 1.0))
	construction_site_info_title_label.add_theme_font_size_override("font_size", 16)
	construction_site_info_panel.add_child(construction_site_info_title_label)
	construction_site_info_body_label = Label.new()
	construction_site_info_body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	construction_site_info_body_label.add_theme_color_override("font_color", Color(0.82, 0.82, 0.82, 1.0))
	construction_site_info_body_label.add_theme_font_size_override("font_size", 14)
	construction_site_info_body_label.add_theme_constant_override("line_spacing", 4)
	construction_site_info_panel.add_child(construction_site_info_body_label)


func _create_flat_style(fill_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	return style


func _layout_workplace_details_button(body_line_count: int) -> void:
	if workplace_details_button == null:
		return
	var button_y := 56.0 + float(body_line_count) * 21.0 + 6.0
	workplace_details_button.position = Vector2(14.0, button_y)
	workplace_details_button.size = Vector2(object_info_panel.size.x - 28.0, 30.0)


func _layout_workplace_details_panel() -> void:
	if workplace_details_panel == null:
		return
	var panel_width := 320.0
	var panel_height := object_info_panel.size.y
	workplace_details_panel.size = Vector2(panel_width, panel_height)
	workplace_details_panel.position = Vector2(
		object_info_panel.position.x + object_info_panel.size.x + WORKPLACE_DETAILS_GAP,
		object_info_panel.position.y
	)
	workplace_details_title_label.position = Vector2(0.0, 10.0)
	workplace_details_title_label.size = Vector2(panel_width, 32.0)
	workplace_details_body_label.position = Vector2(14.0, 56.0)
	workplace_details_body_label.size = Vector2(panel_width - 28.0, panel_height - 70.0)


func _layout_construction_panel_content(resource_row_count: int) -> void:
	var safe_row_count := maxi(resource_row_count, 1)
	var panel_height := (
		CONSTRUCTION_PANEL_HEADER_HEIGHT
		+ float(safe_row_count) * CONSTRUCTION_PANEL_RESOURCE_ROW_HEIGHT
		+ CONSTRUCTION_PANEL_BOTTOM_PADDING
	)
	construction_site_info_panel.size = Vector2(CONSTRUCTION_PANEL_WIDTH, panel_height)
	construction_site_info_title_label.position = Vector2(12.0, 8.0)
	construction_site_info_title_label.size = Vector2(CONSTRUCTION_PANEL_WIDTH - 24.0, 32.0)
	construction_site_info_body_label.position = Vector2(20.0, CONSTRUCTION_PANEL_HEADER_HEIGHT)
	construction_site_info_body_label.size = Vector2(
		CONSTRUCTION_PANEL_WIDTH - 40.0,
		float(safe_row_count) * CONSTRUCTION_PANEL_RESOURCE_ROW_HEIGHT
	)


func _layout_storage_rows(panel_width: float) -> void:
	object_info_storage_title_label.position = Vector2(14.0, 436.0)
	object_info_storage_title_label.size = Vector2(panel_width - 28.0, 24.0)
	for i in range(object_info_storage_icons.size()):
		var row_y := 468.0 + float(i) * 28.0
		object_info_storage_icons[i].position = Vector2(18.0, row_y + 4.0)
		object_info_storage_icons[i].size = Vector2(16.0, 16.0)
		if i < object_info_storage_amount_labels.size():
			object_info_storage_amount_labels[i].position = Vector2(44.0, row_y)
			object_info_storage_amount_labels[i].size = Vector2(panel_width - 58.0, 28.0)


func _update_selected_citizen_panel(citizen_id: int) -> bool:
	hide_workplace_details_ui()
	var city_state := _get_bound_city_state()
	var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id_for_city_state(
		city_state, citizen_id
	)
	if citizen.is_empty():
		object_info_panel.visible = false
		_hide_storage_display()
		return false

	object_info_panel.visible = true
	_hide_storage_display()
	var citizen_name := str(citizen.get("name", "Citizen " + str(citizen_id)))
	var raw_position = citizen.get("city_tile_position", CityCitizens.INVALID_CITY_TILE_POSITION)
	var position_text := "invalid"
	if raw_position is Vector2i:
		position_text = str(raw_position.x) + ", " + str(raw_position.y)
	var raw_current_task = citizen.get("current_task", {})
	var task_target_text := "none"
	if raw_current_task is Dictionary:
		var raw_task_target_tile = raw_current_task.get(
			"target_tile", CityCitizens.INVALID_CITY_TILE_POSITION
		)
		if (
			raw_task_target_tile is Vector2i
			and raw_task_target_tile != CityCitizens.INVALID_CITY_TILE_POSITION
		):
			task_target_text = str(raw_task_target_tile)
	var movement_state_text := str(citizen.get(
		"movement_state", CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_IDLE
	))
	var movement_text := movement_state_text.capitalize()
	if movement_state_text == CityCitizens.CITY_CITIZEN_MOVEMENT_STATE_MOVING:
		movement_text += " -> " + str(citizen.get(
			"movement_destination_tile", CityCitizens.INVALID_CITY_TILE_POSITION
		))

	object_info_title_label.text = citizen_name
	var body_lines: Array = [
		"Citizen #" + str(citizen_id),
		"Sex: " + CityCitizens.get_city_citizen_sex_display_name(str(citizen.get("sex", ""))),
		"Position: " + position_text,
		"State: " + str(citizen.get("state", "unknown")).capitalize(),
		"Task: " + _get_citizen_task_text(citizen),
		"Activity tile: " + task_target_text,
		"Movement: " + movement_text,
		"Hunger: " + str(CitizenNeedsSystem.get_city_citizen_hunger_for_city_state(city_state, citizen_id)) + " / " + str(CityCitizens.MAX_CITIZEN_HUNGER),
		"Personal food: " + str(CityResourceContainerSystem.get_food_nutrition_in_resource_container(CityCitizenInventorySystem.get_city_citizen_inventory_for_city_state(city_state, citizen_id))) + " nutrition",
		"Home: " + _get_citizen_home_text(citizen),
		"Workplace: " + _get_citizen_job_text(citizen),
	]
	body_lines.append_array(_get_citizen_haul_status_lines(citizen))
	object_info_body_label.text = _lines_text(body_lines)
	_update_citizen_inventory_display(citizen)
	return true


func _get_citizen_haul_status_lines(citizen: Dictionary) -> Array:
	var city_state := _get_bound_city_state()
	var citizen_id := int(citizen.get("id", -1))
	if not CitizenHaulingSystem.city_citizen_is_hauling_for_city_state(city_state, citizen_id):
		return ["Hauling: No"]

	var haul := CityCitizenTaskRuntimeSystem.get_city_citizen_current_haul_for_city_state(city_state, citizen_id)
	var cargo_resources := CityCitizenInventorySystem.get_city_citizen_haul_cargo_resources_for_city_state(city_state, citizen_id)
	var resource := str(haul.get("resource_type", WorldData.RESOURCE_NONE))
	if resource == WorldData.RESOURCE_NONE and not cargo_resources.is_empty():
		var cargo_resource_names: Array = cargo_resources.keys()
		cargo_resource_names.sort()
		resource = str(cargo_resource_names[0])
	var cargo_amount := CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount_for_city_state(city_state, citizen_id)
	var carry_capacity := CityCitizenInventorySystem.get_city_citizen_carry_capacity_for_city_state(city_state, citizen_id)
	var personal_inventory_used := CityCitizenInventorySystem.get_city_citizen_inventory_used_capacity_for_city_state(city_state, citizen_id)
	var lines: Array = [
		"Hauling: Yes",
		"Current pickup: " + resource.capitalize(),
		"Cargo contents: " + CitizenDebugPanel.format_resource_manifest(cargo_resources),
		"Cargo total: " + str(cargo_amount) + " / " + str(maxi(carry_capacity - personal_inventory_used, 0)) + " (shared carry " + str(personal_inventory_used + cargo_amount) + " / " + str(carry_capacity) + ")",
		"Haul source: " + _format_haul_endpoint(haul.get("source", {})),
		"Haul destination: " + _format_haul_endpoint(haul.get("destination", {})),
		"Pickup stops: " + str(maxi(int(haul.get("pickup_stop_count", 0)), 0)),
		"Haul phase: " + str(haul.get("phase", CityCitizens.CITY_CITIZEN_HAUL_PHASE_NONE)).replace("_", " ").capitalize(),
	]
	var reservation_id := int(haul.get(
		"reservation_id", CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
	))
	if reservation_id > 0:
		var reservation := CityLogisticsSystem.get_city_haul_reservation_for_city_state(city_state, reservation_id)
		if not reservation.is_empty():
			var reserved_resources := CityLogisticsSystem.get_city_haul_reservation_destination_resources_for_city_state(city_state, reservation_id)
			lines.append(
				"Reservation #" + str(reservation_id)
				+ ": source " + str(maxi(int(reservation.get("source_reserved_amount", 0)), 0))
				+ ", destination " + str(maxi(int(reservation.get("destination_reserved_amount", 0)), 0))
				+ " [" + CitizenDebugPanel.format_resource_manifest(reserved_resources) + "]"
			)
	return lines


func _update_citizen_inventory_display(citizen: Dictionary) -> void:
	var city_state := _get_bound_city_state()
	var citizen_id := int(citizen.get("id", -1))
	if citizen_id <= 0:
		_hide_storage_display()
		return
	var inventory := CityCitizenInventorySystem.get_city_citizen_inventory_for_city_state(city_state, citizen_id)
	var present_resources := CityResourceContainerSystem.get_resource_container_present_resources(inventory)
	var used_capacity := CityCitizenInventorySystem.get_city_citizen_inventory_used_capacity_for_city_state(city_state, citizen_id)
	var carry_capacity := CityCitizenInventorySystem.get_city_citizen_carry_capacity_for_city_state(city_state, citizen_id)
	var haul_cargo_amount := CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount_for_city_state(city_state, citizen_id)
	var inventory_title := "Personal Inventory (" + str(used_capacity) + " / " + str(carry_capacity) + ")"
	if haul_cargo_amount > 0:
		inventory_title += " | Total Carried " + str(used_capacity + haul_cargo_amount) + " / " + str(carry_capacity)
	_show_resource_rows(
		inventory_title,
		present_resources,
		func(resource: String) -> int:
			return CityResourceContainerSystem.get_resource_container_resource_amount(inventory, resource)
	)


func _update_selected_construction_site_panel(site_id: int) -> bool:
	object_info_panel.visible = false
	_hide_storage_display()
	hide_workplace_details_ui()
	var city_state := _get_bound_city_state()
	var site := CityConstructionSystem.get_city_construction_site_by_id_for_city_state(city_state, site_id)
	if site.is_empty():
		hide_construction_site_info_panel()
		return false
	var progress_summary := CityConstructionSystem.get_city_construction_site_progress_summary_for_city_state(city_state, site_id)
	if progress_summary.is_empty():
		hide_construction_site_info_panel()
		return false

	construction_site_info_title_label.text = (
		"Construction Progress: "
		+ str(int(progress_summary.get("progress_percent", 0)))
		+ "%"
	)
	var resource_lines: Array[String] = []
	resource_lines.append("Phase: " + str(site.get("phase", "unknown")).capitalize())
	resource_lines.append(
		"Labor: " + str(maxi(int(site.get("completed_labor_minutes", 0)), 0))
		+ "/" + str(maxi(int(site.get("required_labor_minutes", 0)), 0))
		+ " minutes"
	)
	var material_line_start_index := resource_lines.size()
	var material_recipe = site.get("material_recipe", {})
	if material_recipe is Dictionary:
		for resource in CityResourceCatalog.get_city_resource_types():
			var required_amount := maxi(int(material_recipe.get(resource, 0)), 0)
			if required_amount <= 0:
				continue
			var delivered_amount := mini(
				CityConstructionSystem.get_city_construction_site_reserved_resource_amount_for_city_state(
					city_state, site_id, resource
				),
				required_amount
			)
			resource_lines.append(
				resource.capitalize() + ": " + str(delivered_amount) + "/" + str(required_amount)
			)
	if resource_lines.size() == material_line_start_index:
		resource_lines.append("Materials: none")
	construction_site_info_body_label.text = "\n".join(resource_lines)
	_layout_construction_panel_content(resource_lines.size())
	construction_site_info_panel.visible = true
	construction_site_info_panel.move_to_front()
	update_construction_site_info_panel_screen_position()
	return true


func _update_selected_object_panel(city_object: Dictionary) -> void:
	object_info_panel.visible = true
	var object_type := str(city_object.get("type", ""))
	object_info_title_label.text = (
		"City Keep"
		if object_type == CityObjectCatalog.CITY_OBJECT_CITY_CENTER
		else _get_city_object_display_name(city_object)
	)
	var body_lines: Array = ["Object: " + _get_city_object_display_name(city_object)]
	var workplace_detail_lines: Array = []
	var is_workplace := CityObjectCatalog.city_object_is_workplace(city_object)
	if object_type == CityObjectCatalog.CITY_OBJECT_CITY_CENTER:
		_append_city_center_info(body_lines)
	elif object_type == CityObjectCatalog.CITY_OBJECT_HOUSE:
		_append_house_info(city_object, body_lines)
	elif is_workplace:
		_append_workplace_info(city_object, body_lines, workplace_detail_lines)
	var metadata_lines: Array = workplace_detail_lines if is_workplace else body_lines
	_append_object_metadata(city_object, metadata_lines)
	object_info_body_label.text = _lines_text(body_lines)
	if is_workplace:
		_update_workplace_details(city_object, body_lines.size(), workplace_detail_lines)
	else:
		hide_workplace_details_ui()
	_update_object_storage_display(city_object)


func _append_city_center_info(body_lines: Array) -> void:
	var city_state := _get_bound_city_state()
	body_lines.append(
		"Population: "
		+ str(CityCitizenRegistrySystem.get_city_population_count_for_city_state(city_state))
	)
	body_lines.append(
		"Male: "
		+ str(CityCitizenRegistrySystem.get_city_citizen_count_by_sex_for_city_state(
			city_state, CityCitizens.CITY_CITIZEN_SEX_MALE
		))
		+ " | Female: "
		+ str(CityCitizenRegistrySystem.get_city_citizen_count_by_sex_for_city_state(
			city_state, CityCitizens.CITY_CITIZEN_SEX_FEMALE
		))
	)
	body_lines.append(
		"Housed: "
		+ str(CityAssignmentSystem.get_city_housed_citizen_count_for_city_state(city_state))
		+ " / "
		+ str(CityAssignmentSystem.get_total_city_resident_capacity_for_city_state(city_state))
	)
	body_lines.append(
		"Unemployed: "
		+ str(CityEmploymentSystem.get_city_unemployed_citizen_count_for_city_state(city_state))
	)


func _append_house_info(city_object: Dictionary, body_lines: Array) -> void:
	var city_state := _get_bound_city_state()
	body_lines.append(
		"Residents: "
		+ str(CityAssignmentSystem.get_city_object_resident_count_for_city_state(city_state, city_object))
		+ " / " + str(CityObjectCatalog.get_city_object_resident_capacity(city_object))
	)
	var food_supply := CityResourceMatcher.get_city_home_food_supply_status_for_city_state(
		city_state, city_object
	)
	body_lines.append(
		"Food reserve: " + str(int(food_supply.get("stored_nutrition", 0)))
		+ " / " + str(int(food_supply.get("target_nutrition", 0))) + " nutrition"
	)
	body_lines.append(
		"Incoming food: " + str(int(food_supply.get("incoming_nutrition", 0)))
		+ " | Unfilled: " + str(int(food_supply.get("unfulfilled_nutrition", 0)))
	)
	for resident_name in CityAssignmentSystem.get_city_object_resident_names_for_city_state(
		city_state, city_object
	):
		body_lines.append("- " + str(resident_name))


func _append_workplace_info(
	city_object: Dictionary,
	body_lines: Array,
	detail_lines: Array
) -> void:
	var city_state := _get_bound_city_state()
	var production_status := CityObjectCatalog.get_city_object_production_status(city_object)
	body_lines.append("Status: " + _get_workplace_status_display_name(production_status))
	body_lines.append(
		"Assigned: "
		+ str(CityEmploymentSystem.get_city_object_worker_count_for_city_state(city_state, city_object))
		+ " / " + str(CityObjectCatalog.get_city_object_worker_capacity(city_object))
	)
	body_lines.append(
		"Present: "
		+ str(CityEmploymentSystem.get_city_object_attending_worker_count_for_city_state(city_state, city_object))
	)
	body_lines.append(
		"Productive: " + str(CityObjectCatalog.get_city_object_productive_worker_count(city_object))
	)
	for worker_name in CityEmploymentSystem.get_city_object_worker_names_for_city_state(
		city_state, city_object
	):
		body_lines.append("- " + str(worker_name))

	var output_resources := CityObjectCatalog.get_city_object_output_resources(city_object)
	if not output_resources.is_empty():
		var output_names: Array[String] = []
		for output_resource in output_resources:
			output_names.append(output_resource.capitalize())
		detail_lines.append("Output: " + ", ".join(output_names))
	var production_recipe := CityObjectCatalog.get_city_object_production_recipe(city_object)
	var work_units_per_batch := int(production_recipe.get("work_units_per_batch", 0))
	if work_units_per_batch > 0:
		detail_lines.append(
			"Progress: "
			+ str(CityObjectCatalog.get_city_object_production_progress_work_units(city_object))
			+ " / " + str(work_units_per_batch)
		)
	for output_resource in output_resources:
		detail_lines.append(
			"Rate: "
			+ _format_compact_number(WorkplaceProductionSystem.get_estimated_output_per_hour(
				city_object, output_resource
			))
			+ " " + output_resource + "/hour"
		)
	_append_workplace_resource_source_details(city_object, detail_lines)
	var site_productivity_percentage := float(
		WorkplaceProductionSystem.get_current_site_productivity_basis_points(
			city_object, _get_bound_world()
		)
	) / 100.0
	detail_lines.append(
		"Site Productivity: " + _format_compact_number(site_productivity_percentage) + "%"
	)


func _append_workplace_resource_source_details(
	city_object: Dictionary,
	detail_lines: Array
) -> void:
	var source_evaluation := WorkplaceProductionSystem.get_resource_source_evaluation(
		city_object, _get_bound_world()
	)
	if not bool(source_evaluation.get("uses_environmental_source", false)):
		return
	var source_resource := str(source_evaluation.get("resource_type", WorldData.RESOURCE_NONE))
	var resource_tile_count := int(source_evaluation.get("resource_tile_count", 0))
	var zone_tile_count := int(source_evaluation.get("zone_tile_count", 0))
	var density_percentage := float(source_evaluation.get("density_basis_points", 0)) / 100.0
	var full_density_percentage := float(
		source_evaluation.get("source_density_for_full_productivity_basis_points", 0)
	) / 100.0
	var reach_tiles := int(source_evaluation.get("reach_tiles", 0))
	detail_lines.append(
		source_resource.capitalize() + " Source: " + str(resource_tile_count)
		+ " / " + str(zone_tile_count) + " zone tiles"
	)
	detail_lines.append(
		"Density: " + _format_compact_number(density_percentage)
		+ "% | Full Density: " + _format_compact_number(full_density_percentage)
		+ "% | Reach: " + str(reach_tiles)
	)


func _append_object_metadata(city_object: Dictionary, metadata_lines: Array) -> void:
	var top_left: Vector2i = city_object.get("top_left", Vector2i(-1, -1))
	var size_tiles: Vector2i = city_object.get("size", Vector2i.ZERO)
	if top_left == Vector2i(-1, -1) or size_tiles == Vector2i.ZERO:
		var footprint_tiles := CityObjectSystem.get_city_object_footprint_tiles(city_object)
		if not footprint_tiles.is_empty():
			var footprint_rect := _get_tile_collection_world_rect(footprint_tiles)
			top_left = Vector2i(
				roundi(footprint_rect.position.x / float(tile_size)),
				roundi(footprint_rect.position.y / float(tile_size))
			)
			size_tiles = Vector2i(
				roundi(footprint_rect.size.x / float(tile_size)),
				roundi(footprint_rect.size.y / float(tile_size))
			)
	metadata_lines.append("Owner: " + str(city_object.get("owner", "none")))
	metadata_lines.append(
		"Container: "
		+ _get_container_type_display_name(
			CityResourceContainerSystem.get_city_object_container_type(city_object)
		)
	)
	metadata_lines.append("Position: " + str(top_left.x) + ", " + str(top_left.y))
	metadata_lines.append("Size: " + str(size_tiles.x) + " x " + str(size_tiles.y))


func _update_object_storage_display(city_object: Dictionary) -> void:
	if CityResourceContainerSystem.get_city_object_storage_resources(city_object).is_empty():
		_hide_storage_display()
		return
	var stored_resources := CityResourceContainerSystem.get_city_object_present_storage_resources(city_object)
	var used_capacity := CityResourceContainerSystem.get_city_object_storage_used_capacity(city_object)
	var total_capacity := CityResourceContainerSystem.get_city_object_storage_capacity(city_object)
	_show_resource_rows(
		_get_storage_panel_title(city_object)
		+ " (" + str(used_capacity) + " / " + str(total_capacity) + ")",
		stored_resources,
		func(resource: String) -> int:
			return CityResourceContainerSystem.get_city_object_stored_resource_amount(
				city_object, resource
			)
	)


func _show_resource_rows(
	title: String,
	resources: Array,
	amount_provider: Callable
) -> void:
	object_info_storage_title_label.text = title
	object_info_storage_title_label.visible = true
	for i in range(object_info_storage_icons.size()):
		var has_resource := i < resources.size()
		object_info_storage_icons[i].visible = has_resource
		if i < object_info_storage_amount_labels.size():
			object_info_storage_amount_labels[i].visible = has_resource
		if not has_resource:
			continue
		var resource := str(resources[i])
		object_info_storage_icons[i].color = MapVisuals.get_resource_color(resource)
		if i < object_info_storage_amount_labels.size():
			object_info_storage_amount_labels[i].text = (
				resource.capitalize() + ": " + str(int(amount_provider.call(resource)))
			)


func _hide_storage_display() -> void:
	if object_info_storage_title_label != null:
		object_info_storage_title_label.visible = false
	for icon in object_info_storage_icons:
		icon.visible = false
	for amount_label in object_info_storage_amount_labels:
		amount_label.visible = false


func _update_workplace_details(
	city_object: Dictionary,
	main_body_line_count: int,
	detail_lines: Array
) -> void:
	var object_id := int(city_object.get("id", -1))
	if workplace_details_object_id != object_id:
		workplace_details_open = false
		workplace_details_object_id = object_id
	workplace_details_button_body_line_count = main_body_line_count
	workplace_details_button.visible = true
	workplace_details_button.text = (
		"Hide Workplace Details" if workplace_details_open else "Workplace Details"
	)
	_layout_workplace_details_button(main_body_line_count)
	workplace_details_title_label.text = _get_city_object_display_name(city_object) + " Details"
	workplace_details_body_label.text = _lines_text(detail_lines)
	workplace_details_panel.visible = workplace_details_open
	if workplace_details_open:
		workplace_details_panel.move_to_front()


func _on_workplace_details_pressed() -> void:
	if selected_entity_kind != SELECTION_KIND_OBJECT:
		hide_workplace_details_ui()
		return
	var city_object := _get_city_object_by_id(selected_entity_id)
	if city_object.is_empty() or not CityObjectCatalog.city_object_is_workplace(city_object):
		hide_workplace_details_ui()
		return
	workplace_details_open = not workplace_details_open
	_update_selected_object_panel(city_object)


func _attach_panel_to_object(city_object: Dictionary) -> void:
	var object_world_rect := _get_city_object_world_rect(city_object)
	if (
		object_world_rect.size.x <= 0.0
		or object_world_rect.size.y <= 0.0
	):
		_restore_hud_layout_if_needed()
		return
	var canvas_transform := get_global_transform_with_canvas()
	var right_middle_screen := canvas_transform * Vector2(
		object_world_rect.end.x,
		object_world_rect.position.y + object_world_rect.size.y * 0.5
	)
	var desired_primary_position := Vector2(
		right_middle_screen.x + PANEL_SIDE_GAP,
		right_middle_screen.y - object_info_panel.size.y * 0.5
	)
	object_info_panel.scale = Vector2.ONE
	object_info_panel.position = desired_primary_position
	workplace_details_panel.scale = Vector2.ONE
	_layout_workplace_details_panel()
	_layout_viewport_safe_panel_group(desired_primary_position)
	object_info_panel.move_to_front()
	was_world_attached = true
	if workplace_details_panel.visible:
		workplace_details_panel.move_to_front()


func _layout_viewport_safe_panel_group(desired_primary_position: Vector2) -> void:
	var viewport_size := _get_viewport_size()
	if not _viewport_can_contain_panel(viewport_size, object_info_panel.size):
		object_info_panel.position = desired_primary_position
		return
	if not workplace_details_panel.visible:
		object_info_panel.position = _clamp_panel_position(
			desired_primary_position, object_info_panel.size, viewport_size
		)
		return
	if not _viewport_can_contain_panel(viewport_size, workplace_details_panel.size):
		object_info_panel.position = desired_primary_position
		return
	var combined_width := (
		object_info_panel.size.x + WORKPLACE_DETAILS_GAP + workplace_details_panel.size.x
	)
	if combined_width <= maxf(viewport_size.x - VIEWPORT_MARGIN * 2.0, 0.0):
		_layout_horizontal_panel_group(desired_primary_position, viewport_size)
	else:
		_layout_vertical_panel_group(desired_primary_position, viewport_size)


func _layout_horizontal_panel_group(
	desired_primary_position: Vector2,
	viewport_size: Vector2
) -> void:
	var primary_size := object_info_panel.size
	var details_size := workplace_details_panel.size
	var right_edge := viewport_size.x - VIEWPORT_MARGIN
	var common_y := _clamp_axis_position(
		desired_primary_position.y,
		maxf(primary_size.y, details_size.y),
		viewport_size.y
	)
	var primary_x := _clamp_axis_position(
		desired_primary_position.x, primary_size.x, viewport_size.x
	)
	var right_details_x := primary_x + primary_size.x + WORKPLACE_DETAILS_GAP
	if right_details_x + details_size.x <= right_edge:
		object_info_panel.position = Vector2(primary_x, common_y)
		workplace_details_panel.position = Vector2(right_details_x, common_y)
		return
	var left_details_x := primary_x - WORKPLACE_DETAILS_GAP - details_size.x
	if left_details_x >= VIEWPORT_MARGIN:
		object_info_panel.position = Vector2(primary_x, common_y)
		workplace_details_panel.position = Vector2(left_details_x, common_y)
		return
	var right_primary_x := clampf(
		desired_primary_position.x,
		VIEWPORT_MARGIN,
		right_edge - primary_size.x - WORKPLACE_DETAILS_GAP - details_size.x
	)
	var left_group_x := clampf(
		desired_primary_position.x - details_size.x - WORKPLACE_DETAILS_GAP,
		VIEWPORT_MARGIN,
		right_edge - details_size.x - WORKPLACE_DETAILS_GAP - primary_size.x
	)
	var left_primary_x := left_group_x + details_size.x + WORKPLACE_DETAILS_GAP
	if (
		absf(left_primary_x - desired_primary_position.x)
		< absf(right_primary_x - desired_primary_position.x)
	):
		workplace_details_panel.position = Vector2(left_group_x, common_y)
		object_info_panel.position = Vector2(left_primary_x, common_y)
	else:
		object_info_panel.position = Vector2(right_primary_x, common_y)
		workplace_details_panel.position = Vector2(
			right_primary_x + primary_size.x + WORKPLACE_DETAILS_GAP, common_y
		)


func _layout_vertical_panel_group(
	desired_primary_position: Vector2,
	viewport_size: Vector2
) -> void:
	var primary_size := object_info_panel.size
	var details_size := workplace_details_panel.size
	var combined_height := primary_size.y + WORKPLACE_DETAILS_GAP + details_size.y
	var primary_x := _clamp_axis_position(
		desired_primary_position.x, primary_size.x, viewport_size.x
	)
	var details_x := _clamp_axis_position(
		desired_primary_position.x, details_size.x, viewport_size.x
	)
	if combined_height <= maxf(viewport_size.y - VIEWPORT_MARGIN * 2.0, 0.0):
		var group_y := clampf(
			desired_primary_position.y,
			VIEWPORT_MARGIN,
			viewport_size.y - VIEWPORT_MARGIN - combined_height
		)
		object_info_panel.position = Vector2(primary_x, group_y)
		workplace_details_panel.position = Vector2(
			details_x, group_y + primary_size.y + WORKPLACE_DETAILS_GAP
		)
		return
	object_info_panel.position = _clamp_panel_position(
		desired_primary_position, primary_size, viewport_size
	)
	workplace_details_panel.position = _clamp_panel_position(
		desired_primary_position, details_size, viewport_size
	)


func _suppress_road_object_panels() -> void:
	if was_world_attached:
		_restore_screen_space_layout()
	object_info_panel.visible = false
	workplace_details_panel.visible = false
	if not road_panel_suppressed:
		hide_workplace_details_ui()
	was_world_attached = false
	road_panel_suppressed = true


func _restore_hud_layout_if_needed() -> void:
	if not was_world_attached and not road_panel_suppressed:
		return
	_restore_screen_space_layout()
	was_world_attached = false
	road_panel_suppressed = false


func _restore_screen_space_layout() -> void:
	object_info_panel.scale = Vector2.ONE
	workplace_details_panel.scale = Vector2.ONE
	layout(last_viewport_size, last_reserved_bottom_y)


func _hide_selected_object_panel() -> void:
	if object_info_panel != null:
		object_info_panel.visible = false
	_hide_storage_display()
	hide_workplace_details_ui()


func _get_city_object_by_id(object_id: int) -> Dictionary:
	var city_state := _get_bound_city_state()
	if city_state == null or object_id < 0:
		return {}
	return CityObjectSystem.get_city_object_by_id_for_city_state(city_state, object_id)


func _get_city_object_world_rect(city_object: Dictionary) -> Rect2:
	if city_object.is_empty():
		return Rect2()
	if city_object.has("top_left") and city_object.has("size"):
		var top_left: Vector2i = city_object["top_left"]
		var size_tiles: Vector2i = city_object["size"]
		return Rect2(
			Vector2(top_left * tile_size),
			Vector2(size_tiles * tile_size)
		)
	return _get_tile_collection_world_rect(
		CityObjectSystem.get_city_object_footprint_tiles(city_object)
	)


func _get_construction_site_world_rect(site: Dictionary) -> Rect2:
	var footprint_tiles = site.get("footprint_tiles", [])
	if not footprint_tiles is Array:
		return Rect2()
	return _get_tile_collection_world_rect(footprint_tiles)


func _get_tile_collection_world_rect(raw_tiles: Array) -> Rect2:
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
		else:
			minimum_tile.x = mini(minimum_tile.x, tile_position.x)
			minimum_tile.y = mini(minimum_tile.y, tile_position.y)
			maximum_tile.x = maxi(maximum_tile.x, tile_position.x)
			maximum_tile.y = maxi(maximum_tile.y, tile_position.y)
	if not has_tile:
		return Rect2()
	return Rect2(
		Vector2(minimum_tile * tile_size),
		Vector2((maximum_tile - minimum_tile + Vector2i.ONE) * tile_size)
	)


func _get_container_type_display_name(container_type: String) -> String:
	match container_type:
		CityObjectCatalog.CONTAINER_TYPE_PUBLIC_CITY_STORAGE:
			return "Public city storage"
		CityObjectCatalog.CONTAINER_TYPE_PRIVATE_HOME_STORAGE:
			return "Private home storage"
		CityObjectCatalog.CONTAINER_TYPE_WORKPLACE_STORAGE:
			return "Workplace output buffer"
		CityObjectCatalog.CONTAINER_TYPE_PERSONAL_INVENTORY:
			return "Personal inventory"
		CityObjectCatalog.CONTAINER_TYPE_GROUND_PILE:
			return "Ground pile"
		_:
			return "None"


func _get_storage_panel_title(city_object: Dictionary) -> String:
	match CityResourceContainerSystem.get_city_object_container_type(city_object):
		CityObjectCatalog.CONTAINER_TYPE_PUBLIC_CITY_STORAGE:
			return "Public Storage"
		CityObjectCatalog.CONTAINER_TYPE_PRIVATE_HOME_STORAGE:
			return "Private Storage"
		CityObjectCatalog.CONTAINER_TYPE_WORKPLACE_STORAGE:
			return "Workplace Output Buffer"
		CityObjectCatalog.CONTAINER_TYPE_PERSONAL_INVENTORY:
			return "Personal Inventory"
		CityObjectCatalog.CONTAINER_TYPE_GROUND_PILE:
			return "Ground Pile"
		_:
			return "Storage"


func _get_workplace_status_display_name(production_status: String) -> String:
	match production_status:
		CityObjectCatalog.WORKPLACE_PRODUCTION_STATUS_WORKING:
			return "Working"
		CityObjectCatalog.WORKPLACE_PRODUCTION_STATUS_IDLE_NO_WORKERS:
			return "Idle - No Workers Present"
		CityObjectCatalog.WORKPLACE_PRODUCTION_STATUS_BLOCKED_OUTPUT_FULL:
			return "Blocked - Output Storage Full"
		CityObjectCatalog.WORKPLACE_PRODUCTION_STATUS_BLOCKED_MISSING_INPUT:
			return "Blocked - Missing Input"
		CityObjectCatalog.WORKPLACE_PRODUCTION_STATUS_BLOCKED_NO_RESOURCE_SOURCE:
			return "Blocked - No Resource Source"
		CityObjectCatalog.WORKPLACE_PRODUCTION_STATUS_INACTIVE:
			return "Inactive"
		_:
			return production_status.capitalize()


func _get_citizen_task_text(citizen: Dictionary) -> String:
	if citizen_text_presenter != null:
		return citizen_text_presenter.get_task_text(citizen)
	return "Unknown"


func _get_citizen_home_text(citizen: Dictionary) -> String:
	if citizen_text_presenter != null:
		return citizen_text_presenter.get_home_text(citizen)
	return "unknown"


func _get_citizen_job_text(citizen: Dictionary) -> String:
	if citizen_text_presenter != null:
		return citizen_text_presenter.get_job_text(citizen)
	return "unknown"


func _format_haul_endpoint(raw_endpoint) -> String:
	if citizen_text_presenter != null:
		return citizen_text_presenter.format_haul_endpoint(raw_endpoint)
	return "unknown"


func _format_compact_number(value: float) -> String:
	var nearest_integer := int(round(value))
	return (
		str(nearest_integer)
		if is_equal_approx(value, float(nearest_integer))
		else "%.2f" % value
	)


func _lines_text(lines: Array) -> String:
	var result := ""
	for line_index in range(lines.size()):
		if line_index > 0:
			result += "\n"
		result += str(lines[line_index])
	return result


func _get_city_object_display_name(city_object: Dictionary) -> String:
	if city_object.is_empty():
		return "Unknown"
	return CityObjectCatalog.get_city_object_display_name_for_type(
		str(city_object.get("type", ""))
	)


func _get_bound_city_state() -> CitySettlementSimulationState:
	if not _has_valid_binding():
		return null
	var capability_state = presentation_binding.get_backend_capability(
		SettlementPresentationBindingScript.CAPABILITY_CITY_DETAIL
	)
	return (
		capability_state
		if capability_state is CitySettlementSimulationState
		else null
	)


func _get_bound_world() -> WorldData:
	if not _has_valid_binding():
		return null
	var capability_world = presentation_binding.get_backend_capability(
		SettlementPresentationBindingScript.CAPABILITY_SETTLEMENT_WORLD
	)
	return capability_world if capability_world is WorldData else null


func _has_valid_binding() -> bool:
	return presentation_binding != null and presentation_binding.is_valid()


func _get_viewport_size() -> Vector2:
	if get_viewport() == null:
		return Vector2.ZERO
	return get_viewport().get_visible_rect().size


func _viewport_can_contain_panel(
	viewport_size: Vector2,
	panel_size: Vector2
) -> bool:
	return (
		viewport_size.x >= panel_size.x + VIEWPORT_MARGIN * 2.0
		and viewport_size.y >= panel_size.y + VIEWPORT_MARGIN * 2.0
	)


func _clamp_panel_position(
	desired_position: Vector2,
	panel_size: Vector2,
	viewport_size: Vector2
) -> Vector2:
	return Vector2(
		_clamp_axis_position(desired_position.x, panel_size.x, viewport_size.x),
		_clamp_axis_position(desired_position.y, panel_size.y, viewport_size.y)
	)


func _clamp_axis_position(
	desired_position: float,
	panel_extent: float,
	viewport_extent: float
) -> float:
	var maximum_position := viewport_extent - VIEWPORT_MARGIN - panel_extent
	if maximum_position < VIEWPORT_MARGIN:
		return desired_position
	return clampf(desired_position, VIEWPORT_MARGIN, maximum_position)
