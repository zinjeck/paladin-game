extends Camera2D
class_name StrategyCamera2D

@export var move_speed: float = 650.0
@export var zoom_speed: float = 0.15
@export var min_zoom: float = 0.25
@export var max_zoom: float = 80.0

@export var edge_scroll_enabled: bool = true
@export var edge_scroll_margin: float = 25.0

# 1/6 abyss, 5/6 generated map at the edge.
@export var abyss_screen_fraction: float = 1.0 / 6.0

var settings: MapSettings = MapSettings.new()

var map_width_tiles: int = 0
var map_height_tiles: int = 0
var map_tile_size: int = 0


func _ready() -> void:
	if map_width_tiles <= 0 or map_height_tiles <= 0 or map_tile_size <= 0:
		configure_for_map(settings.width, settings.height, settings.tile_size, true)
	else:
		clamp_camera_to_map_bounds()


func configure_for_map(width_tiles: int, height_tiles: int, tile_size: int, center_camera: bool = true) -> void:
	map_width_tiles = width_tiles
	map_height_tiles = height_tiles
	map_tile_size = tile_size

	if center_camera:
		position = get_map_center()

	clamp_camera_to_map_bounds()


func _process(delta: float) -> void:
	var direction: Vector2 = get_camera_movement_direction()

	if direction != Vector2.ZERO:
		var zoom_value: float = max(zoom.x, 0.001)
		var adjusted_speed: float = move_speed / zoom_value

		position += direction.normalized() * adjusted_speed * delta
		clamp_camera_to_map_bounds()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_camera(1.0 + zoom_speed)

		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_camera(1.0 - zoom_speed)


func get_camera_movement_direction() -> Vector2:
	var direction: Vector2 = Vector2.ZERO

	if Input.is_key_pressed(KEY_D) or Input.is_action_pressed("ui_right"):
		direction.x += 1.0

	if Input.is_key_pressed(KEY_A) or Input.is_action_pressed("ui_left"):
		direction.x -= 1.0

	if Input.is_key_pressed(KEY_S) or Input.is_action_pressed("ui_down"):
		direction.y += 1.0

	if Input.is_key_pressed(KEY_W) or Input.is_action_pressed("ui_up"):
		direction.y -= 1.0

	if edge_scroll_enabled:
		var viewport_size: Vector2 = get_viewport_rect().size
		var mouse_position: Vector2 = get_viewport().get_mouse_position()

		var mouse_inside_viewport: bool = (
			mouse_position.x >= 0.0
			and mouse_position.y >= 0.0
			and mouse_position.x <= viewport_size.x
			and mouse_position.y <= viewport_size.y
		)

		if mouse_inside_viewport:
			if mouse_position.x <= edge_scroll_margin:
				direction.x -= 1.0
			elif mouse_position.x >= viewport_size.x - edge_scroll_margin:
				direction.x += 1.0

			if mouse_position.y <= edge_scroll_margin:
				direction.y -= 1.0
			elif mouse_position.y >= viewport_size.y - edge_scroll_margin:
				direction.y += 1.0

	return direction


func zoom_camera(multiplier: float) -> void:
	var old_zoom: float = zoom.x
	var new_zoom: float = clamp(old_zoom * multiplier, min_zoom, max_zoom)

	if is_equal_approx(old_zoom, new_zoom):
		return

	var mouse_world_before_zoom: Vector2 = get_global_mouse_position()

	zoom = Vector2(new_zoom, new_zoom)

	var mouse_world_after_zoom: Vector2 = get_global_mouse_position()
	position += mouse_world_before_zoom - mouse_world_after_zoom

	clamp_camera_to_map_bounds()


func clamp_camera_to_map_bounds() -> void:
	var map_size: Vector2 = get_map_pixel_size()
	var visible_size: Vector2 = get_visible_world_size()

	var allowed_abyss: Vector2 = visible_size * abyss_screen_fraction

	var min_position: Vector2 = Vector2(
		visible_size.x * 0.5 - allowed_abyss.x,
		visible_size.y * 0.5 - allowed_abyss.y
	)

	var max_position: Vector2 = Vector2(
		map_size.x - visible_size.x * 0.5 + allowed_abyss.x,
		map_size.y - visible_size.y * 0.5 + allowed_abyss.y
	)

	if min_position.x <= max_position.x:
		position.x = clamp(position.x, min_position.x, max_position.x)
	else:
		position.x = map_size.x * 0.5

	if min_position.y <= max_position.y:
		position.y = clamp(position.y, min_position.y, max_position.y)
	else:
		position.y = map_size.y * 0.5


func get_map_pixel_size() -> Vector2:
	var width_tiles := map_width_tiles
	var height_tiles := map_height_tiles
	var tile_size := map_tile_size

	if width_tiles <= 0:
		width_tiles = settings.width

	if height_tiles <= 0:
		height_tiles = settings.height

	if tile_size <= 0:
		tile_size = settings.tile_size

	var pixel_width: float = float(width_tiles * tile_size)
	var pixel_height: float = float(height_tiles * tile_size)

	return Vector2(pixel_width, pixel_height)


func get_map_center() -> Vector2:
	return get_map_pixel_size() * 0.5


func get_visible_world_size() -> Vector2:
	var zoom_value: float = max(zoom.x, 0.001)
	return get_viewport_rect().size / zoom_value
