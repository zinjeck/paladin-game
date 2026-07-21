extends RefCounted
class_name CityCitizens

# This script owns the intrinsic definition of one citizen record.
# WorldData continues to own the population collection, stable-ID indexes,
# city placement, housing, employment, and other city-level relationships.

const CITY_CITIZEN_SEX_MALE := "male"
const CITY_CITIZEN_SEX_FEMALE := "female"

const DEFAULT_CITIZEN_CARRY_CAPACITY := 10
const DEFAULT_CITIZEN_HUNGER := 100
const DEFAULT_CITIZEN_HAPPINESS := 70
const CITY_CITIZEN_STATE_IDLE := "idle"
const INVALID_CITY_TILE_POSITION := Vector2i(-1, -1)
# A task records why a citizen is acting. It remains separate from movement,
# which records only how the citizen travels between tiles.
const CITY_CITIZEN_TASK_KIND_NONE := "none"
const CITY_CITIZEN_TASK_KIND_WORK := "work"
const CITY_CITIZEN_TASK_KIND_HAUL := "haul"
const CITY_CITIZEN_TASK_KIND_RETURN_HOME := "return_home"

const CITY_CITIZEN_TASK_SOURCE_NONE := "none"
const CITY_CITIZEN_TASK_SOURCE_PLAYER := "player"
const CITY_CITIZEN_TASK_SOURCE_SCHEDULE := "schedule"

const CITY_CITIZEN_TASK_PHASE_NONE := "none"
const CITY_CITIZEN_TASK_PHASE_PENDING := "pending"
const CITY_CITIZEN_TASK_PHASE_TRAVELING := "traveling"
const CITY_CITIZEN_TASK_PHASE_PERFORMING := "performing"
const CITY_CITIZEN_TASK_PHASE_BLOCKED := "blocked"

const CITY_CITIZEN_TASK_PRIORITY_NONE := 0
const INVALID_CITY_CITIZEN_TASK_START_WORLD_MINUTE := -1
const INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE := -1

# Haul execution state is separate from personal inventory and from the
# high-level current_task record. Endpoints and requesters are references so
# future container kinds can be added without changing the haul schema.
const CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE := "none"
const CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER := (
	"city_object_container"
)
const CITY_CITIZEN_HAUL_REASON_NONE := "none"
const CITY_CITIZEN_HAUL_REASON_WORKPLACE_OUTPUT_BEFORE_HOME := (
	"workplace_output_before_home"
)
const CITY_CITIZEN_HAUL_REASON_OUTSTANDING_CARGO := (
	"outstanding_cargo"
)
const CITY_CITIZEN_HAUL_PHASE_NONE := "none"
const CITY_CITIZEN_HAUL_PHASE_PENDING_SOURCE := "pending_source"
const CITY_CITIZEN_HAUL_PHASE_TRAVELING_TO_SOURCE := (
	"traveling_to_source"
)
const CITY_CITIZEN_HAUL_PHASE_PICKING_UP := "picking_up"
const CITY_CITIZEN_HAUL_PHASE_PENDING_DESTINATION := (
	"pending_destination"
)
const CITY_CITIZEN_HAUL_PHASE_TRAVELING_TO_DESTINATION := (
	"traveling_to_destination"
)
const CITY_CITIZEN_HAUL_PHASE_DEPOSITING := "depositing"
const CITY_CITIZEN_HAUL_PHASE_RETARGETING := "retargeting"
const CITY_CITIZEN_HAUL_PHASE_BLOCKED := "blocked"
# High-level citizen state and movement state intentionally remain separate.
# A citizen may later be working, hauling, or eating while its movement state
# independently describes whether it is walking between authoritative tiles.
const CITY_CITIZEN_MOVEMENT_STATE_IDLE := "idle"
const CITY_CITIZEN_MOVEMENT_STATE_MOVING := "moving"
const CITY_CITIZEN_MOVEMENT_STATE_BLOCKED := "blocked"

const CITY_CITIZEN_MOVEMENT_FAILURE_NONE := "none"
const CITY_CITIZEN_MOVEMENT_FAILURE_INVALID_PATH := "invalid_path"
const CITY_CITIZEN_MOVEMENT_FAILURE_NEXT_TILE_BLOCKED := (
	"next_tile_blocked"
)
const CITY_CITIZEN_MOVEMENT_FAILURE_REPATH_FAILED := (
	"repath_failed"
)

