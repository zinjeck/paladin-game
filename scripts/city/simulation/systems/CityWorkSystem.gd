extends RefCounted
class_name CityWorkSystem

const CityConstructionSystemScript = preload(
	"res://scripts/city/simulation/systems/CityConstructionSystem.gd"
)
const CityResourceMatcherScript = preload(
	"res://scripts/city/simulation/systems/CityResourceMatcher.gd"
)
const CityNavigationSystemScript = preload(
	"res://scripts/city/simulation/systems/CityNavigationSystem.gd"
)

# Parent work orders are selected before their individual jobs. This keeps a
# large drag designation from receiving more scheduler weight merely because
# it contains more tiles than a building or road order.
const ORDER_TYPE_COMMAND_GROUP := "command_group"
const ORDER_TYPE_CONSTRUCTION_SITE := "construction_site"

const ORDER_STATE_ACTIVE := "active"
const ORDER_STATE_BLOCKED := "blocked"
const ORDER_STATE_CANCELLED := "cancelled"

const PRIORITY_LOW: int = 0
const PRIORITY_NORMAL: int = 1
const PRIORITY_HIGH: int = 2
const PRIORITY_URGENT: int = 3

const JOB_KIND_CHOP_TREE := "chop_tree"
const JOB_KIND_COLLECT_ROCK := "collect_rock"
const JOB_KIND_CLEARING_RELOCATION := "clearing_relocation"
const JOB_KIND_CONSTRUCTION_DELIVERY := "construction_delivery"
const JOB_KIND_CONSTRUCTION_LABOR := "construction_labor"

const JOB_STATE_ACTIONABLE := "actionable"
const JOB_STATE_ACTIVE := "active"
const JOB_STATE_BLOCKED := "blocked"

const ORDER_PHASE_COMMANDS := "commands"

const BLOCKED_REASON_NONE := ""
const BLOCKED_REASON_NO_ELIGIBLE_WORKER := "NO_ELIGIBLE_WORKER"
const BLOCKED_REASON_NO_REACHABLE_WORK_POSITION := (
	"NO_REACHABLE_WORK_POSITION"
)
const BLOCKED_REASON_SOURCE_EMPTY := "SOURCE_EMPTY"
const BLOCKED_REASON_SOURCE_FULLY_RESERVED := "SOURCE_FULLY_RESERVED"
const BLOCKED_REASON_NO_LEGAL_SOURCE := "NO_LEGAL_SOURCE"
const BLOCKED_REASON_DESTINATION_FULL := "DESTINATION_FULL"
const BLOCKED_REASON_NO_LEGAL_DESTINATION := "NO_LEGAL_DESTINATION"
const BLOCKED_REASON_WAITING_FOR_CLEARING := "WAITING_FOR_CLEARING"
const BLOCKED_REASON_WAITING_FOR_MATERIALS := "WAITING_FOR_MATERIALS"
const BLOCKED_REASON_WAITING_FOR_SAFE_BOUNDARY := (
	"WAITING_FOR_SAFE_BOUNDARY"
)
const BLOCKED_REASON_MAX_USEFUL_WORKERS := "MAX_USEFUL_WORKERS"
const BLOCKED_REASON_CLAIMED := "CLAIMED"
const BLOCKED_REASON_CANCELLED := "CANCELLED"
const BLOCKED_REASON_INVALIDATED := "INVALIDATED"

# Level-A scheduler constants. Priority ranks are deliberately separated by a
# margin larger than every bounded secondary term. Distance can make nearby
# work attractive, but neglect can eventually overcome the entire locality
# benefit without growing without limit.
const PRIORITY_RANK_SCORE: int = 1_000_000
const NEGLECT_SCORE_PER_MINUTE: int = 1_000
const MAX_NEGLECT_SCORE: int = 120_000
const AGE_SCORE_PER_MINUTE: int = 100
const MAX_AGE_SCORE: int = 20_000
const MAX_LOCALITY_SCORE: int = 40_000
const LOCALITY_PATH_COST_CAP: int = 160_000
const MAX_ACTIVE_WORKER_PENALTY: int = 100_000
const PROGRESS_UNLOCK_SCORE: int = 35_000
const EXACT_COMMAND_PATH_HEURISTIC_WEIGHT: int = 1


static func synchronize_player_work_board() -> void:
	var desired_sources: Dictionary = {}

	for raw_command in WorldData.get_city_player_command_snapshot():
		if not raw_command is Dictionary:
			continue

		var command: Dictionary = raw_command
		var construction_site_id := int(
			command.get("construction_site_id", -1)
		)

		if construction_site_id > 0:
			# Clearing commands are child jobs of their construction site.
			continue

		var group_id := int(command.get("group_id", -1))

		if group_id <= 0:
			continue

		var source_key := _make_command_group_source_key(group_id)
		desired_sources[source_key] = {
			"source_key": source_key,
			"order_type": ORDER_TYPE_COMMAND_GROUP,
			"source_id": group_id,
			"created_world_minute": int(
				command.get("issued_world_minute", 0)
			),
		}

	for raw_site in WorldData.get_city_construction_site_snapshot():
		if not raw_site is Dictionary:
			continue

		var site: Dictionary = raw_site
		var site_id := int(site.get("id", -1))

		if site_id <= 0:
			continue

		var source_key := _make_construction_source_key(site_id)
		desired_sources[source_key] = {
			"source_key": source_key,
			"order_type": ORDER_TYPE_CONSTRUCTION_SITE,
			"source_id": site_id,
			"created_world_minute": int(
				site.get("issued_world_minute", 0)
			),
		}

	var source_keys: Array = desired_sources.keys()
	source_keys.sort()

	for raw_source_key in source_keys:
		var source_key := str(raw_source_key)
		var descriptor = desired_sources.get(source_key, {})

		if descriptor is Dictionary:
			_ensure_order_for_source(descriptor)

	var stale_order_ids: Array[int] = []

	for raw_order_id in WorldData.city_work_orders.keys():
		var order_id := int(raw_order_id)
		var raw_order = WorldData.city_work_orders.get(order_id, {})

		if not raw_order is Dictionary:
			stale_order_ids.append(order_id)
			continue

		var order: Dictionary = raw_order

		if not desired_sources.has(str(order.get("source_key", ""))):
			stale_order_ids.append(order_id)

	stale_order_ids.sort()

	for order_id in stale_order_ids:
		_remove_order_record(order_id)

	var order_ids: Array = WorldData.city_work_orders.keys()
	order_ids.sort()

	for raw_order_id in order_ids:
		_refresh_order_runtime(int(raw_order_id))


