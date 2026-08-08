extends RefCounted
class_name CitizenDebugPanel

const BUTTON_SIZE: Vector2 = Vector2(145.0, 24.0)
const LIST_PANEL_MARGIN: float = 10.0
const LIST_PANEL_SIZE: Vector2 = Vector2(540.0, 300.0)
const PANEL_PADDING: Vector2 = Vector2(12.0, 10.0)
const BODY_TOP: float = 42.0
const BODY_BOTTOM_MARGIN: float = 12.0

var debug_panel_ui: DebugPanel
var text_provider: Callable
var button: Button
var list_panel: Panel
var title_label: Label
var body_label: Label
var is_open: bool = false

#region Setup

func setup(values: Dictionary) -> void:
	if not _has_valid_setup_values(values):
		return

	debug_panel_ui = values["debug_panel"]
	text_provider = values["text_provider"]

	_create_button()
	_create_list_panel()
	_connect_debug_panel_signals()
	refresh()


func _has_valid_setup_values(values: Dictionary) -> bool:
	var required_keys: Array[String] = [
		"debug_panel",
		"text_provider",
	]

	for key in required_keys:
		if not values.has(key):
			push_error(
				"CitizenDebugPanel.setup is missing required key: "
				+ key
			)
			return false

	if not values["debug_panel"] is DebugPanel:
		push_error(
			"CitizenDebugPanel.setup debug_panel must be DebugPanel."
		)
		return false

	if typeof(values["text_provider"]) != TYPE_CALLABLE:
		push_error(
			"CitizenDebugPanel.setup text_provider must be Callable."
		)
		return false

	return true

#endregion

#region UI construction


func _create_button() -> void:
	if debug_panel_ui.panel == null:
		return

	button = Button.new()
	button.text = "Citizens"
	button.size = BUTTON_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.visible = WorldData.debug_mode_enabled
	button.pressed.connect(Callable(self, "_toggle_list_panel"))

	debug_panel_ui.panel.add_child(button)
	_layout_button()


func _create_list_panel() -> void:
	if debug_panel_ui.canvas_layer == null:
		return

	list_panel = Panel.new()
	list_panel.visible = false
	list_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.0, 0.0, 0.0, 0.76)
	panel_style.border_color = Color(0.0, 0.55, 1.0, 0.60)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(6)
	list_panel.add_theme_stylebox_override("panel", panel_style)

	debug_panel_ui.canvas_layer.add_child(list_panel)

	title_label = Label.new()
	title_label.text = "CITIZENS"
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.add_theme_color_override(
		"font_color",
		Color(0.88, 0.96, 1.0, 1.0)
	)
	title_label.add_theme_font_size_override("font_size", 15)
	list_panel.add_child(title_label)

	body_label = Label.new()
	body_label.text = ""
	body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	body_label.clip_text = false
	body_label.add_theme_color_override(
		"font_color",
		Color(0.82, 0.94, 1.0, 1.0)
	)
	body_label.add_theme_font_size_override("font_size", 12)
	list_panel.add_child(body_label)

	_layout_list_panel()


func _connect_debug_panel_signals() -> void:
	var moved_callable := Callable(
		self,
		"_on_debug_panel_layout_changed"
	)

	if not debug_panel_ui.panel_moved.is_connected(moved_callable):
		debug_panel_ui.panel_moved.connect(moved_callable)

	var minimized_callable := Callable(
		self,
		"_on_debug_panel_minimized_changed"
	)

	if not debug_panel_ui.minimized_changed.is_connected(
		minimized_callable
	):
		debug_panel_ui.minimized_changed.connect(
			minimized_callable
		)

	if debug_panel_ui.panel == null:
		return

	var resized_callable := Callable(
		self,
		"_on_debug_panel_resized"
	)

	if not debug_panel_ui.panel.resized.is_connected(
		resized_callable
	):
		debug_panel_ui.panel.resized.connect(
			resized_callable
		)

#endregion

#region Visibility and layout


