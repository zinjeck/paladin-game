extends RefCounted
class_name CityCitizenRegistrySystem

const STARTING_CITY_POPULATION := 8
const STARTING_CITY_MALE_POPULATION: int = 4
const STARTING_CITY_FEMALE_POPULATION: int = 4

# Authoritative registry behavior for the active settlement. The paired state
# remains data-only; this system owns lookup, index repair, and registry
# invalidation without routing callers through WorldData.

static func get_current_state() -> CityCitizenRegistryState:
	return WorldPoliticalState.get_current_city_citizen_registry_state()


static func get_state_for_city_state(
	city_state: CitySettlementSimulationState
) -> CityCitizenRegistryState:
	if city_state == null:
		return null

	return city_state.citizen_registry_state


static var city_citizens: Array:
	get:
		return get_current_state().citizens
	set(value):
		get_current_state().citizens = value


static var city_citizen_index_by_id: Dictionary:
	get:
		return get_current_state().citizen_index_by_id
	set(value):
		get_current_state().citizen_index_by_id = value


static var next_city_citizen_id: int:
	get:
		return get_current_state().next_citizen_id
	set(value):
		get_current_state().next_citizen_id = value


static var city_citizen_version: int:
	get:
		return get_current_state().citizen_version
	set(value):
		get_current_state().citizen_version = value


static func get_city_citizens() -> Array:
	return city_citizens


static func get_city_citizens_for_city_state(
	city_state: CitySettlementSimulationState
) -> Array:
	var registry_state := get_state_for_city_state(city_state)
	return registry_state.citizens if registry_state != null else []


static func get_city_citizen_version() -> int:
	return city_citizen_version


static func get_city_citizen_version_for_city_state(
	city_state: CitySettlementSimulationState
) -> int:
	var registry_state := get_state_for_city_state(city_state)
	return registry_state.citizen_version if registry_state != null else 0


static func get_next_city_citizen_id() -> int:
	return next_city_citizen_id


static func reset_city_citizen_registry_state() -> void:
	city_citizens.clear()
	city_citizen_index_by_id.clear()
	next_city_citizen_id = 1
	get_current_state().starting_population_initialized = false
	mark_city_citizens_changed()


static func mark_city_citizens_changed() -> void:
	city_citizen_version += 1


static func mark_city_citizens_changed_for_city_state(
	city_state: CitySettlementSimulationState
) -> void:
	var registry_state := get_state_for_city_state(city_state)

	if registry_state != null:
		registry_state.citizen_version += 1

static func rebuild_city_citizen_index() -> void:
	city_citizen_index_by_id.clear()

	for citizen_index in range(city_citizens.size()):
		var raw_citizen = city_citizens[citizen_index]

		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var citizen_id := int(citizen.get("id", -1))

		if citizen_id < 0:
			continue

		if city_citizen_index_by_id.has(citizen_id):
			push_error(
				"Duplicate city citizen ID while rebuilding index: "
				+ str(citizen_id)
			)
			continue

		city_citizen_index_by_id[citizen_id] = citizen_index

static func register_city_citizen_index(
	citizen: Dictionary,
	citizen_index: int
) -> void:
	if citizen.is_empty():
		return

	if citizen_index < 0 or citizen_index >= city_citizens.size():
		push_error(
			"Cannot register city citizen index outside the citizen array: "
			+ str(citizen_index)
		)
		return

	var citizen_id := int(citizen.get("id", -1))

	if citizen_id < 0:
		push_error("Cannot register city citizen without a valid ID.")
		return

	if city_citizen_index_by_id.has(citizen_id):
		var existing_index := int(city_citizen_index_by_id[citizen_id])

		if existing_index != citizen_index:
			push_error(
				"Duplicate city citizen ID detected: "
				+ str(citizen_id)
			)
			return

	city_citizen_index_by_id[citizen_id] = citizen_index