static func get_best_player_job_for_citizen(citizen_id: int) -> Dictionary:
	var citizen := WorldData.get_city_citizen_by_id(citizen_id)

	if (
		citizen.is_empty()
		or not bool(citizen.get("alive", false))
		or int(citizen.get("job_object_id", -1)) > 0
	):
		return {}

	var best_selection: Dictionary = {}
	var order_ids: Array = WorldData.city_work_orders.keys()
	order_ids.sort()

	for raw_order_id in order_ids:
		var order_id := int(raw_order_id)
		var order := WorldData.get_city_work_order_by_id(order_id)

		if (
			order.is_empty()
			or str(order.get("state", "")) == ORDER_STATE_CANCELLED
		):
			continue

		var candidate := _get_best_job_candidate_for_order(
			citizen_id,
			order
		)

		if candidate.is_empty():
			continue

		var attention_score := _get_parent_attention_score(
			order,
			candidate
		)
		candidate["work_order_id"] = order_id
		candidate["parent_attention_score"] = attention_score
		candidate["priority_rank"] = int(
			order.get("priority_rank", PRIORITY_NORMAL)
		)

		if _selection_is_better(candidate, best_selection):
			best_selection = candidate

	return best_selection


static func assign_player_job(
	citizen_id: int,
	candidate: Dictionary
) -> bool:
	var order_id := int(candidate.get("work_order_id", -1))
	var order := WorldData.get_city_work_order_by_id(order_id)

	if order.is_empty():
		return false

	var job_id := str(candidate.get("job_id", ""))
	var assigned := false

	if str(candidate.get("player_work_kind", "")) == "command":
		var command_id := int(candidate.get("id", -1))

		if not WorldData.claim_city_player_command(command_id, citizen_id):
			return false

		assigned = WorldData.assign_city_citizen_task(
			citizen_id,
			{
				"kind": WorldData.CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND,
				"source": WorldData.CITY_CITIZEN_TASK_SOURCE_PLAYER,
				"priority": WorldData.CITY_PLAYER_COMMAND_TASK_PRIORITY,
				"target_object_id": command_id,
				"player_locked": false,
				"work_order_id": order_id,
				"job_id": job_id,
			}
		)

		if not assigned:
			WorldData.release_city_player_command_claim(
				command_id,
				citizen_id
			)
	else:
		var prepared_candidate := candidate.duplicate(true)
		var raw_task_request = prepared_candidate.get("task_request", {})

		if raw_task_request is Dictionary:
			var task_request: Dictionary = raw_task_request
			task_request["work_order_id"] = order_id
			task_request["job_id"] = job_id
			prepared_candidate["task_request"] = task_request

		assigned = (
			CityConstructionSystemScript.assign_player_work_candidate(
				citizen_id,
				prepared_candidate
			)
		)

	if assigned:
		_note_order_attention(order_id)

	return assigned


static func set_order_priority(order_id: int, priority_rank: int) -> bool:
	if (
		not WorldData.city_work_orders.has(order_id)
		or priority_rank < PRIORITY_LOW
		or priority_rank > PRIORITY_URGENT
	):
		return false

	var raw_order = WorldData.city_work_orders.get(order_id, {})

	if not raw_order is Dictionary:
		return false

	var order: Dictionary = raw_order.duplicate(true)

	if int(order.get("priority_rank", PRIORITY_NORMAL)) == priority_rank:
		return true

	order["priority_rank"] = priority_rank
	WorldData.city_work_orders[order_id] = order
	WorldData.mark_city_work_orders_changed()
	return true


static func cancel_work_order(order_id: int) -> bool:
	var order := WorldData.get_city_work_order_by_id(order_id)

	if order.is_empty():
		return false

	var cancelled := false

	match str(order.get("order_type", "")):
		ORDER_TYPE_COMMAND_GROUP:
			var command_ids: Array[int] = []
			var group_id := int(order.get("source_id", -1))

			for raw_command in WorldData.get_city_player_command_snapshot():
				if (
					raw_command is Dictionary
					and int(raw_command.get("group_id", -1)) == group_id
					and int(raw_command.get("construction_site_id", -1)) <= 0
				):
					command_ids.append(int(raw_command.get("id", -1)))

			command_ids.sort()

			for command_id in command_ids:
				if WorldData.cancel_city_player_command(command_id):
					cancelled = true

		ORDER_TYPE_CONSTRUCTION_SITE:
			cancelled = (
				CityConstructionSystemScript.cancel_city_construction_site(
					int(order.get("source_id", -1))
				)
			)

	if cancelled:
		_remove_order_record(order_id)

	return cancelled


static func cancel_player_targets_at_tiles(raw_tiles: Array) -> int:
	var site_ids: Dictionary = {}
	var command_ids: Dictionary = {}

	for raw_tile in raw_tiles:
		if not raw_tile is Vector2i:
			continue

		var tile: Vector2i = raw_tile
		var site := WorldData.get_city_construction_site_at_tile(tile)

		if not site.is_empty():
			site_ids[int(site.get("id", -1))] = true

		var command := WorldData.get_city_player_command_at_tile(tile)

		if (
			not command.is_empty()
			and int(command.get("construction_site_id", -1)) <= 0
		):
			command_ids[int(command.get("id", -1))] = true

	var cancelled_count := 0
	var ordered_site_ids: Array = site_ids.keys()
	ordered_site_ids.sort()

	for raw_site_id in ordered_site_ids:
		if CityConstructionSystemScript.cancel_city_construction_site(
			int(raw_site_id)
		):
			cancelled_count += 1

	var ordered_command_ids: Array = command_ids.keys()
	ordered_command_ids.sort()

	for raw_command_id in ordered_command_ids:
		if WorldData.cancel_city_player_command(int(raw_command_id)):
			cancelled_count += 1

	synchronize_player_work_board()
	return cancelled_count


static func get_cancel_preview_tiles(raw_tiles: Array) -> Array[Vector2i]:
	var preview_lookup: Dictionary = {}

	for raw_tile in raw_tiles:
		if not raw_tile is Vector2i:
			continue

		var tile: Vector2i = raw_tile
		var site := WorldData.get_city_construction_site_at_tile(tile)

		if not site.is_empty():
			for raw_footprint_tile in site.get("footprint_tiles", []):
				if raw_footprint_tile is Vector2i:
					preview_lookup[raw_footprint_tile] = true

		if not WorldData.get_city_player_command_at_tile(tile).is_empty():
			preview_lookup[tile] = true

	var preview_tiles: Array[Vector2i] = []

	for raw_tile in preview_lookup.keys():
		if raw_tile is Vector2i:
			preview_tiles.append(raw_tile)

	preview_tiles.sort_custom(_sort_tiles_y_then_x)
	return preview_tiles