const CITY_CITIZEN_MOVEMENT_PROGRESS_PER_TILE := 10_000
const DEFAULT_CITIZEN_MOVEMENT_SPEED_PER_MINUTE := 4_167
const MAX_CITIZEN_MOVEMENT_REPATH_ATTEMPTS := 3

static var city_citizen_male_name_pool: Array[String] = [
	"Arlen",
	"Tovan",
	"Calen",
	"Ronan",
	"Darian",
	"Kael",
	"Bren",
	"Orin",
	"Levon",
	"Theron",
	"Jarek",
	"Corin",
	"Malric",
	"Edrin",
	"Tomas",
	"Varon",
	"Lucan",
	"Alric",
	"Fenric",
	"Soren",
	"Aldren",
	"Beran",
	"Cedran",
	"Doran",
	"Evren",
	"Garric",
	"Hadren",
	"Ivarn",
	"Joren",
	"Kellan",
	"Merek",
	"Nolan",
	"Odran",
	"Perric",
	"Roder",
	"Stellan",
	"Torren",
	"Ulren",
	"Wystan",
	"Yorick",
]

static var city_citizen_female_name_pool: Array[String] = [
	"Mira",
	"Elia",
	"Sera",
	"Nira",
	"Liora",
	"Kaela",
	"Maris",
	"Elara",
	"Vessa",
	"Talia",
	"Rina",
	"Anya",
	"Selene",
	"Maera",
	"Isolde",
	"Lyra",
	"Vela",
	"Seris",
	"Amara",
	"Coralie",
	"Aveline",
	"Briala",
	"Ceryn",
	"Delara",
	"Eirwen",
	"Fiora",
	"Giselle",
	"Halia",
	"Ilara",
	"Jessamine",
	"Kerra",
	"Lenora",
	"Mirelle",
	"Nerissa",
	"Odelle",
	"Petra",
	"Roselyn",
	"Sabine",
	"Thalia",
	"Ysara",
]
static var city_citizen_unassigned_name_pool: Array[String] = []

static func get_city_citizen_task_kind_types() -> Array[String]:
	return [
		CITY_CITIZEN_TASK_KIND_NONE,
		CITY_CITIZEN_TASK_KIND_WORK,
		CITY_CITIZEN_TASK_KIND_HAUL,
		CITY_CITIZEN_TASK_KIND_RETURN_HOME
	]


static func is_valid_city_citizen_task_kind(
	task_kind: String
) -> bool:
	return get_city_citizen_task_kind_types().has(task_kind)


static func get_city_citizen_task_source_types() -> Array[String]:
	return [
		CITY_CITIZEN_TASK_SOURCE_NONE,
		CITY_CITIZEN_TASK_SOURCE_PLAYER,
		CITY_CITIZEN_TASK_SOURCE_SCHEDULE
	]


static func is_valid_city_citizen_task_source(
	task_source: String
) -> bool:
	return get_city_citizen_task_source_types().has(task_source)


static func get_city_citizen_task_phase_types() -> Array[String]:
	return [
		CITY_CITIZEN_TASK_PHASE_NONE,
		CITY_CITIZEN_TASK_PHASE_PENDING,
		CITY_CITIZEN_TASK_PHASE_TRAVELING,
		CITY_CITIZEN_TASK_PHASE_PERFORMING,
		CITY_CITIZEN_TASK_PHASE_BLOCKED
	]


static func is_valid_city_citizen_task_phase(
	task_phase: String
) -> bool:
	return get_city_citizen_task_phase_types().has(task_phase)


static func make_city_citizen_task(
	values: Dictionary = {}
) -> Dictionary:
	return {
		"kind": str(
			values.get(
				"kind",
				CITY_CITIZEN_TASK_KIND_NONE
			)
		),
		"source": str(
			values.get(
				"source",
				CITY_CITIZEN_TASK_SOURCE_NONE
			)
		),
		"phase": str(
			values.get(
				"phase",
				CITY_CITIZEN_TASK_PHASE_NONE
			)
		),
		"priority": int(
			values.get(
				"priority",
				CITY_CITIZEN_TASK_PRIORITY_NONE
			)
		),
		"target_object_id": int(
			values.get("target_object_id", -1)
		),
		"start_world_minute": int(
			values.get(
				"start_world_minute",
				INVALID_CITY_CITIZEN_TASK_START_WORLD_MINUTE
			)
		),
		"target_tile": values.get(
			"target_tile",
			INVALID_CITY_TILE_POSITION
		),
		"previous_target_tile": values.get(
			"previous_target_tile",
			INVALID_CITY_TILE_POSITION
		),
		"next_action_world_minute": int(
			values.get(
				"next_action_world_minute",
				INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
			)
		),
		"relocation_count": maxi(
			int(values.get("relocation_count", 0)),
			0
		),
		"player_locked": bool(
			values.get("player_locked", false)
		)
	}


