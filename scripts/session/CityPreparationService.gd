extends RefCounted
class_name CityPreparationService

# Builds the immutable, CPU-heavy portion of first city entry away from the
# main thread. City terrain, natural-feature indexes, and the complete six-mode
# RGBA8 atlas are produced in the same tile traversal. The main thread receives
# one atomic payload and performs only the final GPU resource publication.

const STATUS_RUNNING: String = "RUNNING"
const STATUS_SUCCEEDED: String = "SUCCEEDED"
const STATUS_FAILED: String = "FAILED"
const STATUS_CANCELLED: String = "CANCELLED"
const STATUS_SUPERSEDED: String = "SUPERSEDED"

var _thread
var _active_record: Dictionary = {}
var _queued_record: Dictionary = {}
var _next_generation: int = 1
var _latest_generation_by_signature: Dictionary = {}
var _status_by_generation: Dictionary = {}
var _terminal_results_by_generation: Dictionary = {}


func request_preparation(request: Dictionary) -> int:
	if not is_valid_request(request):
		return 0

	# Reap a finished worker without promoting queued work. The incoming request
	# must get a chance to join or supersede that queue first.
	poll(false)
	var signature := str(request.get("signature", ""))
	var joinable_generation := _get_joinable_generation(signature)

	if joinable_generation > 0:
		return joinable_generation

	var generation := _next_generation
	_next_generation += 1
	var record := {
		"generation": generation,
		"signature": signature,
		"request": request.duplicate(true),
	}
	_latest_generation_by_signature[signature] = generation
	_status_by_generation[generation] = STATUS_RUNNING
	if not _queued_record.is_empty():
		_publish_terminal(
			_queued_record,
			STATUS_SUPERSEDED,
			{},
			"replaced_by_newer_queued_request"
		)
		_queued_record = {}

	if _thread != null and _thread.is_started():
		_queued_record = record
		return generation

	_start_record(record)
	return generation


func poll(should_start_queued_record: bool = true) -> void:
	if _thread == null:
		if should_start_queued_record:
			_start_queued_record_if_possible()
		return
	if not _thread.is_started():
		var unstarted_record := _active_record
		_thread = null
		_active_record = {}

		if (
			not unstarted_record.is_empty()
			and get_request_status(
				int(unstarted_record.get("generation", 0)),
				false
			) == STATUS_RUNNING
		):
			_publish_terminal(
				unstarted_record,
				STATUS_FAILED,
				{},
				"thread_stopped_without_result"
			)

		if should_start_queued_record:
			_start_queued_record_if_possible()
		return
	if _thread.is_alive():
		return

	var finished_record := _active_record
	var raw_result = _thread.wait_to_finish()
	_thread = null
	_active_record = {}

	if (
		not finished_record.is_empty()
		and get_request_status(
			int(finished_record.get("generation", 0)),
			false
		) == STATUS_RUNNING
	):
		_publish_worker_result(finished_record, raw_result)

	if should_start_queued_record:
		_start_queued_record_if_possible()


func take_terminal_result(generation: int) -> Dictionary:
	poll()

	if not _terminal_results_by_generation.has(generation):
		return {}

	var terminal: Dictionary = _terminal_results_by_generation[generation]
	_terminal_results_by_generation.erase(generation)
	return terminal


func has_terminal_result(generation: int) -> bool:
	poll()
	return _terminal_results_by_generation.has(generation)


func discard_terminal_result(generation: int) -> void:
	_terminal_results_by_generation.erase(generation)


func get_request_status(
	generation: int,
	should_poll: bool = true
) -> String:
	if should_poll:
		poll()

	return str(_status_by_generation.get(generation, ""))


func get_latest_generation(signature: String) -> int:
	poll()
	return int(_latest_generation_by_signature.get(signature, 0))


func supersede_request(generation: int) -> bool:
	if get_request_status(generation, false) != STATUS_RUNNING:
		return false

	if int(_active_record.get("generation", 0)) == generation:
		_publish_terminal(
			_active_record,
			STATUS_SUPERSEDED,
			{},
			"superseded_by_newer_request"
		)
		return true

	if int(_queued_record.get("generation", 0)) == generation:
		_publish_terminal(
			_queued_record,
			STATUS_SUPERSEDED,
			{},
			"superseded_by_newer_request"
		)
		_queued_record.clear()
		return true

	return false