static func get_order_debug_snapshot() -> Array:
	synchronize_player_work_board()
	var snapshot := WorldData.get_city_work_order_snapshot()
	var now := SimulationClock.absolute_world_minutes

	for order_index in range(snapshot.size()):
		var raw_order = snapshot[order_index]

		if not raw_order is Dictionary:
			continue

		var order: Dictionary = raw_order
		order["minutes_since_progress"] = maxi(
			now - int(order.get("last_progress_world_minute", now)),
			0
		)
		order["minutes_since_attention"] = maxi(
			now - int(order.get("last_attention_world_minute", now)),
			0
		)
		snapshot[order_index] = order

	return snapshot


static func _ensure_order_for_source(descriptor: Dictionary) -> int:
	var source_key := str(descriptor.get("source_key", ""))

	if source_key.is_empty():
		return -1

	var existing_id := int(
		WorldData.city_work_order_id_by_source_key.get(source_key, -1)
	)

	if existing_id > 0 and WorldData.city_work_orders.has(existing_id):
		return existing_id

	var order_id := WorldData.next_city_work_order_id
	WorldData.next_city_work_order_id += 1
	var created_minute := int(
		descriptor.get(
			"created_world_minute",
			SimulationClock.absolute_world_minutes
		)
	)
	var order := {
		"id": order_id,
		"source_key": source_key,
		"order_type": str(descriptor.get("order_type", "")),
		"source_id": int(descriptor.get("source_id", -1)),
		"creation_sequence": order_id,
		"created_world_minute": created_minute,
		"priority_rank": PRIORITY_NORMAL,
		"state": ORDER_STATE_ACTIVE,
		"phase": "",
		"jobs": [],
		"active_worker_count": 0,
		"active_citizen_ids": [],
		"useful_parallel_capacity": 1,
		"blocked_reason": BLOCKED_REASON_NONE,
		"last_progress_world_minute": created_minute,
		"last_attention_world_minute": created_minute,
		"progress_signature": "",
	}

	WorldData.city_work_orders[order_id] = order
	WorldData.city_work_order_id_by_source_key[source_key] = order_id
	WorldData.mark_city_work_orders_changed()
	return order_id


static func _remove_order_record(order_id: int) -> void:
	var raw_order = WorldData.city_work_orders.get(order_id, {})

	if raw_order is Dictionary:
		WorldData.city_work_order_id_by_source_key.erase(
			str(raw_order.get("source_key", ""))
		)

	WorldData.city_work_orders.erase(order_id)
	WorldData.mark_city_work_orders_changed()


static func _refresh_order_runtime(order_id: int) -> void:
	var raw_order = WorldData.city_work_orders.get(order_id, {})

	if not raw_order is Dictionary:
		return

	var order: Dictionary = raw_order.duplicate(true)
	var jobs := _build_jobs_for_order(order)
	_apply_runtime_worker_actionability(order, jobs)
	_finalize_job_runtime_diagnostics(order, jobs)
	var progress_signature := _build_progress_signature(order)
	var previous_signature := str(order.get("progress_signature", ""))

	if (
		not previous_signature.is_empty()
		and progress_signature != previous_signature
	):
		order["last_progress_world_minute"] = (
			SimulationClock.absolute_world_minutes
		)

	order["progress_signature"] = progress_signature
	order["phase"] = _get_order_phase(order)
	order["jobs"] = jobs
	order["active_citizen_ids"] = _get_active_citizen_ids_for_order(order)
	order["active_worker_count"] = order["active_citizen_ids"].size()
	order["useful_parallel_capacity"] = (
		_get_useful_parallel_capacity(order, jobs)
	)
	order["blocked_reason"] = _get_order_blocked_reason(order, jobs)
	order["state"] = (
		ORDER_STATE_ACTIVE
		if str(order.get("blocked_reason", "")).is_empty()
		else ORDER_STATE_BLOCKED
	)

	if order != raw_order:
		WorldData.city_work_orders[order_id] = order
		WorldData.mark_city_work_orders_changed()


# Source validity says that work is physically meaningful; runtime
# actionability additionally requires at least one presently eligible
# unemployed citizen with an exact route to some job in the parent order.
# Candidate selection remains citizen-specific below. This pass only prevents
# diagnostics from advertising unreachable work as actionable/ACTIVE.
static func _apply_runtime_worker_actionability(
	order: Dictionary,
	jobs: Array
) -> void:
	var has_source_actionable_job := false

	for raw_job in jobs:
		if raw_job is Dictionary and bool(raw_job.get("actionable", false)):
			has_source_actionable_job = true
			break

	if not has_source_actionable_job:
		return

	var eligible_citizen_ids := _get_runtime_eligible_worker_ids()

	if eligible_citizen_ids.is_empty():
		_override_actionable_jobs_with_reason(
			jobs,
			BLOCKED_REASON_NO_ELIGIBLE_WORKER
		)
		return

	var candidate_order := order.duplicate(true)
	candidate_order["jobs"] = jobs

	for citizen_id in eligible_citizen_ids:
		if not _get_best_job_candidate_for_order(
			citizen_id,
			candidate_order
		).is_empty():
			return

	_override_actionable_jobs_with_reason(
		jobs,
		BLOCKED_REASON_NO_REACHABLE_WORK_POSITION
	)


static func _get_runtime_eligible_worker_ids() -> Array[int]:
	var citizen_ids: Array[int] = []

	for raw_citizen in WorldData.city_citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var citizen_id := int(citizen.get("id", -1))

		if (
			citizen_id <= 0
			or not bool(citizen.get("alive", false))
			or int(citizen.get("job_object_id", -1)) > 0
			or WorldData.get_city_citizen_haul_cargo_amount(citizen_id) > 0
			or CitizenNeedsSystem.citizen_should_seek_food(citizen_id)
		):
			continue

		var current_task := WorldData.get_city_citizen_current_task(
			citizen_id
		)

		if (
			str(current_task.get("source", ""))
			== WorldData.CITY_CITIZEN_TASK_SOURCE_PLAYER
			or str(current_task.get("kind", ""))
			== WorldData.CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD
		):
			continue

		citizen_ids.append(citizen_id)

	citizen_ids.sort()
	return citizen_ids


static func _override_actionable_jobs_with_reason(
	jobs: Array,
	blocked_reason: String
) -> void:
	for job_index in range(jobs.size()):
		var raw_job = jobs[job_index]

		if not raw_job is Dictionary:
			continue

		var job: Dictionary = raw_job

		if not bool(job.get("actionable", false)):
			continue

		job["actionable"] = false
		job["blocked_reason"] = blocked_reason
		jobs[job_index] = job


