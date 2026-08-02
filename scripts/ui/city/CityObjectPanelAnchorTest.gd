extends Node

const PANEL_ANCHOR_SCRIPT := preload(
	"res://scripts/ui/city/CityObjectPanelAnchor.gd"
)

var failure_count: int = 0


class FakeRenderer:
	extends Node2D

	var selected_city_entity_kind: String = "object"
	var selected_city_entity_id: int = 1
	var object_info_panel: Panel
	var workplace_details_panel: Panel
	var ui_layer: CanvasLayer
	var ui_root: Control
	var hud_layout_call_count: int = 0
	var workplace_layout_call_count: int = 0
	var hide_workplace_details_call_count: int = 0
	var objects := {
		1: {
			"id": 1,
			"type": WorldData.CITY_OBJECT_HOUSE,
		},
		2: {
			"id": 2,
			"type": WorldData.CITY_OBJECT_ROAD,
		},
	}
	var object_rects := {
		1: Rect2(Vector2(100.0, 50.0), Vector2(20.0, 30.0)),
		2: Rect2(Vector2(40.0, 80.0), Vector2(8.0, 8.0)),
	}


	func setup_panels() -> void:
		ui_layer = CanvasLayer.new()
		add_child(ui_layer)

		ui_root = Control.new()
		ui_root.set_anchors_and_offsets_preset(
			Control.PRESET_FULL_RECT
		)
		ui_layer.add_child(ui_root)

		object_info_panel = Panel.new()
		object_info_panel.size = Vector2(240.0, 160.0)
		object_info_panel.visible = true
		ui_root.add_child(object_info_panel)

		workplace_details_panel = Panel.new()
		workplace_details_panel.size = Vector2(320.0, 160.0)
		workplace_details_panel.visible = true
		ui_root.add_child(workplace_details_panel)


	func get_city_object_by_id(object_id: int) -> Dictionary:
		return objects.get(object_id, {}).duplicate(true)


	func get_city_object_world_rect(
		city_object: Dictionary
	) -> Rect2:
		return object_rects.get(
			int(city_object.get("id", -1)),
			Rect2()
		)


	func layout_object_info_panel(
		_viewport_size: Vector2
	) -> void:
		hud_layout_call_count += 1
		object_info_panel.position = Vector2(0.0, 64.0)
		layout_workplace_details_panel(_viewport_size)


	func layout_workplace_details_panel(
		_viewport_size: Vector2
	) -> void:
		workplace_layout_call_count += 1
		workplace_details_panel.position = Vector2(
			object_info_panel.position.x
			+ object_info_panel.size.x
			+ 8.0,
			object_info_panel.position.y
		)


	func hide_workplace_details_ui() -> void:
		hide_workplace_details_call_count += 1
		workplace_details_panel.visible = false


func _ready() -> void:
	await _test_world_attachment_and_road_exclusion()

	if failure_count > 0:
		push_error(
			"City object panel anchor test failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City object panel anchor tests passed.")
	get_tree().quit(0)


func _test_world_attachment_and_road_exclusion() -> void:
	var renderer := FakeRenderer.new()
	renderer.position = Vector2(12.0, 18.0)
	renderer.scale = Vector2(2.0, 2.0)
	add_child(renderer)
	renderer.setup_panels()

	var anchor = PANEL_ANCHOR_SCRIPT.new()
	renderer.add_child(anchor)
	await get_tree().process_frame

	anchor.synchronize()
	var object_rect: Rect2 = renderer.object_rects[1]
	var right_middle_world := Vector2(
		object_rect.end.x,
		object_rect.position.y + object_rect.size.y * 0.5
	)
	var right_middle_screen := (
		renderer.get_global_transform_with_canvas()
		* right_middle_world
	)
	var expected_position := Vector2(
		right_middle_screen.x + 10.0,
		right_middle_screen.y
		- renderer.object_info_panel.size.y * 0.5
	)

	_expect(
		renderer.object_info_panel.visible
		and renderer.object_info_panel.position.is_equal_approx(
			expected_position
		),
		"A selected non-road object panel must attach to the object's transformed right side."
	)
	_expect(
		renderer.workplace_details_panel.position.is_equal_approx(
			Vector2(
				expected_position.x
				+ renderer.object_info_panel.size.x
				+ 8.0,
				expected_position.y
			)
		),
		"The workplace details sidecar must remain attached to the main object panel."
	)

	var first_position := renderer.object_info_panel.position
	renderer.scale = Vector2(3.0, 3.0)
	renderer.position = Vector2(-25.0, 9.0)
	anchor.synchronize()
	right_middle_screen = (
		renderer.get_global_transform_with_canvas()
		* right_middle_world
	)
	expected_position = Vector2(
		right_middle_screen.x + 10.0,
		right_middle_screen.y
		- renderer.object_info_panel.size.y * 0.5
	)
	_expect(
		not renderer.object_info_panel.position.is_equal_approx(
			first_position
		)
		and renderer.object_info_panel.position.is_equal_approx(
			expected_position
		),
		"The attachment point must track camera-style canvas pan and zoom transforms."
	)

	renderer.selected_city_entity_id = 2
	renderer.object_info_panel.visible = true
	renderer.workplace_details_panel.visible = true
	anchor.synchronize()
	anchor.synchronize()
	_expect(
		not renderer.object_info_panel.visible
		and not renderer.workplace_details_panel.visible
		and renderer.selected_city_entity_id == 2,
		"Roads must remain selectable without opening object or workplace panels."
	)
	_expect(
		renderer.hide_workplace_details_call_count == 1,
		"Continuous road suppression must not repeatedly reset workplace UI state."
	)

	renderer.selected_city_entity_kind = "citizen"
	renderer.object_info_panel.visible = true
	anchor.synchronize()
	_expect(
		renderer.hud_layout_call_count > 0
		and renderer.object_info_panel.position.is_equal_approx(
			Vector2(0.0, 64.0)
		),
		"Leaving object selection must restore the existing screen-space citizen panel layout."
	)

	renderer.queue_free()
	await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error("City object panel anchor test: " + message)