# Compatibility helpers for callers that still consume preparation by
# signature. They only inspect the latest generation, so an older failure can
# never be mistaken for the outcome of a same-signature retry.
func take_completed_payload(signature: String) -> Dictionary:
	poll()
	var generation := int(
		_latest_generation_by_signature.get(signature, 0)
	)

	if generation <= 0:
		return {}
	if get_request_status(generation, false) != STATUS_SUCCEEDED:
		return {}
	if not _terminal_results_by_generation.has(generation):
		return {}

	var terminal := take_terminal_result(generation)
	var payload = terminal.get("payload", {})

	if payload is Dictionary:
		return payload

	return {}


func has_completed_payload(signature: String) -> bool:
	poll()
	var generation := int(
		_latest_generation_by_signature.get(signature, 0)
	)
	return (
		generation > 0
		and get_request_status(generation, false) == STATUS_SUCCEEDED
		and _terminal_results_by_generation.has(generation)
	)


func take_failure(signature: String) -> bool:
	poll()
	var generation := int(
		_latest_generation_by_signature.get(signature, 0)
	)

	if generation <= 0:
		return false
	if get_request_status(generation, false) != STATUS_FAILED:
		return false
	if not _terminal_results_by_generation.has(generation):
		return false

	take_terminal_result(generation)
	return true


func is_preparing_signature(signature: String) -> bool:
	poll()
	var generation := int(
		_latest_generation_by_signature.get(signature, 0)
	)
	return (
		generation > 0
		and get_request_status(generation, false) == STATUS_RUNNING
	)


func cancel_pending_requests() -> void:
	# Preserve the old cancellation contract of discarding already cached
	# success/failure outcomes, then publish exact cancellation outcomes for work
	# still pending. Earlier cancellation/supersession terminals remain observable.
	for raw_generation in _terminal_results_by_generation.keys():
		var terminal: Dictionary = (
			_terminal_results_by_generation[raw_generation]
		)
		var terminal_status := str(terminal.get("status", ""))

		if (
			terminal_status == STATUS_SUCCEEDED
			or terminal_status == STATUS_FAILED
		):
			_terminal_results_by_generation.erase(raw_generation)

	if (
		not _active_record.is_empty()
		and get_request_status(
			int(_active_record.get("generation", 0)),
			false
		) == STATUS_RUNNING
	):
		_publish_terminal(
			_active_record,
			STATUS_CANCELLED,
			{},
			"cancelled_by_session"
		)

	if (
		not _queued_record.is_empty()
		and get_request_status(
			int(_queued_record.get("generation", 0)),
			false
		) == STATUS_RUNNING
	):
		_publish_terminal(
			_queued_record,
			STATUS_CANCELLED,
			{},
			"cancelled_by_session"
		)

	_queued_record.clear()


func shutdown() -> void:
	if (
		not _active_record.is_empty()
		and get_request_status(
			int(_active_record.get("generation", 0)),
			false
		) == STATUS_RUNNING
	):
		_publish_terminal(
			_active_record,
			STATUS_CANCELLED,
			{},
			"cancelled_by_service_shutdown"
		)

	if (
		not _queued_record.is_empty()
		and get_request_status(
			int(_queued_record.get("generation", 0)),
			false
		) == STATUS_RUNNING
	):
		_publish_terminal(
			_queued_record,
			STATUS_CANCELLED,
			{},
			"cancelled_by_service_shutdown"
		)

	_queued_record = {}

	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()

	_thread = null
	_active_record = {}


func prepare_synchronously(request: Dictionary) -> Dictionary:
	if not is_valid_request(request):
		return {}

	var synchronous_request := request.duplicate(true)
	synchronous_request["preparation_generation"] = 0
	var payload := _build_payload(synchronous_request)
	if (
		not bool(payload.get("valid", false))
		or not _is_valid_success_payload(payload)
	):
		return {}

	return payload


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
		and typeof(request["region_size"]) == TYPE_INT
		and int(request["region_size"]) > 0
		and typeof(request["local_tiles_per_world_tile"]) == TYPE_INT
		and int(request["local_tiles_per_world_tile"]) > 0
		and typeof(request["city_seed"]) == TYPE_INT
	)