static func get_city_citizen_index_by_id(citizen_id: int) -> int:
	if citizen_id < 0:
		return -1

	if not city_citizen_index_by_id.has(citizen_id):
		return -1

	var citizen_index := int(city_citizen_index_by_id[citizen_id])

	if citizen_index < 0 or citizen_index >= city_citizens.size():
		push_error(
			"Stale city citizen index for citizen ID "
			+ str(citizen_id)
		)

		city_citizen_index_by_id.erase(citizen_id)
		return -1

	var raw_citizen = city_citizens[citizen_index]

	if not raw_citizen is Dictionary:
		push_error(
			"City citizen index points to non-Dictionary data for citizen ID "
			+ str(citizen_id)
		)

		city_citizen_index_by_id.erase(citizen_id)
		return -1

	var citizen: Dictionary = raw_citizen
	var indexed_citizen_id := int(citizen.get("id", -1))

	if indexed_citizen_id != citizen_id:
		push_error(
			"City citizen index mismatch for requested ID "
			+ str(citizen_id)
			+ ". Indexed citizen contains ID "
			+ str(indexed_citizen_id)
		)

		city_citizen_index_by_id.erase(citizen_id)
		return -1

	return citizen_index


static func get_city_citizen_index_by_id_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> int:
	var registry_state := get_state_for_city_state(city_state)

	if registry_state == null or citizen_id < 0:
		return -1

	var citizen_index := int(
		registry_state.citizen_index_by_id.get(citizen_id, -1)
	)

	if citizen_index < 0 or citizen_index >= registry_state.citizens.size():
		registry_state.citizen_index_by_id.erase(citizen_id)
		return -1

	var raw_citizen = registry_state.citizens[citizen_index]

	if (
		not raw_citizen is Dictionary
		or int(raw_citizen.get("id", -1)) != citizen_id
	):
		registry_state.citizen_index_by_id.erase(citizen_id)
		return -1

	return citizen_index

static func get_city_population_count() -> int:
	return city_citizens.size()

static func get_city_citizen_by_id(citizen_id: int) -> Dictionary:

	var citizen_index := get_city_citizen_index_by_id(citizen_id)

	if citizen_index < 0:
		return {}

	var raw_citizen = city_citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return {}

	return raw_citizen


static func get_city_citizen_by_id_for_city_state(
	city_state: CitySettlementSimulationState,
	citizen_id: int
) -> Dictionary:
	var citizen_index := get_city_citizen_index_by_id_for_city_state(
		city_state,
		citizen_id
	)

	if citizen_index < 0:
		return {}

	var registry_state := get_state_for_city_state(city_state)
	var raw_citizen = registry_state.citizens[citizen_index]

	return raw_citizen if raw_citizen is Dictionary else {}

static func get_city_citizen_snapshot() -> Array:

	var citizen_snapshot := []

	for citizen in city_citizens:
		if not citizen is Dictionary:
			continue

		citizen_snapshot.append(citizen.duplicate(true))

	return citizen_snapshot

static func get_city_citizen_display_name(citizen_id: int) -> String:
	var citizen := get_city_citizen_by_id(citizen_id)

	if citizen.is_empty():
		return "Citizen " + str(citizen_id)

	return str(citizen.get("name", "Citizen " + str(citizen_id)))

static func reset_city_citizen_state() -> void:
	CityLogisticsSystem.reset_city_haul_reservation_state()
	CityCitizenRegistrySystem.reset_city_citizen_registry_state()
	CityCitizenSpatialSystem.reset_city_citizen_spatial_state()
	CityCitizenMovementRuntimeSystem.reset_city_citizen_movement_runtime_state()
	CityCitizenTaskRuntimeSystem.reset_city_citizen_task_runtime_state()
	CitizenDecisionSystem.reset_runtime_state()
	CityAssignmentSystem.mark_city_assignments_changed()

#endregion

#region Haul Reservations and Endpoint Accounting

static func get_city_citizen_name_seed() -> int:
	var name_seed := get_city_citizen_name_seed_for_city_state(
		WorldPoliticalState.get_current_city_simulation_state()
	)

	if name_seed == 0:
		name_seed = int(WorldData.city_start_world_seed)

	if name_seed == 0:
		name_seed = 12345

	return name_seed