static func _finalize_job_runtime_diagnostics(
	order: Dictionary,
	jobs: Array
) -> void:
	for job_index in range(jobs.size()):
		var raw_job = jobs[job_index]

		if not raw_job is Dictionary:
			continue

		var job: Dictionary = raw_job
		var active_citizen_ids := _get_active_citizen_ids_for_job(
			order,
			job
		)
		job["active_citizen_ids"] = active_citizen_ids

		if (
			int(job.get("claimed_citizen_id", -1)) <= 0
			and not active_citizen_ids.is_empty()
		):
			job["claimed_citizen_id"] = active_citizen_ids[0]

		var job_kind := str(job.get("kind", ""))

		if job_kind in [
			JOB_KIND_CLEARING_RELOCATION,
			JOB_KIND_CONSTRUCTION_DELIVERY,
		]:
			var resource := str(
				job.get("resource_type", WorldData.RESOURCE_NONE)
			)
			var reservation_amounts := _get_job_reservation_amounts(
				active_citizen_ids,
				resource
			)
			job["source_reserved_amount"] = int(
				reservation_amounts.get("source_reserved_amount", 0)
			)
			job["destination_reserved_amount"] = maxi(
				int(job.get("destination_reserved_amount", 0)),
				int(
					reservation_amounts.get(
						"destination_reserved_amount",
						0
					)
				)
			)

		# An active job is progressing even when it cannot accept another
		# worker. Its capacity/claim state is expressed by `actionable` and the
		# active IDs, not by advertising the job itself as blocked.
		if (
			bool(job.get("actionable", false))
			or not active_citizen_ids.is_empty()
		):
			job["blocked_reason"] = BLOCKED_REASON_NONE

		if not active_citizen_ids.is_empty():
			job["state"] = JOB_STATE_ACTIVE
		elif bool(job.get("actionable", false)):
			job["state"] = JOB_STATE_ACTIONABLE
		else:
			job["state"] = JOB_STATE_BLOCKED

		jobs[job_index] = job


static func _get_active_citizen_ids_for_job(
	order: Dictionary,
	job: Dictionary
) -> Array[int]:
	var active_citizen_ids: Array[int] = []
	var order_id := int(order.get("id", -1))
	var source_id := int(order.get("source_id", -1))
	var job_kind := str(job.get("kind", ""))
	var job_id := str(job.get("id", ""))
	var command_id := -1

	if job_id.begins_with("command:"):
		command_id = job_id.trim_prefix("command:").to_int()

	for raw_citizen in WorldData.city_citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var citizen_id := int(citizen.get("id", -1))
		var task = citizen.get("current_task", {})

		if (
			citizen_id <= 0
			or not bool(citizen.get("alive", false))
			or not task is Dictionary
		):
			continue

		var task_kind := str(task.get("kind", ""))
		var matches_job := false

		if command_id > 0:
			matches_job = (
				task_kind
				== WorldData.CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND
				and int(task.get("target_object_id", -1)) == command_id
			)
		elif job_kind == JOB_KIND_CONSTRUCTION_LABOR:
			matches_job = (
				task_kind == WorldData.CITY_CITIZEN_TASK_KIND_CONSTRUCTION
				and int(task.get("target_object_id", -1)) == source_id
			)
		elif (
			job_kind == JOB_KIND_CONSTRUCTION_DELIVERY
			or job_kind == JOB_KIND_CLEARING_RELOCATION
		):
			var haul = citizen.get("current_haul", {})

			if haul is Dictionary:
				var requester = haul.get("requester", {})
				var reason := str(haul.get("reason", ""))
				var resource := str(
					haul.get("resource_type", WorldData.RESOURCE_NONE)
				)
				var requester_matches := (
					requester is Dictionary
					and str(requester.get("kind", ""))
					== WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE
					and int(requester.get("id", -1)) == source_id
				)

				if job_kind == JOB_KIND_CONSTRUCTION_DELIVERY:
					matches_job = (
						task_kind == WorldData.CITY_CITIZEN_TASK_KIND_HAUL
						and requester_matches
						and reason
						== WorldData.CITY_CITIZEN_HAUL_REASON_CONSTRUCTION_DELIVERY
						and resource
						== str(job.get("resource_type", ""))
					)
				else:
					var source = haul.get("source", {})
					var pile_id := job_id.trim_prefix(
						"relocate_pile:"
					).to_int()
					matches_job = (
						task_kind == WorldData.CITY_CITIZEN_TASK_KIND_HAUL
						and requester_matches
						and reason
						== WorldData.CITY_CITIZEN_HAUL_REASON_GROUND_PILE_CLEANUP
						and source is Dictionary
						and str(source.get("kind", ""))
						== WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE
						and int(source.get("id", -1)) == pile_id
					)

		if (
			matches_job
			and (
				int(task.get("work_order_id", -1)) in [-1, order_id]
			)
		):
			active_citizen_ids.append(citizen_id)

	active_citizen_ids.sort()
	return active_citizen_ids


static func _get_job_reservation_amounts(
	active_citizen_ids: Array[int],
	resource: String
) -> Dictionary:
	var source_reserved_amount := 0
	var destination_reserved_amount := 0

	for citizen_id in active_citizen_ids:
		var reservation_id := (
			WorldData.get_city_haul_reservation_id_for_citizen(citizen_id)
		)
		var reservation := WorldData.get_city_haul_reservation(
			reservation_id
		)

		if reservation.is_empty():
			continue

		if str(reservation.get("resource_type", "")) == resource:
			source_reserved_amount += maxi(
				int(reservation.get("source_reserved_amount", 0)),
				0
			)

		destination_reserved_amount += (
			WorldData.get_city_haul_reservation_destination_resource_amount(
				reservation_id,
				resource
			)
		)

	return {
		"source_reserved_amount": source_reserved_amount,
		"destination_reserved_amount": destination_reserved_amount,
	}


static func _get_order_phase(order: Dictionary) -> String:
	if str(order.get("order_type", "")) == ORDER_TYPE_COMMAND_GROUP:
		return ORDER_PHASE_COMMANDS

	if str(order.get("order_type", "")) == ORDER_TYPE_CONSTRUCTION_SITE:
		return str(
			WorldData.get_city_construction_site_by_id(
				int(order.get("source_id", -1))
			).get("phase", "")
		)

	return ""