static func has_complete_city_citizen_task_state(
	citizen: Dictionary
) -> bool:
	if not citizen.has("current_task"):
		return false

	var raw_current_task = citizen.get("current_task")

	if not raw_current_task is Dictionary:
		return false

	var current_task: Dictionary = raw_current_task

	return (
		current_task.has("kind")
		and current_task.has("source")
		and current_task.has("phase")
		and current_task.has("priority")
		and current_task.has("target_object_id")
		and current_task.has("start_world_minute")
		and current_task.has("target_tile")
		and current_task.has("previous_target_tile")
		and current_task.has("next_action_world_minute")
		and current_task.has("relocation_count")
		and current_task.has("player_locked")
	)


static func reset_city_citizen_task_state(
	citizen: Dictionary
) -> void:
	citizen["current_task"] = make_city_citizen_task()


static func get_city_citizen_haul_phase_types() -> Array[String]:
	return [
		CITY_CITIZEN_HAUL_PHASE_NONE,
		CITY_CITIZEN_HAUL_PHASE_PENDING_SOURCE,
		CITY_CITIZEN_HAUL_PHASE_TRAVELING_TO_SOURCE,
		CITY_CITIZEN_HAUL_PHASE_PICKING_UP,
		CITY_CITIZEN_HAUL_PHASE_PENDING_DESTINATION,
		CITY_CITIZEN_HAUL_PHASE_TRAVELING_TO_DESTINATION,
		CITY_CITIZEN_HAUL_PHASE_DEPOSITING,
		CITY_CITIZEN_HAUL_PHASE_RETARGETING,
		CITY_CITIZEN_HAUL_PHASE_BLOCKED,
	]


static func is_valid_city_citizen_haul_phase(
	haul_phase: String
) -> bool:
	return get_city_citizen_haul_phase_types().has(
		haul_phase
	)


static func make_city_citizen_haul_endpoint(
	values: Dictionary = {}
) -> Dictionary:
	return {
		"kind": str(
			values.get(
				"kind",
				CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
			)
		),
		"id": int(values.get("id", -1)),
	}


static func is_valid_city_citizen_haul_endpoint(
	endpoint: Dictionary,
	allow_none: bool = false
) -> bool:
	var endpoint_kind := str(
		endpoint.get(
			"kind",
			CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
		)
	)
	var endpoint_id := int(endpoint.get("id", -1))

	if endpoint_kind == CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE:
		return allow_none and endpoint_id == -1

	return (
		endpoint_kind
		== CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER
		and endpoint_id > 0
	)


static func make_city_citizen_haul_cargo(
	values: Dictionary = {}
) -> Dictionary:
	var amount := maxi(
		int(values.get("amount", 0)),
		0
	)
	var resource_type := str(
		values.get("resource_type", "none")
	)

	if amount <= 0:
		resource_type = "none"

	return {
		"resource_type": resource_type,
		"amount": amount,
	}


