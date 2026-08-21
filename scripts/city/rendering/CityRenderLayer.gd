extends Node2D
class_name CityRenderLayer

var _draw_callback: Callable
var _draw_observer: Callable
var _redraw_requested: bool = false
var layer_name: String = ""
var draw_count: int = 0
var last_draw_duration_usec: int = 0
var total_draw_duration_usec: int = 0
var last_draw_timestamp_usec: int = 0


func setup(
	draw_callback: Callable,
	presentation_layer_name: String = "",
	draw_observer: Callable = Callable()
) -> void:
	_draw_callback = draw_callback
	_draw_observer = draw_observer
	layer_name = presentation_layer_name
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func request_redraw() -> void:
	# Rendering invalidations can arrive from several simulation versions during
	# one frame. Collapse them into one draw request for this layer.
	if _redraw_requested:
		return

	_redraw_requested = true
	queue_redraw()


func _draw() -> void:
	_redraw_requested = false

	if _draw_callback.is_valid():
		var draw_started_usec := Time.get_ticks_usec()
		_draw_callback.call(self)
		last_draw_duration_usec = maxi(
			Time.get_ticks_usec() - draw_started_usec,
			0
		)
		draw_count += 1
		total_draw_duration_usec += last_draw_duration_usec
		last_draw_timestamp_usec = Time.get_ticks_usec()
		if _draw_observer.is_valid():
			_draw_observer.call(self, last_draw_duration_usec)


func get_metrics() -> Dictionary:
	return {
		"layer_name": layer_name,
		"draw_count": draw_count,
		"last_draw_duration_usec": last_draw_duration_usec,
		"total_draw_duration_usec": total_draw_duration_usec,
		"last_draw_timestamp_usec": last_draw_timestamp_usec,
	}


#region Shared Drawing Primitives

static func get_screen_constant_world_width(
	viewport: Viewport,
	pixel_width: float
) -> float:
	var active_camera := viewport.get_camera_2d()

	if active_camera == null:
		return pixel_width

	var zoom_x: float = maxf(active_camera.zoom.x, 0.001)
	return pixel_width / zoom_x


static func draw_screen_constant_inset_rect_border(
	values: Dictionary
) -> void:
	var draw_target: CanvasItem = values.get("draw_target")
	var viewport: Viewport = values.get("viewport")
	var rect: Rect2 = values.get("rect", Rect2())
	var border_color: Color = values.get("border_color", Color.WHITE)
	var inset_amount := float(values.get("inset_amount", 0.0))
	var border_width_pixels := float(values.get("border_width_pixels", 1.0))

	if draw_target == null or viewport == null:
		return

	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var border_width := get_screen_constant_world_width(
		viewport,
		border_width_pixels
	)
	var max_x_inset: float = maxf(0.0, rect.size.x * 0.5 - 0.01)
	var max_y_inset: float = maxf(0.0, rect.size.y * 0.5 - 0.01)
	var safe_inset: float = minf(
		inset_amount,
		minf(max_x_inset, max_y_inset)
	)
	var max_x_width: float = maxf(0.01, rect.size.x - safe_inset * 2.0)
	var max_y_width: float = maxf(0.01, rect.size.y - safe_inset * 2.0)
	var safe_width: float = minf(
		border_width,
		minf(max_x_width, max_y_width)
	)
	var inner := rect.grow(-safe_inset)

	draw_target.draw_rect(
		Rect2(inner.position, Vector2(inner.size.x, safe_width)),
		border_color,
		true
	)
	draw_target.draw_rect(
		Rect2(
			Vector2(
				inner.position.x,
				inner.position.y + inner.size.y - safe_width
			),
			Vector2(inner.size.x, safe_width)
		),
		border_color,
		true
	)
	draw_target.draw_rect(
		Rect2(inner.position, Vector2(safe_width, inner.size.y)),
		border_color,
		true
	)
	draw_target.draw_rect(
		Rect2(
			Vector2(
				inner.position.x + inner.size.x - safe_width,
				inner.position.y
			),
			Vector2(safe_width, inner.size.y)
		),
		border_color,
		true
	)