static func _build_jobs_for_order(order: Dictionary) -> Array:
	var jobs: Array = []
	var order_type := str(order.get("order_type", ""))
	var source_id := int(order.get("source_id", -1))

	if order_type == ORDER_TYPE_COMMAND_GROUP:
		_append_command_jobs(jobs, source_id, -1)
		return jobs

	if order_type != ORDER_TYPE_CONSTRUCTION_SITE:
		return jobs

	var site := WorldData.get_city_construction_site_by_id(source_id)

	if site.is_empty():
		return jobs

	var phase := str(site.get("phase", ""))

	if phase == WorldData.CITY_CONSTRUCTION_PHASE_CLEARING:
		_append_command_jobs(jobs, -1, source_id)
		var footprint_tiles: Array = site.get("footprint_tiles", [])

		for raw_pile in WorldData.get_city_ground_pile_snapshot():
			if not raw_pile is Dictionary:
				continue

			var pile: Dictionary = raw_pile
			var pile_tile = pile.get(
				"tile_position",
				WorldData.INVALID_CITY_TILE_POSITION
			)

			if (
				not pile_tile is Vector2i
				or not footprint_tiles.has(pile_tile)
				or WorldData.city_ground_pile_is_construction_reserved(pile)
			):
				continue

			var resource := str(
				pile.get("resource_type", WorldData.RESOURCE_NONE)
			)
			var pile_id := int(pile.get("id", -1))
			var requested_amount := maxi(
				WorldData.get_city_haul_endpoint_resource_amount(
					WorldData.make_city_ground_pile_haul_endpoint(pile_id),
					resource
				),
				0
			)
			var source_available := (
				WorldData.get_city_haul_endpoint_unreserved_resource_amount(
					WorldData.make_city_ground_pile_haul_endpoint(pile_id),
					resource
				)
			)
			var destination_diagnostics := (
				_get_relocation_destination_diagnostics(
					source_id,
					pile_id,
					resource
				)
			)
			var destination_available := bool(
				destination_diagnostics.get("available", false)
			)
			var actionable := (
				source_available > 0 and destination_available
			)
			var blocked_reason := str(
				destination_diagnostics.get(
					"blocked_reason",
					BLOCKED_REASON_NO_LEGAL_DESTINATION
				)
			)

			if source_available <= 0:
				blocked_reason = BLOCKED_REASON_SOURCE_FULLY_RESERVED
			elif destination_available:
				blocked_reason = BLOCKED_REASON_NONE

			jobs.append({
				"id": "relocate_pile:" + str(pile_id),
				"kind": JOB_KIND_CLEARING_RELOCATION,
				"resource_type": resource,
				"source_endpoint": (
					WorldData.make_city_ground_pile_haul_endpoint(pile_id)
				),
				"source_available_amount": source_available,
				"requested_amount": requested_amount,
				"destination_available_amount": int(
					destination_diagnostics.get("available_amount", 0)
				),
				"actionable": actionable,
				"blocked_reason": blocked_reason,
				"claimed_citizen_id": -1,
			})
	elif phase == WorldData.CITY_CONSTRUCTION_PHASE_GATHERING:
		for resource in WorldData.get_city_resource_types():
			var remaining_amount := (
				WorldData.get_city_construction_site_remaining_resource_amount(
					source_id,
					resource
				)
			)

			if remaining_amount <= 0:
				continue

			var destination_reserved_amount := (
				WorldData.get_city_construction_site_destination_reserved_resource_amount(
					source_id,
					resource
				)
			)
			var requested_amount := (
				WorldData.get_city_construction_site_unreserved_resource_space(
					source_id,
					resource
				)
			)
			var source_diagnostics := _get_construction_source_diagnostics(
				resource,
				maxi(requested_amount, 1)
			)
			var actionable := (
				requested_amount > 0
				and bool(source_diagnostics.get("available", false))
			)
			var blocked_reason := str(
				source_diagnostics.get(
					"blocked_reason",
					BLOCKED_REASON_NO_LEGAL_SOURCE
				)
			)

			if requested_amount <= 0 and destination_reserved_amount > 0:
				blocked_reason = BLOCKED_REASON_WAITING_FOR_MATERIALS
			elif actionable:
				blocked_reason = BLOCKED_REASON_NONE

			jobs.append({
				"id": "deliver:" + resource,
				"kind": JOB_KIND_CONSTRUCTION_DELIVERY,
				"resource_type": resource,
				"remaining_amount": remaining_amount,
				"requested_amount": requested_amount,
				"source_available_amount": int(
					source_diagnostics.get("available_amount", 0)
				),
				"destination_reserved_amount": (
					destination_reserved_amount
				),
				"actionable": actionable,
				"blocked_reason": blocked_reason,
				"claimed_citizen_id": -1,
			})
	elif phase == WorldData.CITY_CONSTRUCTION_PHASE_LABOR:
		var maximum_workers := maxi(int(site.get("maximum_workers", 1)), 1)
		var active_workers := _count_construction_workers(source_id)
		var remaining_labor := maxi(
			int(site.get("required_labor_minutes", 0))
			- int(site.get("completed_labor_minutes", 0)),
			0
		)
		jobs.append({
			"id": "labor:" + str(source_id),
			"kind": JOB_KIND_CONSTRUCTION_LABOR,
			"remaining_labor_minutes": remaining_labor,
			"actionable": (
				remaining_labor > 0 and active_workers < maximum_workers
			),
			"blocked_reason": (
				BLOCKED_REASON_MAX_USEFUL_WORKERS
				if active_workers >= maximum_workers
				else (
					BLOCKED_REASON_INVALIDATED
					if remaining_labor <= 0
					else BLOCKED_REASON_NONE
				)
			),
			"claimed_citizen_id": -1,
		})

	return jobs


static func _append_command_jobs(
	jobs: Array,
	group_id: int,
	construction_site_id: int
) -> void:
	for raw_command in WorldData.get_city_player_command_snapshot():
		if not raw_command is Dictionary:
			continue

		var command: Dictionary = raw_command

		if (
			group_id > 0
			and (
				int(command.get("group_id", -1)) != group_id
				or int(command.get("construction_site_id", -1)) > 0
			)
		):
			continue

		if (
			construction_site_id > 0
			and int(command.get("construction_site_id", -1))
			!= construction_site_id
		):
			continue

		var command_id := int(command.get("id", -1))
		var claimed_citizen_id := int(
			command.get("claimed_citizen_id", -1)
		)
		var target_valid := WorldData.is_city_player_command_target_valid(
			command
		)
		var assignable := WorldData.city_player_command_is_assignable(command)
		jobs.append({
			"id": "command:" + str(command_id),
			"kind": str(command.get("type", "")),
			"actionable": assignable,
			"claimed_citizen_id": claimed_citizen_id,
			"blocked_reason": (
				BLOCKED_REASON_INVALIDATED
				if not target_valid
				else (
					BLOCKED_REASON_CLAIMED
					if claimed_citizen_id > 0
					else (
						BLOCKED_REASON_WAITING_FOR_SAFE_BOUNDARY
						if not assignable
						else BLOCKED_REASON_NONE
					)
				)
			),
		})