static func make_city_citizen_haul(
	values: Dictionary = {}
) -> Dictionary:
	var raw_source = values.get("source", {})
	var raw_destination = values.get("destination", {})
	var raw_requester = values.get("requester", {})
	var source_values: Dictionary = {}
	var destination_values: Dictionary = {}
	var requester_values: Dictionary = {}

	if raw_source is Dictionary:
		source_values = raw_source

	if raw_destination is Dictionary:
		destination_values = raw_destination

	if raw_requester is Dictionary:
		requester_values = raw_requester

	return {
		"source": make_city_citizen_haul_endpoint(
			source_values
		),
		"destination": make_city_citizen_haul_endpoint(
			destination_values
		),
		"resource_type": str(
			values.get("resource_type", "none")
		),
		"requested_amount": maxi(
			int(values.get("requested_amount", 0)),
			0
		),
		"reason": str(
			values.get(
				"reason",
				CITY_CITIZEN_HAUL_REASON_NONE
			)
		),
		"requester": make_city_citizen_haul_endpoint(
			requester_values
		),
		"source_access_purpose": str(
			values.get("source_access_purpose", "none")
		),
		"destination_access_purpose": str(
			values.get("destination_access_purpose", "none")
		),
		"phase": str(
			values.get(
				"phase",
				CITY_CITIZEN_HAUL_PHASE_NONE
			)
		),
		"source_tile": values.get(
			"source_tile",
			INVALID_CITY_TILE_POSITION
		),
		"destination_tile": values.get(
			"destination_tile",
			INVALID_CITY_TILE_POSITION
		),
	}


static func has_complete_city_citizen_haul_state(
	citizen: Dictionary
) -> bool:
	if not citizen.has("current_haul"):
		return false

	if not citizen.has("haul_cargo"):
		return false

	var raw_current_haul = citizen.get("current_haul")
	var raw_haul_cargo = citizen.get("haul_cargo")

	if not raw_current_haul is Dictionary:
		return false

	if not raw_haul_cargo is Dictionary:
		return false

	var current_haul: Dictionary = raw_current_haul
	var haul_cargo: Dictionary = raw_haul_cargo
	var required_haul_keys := [
		"source",
		"destination",
		"resource_type",
		"requested_amount",
		"reason",
		"requester",
		"source_access_purpose",
		"destination_access_purpose",
		"phase",
		"source_tile",
		"destination_tile",
	]

	for key in required_haul_keys:
		if not current_haul.has(key):
			return false

	return (
		haul_cargo.has("resource_type")
		and haul_cargo.has("amount")
	)


static func reset_city_citizen_haul_state(
	citizen: Dictionary,
	preserve_cargo: bool = false
) -> void:
	var cargo := make_city_citizen_haul_cargo()

	if preserve_cargo:
		var raw_cargo = citizen.get("haul_cargo", {})

		if raw_cargo is Dictionary:
			cargo = make_city_citizen_haul_cargo(raw_cargo)

	citizen["current_haul"] = make_city_citizen_haul()
	citizen["haul_cargo"] = cargo

static func get_city_citizen_movement_state_types() -> Array[String]:
	return [
		CITY_CITIZEN_MOVEMENT_STATE_IDLE,
		CITY_CITIZEN_MOVEMENT_STATE_MOVING,
		CITY_CITIZEN_MOVEMENT_STATE_BLOCKED
	]

static func is_valid_city_citizen_movement_state(
	movement_state: String
) -> bool:
	return get_city_citizen_movement_state_types().has(
		movement_state
	)


static func get_city_citizen_movement_failure_types() -> Array[String]:
	return [
		CITY_CITIZEN_MOVEMENT_FAILURE_NONE,
		CITY_CITIZEN_MOVEMENT_FAILURE_INVALID_PATH,
		CITY_CITIZEN_MOVEMENT_FAILURE_NEXT_TILE_BLOCKED,
		CITY_CITIZEN_MOVEMENT_FAILURE_REPATH_FAILED
	]


static func is_valid_city_citizen_movement_failure(
	failure_reason: String
) -> bool:
	return get_city_citizen_movement_failure_types().has(
		failure_reason
	)


static func has_complete_city_citizen_movement_state(
	citizen: Dictionary
) -> bool:
	return (
		citizen.has("movement_state")
		and citizen.has("movement_path")
		and citizen.has("movement_path_index")
		and citizen.has("movement_progress_basis_points")
		and citizen.has("movement_destination_tile")
		and citizen.has("movement_speed_basis_points_per_minute")
		and citizen.has("movement_repath_attempt_count")
		and citizen.has("movement_failure_reason")
	)