func refresh() -> void:
	var is_debug_panel_expanded := (
		WorldData.debug_mode_enabled
		and debug_panel_ui != null
		and not debug_panel_ui.is_minimized
	)

	if button != null:
		button.visible = is_debug_panel_expanded
		button.text = "Hide Citizens" if is_open else "Citizens"
		_layout_button()

	if list_panel == null:
		return

	list_panel.visible = is_debug_panel_expanded and is_open

	if not list_panel.visible:
		return

	_layout_list_panel()
	_refresh_list_text()


func _toggle_list_panel() -> void:
	is_open = not is_open
	refresh()


func _layout_button() -> void:
	if button == null or debug_panel_ui == null:
		return

	var accessory_rect := debug_panel_ui.get_header_accessory_rect()

	button.position = Vector2(
		accessory_rect.end.x - button.size.x,
		accessory_rect.position.y
		+ maxf(
			(accessory_rect.size.y - button.size.y) * 0.5,
			0.0
		)
	)
	button.move_to_front()


func _layout_list_panel() -> void:
	if list_panel == null or debug_panel_ui == null:
		return

	if debug_panel_ui.panel == null:
		return

	list_panel.position = (
		debug_panel_ui.panel.position
		+ Vector2(
			debug_panel_ui.panel.size.x + LIST_PANEL_MARGIN,
			0.0
		)
	)
	list_panel.size = LIST_PANEL_SIZE

	if title_label != null:
		title_label.position = PANEL_PADDING
		title_label.size = Vector2(
			LIST_PANEL_SIZE.x - PANEL_PADDING.x * 2.0,
			24.0
		)

	if body_label != null:
		body_label.position = Vector2(
			PANEL_PADDING.x,
			BODY_TOP
		)
		body_label.size = Vector2(
			LIST_PANEL_SIZE.x - PANEL_PADDING.x * 2.0,
			LIST_PANEL_SIZE.y - BODY_TOP - BODY_BOTTOM_MARGIN
		)


func _refresh_list_text() -> void:
	if body_label == null or not text_provider.is_valid():
		return

	body_label.text = str(text_provider.call())

#endregion

#region Signal callbacks


func _on_debug_panel_layout_changed(
	_new_position: Vector2
) -> void:
	_layout_list_panel()


func _on_debug_panel_minimized_changed(
	_is_minimized: bool
) -> void:
	refresh()


func _on_debug_panel_resized() -> void:
	_layout_button()
	_layout_list_panel()

#endregion

#region Citizen debug text presentation


static func get_debug_list_text() -> String:
	var citizens := WorldData.get_city_citizen_snapshot()

	if citizens.is_empty():
		return "No citizens."

	var lines := []

	for citizen in citizens:
		if not citizen is Dictionary:
			continue

		lines.append(get_debug_line(citizen))

	return "\n".join(lines)


static func get_debug_line(citizen: Dictionary) -> String:
	var citizen_id := int(citizen.get("id", -1))
	var citizen_name := str(
		citizen.get("name", "Citizen " + str(citizen_id))
	)
	var home_text := get_home_text(citizen)
	var job_text := get_job_text(citizen)
	var task_text := get_task_text(citizen)
	var state_text := str(citizen.get("state", "unknown"))
	var raw_position = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)
	var position_text := "invalid"

	if raw_position is Vector2i:
		position_text = str(raw_position)

	var sex_text := (
		WorldData.get_city_citizen_sex_display_name(
			str(citizen.get("sex", ""))
		)
	)
	var hunger := int(citizen.get("hunger", 0))
	var happiness := int(citizen.get("happiness", 0))
	var inventory_used := get_inventory_used(citizen)
	var carry_capacity := int(citizen.get("carry_capacity", 0))
	var haul_text := get_haul_text(citizen)

	return (
		"#" + str(citizen_id)
		+ " " + citizen_name
		+ " | " + sex_text
		+ " | Home: " + home_text
		+ " | Job: " + job_text
		+ " | Pos " + position_text
		+ " | " + state_text
		+ " | Task: " + task_text
		+ " | Hunger " + str(hunger)
		+ " | Happiness " + str(happiness)
		+ " | Inv " + str(inventory_used) + "/" + str(carry_capacity)
		+ " | Haul " + haul_text
	)