static func _build_progress_signature(order: Dictionary) -> String:
	var order_type := str(order.get("order_type", ""))
	var source_id := int(order.get("source_id", -1))

	if order_type == ORDER_TYPE_COMMAND_GROUP:
		var command_ids: Array[int] = []

		for raw_command in WorldData.get_city_player_command_snapshot():
			if (
				raw_command is Dictionary
				and int(raw_command.get("group_id", -1)) == source_id
				and int(raw_command.get("construction_site_id", -1)) <= 0
			):
				command_ids.append(int(raw_command.get("id", -1)))

		command_ids.sort()
		return "commands:" + ",".join(command_ids)

	if order_type != ORDER_TYPE_CONSTRUCTION_SITE:
		return "invalid"

	var site := WorldData.get_city_construction_site_by_id(source_id)

	if site.is_empty():
		return "missing"

	var parts: Array[String] = [
		"phase=" + str(site.get("phase", "")),
		"labor=" + str(int(site.get("completed_labor_minutes", 0))),
	]

	for resource in WorldData.get_city_resource_types():
		parts.append(
			resource
			+ "="
			+ str(
				WorldData.get_city_construction_site_reserved_resource_amount(
					source_id,
					resource
				)
			)
		)

	var obstruction_count := 0
	var footprint_tiles: Array = site.get("footprint_tiles", [])
	var city_world: WorldData = WorldData.official_city_world

	if city_world != null:
		for raw_tile in footprint_tiles:
			if not raw_tile is Vector2i:
				continue

			var tile: Vector2i = raw_tile

			if WorldData.is_city_surface_feature(
				WorldData.get_city_surface_feature(
					city_world.get_tile(tile.x, tile.y)
				)
			):
				obstruction_count += 1

	var ordinary_pile_amount := 0

	for raw_pile in WorldData.get_city_ground_pile_snapshot():
		if (
			raw_pile is Dictionary
			and footprint_tiles.has(
				raw_pile.get(
					"tile_position",
					WorldData.INVALID_CITY_TILE_POSITION
				)
			)
			and not WorldData.city_ground_pile_is_construction_reserved(
				raw_pile
			)
		):
			ordinary_pile_amount += maxi(int(raw_pile.get("amount", 0)), 0)

	parts.append("obstructions=" + str(obstruction_count))
	parts.append("ordinary_piles=" + str(ordinary_pile_amount))
	return "|".join(parts)


static func _get_best_job_candidate_for_order(
	citizen_id: int,
	order: Dictionary
) -> Dictionary:
	var order_type := str(order.get("order_type", ""))
	var source_id := int(order.get("source_id", -1))
	var best_candidate: Dictionary = {}

	if order_type == ORDER_TYPE_COMMAND_GROUP:
		return _get_best_command_candidate(
			citizen_id,
			source_id,
			-1
		)

	if order_type != ORDER_TYPE_CONSTRUCTION_SITE:
		return best_candidate

	var command_candidate := _get_best_command_candidate(
		citizen_id,
		-1,
		source_id
	)

	if not command_candidate.is_empty():
		best_candidate = command_candidate

	var construction_candidate := (
		CityConstructionSystemScript
		.get_best_assignable_player_work_for_citizen_and_site(
			citizen_id,
			source_id
		)
	)

	if not construction_candidate.is_empty():
		var kind := str(
			construction_candidate.get("player_work_kind", "")
		)
		var tie_break_key := str(
			construction_candidate.get("tie_break_key", "")
		)
		construction_candidate["job_id"] = kind + ":" + tie_break_key

		if _job_candidate_is_better(
			construction_candidate,
			best_candidate
		):
			best_candidate = construction_candidate

	if not best_candidate.is_empty():
		best_candidate["progress_unlocking"] = (
			_candidate_unlocks_progress(order, best_candidate)
		)

	return best_candidate