func _get_joinable_generation(signature: String) -> int:
	var generation := int(
		_latest_generation_by_signature.get(signature, 0)
	)

	if generation <= 0:
		return 0

	var status := get_request_status(generation, false)

	if status == STATUS_RUNNING:
		return generation
	if (
		(status == STATUS_SUCCEEDED or status == STATUS_FAILED)
		and _terminal_results_by_generation.has(generation)
	):
		return generation

	return 0


func _start_record(record: Dictionary) -> void:
	_active_record = record
	var generation := int(record.get("generation", 0))
	var worker_request: Dictionary = record.get("request", {}).duplicate(true)
	worker_request["preparation_generation"] = generation
	_thread = _create_thread()

	if _thread == null:
		_publish_terminal(
			record,
			STATUS_FAILED,
			{},
			"thread_factory_failed"
		)
		_active_record = {}
		_start_queued_record_if_possible()
		return

	var start_error: int = int(
		_thread.start(
			Callable(self, "_build_payload").bind(worker_request),
			Thread.PRIORITY_LOW
		)
	)

	if start_error == OK:
		return

	_report_thread_start_failure(start_error)
	_thread = null
	_active_record = {}
	_publish_terminal(
		record,
		STATUS_FAILED,
		{},
		"thread_start_failed:" + str(start_error)
	)
	_start_queued_record_if_possible()


func _create_thread():
	return Thread.new()


func _report_thread_start_failure(_start_error: int) -> void:
	push_error("Could not start asynchronous city preparation.")


func _start_queued_record_if_possible() -> void:
	if _thread != null:
		return
	if _queued_record.is_empty():
		return

	var next_record := _queued_record
	_queued_record = {}

	if (
		get_request_status(
			int(next_record.get("generation", 0)),
			false
		) == STATUS_RUNNING
	):
		_start_record(next_record)


func _publish_worker_result(
	record: Dictionary,
	raw_result
) -> void:
	if not raw_result is Dictionary:
		_publish_terminal(
			record,
			STATUS_FAILED,
			{},
			"invalid_worker_result_type"
		)
		return

	var result: Dictionary = raw_result
	var generation := int(record.get("generation", 0))
	var signature := str(record.get("signature", ""))

	if (
		typeof(result.get("valid")) != TYPE_BOOL
		or typeof(result.get("preparation_generation")) != TYPE_INT
		or int(result.get("preparation_generation")) != generation
		or str(result.get("signature", "")) != signature
	):
		_publish_terminal(
			record,
			STATUS_FAILED,
			{},
			"invalid_worker_result_identity"
		)
		return

	if not bool(result.get("valid", false)):
		_publish_terminal(
			record,
			STATUS_FAILED,
			{},
			"worker_reported_failure"
		)
		return

	if not _is_valid_success_payload(result):
		_publish_terminal(
			record,
			STATUS_FAILED,
			{},
			"invalid_worker_success_payload"
		)
		return

	_publish_terminal(record, STATUS_SUCCEEDED, result)