static func draw_framed_rect(values: Dictionary) -> void:
	var draw_target: CanvasItem = values.get("draw_target")
	var rect: Rect2 = values.get("rect", Rect2())
	var frame_color: Color = values.get("frame_color", Color.WHITE)
	var fill_color: Color = values.get("fill_color", Color.TRANSPARENT)
	var frame_thickness := float(values.get("frame_thickness", 0.0))

	if draw_target == null:
		return

	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var max_x_thickness: float = maxf(0.01, rect.size.x * 0.5 - 0.01)
	var max_y_thickness: float = maxf(0.01, rect.size.y * 0.5 - 0.01)
	var safe_thickness: float = minf(
		frame_thickness,
		minf(max_x_thickness, max_y_thickness)
	)

	draw_target.draw_rect(rect, frame_color, true)
	var inner_rect := rect.grow(-safe_thickness)

	if inner_rect.size.x <= 0.0 or inner_rect.size.y <= 0.0:
		return

	draw_target.draw_rect(inner_rect, fill_color, true)


static func draw_inner_box_border(values: Dictionary) -> void:
	var draw_target: CanvasItem = values.get("draw_target")
	var rect: Rect2 = values.get("rect", Rect2())
	var border_color: Color = values.get("border_color", Color.WHITE)
	var border_width := float(values.get("border_width", 0.0))

	if draw_target == null:
		return

	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return

	var safe_width: float = minf(
		border_width,
		minf(rect.size.x * 0.5, rect.size.y * 0.5)
	)
	safe_width = maxf(safe_width, 0.01)

	draw_target.draw_rect(
		Rect2(rect.position, Vector2(rect.size.x, safe_width)),
		border_color,
		true
	)
	draw_target.draw_rect(
		Rect2(
			Vector2(
				rect.position.x,
				rect.position.y + rect.size.y - safe_width
			),
			Vector2(rect.size.x, safe_width)
		),
		border_color,
		true
	)
	draw_target.draw_rect(
		Rect2(rect.position, Vector2(safe_width, rect.size.y)),
		border_color,
		true
	)
	draw_target.draw_rect(
		Rect2(
			Vector2(
				rect.position.x + rect.size.x - safe_width,
				rect.position.y
			),
			Vector2(safe_width, rect.size.y)
		),
		border_color,
		true
	)


static func draw_tile_footprint_border(values: Dictionary) -> void:
	var draw_target: CanvasItem = values.get("draw_target")
	var footprint_tiles: Array = values.get("footprint_tiles", [])
	var border_color: Color = values.get("border_color", Color.WHITE)
	var border_width := float(values.get("border_width", 0.0))
	var tile_size := maxi(int(values.get("tile_size", 1)), 1)

	if draw_target == null or footprint_tiles.is_empty():
		return

	var footprint_lookup: Dictionary = {}

	for raw_tile in footprint_tiles:
		if raw_tile is Vector2i:
			footprint_lookup[raw_tile] = true

	var safe_width := minf(border_width, float(tile_size) * 0.5)

	for raw_tile in footprint_tiles:
		if not raw_tile is Vector2i:
			continue

		var tile_position: Vector2i = raw_tile
		var tile_rect := Rect2(
			Vector2(
				float(tile_position.x * tile_size),
				float(tile_position.y * tile_size)
			),
			Vector2(float(tile_size), float(tile_size))
		)

		if not footprint_lookup.has(tile_position + Vector2i.UP):
			draw_target.draw_rect(
				Rect2(
					tile_rect.position,
					Vector2(tile_rect.size.x, safe_width)
				),
				border_color,
				true
			)

		if not footprint_lookup.has(tile_position + Vector2i.DOWN):
			draw_target.draw_rect(
				Rect2(
					Vector2(
						tile_rect.position.x,
						tile_rect.end.y - safe_width
					),
					Vector2(tile_rect.size.x, safe_width)
				),
				border_color,
				true
			)

		if not footprint_lookup.has(tile_position + Vector2i.LEFT):
			draw_target.draw_rect(
				Rect2(
					tile_rect.position,
					Vector2(safe_width, tile_rect.size.y)
				),
				border_color,
				true
			)

		if not footprint_lookup.has(tile_position + Vector2i.RIGHT):
			draw_target.draw_rect(
				Rect2(
					Vector2(
						tile_rect.end.x - safe_width,
						tile_rect.position.y
					),
					Vector2(safe_width, tile_rect.size.y)
				),
				border_color,
				true
			)

#endregion
