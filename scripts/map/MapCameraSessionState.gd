extends RefCounted
class_name MapCameraSessionState

# Owns presentation-only camera persistence between world and city scenes.
# Authoritative simulation state must not depend on these values.

static var has_world_camera_state: bool = false
static var world_camera_position: Vector2 = Vector2.ZERO
static var world_camera_zoom: Vector2 = Vector2.ONE

static var has_city_camera_state: bool = false
static var city_camera_position: Vector2 = Vector2.ZERO
static var city_camera_zoom: Vector2 = Vector2.ONE


#region World Camera

static func store_world_camera(position: Vector2, zoom: Vector2) -> void:
	world_camera_position = position
	world_camera_zoom = zoom
	has_world_camera_state = true


static func reset_world_camera() -> void:
	has_world_camera_state = false
	world_camera_position = Vector2.ZERO
	world_camera_zoom = Vector2.ONE

#endregion


#region City Camera

static func store_city_camera(position: Vector2, zoom: Vector2) -> void:
	city_camera_position = position
	city_camera_zoom = zoom
	has_city_camera_state = true


static func reset_city_camera() -> void:
	has_city_camera_state = false
	city_camera_position = Vector2.ZERO
	city_camera_zoom = Vector2.ONE

#endregion