func _is_valid_success_payload(result: Dictionary) -> bool:
	var prepared_world = result.get("city_world")
	var map_atlas = result.get("map_atlas")

	if not prepared_world is WorldData:
		return false
	if typeof(result.get("city_seed")) != TYPE_INT:
		return false
	if not map_atlas is Dictionary or map_atlas.is_empty():
		return false
	var rgba8 = map_atlas.get("rgba8")
	var raw_modes = map_atlas.get("modes")
	var expected_modes := MapVisuals.get_all_view_modes()

	if not rgba8 is PackedByteArray:
		return false
	if (
		typeof(map_atlas.get("width")) != TYPE_INT
		or typeof(map_atlas.get("height")) != TYPE_INT
		or int(map_atlas.get("width")) != prepared_world.width
		or int(map_atlas.get("height")) != prepared_world.height
		or prepared_world.width <= 0
		or prepared_world.height <= 0
		or not raw_modes is Array
		or raw_modes.size() != expected_modes.size()
		or typeof(map_atlas.get("tile_data_version")) != TYPE_INT
		or int(map_atlas.get("tile_data_version", -1))
		!= prepared_world.tile_data_version
		or typeof(map_atlas.get("visual_version")) != TYPE_INT
		or int(map_atlas.get("visual_version", -1))
		!= MapVisuals.MAP_VISUAL_CACHE_VERSION
	):
		return false

	for mode_index in range(expected_modes.size()):
		if (
			typeof(raw_modes[mode_index]) != TYPE_INT
			or int(raw_modes[mode_index]) != expected_modes[mode_index]
		):
			return false

	if (
		rgba8.size()
		!= prepared_world.width
		* prepared_world.height
		* expected_modes.size()
		* 4
	):
		return false
	if (
		typeof(result.get("feature_tile_data_version")) != TYPE_INT
		or int(result.get("feature_tile_data_version", -1))
		!= prepared_world.tile_data_version
		or typeof(result.get("city_surface_feature_change_version"))
		!= TYPE_INT
		or int(result.get("city_surface_feature_change_version", -1))
		!= prepared_world.city_surface_feature_change_version
	):
		return false
	var tree_tiles = result.get("tree_tiles")
	var rock_tiles = result.get("rock_tiles")

	if not tree_tiles is Array or not rock_tiles is Array:
		return false
	if not _are_valid_prepared_feature_tiles(
		prepared_world,
		tree_tiles,
		WorldData.CITY_SURFACE_FEATURE_TREE
	):
		return false
	if not _are_valid_prepared_feature_tiles(
		prepared_world,
		rock_tiles,
		WorldData.CITY_SURFACE_FEATURE_ROCK
	):
		return false
	if typeof(result.get("preparation_duration_usec")) != TYPE_INT:
		return false

	return true


func _are_valid_prepared_feature_tiles(
	prepared_world: WorldData,
	raw_tiles: Array,
	expected_feature: String
) -> bool:
	var seen_tiles: Dictionary = {}

	for raw_tile in raw_tiles:
		if not raw_tile is Vector2i:
			return false

		var tile_position: Vector2i = raw_tile

		if (
			not prepared_world.is_in_bounds(tile_position.x, tile_position.y)
			or seen_tiles.has(tile_position)
			or WorldData.get_city_surface_feature(
				prepared_world.get_tile_for_internal_read(
					tile_position.x,
					tile_position.y
				)
			) != expected_feature
		):
			return false

		seen_tiles[tile_position] = true

	return true


func _publish_terminal(
	record: Dictionary,
	status: String,
	payload: Dictionary = {},
	reason: String = ""
) -> void:
	var generation := int(record.get("generation", 0))

	if generation <= 0:
		return
	if get_request_status(generation, false) != STATUS_RUNNING:
		return

	_status_by_generation[generation] = status
	var terminal := {
		"generation": generation,
		"signature": str(record.get("signature", "")),
		"status": status,
		"reason": reason,
	}

	if status == STATUS_SUCCEEDED:
		terminal["payload"] = payload

	_terminal_results_by_generation[generation] = terminal


func _build_payload(request: Dictionary) -> Dictionary:
	var start_usec := Time.get_ticks_usec()
	var generator := CityWorldGenerator.new()
	var city_world := generator.generate_city_world_from_region(
		request["region_tiles"],
		int(request["region_size"]),
		int(request["local_tiles_per_world_tile"]),
		int(request["city_seed"]),
		true,
		0.45
	)

	if (
		city_world == null
		or generator.generated_map_atlas_data.is_empty()
	):
		return {
			"valid": false,
			"signature": str(request.get("signature", "")),
			"preparation_generation": int(
				request.get("preparation_generation", 0)
			),
		}

	return {
		"valid": true,
		"signature": str(request["signature"]),
		"preparation_generation": int(
			request.get("preparation_generation", 0)
		),
		"city_world": city_world,
		"city_seed": int(request["city_seed"]),
		"map_atlas": generator.generated_map_atlas_data,
		"tree_tiles": city_world.prepared_city_tree_tiles.duplicate(),
		"rock_tiles": city_world.prepared_city_rock_tiles.duplicate(),
		"feature_tile_data_version": (
			city_world.prepared_city_feature_tile_data_version
		),
		"city_surface_feature_change_version": (
			city_world.city_surface_feature_change_version
		),
		"preparation_duration_usec": Time.get_ticks_usec() - start_usec,
	}
