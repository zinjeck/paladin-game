extends Node

const PANEL_ANCHOR_SCRIPT := preload(
	"res://scripts/ui/city/CityObjectPanelAnchor.gd"
)

const VIEWPORT_MARGIN: float = 8.0
const DETAILS_GAP: float = 8.0

var failure_count: int = 0


class FakeRenderer:
	extends Node2D

	const SIDECAR_GAP: float = 8.0

	var selected_city_entity_kind: String = "object"
	var selected_city_entity_id: int = 1
	var object_info_panel: Panel
	var workplace_details_panel: Panel
	var ui_layer: CanvasLayer
	var ui_root: Control
	var objects := {
		1: {
			"id": 1,
			"type": WorldData.CITY_OBJECT_FISHING_GROUNDS,
		},
	}
	var object_rects := {
		1: Rect2(Vector2(100.0, 100.0), Vector2(20.0, 20.0)),
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
		object_info_panel.size = Vector2(240.0, 180.0)
		object_info_panel.visible = true
		ui_root.add_child(object_info_panel)

		workplace_details_panel = Panel.new()
		workplace_details_panel.size = Vector2(320.0, 220.0)
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


	func layout_workplace_details_panel(
		_viewport_size: Vector2
	) -> void:
		workplace_details_panel.position = Vector2(
			object_info_panel.position.x
			+ object_info_panel.size.x
			+ SIDECAR_GAP,
			object_info_panel.position.y
		)


func _ready() -> void:
	await _test_secondary_panel_flips_left_at_right_edge()
	await _test_panel_group_reclamps_after_anchor_and_size_changes()

	if failure_count > 0:
		push_error(
			"City panel viewport safety tests failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("City panel viewport safety tests passed.")
	get_tree().quit(0)


func _test_secondary_panel_flips_left_at_right_edge() -> void:
	var renderer := await _make_renderer()
	var viewport_size := get_viewport().get_visible_rect().size
	var primary_size := renderer.object_info_panel.size
	var target_primary_x := (
		viewport_size.x - VIEWPORT_MARGIN - primary_size.x
	)
	var object_right_x := target_primary_x - 10.0

	renderer.object_rects[1] = Rect2(
		Vector2(object_right_x - 20.0, 180.0),
		Vector2(20.0, 20.0)
	)

	var anchor = renderer.get_node("CityObjectPanelAnchor")
	anchor.synchronize()
	var expected_details_x := (
		renderer.object_info_panel.position.x
		- DETAILS_GAP
		- renderer.workplace_details_panel.size.x
	)

	_expect(
		is_equal_approx(
			renderer.workplace_details_panel.position.x,
			expected_details_x
		),
		"A visible secondary panel must flip directly left when the preferred right side would leave the viewport."
	)
	_expect(
		_panel_fits_viewport(renderer.object_info_panel, viewport_size)
		and _panel_fits_viewport(
			renderer.workplace_details_panel,
			viewport_size
		),
		"Both panels must remain fully visible after the right-edge flip."
	)

	renderer.queue_free()
	await get_tree().process_frame


func _test_panel_group_reclamps_after_anchor_and_size_changes() -> void:
	var renderer := await _make_renderer()
	var viewport_size := get_viewport().get_visible_rect().size
	var anchor = renderer.get_node("CityObjectPanelAnchor")

	# Force the requested anchor below and left of the visible screen.
	renderer.object_rects[1] = Rect2(
		Vector2(-200.0, viewport_size.y + 140.0),
		Vector2(20.0, 20.0)
	)
	anchor.synchronize()

	_expect(
		_panel_fits_viewport(renderer.object_info_panel, viewport_size)
		and _panel_fits_viewport(
			renderer.workplace_details_panel,
			viewport_size
		),
		"Changing camera-style attachment coordinates must immediately reclamp the complete popup group."
	)

	# A later content expansion must trigger the same universal layout rule.
	renderer.workplace_details_panel.size = Vector2(380.0, 260.0)
	renderer.object_rects[1] = Rect2(
		Vector2(viewport_size.x - 80.0, viewport_size.y - 30.0),
		Vector2(20.0, 20.0)
	)
	anchor.synchronize()

	_expect(
		_panel_fits_viewport(renderer.object_info_panel, viewport_size)
		and _panel_fits_viewport(
			renderer.workplace_details_panel,
			viewport_size
		),
		"Popup placement must be recalculated when a secondary panel changes size."
	)

	renderer.queue_free()
	await get_tree().process_frame


func _make_renderer() -> FakeRenderer:
	var renderer := FakeRenderer.new()
	renderer.name = "FakeRenderer"
	add_child(renderer)
	renderer.setup_panels()

	var anchor = PANEL_ANCHOR_SCRIPT.new()
	anchor.name = "CityObjectPanelAnchor"
	renderer.add_child(anchor)
	await get_tree().process_frame
	return renderer


func _panel_fits_viewport(
	panel: Control,
	viewport_size: Vector2
) -> bool:
	var panel_rect := Rect2(panel.position, panel.size)

	return (
		panel_rect.position.x >= VIEWPORT_MARGIN
		and panel_rect.position.y >= VIEWPORT_MARGIN
		and panel_rect.end.x
		<= viewport_size.x - VIEWPORT_MARGIN
		and panel_rect.end.y
		<= viewport_size.y - VIEWPORT_MARGIN
	)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error(message)