static func get_haul_text(citizen: Dictionary) -> String:
	var citizen_id := int(citizen.get("id", -1))

	if not WorldData.city_citizen_is_hauling(citizen_id):
		return "No"

	var haul := WorldData.get_city_citizen_current_haul(citizen_id)
	var cargo_resources := (
		WorldData.get_city_citizen_haul_cargo_resources(citizen_id)
	)
	var inventory_used := get_inventory_used(citizen)
	var haul_capacity := maxi(
		int(citizen.get("carry_capacity", 0)) - inventory_used,
		0
	)
	var phase := str(
		haul.get(
			"phase",
			WorldData.CITY_CITIZEN_HAUL_PHASE_NONE
		)
	)

	return (
		format_resource_manifest(cargo_resources)
		+ " "
		+ str(WorldData.get_city_citizen_haul_cargo_amount(citizen_id))
		+ "/"
		+ str(haul_capacity)
		+ " | "
		+ format_haul_endpoint(haul.get("source", {}))
		+ " -> "
		+ format_haul_endpoint(haul.get("destination", {}))
		+ " | Stops "
		+ str(maxi(int(haul.get("pickup_stop_count", 0)), 0))
		+ " | R#"
		+ str(
			int(
				haul.get(
					"reservation_id",
					WorldData.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
				)
			)
		)
		+ " | "
		+ phase
	)


static func get_home_text(citizen: Dictionary) -> String:
	var home_object_id := int(citizen.get("home_object_id", -1))

	if home_object_id < 0:
		return "none"

	var home_object := WorldData.get_city_object_by_id(home_object_id)

	if home_object.is_empty():
		return "missing #" + str(home_object_id)

	return _get_city_object_display_name(home_object) + " #" + str(home_object_id)


static func get_job_text(citizen: Dictionary) -> String:
	var job_object_id := int(citizen.get("job_object_id", -1))

	if job_object_id < 0:
		return "none"

	var job_object := WorldData.get_city_object_by_id(job_object_id)

	if job_object.is_empty():
		return "missing #" + str(job_object_id)

	return _get_city_object_display_name(job_object) + " #" + str(job_object_id)


static func get_task_text(citizen: Dictionary) -> String:
	var raw_current_task = citizen.get("current_task", {})

	if not raw_current_task is Dictionary:
		return "invalid"

	var current_task: Dictionary = raw_current_task
	var task_kind := str(
		current_task.get(
			"kind",
			WorldData.CITY_CITIZEN_TASK_KIND_NONE
		)
	)

	if task_kind == WorldData.CITY_CITIZEN_TASK_KIND_NONE:
		return "None"

	var task_phase := str(
		current_task.get(
			"phase",
			WorldData.CITY_CITIZEN_TASK_PHASE_NONE
		)
	)
	var task_text := task_kind.capitalize()

	if task_phase != WorldData.CITY_CITIZEN_TASK_PHASE_NONE:
		task_text += " (" + task_phase.capitalize() + ")"

	var target_object_id := int(
		current_task.get("target_object_id", -1)
	)

	if task_kind == WorldData.CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD:
		var food_resource := str(
			current_task.get(
				"food_resource_type",
				WorldData.RESOURCE_NONE
			)
		)
		var food_amount := maxi(
			int(current_task.get("food_requested_amount", 0)),
			0
		)

		if food_amount > 0 and food_resource != WorldData.RESOURCE_NONE:
			task_text += (
				" ["
				+ str(food_amount)
				+ " "
				+ food_resource.capitalize()
				+ "]"
			)

	if task_kind == WorldData.CITY_CITIZEN_TASK_KIND_HAUL:
		var raw_current_haul = citizen.get("current_haul", {})

		if raw_current_haul is Dictionary:
			task_text += (
				" -> "
				+ format_haul_endpoint(
					raw_current_haul.get("source", {})
				)
			)

		return task_text

	if (
		task_kind
		== WorldData.CITY_CITIZEN_TASK_KIND_CONSTRUCTION
		and target_object_id > 0
	):
		var construction_site := (
			CityConstructionSystem.get_city_construction_site_by_id(
				target_object_id
			)
		)

		if construction_site.is_empty():
			return (
				task_text
				+ " -> missing construction site #"
				+ str(target_object_id)
			)

		return (
			task_text
			+ " -> "
			+ WorldData.get_city_object_display_name_for_type(
				str(construction_site.get("object_type", ""))
			)
			+ " Blueprint #"
			+ str(target_object_id)
		)

	if target_object_id > 0:
		var target_object := WorldData.get_city_object_by_id(
			target_object_id
		)

		if target_object.is_empty():
			task_text += " -> missing #" + str(target_object_id)
		else:
			task_text += (
				" -> "
				+ _get_city_object_display_name(target_object)
				+ " #"
				+ str(target_object_id)
			)

	return task_text