static func reset_city_citizen_movement_state(
	citizen: Dictionary,
	preserve_movement_speed: bool = false
) -> void:
	var movement_speed := (
		DEFAULT_CITIZEN_MOVEMENT_SPEED_PER_MINUTE
	)

	if preserve_movement_speed:
		var stored_movement_speed := int(
			citizen.get(
				"movement_speed_basis_points_per_minute",
				movement_speed
			)
		)

		if stored_movement_speed > 0:
			movement_speed = stored_movement_speed

	citizen["movement_state"] = (
		CITY_CITIZEN_MOVEMENT_STATE_IDLE
	)
	citizen["movement_path"] = []
	citizen["movement_path_index"] = 0
	citizen["movement_progress_basis_points"] = 0
	citizen["movement_destination_tile"] = (
		INVALID_CITY_TILE_POSITION
	)
	citizen["movement_speed_basis_points_per_minute"] = (
		movement_speed
	)
	citizen["movement_repath_attempt_count"] = 0
	citizen["movement_failure_reason"] = (
		CITY_CITIZEN_MOVEMENT_FAILURE_NONE
	)

static func normalize_city_citizen_sex(
	citizen_sex: String
) -> String:
	return citizen_sex.strip_edges().to_lower()


static func is_valid_city_citizen_sex(
	citizen_sex: String
) -> bool:
	var normalized_sex := normalize_city_citizen_sex(
		citizen_sex
	)

	return (
		normalized_sex == CITY_CITIZEN_SEX_MALE
		or normalized_sex == CITY_CITIZEN_SEX_FEMALE
	)


static func get_city_citizen_sex_types() -> Array[String]:
	return [
		CITY_CITIZEN_SEX_MALE,
		CITY_CITIZEN_SEX_FEMALE
	]


static func get_city_citizen_sex_display_name(
	citizen_sex: String
) -> String:
	match normalize_city_citizen_sex(citizen_sex):
		CITY_CITIZEN_SEX_MALE:
			return "Male"

		CITY_CITIZEN_SEX_FEMALE:
			return "Female"

	return "Unknown"


static func get_city_citizen_name_pool_for_sex(
	citizen_sex: String
) -> Array[String]:
	match normalize_city_citizen_sex(citizen_sex):
		CITY_CITIZEN_SEX_MALE:
			return city_citizen_male_name_pool.duplicate()

		CITY_CITIZEN_SEX_FEMALE:
			return city_citizen_female_name_pool.duplicate()

	return []


static func city_citizen_name_pools_are_ready() -> bool:
	if city_citizen_male_name_pool.is_empty():
		return false

	if city_citizen_female_name_pool.is_empty():
		return false

	if not city_citizen_unassigned_name_pool.is_empty():
		return false

	var used_name_keys: Dictionary = {}

	for raw_name in city_citizen_male_name_pool:
		var name := str(raw_name)
		var clean_name := name.strip_edges()
		var name_key := clean_name.to_lower()

		if clean_name.is_empty():
			return false

		if clean_name != name:
			return false

		if used_name_keys.has(name_key):
			return false

		used_name_keys[name_key] = CITY_CITIZEN_SEX_MALE

	for raw_name in city_citizen_female_name_pool:
		var name := str(raw_name)
		var clean_name := name.strip_edges()
		var name_key := clean_name.to_lower()

		if clean_name.is_empty():
			return false

		if clean_name != name:
			return false

		if used_name_keys.has(name_key):
			return false

		used_name_keys[name_key] = CITY_CITIZEN_SEX_FEMALE

	return true


static func get_used_city_citizen_name_counts(
	existing_citizens: Array
) -> Dictionary:
	var used_name_counts := {}

	for raw_citizen in existing_citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var citizen_name := str(
			citizen.get("name", "")
		).strip_edges()

		if citizen_name.is_empty():
			continue

		used_name_counts[citizen_name] = int(
			used_name_counts.get(citizen_name, 0)
		) + 1

	return used_name_counts


