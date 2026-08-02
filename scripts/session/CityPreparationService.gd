extends RefCounted
class_name CityPreparationService

# Builds the immutable, CPU-heavy portion of first city entry away from the
# main thread. The finished WorldData and six map-mode Images are handed to the
# city renderer only after the thread has fully completed.

var _thread: Thread
var _active_request: Dictionary = {}
var _queued_request: Dictionary = {}
var _completed_payload: Dictionary = {}
var _failed_signature: String = ""
var _accept_active_result: bool = true


func request_preparation(request: Dictionary) -> void:
	if not is_valid_request(request):
		return

	poll()
	var signature := str(request.get("signature", ""))

	if str(_completed_payload.get("signature", "")) == signature:
		return
	if is_preparing_signature(signature):
		# A pending transition may re-request the same preparation after a
		# cancellation. Re-accept the in-flight result instead of discarding it.
		_accept_active_result = true
		return

	if _thread != null and _thread.is_started():
		_queued_request = request.duplicate(true)
		return

	_start_request(request)


func poll() -> void:
	if _thread == null or not _thread.is_started():
		return
	if _thread.is_alive():
		return

	var raw_result = _thread.wait_to_finish()
	_thread = null
	_active_request.clear()

	if raw_result is Dictionary and _accept_active_result:
		var result: Dictionary = raw_result

		if bool(result.get("valid", false)):
			_completed_payload = result
			_failed_signature = ""
		else:
			_failed_signature = str(result.get("signature", ""))

	_accept_active_result = true

	if not _queued_request.is_empty():
		var next_request := _queued_request
		_queued_request = {}

		if (
			str(next_request.get("signature", ""))
			!= str(_completed_payload.get("signature", ""))
		):
			_start_request(next_request)


func take_completed_payload(signature: String) -> Dictionary:
	poll()

	if str(_completed_payload.get("signature", "")) != signature:
		return {}

	var payload := _completed_payload
	_completed_payload = {}
	return payload


func has_completed_payload(signature: String) -> bool:
	poll()
	return str(_completed_payload.get("signature", "")) == signature


func take_failure(signature: String) -> bool:
	poll()

	if _failed_signature != signature:
		return false

	_failed_signature = ""
	return true


func is_preparing_signature(signature: String) -> bool:
	return (
		_thread != null
		and _thread.is_started()
		and str(_active_request.get("signature", "")) == signature
	)


func cancel_pending_requests() -> void:
	_queued_request.clear()
	_completed_payload.clear()
	_failed_signature = ""
	_accept_active_result = false


func shutdown() -> void:
	_queued_request.clear()
	_completed_payload.clear()
	_failed_signature = ""

	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()

	_thread = null
	_active_request.clear()


func is_valid_request(request: Dictionary) -> bool:
	var required_keys: Array[String] = [
		"signature",
		"region_tiles",
		"region_size",
		"local_tiles_per_world_tile",
		"city_seed",
	]

	for key in required_keys:
		if not request.has(key):
			return false

	return (
		not str(request["signature"]).is_empty()
		and request["region_tiles"] is Array
		and int(request["region_size"]) > 0
		and int(request["local_tiles_per_world_tile"]) > 0
	)


func _start_request(request: Dictionary) -> void:
	_active_request = request.duplicate(true)
	_accept_active_result = true
	_thread = Thread.new()
	var start_error := _thread.start(
		Callable(self, "_build_payload").bind(_active_request)
	)

	if start_error != OK:
		push_error("Could not start asynchronous city preparation.")
		_thread = null
		_active_request.clear()


func _build_payload(request: Dictionary) -> Dictionary:
	var start_usec := Time.get_ticks_usec()
	var generator := CityWorldGenerator.new()
	var city_world := generator.generate_city_world_from_region(
		request["region_tiles"],
		int(request["region_size"]),
		int(request["local_tiles_per_world_tile"]),
		int(request["city_seed"])
	)

	if city_world == null:
		return {
			"valid": false,
			"signature": str(request.get("signature", "")),
		}

	var modes := MapVisuals.get_all_view_modes()
	var mode_images: Dictionary = {}

	for mode in modes:
		mode_images[int(mode)] = Image.create(
			city_world.width,
			city_world.height,
			false,
			Image.FORMAT_RGBA8
		)

	var reusable_colors: Array[Color] = []
	reusable_colors.resize(MapVisuals.VIEW_MODE_COLOR_COUNT)
	var tree_tiles: Array[Vector2i] = []
	var rock_tiles: Array[Vector2i] = []

	for y in range(city_world.height):
		var row: Array = city_world.tiles[y]

		for x in range(city_world.width):
			var tile: Dictionary = row[x]
			MapVisuals.populate_all_tile_colors(tile, reusable_colors, 0.45)

			for mode in modes:
				var mode_int := int(mode)
				var image: Image = mode_images[mode_int]
				image.set_pixel(x, y, reusable_colors[mode_int])

			match WorldData.get_city_surface_feature(tile):
				WorldData.CITY_SURFACE_FEATURE_TREE:
					tree_tiles.append(Vector2i(x, y))

				WorldData.CITY_SURFACE_FEATURE_ROCK:
					rock_tiles.append(Vector2i(x, y))

	return {
		"valid": true,
		"signature": str(request["signature"]),
		"city_world": city_world,
		"city_seed": int(request["city_seed"]),
		"map_images": mode_images,
		"tree_tiles": tree_tiles,
		"rock_tiles": rock_tiles,
		"preparation_duration_usec": Time.get_ticks_usec() - start_usec,
	}
