extends RefCounted
class_name CityCitizenRegistrySystem

# Authoritative registry behavior for the active settlement. The paired state
# remains data-only; this system owns lookup, index repair, and registry
# invalidation without routing callers through WorldData.

static func get_current_state() -> CityCitizenRegistryState:
	return WorldPoliticalState.get_current_city_citizen_registry_state()


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


static func get_city_citizen_version() -> int:
	return city_citizen_version


static func get_next_city_citizen_id() -> int:
	return next_city_citizen_id


static func reset_city_citizen_registry_state() -> void:
	city_citizens.clear()
	city_citizen_index_by_id.clear()
	next_city_citizen_id = 1
	mark_city_citizens_changed()


static func mark_city_citizens_changed() -> void:
	city_citizen_version += 1

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