static func _get_best_command_candidate(
	citizen_id: int,
	group_id: int,
	construction_site_id: int
) -> Dictionary:
	var citizen := WorldData.get_city_citizen_by_id(citizen_id)
	var raw_citizen_tile = citizen.get(
		"city_tile_position",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if citizen.is_empty() or not raw_citizen_tile is Vector2i:
		return {}

	var citizen_tile: Vector2i = raw_citizen_tile
	var command_by_id: Dictionary = {}
	var command_ids_by_work_tile: Dictionary = {}
	var work_tile_lookup: Dictionary = {}

	for raw_command in WorldData.get_city_player_command_snapshot():
		if not raw_command is Dictionary:
			continue

		var command: Dictionary = raw_command

		if (
			group_id > 0
			and (
				int(command.get("group_id", -1)) != group_id
				or int(command.get("construction_site_id", -1)) > 0
			)
		):
			continue

		if (
			construction_site_id > 0
			and int(command.get("construction_site_id", -1))
			!= construction_site_id
		):
			continue

		if not WorldData.city_player_command_is_assignable(command):
			continue

		var command_id := int(command.get("id", -1))
		var work_tiles := WorldData.get_city_player_command_work_tiles(
			command,
			citizen_id
		)

		if command_id <= 0 or work_tiles.is_empty():
			continue

		command_by_id[command_id] = command

		for work_tile in work_tiles:
			work_tile_lookup[work_tile] = true
			var command_ids: Array = command_ids_by_work_tile.get(
				work_tile,
				[]
			)

			if not command_ids.has(command_id):
				command_ids.append(command_id)
				command_ids.sort()
				command_ids_by_work_tile[work_tile] = command_ids

	if work_tile_lookup.is_empty():
		return {}

	var work_tiles: Array = work_tile_lookup.keys()
	work_tiles.sort_custom(_sort_tiles_y_then_x)
	var path_result := CityNavigationSystemScript.find_path_to_any_city_tile(
		WorldData.official_city_world,
		citizen_tile,
		work_tiles,
		_get_city_wide_path_expansion_limit(WorldData.official_city_world),
		citizen_id,
		EXACT_COMMAND_PATH_HEURISTIC_WEIGHT
	)

	if not bool(path_result.get("success", false)):
		return {}

	var raw_destination_tile = path_result.get(
		"destination_tile",
		WorldData.INVALID_CITY_TILE_POSITION
	)

	if not raw_destination_tile is Vector2i:
		return {}

	var matching_command_ids: Array = command_ids_by_work_tile.get(
		raw_destination_tile,
		[]
	)

	if matching_command_ids.is_empty():
		return {}

	matching_command_ids.sort()
	var selected_command_id := int(matching_command_ids[0])
	var raw_selected_command = command_by_id.get(selected_command_id, {})

	if not raw_selected_command is Dictionary:
		return {}

	var candidate: Dictionary = raw_selected_command.duplicate(true)
	candidate["player_work_kind"] = "command"
	candidate["job_id"] = "command:" + str(selected_command_id)
	candidate["estimated_path_cost"] = maxi(
		int(path_result.get("path_cost", 0)),
		0
	)
	candidate["target_tile"] = raw_destination_tile
	candidate["tie_break_key"] = str(selected_command_id)
	return candidate


static func _get_parent_attention_score(
	order: Dictionary,
	candidate: Dictionary
) -> int:
	var now := SimulationClock.absolute_world_minutes
	var created_minute := int(order.get("created_world_minute", now))
	var last_progress_minute := int(
		order.get("last_progress_world_minute", created_minute)
	)
	var neglect_minutes := maxi(now - last_progress_minute, 0)
	var age_minutes := maxi(now - created_minute, 0)
	var neglect_score := mini(
		neglect_minutes * NEGLECT_SCORE_PER_MINUTE,
		MAX_NEGLECT_SCORE
	)
	var age_score := mini(
		age_minutes * AGE_SCORE_PER_MINUTE,
		MAX_AGE_SCORE
	)
	var path_cost := clampi(
		int(candidate.get("estimated_path_cost", LOCALITY_PATH_COST_CAP)),
		0,
		LOCALITY_PATH_COST_CAP
	)
	var locality_score := (
		MAX_LOCALITY_SCORE
		* (LOCALITY_PATH_COST_CAP - path_cost)
		/ LOCALITY_PATH_COST_CAP
	)
	var active_workers := _count_active_workers_for_order(order)
	var useful_capacity := maxi(
		int(order.get("useful_parallel_capacity", 1)),
		1
	)
	var active_worker_penalty := mini(
		MAX_ACTIVE_WORKER_PENALTY,
		MAX_ACTIVE_WORKER_PENALTY * active_workers / useful_capacity
	)
	var unlock_score := (
		PROGRESS_UNLOCK_SCORE
		if bool(candidate.get("progress_unlocking", false))
		else 0
	)

	return (
		int(order.get("priority_rank", PRIORITY_NORMAL))
		* PRIORITY_RANK_SCORE
		+ neglect_score
		+ age_score
		+ locality_score
		+ unlock_score
		- active_worker_penalty
	)


static func _selection_is_better(
	candidate: Dictionary,
	current_best: Dictionary
) -> bool:
	if candidate.is_empty():
		return false

	if current_best.is_empty():
		return true

	var candidate_score := int(
		candidate.get("parent_attention_score", 0)
	)
	var best_score := int(current_best.get("parent_attention_score", 0))

	if candidate_score != best_score:
		return candidate_score > best_score

	var candidate_order_id := int(candidate.get("work_order_id", -1))
	var best_order_id := int(current_best.get("work_order_id", -1))

	if candidate_order_id != best_order_id:
		return candidate_order_id < best_order_id

	return str(candidate.get("job_id", "")) < str(
		current_best.get("job_id", "")
	)


static func _job_candidate_is_better(
	candidate: Dictionary,
	current_best: Dictionary
) -> bool:
	if candidate.is_empty():
		return false

	if current_best.is_empty():
		return true

	var candidate_cost := maxi(
		int(candidate.get("estimated_path_cost", 0)),
		0
	)
	var best_cost := maxi(
		int(current_best.get("estimated_path_cost", 0)),
		0
	)

	if candidate_cost != best_cost:
		return candidate_cost < best_cost

	return str(candidate.get("job_id", "")) < str(
		current_best.get("job_id", "")
	)


static func _candidate_unlocks_progress(
	order: Dictionary,
	candidate: Dictionary
) -> bool:
	var actionable_jobs := 0

	for raw_job in order.get("jobs", []):
		if raw_job is Dictionary and bool(raw_job.get("actionable", false)):
			actionable_jobs += 1

	if actionable_jobs == 1:
		return true

	if (
		str(candidate.get("player_work_kind", ""))
		== CityConstructionSystemScript.PLAYER_WORK_KIND_LABOR
	):
		var site := WorldData.get_city_construction_site_by_id(
			int(order.get("source_id", -1))
		)
		return (
			not site.is_empty()
			and int(site.get("required_labor_minutes", 0))
			- int(site.get("completed_labor_minutes", 0))
			<= 6
		)

	return false


static func _get_active_citizen_ids_for_order(
	order: Dictionary
) -> Array[int]:
	var active_citizen_lookup: Dictionary = {}
	var order_type := str(order.get("order_type", ""))
	var source_id := int(order.get("source_id", -1))
	var order_id := int(order.get("id", -1))

	for raw_citizen in WorldData.city_citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var citizen_id := int(citizen.get("id", -1))
		var task = citizen.get("current_task", {})

		if (
			citizen_id <= 0
			or not bool(citizen.get("alive", false))
			or not task is Dictionary
		):
			continue

		if int(task.get("work_order_id", -1)) == order_id:
			active_citizen_lookup[citizen_id] = true
			continue

		var task_kind := str(task.get("kind", ""))

		if task_kind == WorldData.CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND:
			var command := WorldData.get_city_player_command_by_id(
				int(task.get("target_object_id", -1))
			)

			if command.is_empty():
				continue

			if (
				order_type == ORDER_TYPE_COMMAND_GROUP
				and int(command.get("group_id", -1)) == source_id
				and int(command.get("construction_site_id", -1)) <= 0
			) or (
				order_type == ORDER_TYPE_CONSTRUCTION_SITE
				and int(command.get("construction_site_id", -1)) == source_id
			):
				active_citizen_lookup[citizen_id] = true
		elif (
			order_type == ORDER_TYPE_CONSTRUCTION_SITE
			and task_kind == WorldData.CITY_CITIZEN_TASK_KIND_CONSTRUCTION
			and int(task.get("target_object_id", -1)) == source_id
		):
			active_citizen_lookup[citizen_id] = true
		elif (
			order_type == ORDER_TYPE_CONSTRUCTION_SITE
			and task_kind == WorldData.CITY_CITIZEN_TASK_KIND_HAUL
		):
			var haul = citizen.get("current_haul", {})

			if haul is Dictionary:
				var requester = haul.get("requester", {})

				if (
					requester is Dictionary
					and str(requester.get("kind", ""))
					== WorldData.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CONSTRUCTION_SITE
					and int(requester.get("id", -1)) == source_id
				):
					active_citizen_lookup[citizen_id] = true

	var active_citizen_ids: Array[int] = []

	for raw_citizen_id in active_citizen_lookup.keys():
		active_citizen_ids.append(int(raw_citizen_id))

	active_citizen_ids.sort()
	return active_citizen_ids


static func _count_active_workers_for_order(order: Dictionary) -> int:
	return _get_active_citizen_ids_for_order(order).size()


static func _count_construction_workers(site_id: int) -> int:
	var count := 0

	for raw_citizen in WorldData.city_citizens:
		if not raw_citizen is Dictionary:
			continue

		var task = raw_citizen.get("current_task", {})

		if (
			task is Dictionary
			and str(task.get("kind", ""))
			== WorldData.CITY_CITIZEN_TASK_KIND_CONSTRUCTION
			and int(task.get("target_object_id", -1)) == site_id
		):
			count += 1

	return count


static func _get_useful_parallel_capacity(
	order: Dictionary,
	jobs: Array
) -> int:
	var actionable_job_count := 0

	for raw_job in jobs:
		if raw_job is Dictionary and bool(raw_job.get("actionable", false)):
			actionable_job_count += 1

	if str(order.get("order_type", "")) == ORDER_TYPE_CONSTRUCTION_SITE:
		var site := WorldData.get_city_construction_site_by_id(
			int(order.get("source_id", -1))
		)

		if not site.is_empty():
			return maxi(
				mini(
					maxi(actionable_job_count, 1),
					maxi(int(site.get("maximum_workers", 1)), 1)
				),
				1
			)

	return maxi(actionable_job_count, 1)


static func _get_order_blocked_reason(
	order: Dictionary,
	jobs: Array
) -> String:
	for raw_job in jobs:
		if (
			raw_job is Dictionary
			and (
				bool(raw_job.get("actionable", false))
				or str(raw_job.get("state", "")) == JOB_STATE_ACTIVE
			)
		):
			return BLOCKED_REASON_NONE

	for raw_job in jobs:
		if not raw_job is Dictionary:
			continue

		var blocked_reason := str(raw_job.get("blocked_reason", ""))

		if not blocked_reason.is_empty():
			return blocked_reason

	if jobs.is_empty():
		match _get_order_phase(order):
			WorldData.CITY_CONSTRUCTION_PHASE_CLEARING:
				return BLOCKED_REASON_WAITING_FOR_CLEARING

			WorldData.CITY_CONSTRUCTION_PHASE_GATHERING:
				return BLOCKED_REASON_WAITING_FOR_MATERIALS

	return BLOCKED_REASON_INVALIDATED


static func _get_relocation_destination_diagnostics(
	site_id: int,
	ground_pile_id: int,
	resource: String
) -> Dictionary:
	var compatible_public_destination_exists := false
	var public_available_amount := 0

	for raw_object in WorldData.city_objects:
		if not raw_object is Dictionary:
			continue

		var city_object: Dictionary = raw_object

		if (
			not WorldData.city_object_container_is_publicly_usable(city_object)
			or not WorldData.city_object_can_accept_haul_resource(
				city_object,
				resource,
				WorldData.CONTAINER_HAUL_PURPOSE_PUBLIC_STORAGE,
				false
			)
		):
			continue

		compatible_public_destination_exists = true
		var endpoint := WorldData.make_city_citizen_haul_endpoint(
			int(city_object.get("id", -1))
		)

		if WorldData.city_haul_endpoint_can_accept_resource(
			endpoint,
			resource,
			WorldData.CONTAINER_HAUL_PURPOSE_PUBLIC_STORAGE,
			true
		):
			public_available_amount += (
				WorldData.get_city_haul_endpoint_unreserved_destination_space(
					endpoint
				)
			)

	var ground_available := (
		CityConstructionSystemScript.can_relocate_ground_pile_outside_site(
			site_id,
			ground_pile_id
		)
	)

	if public_available_amount > 0 or ground_available:
		return {
			"available": true,
			"available_amount": maxi(
				public_available_amount,
				1 if ground_available else 0
			),
			"blocked_reason": BLOCKED_REASON_NONE,
		}

	return {
		"available": false,
		"available_amount": 0,
		"blocked_reason": (
			BLOCKED_REASON_DESTINATION_FULL
			if compatible_public_destination_exists
			else BLOCKED_REASON_NO_LEGAL_DESTINATION
		),
	}


static func _get_construction_source_diagnostics(
	resource: String,
	requested_amount: int
) -> Dictionary:
	var supply_candidates := (
		CityResourceMatcherScript.get_resource_supply_candidates(
		CityResourceMatcherScript.PURPOSE_CONSTRUCTION_SUPPLY,
		resource,
		requested_amount
		)
	)
	var available_amount := 0

	for supply_candidate in supply_candidates:
		available_amount += maxi(
			int(supply_candidate.get("available_amount", 0)),
			0
		)

	available_amount = mini(available_amount, requested_amount)

	if available_amount > 0:
		return {
			"available": true,
			"available_amount": available_amount,
			"blocked_reason": BLOCKED_REASON_NONE,
		}

	var legal_physical_source_exists := false
	var legal_unreserved_amount := 0

	for raw_object in WorldData.city_objects:
		if not raw_object is Dictionary:
			continue

		var city_object: Dictionary = raw_object

		if not WorldData.city_object_container_is_publicly_usable(city_object):
			continue

		var endpoint := WorldData.make_city_citizen_haul_endpoint(
			int(city_object.get("id", -1))
		)

		if not WorldData.city_haul_endpoint_can_provide_resource(
			endpoint,
			resource,
			WorldData.CONTAINER_HAUL_PURPOSE_CONSTRUCTION,
			false
		):
			continue

		legal_physical_source_exists = true
		legal_unreserved_amount += (
			WorldData.get_city_haul_endpoint_unreserved_resource_amount(
				endpoint,
				resource
			)
		)

	for raw_pile in WorldData.get_city_ground_pile_snapshot():
		if (
			not raw_pile is Dictionary
			or WorldData.city_ground_pile_is_construction_reserved(raw_pile)
		):
			continue

		var endpoint := WorldData.make_city_ground_pile_haul_endpoint(
			int(raw_pile.get("id", -1))
		)

		if not WorldData.city_haul_endpoint_can_provide_resource(
			endpoint,
			resource,
			WorldData.CONTAINER_HAUL_PURPOSE_CONSTRUCTION,
			false
		):
			continue

		legal_physical_source_exists = true
		legal_unreserved_amount += (
			WorldData.get_city_haul_endpoint_unreserved_resource_amount(
				endpoint,
				resource
			)
		)

	var blocked_reason := BLOCKED_REASON_NO_LEGAL_SOURCE

	if legal_physical_source_exists and legal_unreserved_amount <= 0:
		blocked_reason = BLOCKED_REASON_SOURCE_FULLY_RESERVED
	elif WorldData.get_total_physical_city_resource_amount(resource) <= 0:
		blocked_reason = BLOCKED_REASON_SOURCE_EMPTY

	return {
		"available": false,
		"available_amount": 0,
		"blocked_reason": blocked_reason,
	}


static func _note_order_attention(order_id: int) -> void:
	var raw_order = WorldData.city_work_orders.get(order_id, {})

	if not raw_order is Dictionary:
		return

	var order: Dictionary = raw_order
	order["last_attention_world_minute"] = (
		SimulationClock.absolute_world_minutes
	)
	WorldData.city_work_orders[order_id] = order
	WorldData.mark_city_work_orders_changed()


static func _make_command_group_source_key(group_id: int) -> String:
	return "command_group:" + str(group_id)


static func _make_construction_source_key(site_id: int) -> String:
	return "construction_site:" + str(site_id)


static func _get_city_wide_path_expansion_limit(
	city_world: WorldData
) -> int:
	if city_world == null:
		return 1

	return maxi(city_world.width * city_world.height, 1)


static func _sort_tiles_y_then_x(a: Vector2i, b: Vector2i) -> bool:
	if a.y != b.y:
		return a.y < b.y

	return a.x < b.x