static func get_city_citizen_name_seed_for_city_state(
	city_state: CitySettlementSimulationState
) -> int:
	if city_state == null:
		return 0

	return int(city_state.city_seed)

static func get_city_citizen_count_by_sex(
	citizen_sex: String
) -> int:
	var normalized_sex := (
		CityCitizens.normalize_city_citizen_sex(
			citizen_sex
		)
	)

	if not CityCitizens.is_valid_city_citizen_sex(
		normalized_sex
	):
		return 0

	var citizen_count := 0

	for raw_citizen in CityCitizenRegistrySystem.get_current_state().citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen

		if (
			CityCitizens.normalize_city_citizen_sex(
				str(citizen.get("sex", ""))
			)
			!= normalized_sex
		):
			continue

		citizen_count += 1

	return citizen_count

static func make_random_city_citizen_first_name(
	citizen_sex: String,
	citizen_number: int = -1
) -> String:
	var resolved_citizen_number := citizen_number

	if resolved_citizen_number <= 0:
		resolved_citizen_number = CityCitizenRegistrySystem.get_current_state().next_citizen_id

	return CityCitizens.make_random_city_citizen_first_name(
		citizen_sex,
		resolved_citizen_number,
		get_city_citizen_name_seed(),
		CityCitizenRegistrySystem.get_current_state().citizens
	)

static func resolve_city_citizen_culture_id(
	requested_culture_id: int = WorldData.INVALID_CULTURE_ID
) -> int:
	return resolve_city_citizen_culture_id_for_city_state(
		WorldPoliticalState.get_current_city_simulation_state(),
		requested_culture_id
	)


static func resolve_city_citizen_culture_id_for_city_state(
	city_state: CitySettlementSimulationState,
	requested_culture_id: int = WorldData.INVALID_CULTURE_ID
) -> int:
	if WorldData.has_culture_id(requested_culture_id):
		return requested_culture_id

	if requested_culture_id != WorldData.INVALID_CULTURE_ID:
		return WorldData.INVALID_CULTURE_ID

	if city_state == null or not bool(
		city_state.city_runtime_data.get("founded", false)
	):
		return WorldData.INVALID_CULTURE_ID

	var primary_culture_value = city_state.city_runtime_data.get(
		"primary_culture_id",
		WorldData.INVALID_CULTURE_ID
	)

	if not primary_culture_value is int:
		return WorldData.INVALID_CULTURE_ID

	var primary_culture_id: int = primary_culture_value

	if not WorldData.has_culture_id(primary_culture_id):
		return WorldData.INVALID_CULTURE_ID

	return primary_culture_id

static func make_city_citizen(
	display_name: String = "",
	initial_city_tile_position: Vector2i = (
		CityCitizens.INVALID_CITY_TILE_POSITION
	),
	citizen_sex: String = "",
	culture_id: int = WorldData.INVALID_CULTURE_ID
) -> Dictionary:
	return make_city_citizen_for_city_state(
		WorldPoliticalState.get_current_city_simulation_state(),
		display_name,
		initial_city_tile_position,
		citizen_sex,
		culture_id
	)


static func make_city_citizen_for_city_state(
	city_state: CitySettlementSimulationState,
	display_name: String = "",
	initial_city_tile_position: Vector2i = (
		CityCitizens.INVALID_CITY_TILE_POSITION
	),
	citizen_sex: String = "",
	culture_id: int = WorldData.INVALID_CULTURE_ID
) -> Dictionary:
	var registry_state := get_state_for_city_state(city_state)

	if registry_state == null:
		return {}

	var resolved_culture_id := resolve_city_citizen_culture_id_for_city_state(
		city_state,
		culture_id
	)

	if not WorldData.has_culture_id(resolved_culture_id):
		push_error(
			"Cannot create a city citizen without a valid culture ID."
		)
		return {}

	var name_seed := get_city_citizen_name_seed_for_city_state(city_state)
	if name_seed == 0:
		name_seed = 12345

	var citizen := CityCitizens.make_city_citizen({
		"id": registry_state.next_citizen_id,
		"display_name": display_name,
		"sex": citizen_sex,
		"culture_id": resolved_culture_id,
		"city_tile_position": initial_city_tile_position,
		"name_seed": name_seed,
		"existing_citizens": registry_state.citizens,
	})

	if citizen.is_empty():
		return {}

	registry_state.next_citizen_id += 1
	return citizen