static func get_inventory_used(citizen: Dictionary) -> int:
	var inventory = citizen.get("inventory", {})

	if not inventory is Dictionary:
		return 0

	return WorldData.get_resource_container_total_amount(
		inventory
	)


static func format_resource_manifest(resources: Dictionary) -> String:
	if resources.is_empty():
		return "Empty"

	var resource_names: Array = resources.keys()
	resource_names.sort()
	var parts: Array[String] = []

	for raw_resource in resource_names:
		var resource := str(raw_resource)
		var amount := maxi(int(resources.get(raw_resource, 0)), 0)

		if amount <= 0:
			continue

		parts.append(resource.capitalize() + " " + str(amount))

	if parts.is_empty():
		return "Empty"

	return ", ".join(parts)


static func format_haul_endpoint(raw_endpoint) -> String:
	if not raw_endpoint is Dictionary:
		return "invalid"

	var endpoint: Dictionary = raw_endpoint
	var endpoint_kind := str(
		endpoint.get(
			"kind",
			WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
		)
	)
	var endpoint_id := int(endpoint.get("id", -1))

	if endpoint_kind == WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE:
		return "none"

	if (
		endpoint_kind
		== WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE
	):
		var ground_pile := CityLogisticsSystem.get_city_ground_pile_by_id(
			endpoint_id
		)

		if ground_pile.is_empty():
			return "missing ground pile #" + str(endpoint_id)

		return (
			"Ground Pile #"
			+ str(endpoint_id)
			+ " ("
			+ str(
				ground_pile.get(
					"resource_type",
					WorldData.RESOURCE_NONE
				)
			).capitalize()
			+ " "
			+ str(maxi(int(ground_pile.get("amount", 0)), 0))
			+ ")"
		)

	if (
		endpoint_kind
		== WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE
	):
		var site := CityConstructionSystem.get_city_construction_site_by_id(
			endpoint_id
		)

		if site.is_empty():
			return "missing construction site #" + str(endpoint_id)

		return (
			WorldData.get_city_object_display_name_for_type(
				str(site.get("object_type", ""))
			)
			+ " Blueprint #"
			+ str(endpoint_id)
		)

	if (
		endpoint_kind
		!= WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER
	):
		return endpoint_kind + " #" + str(endpoint_id)

	var city_object := WorldData.get_city_object_by_id(endpoint_id)

	if city_object.is_empty():
		return "missing #" + str(endpoint_id)

	return (
		_get_city_object_display_name(city_object)
		+ " #"
		+ str(endpoint_id)
	)


static func _get_city_object_display_name(
	city_object: Dictionary
) -> String:
	if city_object.is_empty():
		return "Unknown"

	return WorldData.get_city_object_display_name_for_type(
		str(city_object.get("type", ""))
	)

#endregion
