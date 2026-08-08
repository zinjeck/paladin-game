extends Node

const StrategyCameraScript = preload("res://scripts/camera/Camera.gd")
const SimulationSpeedControlsScript = preload(
	"res://scripts/ui/common/SimulationSpeedControls.gd"
)

var failure_count: int = 0


func _ready() -> void:
	var test_viewport := SubViewport.new()
	test_viewport.size = Vector2i(800, 600)
	test_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(test_viewport)

	var camera = StrategyCameraScript.new()
	camera.set_process(false)
	test_viewport.add_child(camera)

	var speed_controls = SimulationSpeedControlsScript.new()
	test_viewport.add_child(speed_controls)

	await get_tree().process_frame
	await get_tree().process_frame

	var speed_button_rect: Rect2 = (
		speed_controls.speed_one_button.get_global_rect()
	)
	var speed_button_edge_point := Vector2(
		speed_button_rect.get_center().x,
		speed_button_rect.position.y + 2.0
	)

	await _move_pointer(test_viewport, speed_button_edge_point)

	var hovered_control := test_viewport.gui_get_hovered_control()
	_expect(
		hovered_control != null
		and (
			hovered_control == speed_controls.speed_one_button
			or speed_controls.speed_one_button.is_ancestor_of(
				hovered_control
			)
		),
		"The speed button fixture must own GUI hover at the top edge."
	)
	_expect(
		camera.get_camera_movement_direction().y == 0.0,
		"Hovering top-edge playback controls must not edge-scroll the camera."
	)

	Input.action_press("ui_right")
	var keyboard_direction := camera.get_camera_movement_direction()
	Input.action_release("ui_right")
	_expect(
		keyboard_direction.x > 0.0,
		"GUI hover must not suppress keyboard camera movement."
	)

	var empty_top_edge_point := Vector2(
		float(test_viewport.size.x) * 0.25,
		2.0
	)
	await _move_pointer(test_viewport, empty_top_edge_point)
	_expect(
		test_viewport.gui_get_hovered_control() == null,
		"The empty top-edge fixture point must not hover GUI."
	)
	_expect(
		camera.get_camera_movement_direction().y < 0.0,
		"The unobstructed top edge must retain camera edge scrolling."
	)

	if failure_count > 0:
		push_error(
			"Strategy camera UI edge-scroll tests failed: "
			+ str(failure_count)
		)
		get_tree().quit(1)
		return

	print("Strategy camera UI edge-scroll tests passed.")
	get_tree().quit(0)


func _move_pointer(viewport: Viewport, position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	viewport.push_input(motion, true)
	await get_tree().process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		return

	failure_count += 1
	push_error(message)