static func add_city_citizen(
	display_name: String = "",
	initial_city_tile_position: Vector2i = (
		CityCitizens.INVALID_CITY_TILE_POSITION
	),
	citizen_sex: String = "",
	culture_id: int = WorldData.INVALID_CULTURE_ID
) -> Dictionary:
	return add_city_citizen_for_city_state(
		WorldPoliticalState.get_current_city_simulation_state(),
		display_name,
		initial_city_tile_position,
		citizen_sex,
		culture_id
	)


static func add_city_citizen_for_city_state(
	city_state: CitySettlementSimulationState,
	display_name: String = "",
	initial_city_tile_position: Vector2i = (
		CityCitizens.INVALID_CITY_TILE_POSITION
	),
	citizen_sex: String = "",
	culture_id: int = WorldData.INVALID_CULTURE_ID
) -> Dictionary:
	var registry_state := get_state_for_city_state(city_state)

	if registry_state == null:
		return {}

	var previous_next_citizen_id := registry_state.next_citizen_id
	var citizen := make_city_citizen_for_city_state(
		city_state,
		display_name,
		initial_city_tile_position,
		citizen_sex,
		culture_id
	)

	if citizen.is_empty():
		return {}

	var citizen_id := int(citizen.get("id", -1))
	if citizen_id <= 0 or registry_state.citizen_index_by_id.has(citizen_id):
		registry_state.next_citizen_id = previous_next_citizen_id
		return {}

	registry_state.citizens.append(citizen)
	var citizen_index := registry_state.citizens.size() - 1
	registry_state.citizen_index_by_id[citizen_id] = citizen_index

	CityCitizenSpatialSystem.register_city_citizen_spatial_index_entry_for_city_state(
		city_state,
		citizen
	)

	mark_city_citizens_changed_for_city_state(city_state)
	CityCitizenSpatialSystem.mark_city_citizen_spatial_changed_for_city_state(
		city_state
	)

	return citizen

static func initialize_starting_city_population() -> int:
	return initialize_starting_city_population_for_city_state(
		WorldPoliticalState.get_current_city_simulation_state()
	)