static func make_random_city_citizen_first_name(
	citizen_sex: String,
	citizen_number: int,
	name_seed: int,
	existing_citizens: Array
) -> String:
	var normalized_sex := normalize_city_citizen_sex(
		citizen_sex
	)

	if not is_valid_city_citizen_sex(normalized_sex):
		return ""

	var source_name_pool := get_city_citizen_name_pool_for_sex(
		normalized_sex
	)

	if source_name_pool.is_empty():
		return ""

	var used_name_counts := get_used_city_citizen_name_counts(
		existing_citizens
	)
	var available_names: Array[String] = []

	for raw_name in source_name_pool:
		var candidate_name := str(raw_name).strip_edges()

		if candidate_name.is_empty():
			continue

		if used_name_counts.has(candidate_name):
			continue

		available_names.append(candidate_name)

	var candidate_pool: Array[String] = available_names

	# Names may repeat after every unique name in the appropriate
	# pool has been used. Family names can solve this later.
	if candidate_pool.is_empty():
		candidate_pool = source_name_pool

	if candidate_pool.is_empty():
		return ""

	var resolved_citizen_number := citizen_number

	if resolved_citizen_number <= 0:
		resolved_citizen_number = existing_citizens.size() + 1

	var sex_seed_offset := 0

	if normalized_sex == CITY_CITIZEN_SEX_MALE:
		sex_seed_offset = 104_729
	else:
		sex_seed_offset = 130_363

	var rng := RandomNumberGenerator.new()
	var population_number := existing_citizens.size()

	rng.seed = int(
		abs(
			name_seed * 1_000_003
			+ resolved_citizen_number * 9_176
			+ population_number * 6_113
			+ sex_seed_offset
			+ 1_337
		)
	)

	var random_index := rng.randi_range(
		0,
		candidate_pool.size() - 1
	)

	return str(candidate_pool[random_index]).strip_edges()


static func make_sparse_city_citizen_inventory(
	raw_inventory
) -> Dictionary:
	var inventory: Dictionary = {}

	if not raw_inventory is Dictionary:
		return inventory

	for raw_resource in raw_inventory.keys():
		var raw_amount = raw_inventory[raw_resource]

		if typeof(raw_amount) != TYPE_INT:
			continue

		var amount: int = raw_amount

		if amount <= 0:
			continue

		inventory[str(raw_resource)] = amount

	return inventory


static func make_city_citizen(
	values: Dictionary
) -> Dictionary:
	var citizen_id := int(values.get("id", -1))

	if citizen_id <= 0:
		push_error(
			"Cannot create city citizen without a valid positive ID."
		)
		return {}

	var normalized_sex := normalize_city_citizen_sex(
		str(values.get("sex", ""))
	)

	if not is_valid_city_citizen_sex(normalized_sex):
		push_error(
			"Cannot create city citizen with invalid sex '"
			+ str(values.get("sex", ""))
			+ "'."
		)
		return {}

	var existing_citizens: Array = []
	var raw_existing_citizens = values.get(
		"existing_citizens",
		[]
	)

	if raw_existing_citizens is Array:
		existing_citizens = raw_existing_citizens

	var citizen_name := str(
		values.get("display_name", "")
	).strip_edges()

	if citizen_name.is_empty():
		citizen_name = make_random_city_citizen_first_name(
			normalized_sex,
			citizen_id,
			int(values.get("name_seed", 12345)),
			existing_citizens
		)

	if citizen_name.is_empty():
		push_error(
			"Cannot create "
			+ normalized_sex
			+ " citizen because its name pool "
			+ "contains no usable names."
		)
		return {}

	var allowed_name_pool := get_city_citizen_name_pool_for_sex(
		normalized_sex
	)

	if not allowed_name_pool.has(citizen_name):
		push_error(
			"Cannot assign name '"
			+ citizen_name
			+ "' to "
			+ normalized_sex
			+ " citizen because it is absent "
			+ "from that sex's name pool."
		)
		return {}

	var city_tile_position := INVALID_CITY_TILE_POSITION
	var raw_city_tile_position = values.get(
		"city_tile_position",
		INVALID_CITY_TILE_POSITION
	)

	if raw_city_tile_position is Vector2i:
		city_tile_position = raw_city_tile_position

	var inventory := make_sparse_city_citizen_inventory(
		values.get("inventory", {})
	)

	var citizen := {
		"id": citizen_id,
		"name": citizen_name,
		"sex": normalized_sex,
		"alive": true,
		"hunger": DEFAULT_CITIZEN_HUNGER,
		"happiness": DEFAULT_CITIZEN_HAPPINESS,
		"home_object_id": -1,
		"job_object_id": -1,
		"state": CITY_CITIZEN_STATE_IDLE,
		"city_tile_position": city_tile_position,
		"carry_capacity": DEFAULT_CITIZEN_CARRY_CAPACITY,
		"inventory": inventory
	}

	reset_city_citizen_task_state(citizen)
	reset_city_citizen_haul_state(citizen)
	reset_city_citizen_movement_state(citizen)
	return citizen
