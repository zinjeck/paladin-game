extends RefCounted
class_name MapCameraSessionState

# Presentation-only camera persistence. World camera state is singular; city
# camera state is keyed by explicit settlement and exact state/world identity.

const MAX_CITY_CAMERA_ENTRIES: int = 16

static var has_world_camera_state: bool = false
static var world_camera_position: Vector2 = Vector2.ZERO
static var world_camera_zoom: Vector2 = Vector2.ONE

static var city_camera_state_by_settlement_id: Dictionary = {}
static var city_camera_recency: Array[int] = []


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

static func store_city_camera_for_binding(
	binding: CityPresentationBinding,
	position: Vector2,
	zoom: Vector2
) -> bool:
	if binding == null or not binding.is_valid():
		return false
	city_camera_state_by_settlement_id[binding.settlement_id] = {
		"settlement_id": binding.settlement_id,
		"city_state_ref": weakref(binding.city_state),
		"city_world_ref": weakref(binding.city_world),
		"city_state_instance_id": int(binding.city_state.get_instance_id()),
		"city_world_instance_id": int(binding.city_world.get_instance_id()),
		"city_seed": binding.city_seed,
		"position": position,
		"zoom": zoom,
	}
	_touch_city_camera_entry(binding.settlement_id)
	_trim_city_camera_entries()
	return true


static func get_city_camera_for_binding(
	binding: CityPresentationBinding
) -> Dictionary:
	if binding == null or not binding.is_valid():
		return {}
	var raw_entry = city_camera_state_by_settlement_id.get(
		binding.settlement_id,
		{}
	)
	if not raw_entry is Dictionary:
		return {}
	var entry: Dictionary = raw_entry
	var state_ref = entry.get("city_state_ref")
	var world_ref = entry.get("city_world_ref")
	var cached_state = (
		state_ref.get_ref() if state_ref is WeakRef else null
	)
	var cached_world = (
		world_ref.get_ref() if world_ref is WeakRef else null
	)
	if (
		cached_state == null
		or cached_world == null
		or not is_same(cached_state, binding.city_state)
		or not is_same(cached_world, binding.city_world)
		or int(entry.get("city_state_instance_id", -1))
		!= int(binding.city_state.get_instance_id())
		or int(entry.get("city_world_instance_id", -1))
		!= int(binding.city_world.get_instance_id())
		or int(entry.get("city_seed", 0)) != binding.city_seed
	):
		reset_city_camera_for_settlement(binding.settlement_id)
		return {}
	_touch_city_camera_entry(binding.settlement_id)
	return entry.duplicate(true)


static func has_city_camera_for_binding(
	binding: CityPresentationBinding
) -> bool:
	return not get_city_camera_for_binding(binding).is_empty()


static func reset_city_camera_for_settlement(settlement_id: int) -> void:
	city_camera_state_by_settlement_id.erase(settlement_id)
	city_camera_recency.erase(settlement_id)


static func reset_city_camera() -> void:
	city_camera_state_by_settlement_id.clear()
	city_camera_recency.clear()


static func get_city_camera_entry_count() -> int:
	return city_camera_state_by_settlement_id.size()


static func _touch_city_camera_entry(settlement_id: int) -> void:
	city_camera_recency.erase(settlement_id)
	city_camera_recency.append(settlement_id)


static func _trim_city_camera_entries() -> void:
	while city_camera_recency.size() > MAX_CITY_CAMERA_ENTRIES:
		var oldest_settlement_id: int = int(city_camera_recency.pop_front())
		city_camera_state_by_settlement_id.erase(oldest_settlement_id)

#endregion