static func initialize_starting_city_population_for_city_state(
	city_state: CitySettlementSimulationState
) -> int:
	var registry_state := get_state_for_city_state(city_state)

	if registry_state == null:
		return 0

	if registry_state.starting_population_initialized:
		return 0

	if not bool(city_state.city_runtime_data.get("founded", false)):
		push_error(
			"Cannot initialize the starting population "
			+ "before the target settlement is founded."
		)
		return 0

	if not registry_state.citizens.is_empty():
		push_error(
			"Cannot initialize the starting population over an existing registry."
		)
		return 0

	if (
		STARTING_CITY_MALE_POPULATION
		+ STARTING_CITY_FEMALE_POPULATION
		!= STARTING_CITY_POPULATION
	):
		push_error(
			"Starting male and female population counts "
			+ "do not equal STARTING_CITY_POPULATION."
		)
		return 0

	if not CityCitizens.city_citizen_name_pools_are_ready():
		push_error(
			"Cannot initialize citizens because the "
			+ "male/female name pools are incomplete, "
			+ "duplicated, or still contain "
			+ "unassigned names."
		)
		return 0

	var primary_culture_id := resolve_city_citizen_culture_id_for_city_state(
		city_state,
		WorldData.INVALID_CULTURE_ID
	)

	if not WorldData.has_culture_id(primary_culture_id):
		push_error(
			"Cannot initialize starting citizens because the settlement's "
			+ "primary culture does not exist."
		)
		return 0

	var city_world: WorldData = city_state.city_world

	if city_world == null:
		push_error(
			"Cannot initialize starting citizens "
			+ "without the settlement's city world."
		)
		return 0

	var spawn_tiles := (
		CityCitizenSpatialSystem.get_starting_city_citizen_spawn_tiles_for_city_state(
			city_state,
			city_world
		)
	)

	if spawn_tiles.is_empty():
		push_error(
			"Cannot initialize starting citizens: "
			+ "the City Keep has no walkable access tiles."
		)
		return 0

	var transaction_state := _capture_starting_population_transaction_state(
		city_state
	)
	var created_count := 0
	var created_male_count := 0
	var created_female_count := 0

	for citizen_number in range(
		STARTING_CITY_POPULATION
	):
		var citizen_sex := (
			CityCitizens.CITY_CITIZEN_SEX_FEMALE
		)

		if (
			citizen_number
			< STARTING_CITY_MALE_POPULATION
		):
			citizen_sex = CityCitizens.CITY_CITIZEN_SEX_MALE

		var spawn_tile: Vector2i = spawn_tiles[
			citizen_number % spawn_tiles.size()
		]

		var citizen := add_city_citizen_for_city_state(
			city_state,
			"",
			spawn_tile,
			citizen_sex,
			primary_culture_id
		)

		if citizen.is_empty() or not _starting_citizen_has_spatial_entry(
			city_state,
			citizen
		):
			_restore_starting_population_transaction_state(
				city_state,
				transaction_state
			)
			push_error(
				"Starting population creation failed and was rolled back."
			)
			return 0

		if (
			citizen_sex
			== CityCitizens.CITY_CITIZEN_SEX_MALE
		):
			created_male_count += 1
		else:
			created_female_count += 1

		created_count += 1

	if (
		created_count != STARTING_CITY_POPULATION
		or created_male_count
		!= STARTING_CITY_MALE_POPULATION
		or created_female_count
		!= STARTING_CITY_FEMALE_POPULATION
	):
		push_error(
			"Starting population sex balance failed. "
			+ "Created "
			+ str(created_male_count)
			+ " male and "
			+ str(created_female_count)
			+ " female citizens."
		)
		_restore_starting_population_transaction_state(
			city_state,
			transaction_state
		)
		return 0

	registry_state.starting_population_initialized = true
	return created_count


static func _capture_starting_population_transaction_state(
	city_state: CitySettlementSimulationState
) -> Dictionary:
	var registry_state := city_state.citizen_registry_state
	var spatial_state := city_state.citizen_spatial_state
	return {
		"citizens": registry_state.citizens.duplicate(true),
		"citizen_index_by_id": registry_state.citizen_index_by_id.duplicate(true),
		"next_citizen_id": registry_state.next_citizen_id,
		"citizen_version": registry_state.citizen_version,
		"starting_population_initialized": (
			registry_state.starting_population_initialized
		),
		"citizen_ids_by_tile": spatial_state.citizen_ids_by_tile.duplicate(true),
		"citizen_spatial_version": spatial_state.citizen_spatial_version,
	}


static func _restore_starting_population_transaction_state(
	city_state: CitySettlementSimulationState,
	snapshot: Dictionary
) -> void:
	var registry_state := city_state.citizen_registry_state
	var spatial_state := city_state.citizen_spatial_state
	var restored_citizens: Array = snapshot["citizens"]
	var restored_citizen_index: Dictionary = snapshot["citizen_index_by_id"]
	var restored_spatial_index: Dictionary = snapshot["citizen_ids_by_tile"]

	registry_state.citizens.clear()
	registry_state.citizens.append_array(restored_citizens)
	registry_state.citizen_index_by_id.clear()
	registry_state.citizen_index_by_id.merge(restored_citizen_index, true)
	registry_state.next_citizen_id = int(snapshot["next_citizen_id"])
	registry_state.citizen_version = int(snapshot["citizen_version"])
	registry_state.starting_population_initialized = bool(
		snapshot["starting_population_initialized"]
	)
	spatial_state.citizen_ids_by_tile.clear()
	spatial_state.citizen_ids_by_tile.merge(restored_spatial_index, true)
	spatial_state.citizen_spatial_version = int(
		snapshot["citizen_spatial_version"]
	)


