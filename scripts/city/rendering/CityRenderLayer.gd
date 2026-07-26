extends Node2D
class_name CityRenderLayer

var _draw_callback: Callable


func setup(draw_callback: Callable) -> void:
	_draw_callback = draw_callback
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _draw() -> void:
	if _draw_callback.is_valid():
		_draw_callback.call(self)