static func _starting_citizen_has_spatial_entry(
	city_state: CitySettlementSimulationState,
	citizen: Dictionary
) -> bool:
	var tile_position = citizen.get(
		"city_tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	if not tile_position is Vector2i:
		return false

	var raw_citizen_ids = (
		city_state.citizen_spatial_state.citizen_ids_by_tile.get(
			tile_position,
			[]
		)
	)
	return (
		raw_citizen_ids is Array
		and raw_citizen_ids.has(int(citizen.get("id", -1)))
	)

static func ensure_city_citizen_demographic_state() -> int:
	if CityCitizenRegistrySystem.get_current_state().citizens.is_empty():
		return 0

	if not CityCitizens.city_citizen_name_pools_are_ready():
		push_error(
			"Cannot migrate citizen demographics "
			+ "until the name pools are valid."
		)
		return 0

	var male_count := get_city_citizen_count_by_sex(
		CityCitizens.CITY_CITIZEN_SEX_MALE
	)
	var female_count := get_city_citizen_count_by_sex(
		CityCitizens.CITY_CITIZEN_SEX_FEMALE
	)
	var migrated_count := 0

	for citizen_index in range(
		CityCitizenRegistrySystem.get_current_state().citizens.size()
	):
		var raw_citizen = CityCitizenRegistrySystem.get_current_state().citizens[
			citizen_index
		]

		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var existing_sex := (
			CityCitizens.normalize_city_citizen_sex(
				str(citizen.get("sex", ""))
			)
		)

		if CityCitizens.is_valid_city_citizen_sex(
			existing_sex
		):
			continue

		var assigned_sex := (
			CityCitizens.CITY_CITIZEN_SEX_MALE
		)

		if male_count > female_count:
			assigned_sex = (
				CityCitizens.CITY_CITIZEN_SEX_FEMALE
			)

		var existing_name := str(
			citizen.get("name", "")
		).strip_edges()
		var assigned_name_pool := (
			CityCitizens.get_city_citizen_name_pool_for_sex(
				assigned_sex
			)
		)

		if not assigned_name_pool.has(
			existing_name
		):
			existing_name = (
				make_random_city_citizen_first_name(
					assigned_sex,
					int(citizen.get("id", -1))
				)
			)

		if existing_name.is_empty():
			push_error(
				"Could not migrate demographic state "
				+ "for citizen "
				+ str(citizen.get("id", -1))
				+ "."
			)
			continue

		citizen["sex"] = assigned_sex
		citizen["name"] = existing_name
		CityCitizenRegistrySystem.get_current_state().citizens[citizen_index] = citizen

		if assigned_sex == CityCitizens.CITY_CITIZEN_SEX_MALE:
			male_count += 1
		else:
			female_count += 1

		migrated_count += 1

	if migrated_count > 0:
		CityCitizenRegistrySystem.mark_city_citizens_changed()

	return migrated_count


#endregion

#region Population, Housing, and Workplace Queries

static func get_city_citizen_culture_id(citizen_id: int) -> int:
	var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)

	if citizen.is_empty():
		return WorldData.INVALID_CULTURE_ID

	var culture_id_value = citizen.get(
		"culture_id",
		WorldData.INVALID_CULTURE_ID
	)

	if not culture_id_value is int:
		return WorldData.INVALID_CULTURE_ID

	var culture_id: int = culture_id_value

	if not WorldData.has_culture_id(culture_id):
		return WorldData.INVALID_CULTURE_ID

	return culture_id

static func get_city_citizen_culture(citizen_id: int) -> Dictionary:
	return WorldData.get_culture_by_id(get_city_citizen_culture_id(citizen_id))

static func get_city_citizen_culture_name(citizen_id: int) -> String:
	return WorldData.get_culture_name_by_id(
		get_city_citizen_culture_id(citizen_id)
	)
