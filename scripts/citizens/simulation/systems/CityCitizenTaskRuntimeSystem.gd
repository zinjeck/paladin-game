extends RefCounted
class_name CityCitizenTaskRuntimeSystem

const CityCitizensScript = preload(
	"res://scripts/citizens/simulation/CityCitizens.gd"
)

# Authoritative current-task and task-runtime behavior for the active
# settlement. Task selection/execution remains in the focused behavior systems.

static func get_current_state() -> CityCitizenTaskRuntimeState:
	return WorldPoliticalState.get_current_city_citizen_task_runtime_state()


static var city_active_task_ids: Array[int]:
	get:
		return get_current_state().active_task_ids
	set(value):
		get_current_state().active_task_ids = value


static var city_active_task_id_lookup: Dictionary:
	get:
		return get_current_state().active_task_id_lookup
	set(value):
		get_current_state().active_task_id_lookup = value


static var city_citizen_task_version: int:
	get:
		return get_current_state().citizen_task_version
	set(value):
		get_current_state().citizen_task_version = value


static func get_city_citizen_task_version() -> int:
	return city_citizen_task_version


static func reset_city_citizen_task_runtime_state() -> void:
	city_active_task_ids.clear()
	city_active_task_id_lookup.clear()
	mark_city_citizen_task_changed()


static func mark_city_citizen_task_changed() -> void:
	city_citizen_task_version += 1

static func _add_city_active_task_id(
	citizen_id: int
) -> bool:
	if citizen_id <= 0:
		return false

	var insertion_index := city_active_task_ids.bsearch(citizen_id)
	var array_has_id := (
		insertion_index < city_active_task_ids.size()
		and city_active_task_ids[insertion_index] == citizen_id
	)
	var lookup_is_valid := (
		city_active_task_id_lookup.has(citizen_id)
		and bool(city_active_task_id_lookup[citizen_id])
	)
	var array_has_duplicate := (
		array_has_id
		and insertion_index + 1 < city_active_task_ids.size()
		and city_active_task_ids[insertion_index + 1] == citizen_id
	)

	if array_has_id and not array_has_duplicate:
		if lookup_is_valid:
			return false
		city_active_task_id_lookup[citizen_id] = true
		return true

	if not array_has_id:
		city_active_task_ids.insert(insertion_index, citizen_id)
		city_active_task_id_lookup[citizen_id] = true
		return true

	# Duplicate targets are corruption, not a healthy assignment path.
	_remove_all_city_active_task_array_entries(citizen_id)
	city_active_task_ids.insert(
		city_active_task_ids.bsearch(citizen_id),
		citizen_id
	)
	city_active_task_id_lookup[citizen_id] = true
	return true

static func _remove_city_active_task_id(
	citizen_id: int
) -> bool:
	var changed := city_active_task_id_lookup.erase(citizen_id)

	if _remove_all_city_active_task_array_entries(citizen_id):
		changed = true

	return changed

static func _remove_all_city_active_task_array_entries(
	citizen_id: int
) -> bool:
	var original_size := city_active_task_ids.size()
	var write_index := 0

	for read_index in range(original_size):
		var active_task_id := city_active_task_ids[read_index]

		if active_task_id == citizen_id:
			continue

		if write_index != read_index:
			city_active_task_ids[write_index] = active_task_id

		write_index += 1

	while city_active_task_ids.size() > write_index:
		city_active_task_ids.pop_back()

	return write_index != original_size

static func rebuild_city_active_task_registry() -> bool:
	var previous_active_ids := city_active_task_ids.duplicate()
	var previous_active_lookup := city_active_task_id_lookup.duplicate()
	var expected_active_ids: Array[int] = []
	var expected_active_lookup: Dictionary = {}

	for raw_citizen in CityCitizenRegistrySystem.get_current_state().citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen

		if not bool(citizen.get("alive", false)):
			continue

		var raw_current_task = citizen.get("current_task", {})

		if not raw_current_task is Dictionary:
			continue

		var current_task: Dictionary = raw_current_task

		if (
			str(current_task.get("kind", ""))
			== CityCitizens.CITY_CITIZEN_TASK_KIND_NONE
		):
			continue

		var citizen_id := int(citizen.get("id", -1))

		if citizen_id <= 0:
			continue

		if expected_active_lookup.has(citizen_id):
			continue

		expected_active_ids.append(citizen_id)
		expected_active_lookup[citizen_id] = true

	expected_active_ids.sort()

	var registry_changed := (
		previous_active_ids != expected_active_ids
		or previous_active_lookup != expected_active_lookup
	)
	city_active_task_ids.clear()
	city_active_task_id_lookup.clear()
	city_active_task_ids.append_array(expected_active_ids)
	city_active_task_id_lookup.merge(expected_active_lookup)
	if registry_changed:
		mark_city_citizen_task_changed()

	return registry_changed

static func get_city_active_task_ids_snapshot() -> Array[int]:
	return city_active_task_ids.duplicate()

static func get_city_citizen_current_haul(
	citizen_id: int
) -> Dictionary:
	var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)

	if citizen.is_empty():
		return CityCitizens.make_city_citizen_haul()

	var raw_haul = citizen.get("current_haul", {})

	if not raw_haul is Dictionary:
		return CityCitizens.make_city_citizen_haul()

	return CityCitizens.make_city_citizen_haul(
		raw_haul
	)

static func set_city_citizen_current_haul(
	citizen_id: int,
	haul_values: Dictionary
) -> bool:
	var citizen_index := CityCitizenRegistrySystem.get_city_citizen_index_by_id(
		citizen_id
	)

	if citizen_index < 0:
		return false

	var raw_citizen = CityCitizenRegistrySystem.get_current_state().citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return false

	var normalized_haul := (
		CityCitizens.make_city_citizen_haul(
			haul_values
		)
	)
	var haul_phase := str(
		normalized_haul.get(
			"phase",
			CityCitizens.CITY_CITIZEN_HAUL_PHASE_NONE
		)
	)

	if not CityCitizens.is_valid_city_citizen_haul_phase(
		haul_phase
	):
		return false

	if not normalized_haul.get("source_tile") is Vector2i:
		return false

	if not normalized_haul.get("destination_tile") is Vector2i:
		return false

	var citizen: Dictionary = raw_citizen
	var raw_existing_haul = citizen.get("current_haul", {})

	if (
		raw_existing_haul is Dictionary
		and raw_existing_haul == normalized_haul
	):
		return true

	citizen["current_haul"] = normalized_haul
	CityCitizenRegistrySystem.get_current_state().citizens[citizen_index] = citizen
	mark_city_citizen_task_changed()
	return true

static func get_city_food_task_reserved_endpoint_amount(
	endpoint_kind: String,
	endpoint_id: int,
	resource: String,
	excluding_citizen_id: int = -1
) -> int:
	if (
		endpoint_id <= 0
		or CityResourceCatalog.get_city_food_hunger_restore(resource) <= 0
		or not [
			CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER,
			CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_GROUND_PILE,
		].has(endpoint_kind)
	):
		return 0

	var reserved_amount := 0

	for raw_citizen in CityCitizenRegistrySystem.get_current_state().citizens:
		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var citizen_id := int(citizen.get("id", -1))
		var raw_task = citizen.get("current_task", {})

		if citizen_id == excluding_citizen_id or not raw_task is Dictionary:
			continue

		var task: Dictionary = raw_task
		var task_endpoint_kind := str(
			task.get(
				"food_source_endpoint_kind",
				CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER
			)
		)

		if (
			str(task.get("kind", CityCitizens.CITY_CITIZEN_TASK_KIND_NONE))
			!= CityCitizens.CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD
			or task_endpoint_kind != endpoint_kind
			or int(task.get("target_object_id", -1)) != endpoint_id
			or str(task.get("food_resource_type", WorldData.RESOURCE_NONE)) != resource
		):
			continue

		reserved_amount += maxi(
			int(task.get("food_requested_amount", 0)),
			0
		)

	return reserved_amount

static func ensure_city_citizen_task_state() -> int:
	if CityCitizenRegistrySystem.get_current_state().citizens.is_empty():
		rebuild_city_active_task_registry()
		return 0

	var migrated_count := 0

	for citizen_index in range(CityCitizenRegistrySystem.get_current_state().citizens.size()):
		var raw_citizen = CityCitizenRegistrySystem.get_current_state().citizens[citizen_index]

		if not raw_citizen is Dictionary:
			continue

		var citizen: Dictionary = raw_citizen
		var citizen_was_migrated := false

		if (
			not CityCitizensScript
			.has_complete_city_citizen_task_state(citizen)
		):
			var raw_current_task = citizen.get("current_task", {})

			if raw_current_task is Dictionary:
				citizen["current_task"] = (
					CityCitizens.make_city_citizen_task(
						raw_current_task
					)
				)
			else:
				CityCitizens.reset_city_citizen_task_state(citizen)

			citizen_was_migrated = true

		if (
			not CityCitizensScript
			.has_complete_city_citizen_haul_runtime_state(citizen)
		):
			var raw_current_haul = citizen.get("current_haul", {})

			if raw_current_haul is Dictionary:
				citizen["current_haul"] = (
					CityCitizens.make_city_citizen_haul(
						raw_current_haul
					)
				)
			else:
				CityCitizens.reset_city_citizen_haul_runtime_state(
					citizen
				)
			citizen_was_migrated = true

		if not citizen_was_migrated:
			continue

		CityCitizenRegistrySystem.get_current_state().citizens[citizen_index] = citizen
		migrated_count += 1

	var task_version_before_rebuild := city_citizen_task_version
	rebuild_city_active_task_registry()

	if (
		migrated_count > 0
		and city_citizen_task_version == task_version_before_rebuild
	):
		mark_city_citizen_task_changed()

	return migrated_count

static func get_city_citizen_current_task(
	citizen_id: int
) -> Dictionary:
	var citizen := CityCitizenRegistrySystem.get_city_citizen_by_id(citizen_id)
	if citizen.is_empty():
		return {}

	var raw_current_task = citizen.get("current_task", {})

	if not raw_current_task is Dictionary:
		return {}

	return raw_current_task.duplicate(true)

static func assign_city_citizen_task(
	citizen_id: int,
	task_values: Dictionary
) -> bool:
	var assignment := _make_city_citizen_task_assignment_context(
		citizen_id,
		task_values
	)

	if assignment.is_empty():
		return false

	if not _prepare_city_citizen_task_assignment(assignment):
		return false

	return _commit_city_citizen_task_assignment(assignment)

static func _make_city_citizen_task_assignment_context(
	citizen_id: int,
	task_values: Dictionary
) -> Dictionary:
	var citizen_index := CityCitizenRegistrySystem.get_city_citizen_index_by_id(citizen_id)

	if citizen_index < 0:
		return {}

	var raw_citizen = CityCitizenRegistrySystem.get_current_state().citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return {}

	var citizen: Dictionary = raw_citizen

	if not bool(citizen.get("alive", false)):
		return {}

	var raw_task_kind = task_values.get("kind")
	var raw_task_source = task_values.get("source")
	var raw_task_priority = task_values.get("priority")
	var raw_target_object_id = task_values.get("target_object_id")
	var raw_work_order_id = task_values.get("work_order_id", -1)
	var raw_job_id = task_values.get("job_id", "")
	var raw_player_locked = task_values.get("player_locked", false)

	if typeof(raw_task_kind) != TYPE_STRING:
		return {}

	if typeof(raw_task_source) != TYPE_STRING:
		return {}

	if typeof(raw_task_priority) != TYPE_INT:
		return {}

	if typeof(raw_target_object_id) != TYPE_INT:
		return {}

	if typeof(raw_work_order_id) != TYPE_INT:
		return {}

	if typeof(raw_job_id) != TYPE_STRING:
		return {}

	if typeof(raw_player_locked) != TYPE_BOOL:
		return {}

	var task_kind: String = raw_task_kind
	var task_source: String = raw_task_source
	var task_priority: int = raw_task_priority
	var target_object_id: int = raw_target_object_id
	var work_order_id: int = raw_work_order_id
	var job_id: String = raw_job_id
	var player_locked: bool = raw_player_locked

	if (
		not CityCitizens.is_valid_city_citizen_task_kind(task_kind)
		or task_kind == CityCitizens.CITY_CITIZEN_TASK_KIND_NONE
	):
		return {}

	if (
		not CityCitizens.is_valid_city_citizen_task_source(task_source)
		or task_source == CityCitizens.CITY_CITIZEN_TASK_SOURCE_NONE
	):
		return {}

	if task_priority <= CityCitizens.CITY_CITIZEN_TASK_PRIORITY_NONE:
		return {}

	if target_object_id <= 0:
		return {}

	if (
		player_locked
		and task_source != CityCitizens.CITY_CITIZEN_TASK_SOURCE_PLAYER
	):
		return {}

	# Employment is already a standing player directive. Direct commands and
	# autonomous logistics require unemployment, but biological food seeking is
	# allowed to interrupt employed citizens at critical hunger.
	if (
		(
			task_source == CityCitizens.CITY_CITIZEN_TASK_SOURCE_PLAYER
			or task_source == CityCitizens.CITY_CITIZEN_TASK_SOURCE_AUTONOMY
		)
		and int(citizen.get("job_object_id", -1)) > 0
		and task_kind != CityCitizens.CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD
	):
		return {}

	var raw_existing_task = citizen.get("current_task", {})

	if raw_existing_task is Dictionary:
		var existing_task: Dictionary = raw_existing_task

		if (
			bool(existing_task.get("player_locked", false))
			and task_source != CityCitizens.CITY_CITIZEN_TASK_SOURCE_PLAYER
		):
			return {}

		# Replacements must pass through the appropriate cancellation or player-
		# interruption gateway first. That path owns reservation release and cargo
		# preservation, so assigning over an active task can never leak a claim.
		if (
			str(existing_task.get("kind", CityCitizens.CITY_CITIZEN_TASK_KIND_NONE))
			!= CityCitizens.CITY_CITIZEN_TASK_KIND_NONE
		):
			return {}

	var haul_cargo_amount := maxi(
		int(CityCitizenInventorySystem.get_city_citizen_haul_cargo(citizen_id).get("amount", 0)),
		0
	)

	if (
		haul_cargo_amount > 0
		and task_kind != CityCitizens.CITY_CITIZEN_TASK_KIND_HAUL
	):
		return {}

	return {
		"citizen_id": citizen_id,
		"citizen_index": citizen_index,
		"citizen": citizen,
		"task_values": task_values,
		"task_kind": task_kind,
		"task_source": task_source,
		"task_priority": task_priority,
		"target_object_id": target_object_id,
		"work_order_id": work_order_id,
		"job_id": job_id,
		"player_locked": player_locked,
		"haul_cargo_amount": haul_cargo_amount,
		"assigned_haul": CityCitizens.make_city_citizen_haul(),
		"assigned_target_tile": CityCitizens.INVALID_CITY_TILE_POSITION,
		"assigned_food_resource": WorldData.RESOURCE_NONE,
		"assigned_food_requested_amount": 0,
		"assigned_food_endpoint_kind": CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE,
		"assigned_food_access_purpose": CityObjectCatalog.CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_NONE,
	}

static func _prepare_city_citizen_task_assignment(
	assignment: Dictionary
) -> bool:
	match str(assignment.get("task_kind", CityCitizens.CITY_CITIZEN_TASK_KIND_NONE)):
		CityCitizens.CITY_CITIZEN_TASK_KIND_WORK:
			return _prepare_city_work_task_assignment(assignment)

		CityCitizens.CITY_CITIZEN_TASK_KIND_ACQUIRE_FOOD:
			return _prepare_city_food_task_assignment(assignment)

		CityCitizens.CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND:
			return _prepare_city_player_command_task_assignment(assignment)

		CityCitizens.CITY_CITIZEN_TASK_KIND_CONSTRUCTION:
			return CityConstructionSystem.prepare_city_construction_task_assignment(assignment)

		CityCitizens.CITY_CITIZEN_TASK_KIND_HAUL:
			return _prepare_city_haul_task_assignment(assignment)

		CityCitizens.CITY_CITIZEN_TASK_KIND_RETURN_HOME:
			return _prepare_city_return_home_task_assignment(assignment)

		_:
			return false

static func _prepare_city_work_task_assignment(
	assignment: Dictionary
) -> bool:
	var citizen: Dictionary = assignment.get("citizen", {})
	var target_object_id := int(assignment.get("target_object_id", -1))
	var workplace := CityObjectSystem.get_city_object_by_id(target_object_id)

	if workplace.is_empty() or not CityObjectCatalog.city_object_is_workplace(workplace):
		return false

	return int(citizen.get("job_object_id", -1)) == target_object_id

static func _prepare_city_food_task_assignment(
	assignment: Dictionary
) -> bool:
	var citizen_id := int(assignment.get("citizen_id", -1))
	var target_object_id := int(assignment.get("target_object_id", -1))
	var task_values: Dictionary = assignment.get("task_values", {})
	var food_resource := str(
		task_values.get("food_resource_type", WorldData.RESOURCE_NONE)
	)
	var food_endpoint_kind := str(
		task_values.get(
			"food_source_endpoint_kind",
			CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_CITY_OBJECT_CONTAINER
		)
	)
	var food_endpoint := {
		"kind": food_endpoint_kind,
		"id": target_object_id,
	}
	var food_requested_amount := maxi(
		int(task_values.get("food_requested_amount", 0)),
		0
	)
	var food_access_purpose := str(
		task_values.get(
			"food_source_access_purpose",
			CityObjectCatalog.CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_NONE
		)
	)
	var raw_food_target_tile = task_values.get(
		"target_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)
	var hunger_restore := CityResourceCatalog.get_city_food_hunger_restore(food_resource)
	var personal_food_nutrition := (
		CityResourceContainerSystem.get_food_nutrition_in_resource_container(
			CityCitizenInventorySystem.get_city_citizen_inventory(citizen_id)
		)
	)
	var desired_nutrition := maxi(
		CityCitizens.CITIZEN_EAT_TARGET_HUNGER
		- CitizenNeedsSystem.get_city_citizen_hunger(citizen_id)
		- personal_food_nutrition,
		0
	)

	if (
		hunger_restore <= 0
		or food_requested_amount <= 0
		or desired_nutrition <= 0
		or food_access_purpose
		!= CityObjectCatalog.CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_PERSONAL_FOOD
		or not raw_food_target_tile is Vector2i
		or not CityCitizens.is_valid_city_citizen_haul_endpoint(
			food_endpoint
		)
		or not CitizenNeedsSystem.get_city_citizen_food_endpoint_target_tiles(
			citizen_id,
			food_endpoint
		).has(raw_food_target_tile)
		or not CitizenNeedsSystem.city_citizen_can_withdraw_food_from_endpoint(
			citizen_id,
			food_endpoint,
			food_resource
		)
	):
		return false

	var assigned_amount := mini(
		food_requested_amount,
		mini(
			CitizenNeedsSystem.get_city_food_endpoint_unreserved_amount(
				citizen_id,
				food_endpoint,
				food_resource,
				citizen_id
			),
			mini(
				CityCitizenInventorySystem.get_city_citizen_inventory_free_space(citizen_id),
				ceili(float(desired_nutrition) / float(hunger_restore))
			)
		)
	)

	if assigned_amount <= 0:
		return false

	assignment["assigned_target_tile"] = raw_food_target_tile
	assignment["assigned_food_resource"] = food_resource
	assignment["assigned_food_requested_amount"] = assigned_amount
	assignment["assigned_food_endpoint_kind"] = food_endpoint_kind
	assignment["assigned_food_access_purpose"] = food_access_purpose
	return true

static func _prepare_city_player_command_task_assignment(
	assignment: Dictionary
) -> bool:
	var citizen_id := int(assignment.get("citizen_id", -1))
	var target_object_id := int(assignment.get("target_object_id", -1))
	var task_source := str(assignment.get("task_source", ""))
	var command := CityWorkSystem.get_city_player_command_by_id(target_object_id)

	if (
		task_source != CityCitizens.CITY_CITIZEN_TASK_SOURCE_PLAYER
		or command.is_empty()
		or int(command.get("claimed_citizen_id", -1)) != citizen_id
		or not CityWorkSystem.is_city_player_command_target_valid(command)
	):
		return false

	var raw_command_tile = command.get(
		"tile_position",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if not raw_command_tile is Vector2i:
		return false

	assignment["assigned_target_tile"] = raw_command_tile
	return true

static func _prepare_city_haul_task_assignment(
	assignment: Dictionary
) -> bool:
	var citizen_id := int(assignment.get("citizen_id", -1))
	var target_object_id := int(assignment.get("target_object_id", -1))
	var task_values: Dictionary = assignment.get("task_values", {})
	var haul_cargo_amount := maxi(
		int(assignment.get("haul_cargo_amount", 0)),
		0
	)
	var raw_haul = task_values.get("haul", {})

	if not raw_haul is Dictionary:
		return false

	var assigned_haul := CityCitizens.make_city_citizen_haul(raw_haul)
	var haul_phase := str(
		assigned_haul.get("phase", CityCitizens.CITY_CITIZEN_HAUL_PHASE_NONE)
	)
	var haul_resource := str(
		assigned_haul.get("resource_type", WorldData.RESOURCE_NONE)
	)
	var haul_source: Dictionary = assigned_haul.get("source", {})
	var haul_destination: Dictionary = assigned_haul.get("destination", {})
	var haul_requester: Dictionary = assigned_haul.get("requester", {})
	var source_endpoint_id := int(haul_source.get("id", -1))

	if (
		not CityCitizens.is_valid_city_citizen_haul_phase(haul_phase)
		or haul_phase == CityCitizens.CITY_CITIZEN_HAUL_PHASE_NONE
		or not CityResourceCatalog.is_city_resource_type(haul_resource)
		or int(assigned_haul.get("requested_amount", 0)) <= 0
		or str(
			assigned_haul.get("reason", CityCitizens.CITY_CITIZEN_HAUL_REASON_NONE)
		) == CityCitizens.CITY_CITIZEN_HAUL_REASON_NONE
		or str(
			assigned_haul.get(
				"source_access_purpose",
				CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
			)
		) == CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		or str(
			assigned_haul.get(
				"destination_access_purpose",
				CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
			)
		) == CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
		or not assigned_haul.get("source_tile") is Vector2i
		or not assigned_haul.get("destination_tile") is Vector2i
	):
		return false

	if not CityCitizens.is_valid_city_citizen_haul_endpoint(haul_source):
		return false

	if not CityCitizens.is_valid_city_citizen_haul_endpoint(haul_requester):
		return false

	if source_endpoint_id != target_object_id:
		return false

	if haul_cargo_amount <= 0:
		if not CityCitizens.is_valid_city_citizen_haul_endpoint(
			haul_destination
		):
			return false

		var source_access_purpose := str(
			assigned_haul.get(
				"source_access_purpose",
				CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
			)
		)

		if not CityLogisticsSystem.city_haul_endpoint_can_provide_resource({
			"endpoint": haul_source,
			"resource": haul_resource,
			"withdrawal_purpose": source_access_purpose,
			"require_unreserved_amount": true,
		}):
			return false
	else:
		var cargo_resources := CityCitizenInventorySystem.get_city_citizen_haul_cargo_resources(citizen_id)

		if cargo_resources.is_empty():
			return false

	if not CityCitizens.is_valid_city_citizen_haul_endpoint(
		haul_destination,
		haul_cargo_amount > 0
	):
		return false

	if (
		str(
			haul_destination.get(
				"kind",
				CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
			)
		)
		!= CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
	):
		var destination_access_purpose := str(
			assigned_haul.get(
				"destination_access_purpose",
				CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
			)
		)
		var destination_resources: Dictionary = {
			haul_resource: int(assigned_haul.get("requested_amount", 0))
		}

		if haul_cargo_amount > 0:
			destination_resources = CityCitizenInventorySystem.get_city_citizen_haul_cargo_resources(
				citizen_id
			)

		for destination_resource in destination_resources.keys():
			if not CityLogisticsSystem.city_haul_endpoint_can_accept_resource({
				"endpoint": haul_destination,
				"resource": str(destination_resource),
				"deposit_purpose": destination_access_purpose,
				"require_unreserved_space": true,
			}):
				return false

		var reservation := CityLogisticsSystem.create_city_haul_reservation({
			"citizen_id": citizen_id,
			"source": haul_source,
			"destination": haul_destination,
			"resource_type": haul_resource,
			"requested_amount": int(
				assigned_haul.get("requested_amount", 0)
			),
			"source_access_purpose": str(
				assigned_haul.get(
					"source_access_purpose",
					CityObjectCatalog.CONTAINER_HAUL_PURPOSE_NONE
				)
			),
			"destination_access_purpose": destination_access_purpose,
		})

		if reservation.is_empty():
			return false

		assigned_haul["reservation_id"] = int(reservation.get("id", -1))

		if haul_cargo_amount <= 0:
			assigned_haul["requested_amount"] = int(
				reservation.get("source_reserved_amount", 0)
			)
		else:
			assigned_haul["requested_amount"] = haul_cargo_amount

	assignment["assigned_haul"] = assigned_haul
	return true

static func _prepare_city_return_home_task_assignment(
	assignment: Dictionary
) -> bool:
	var citizen_id := int(assignment.get("citizen_id", -1))
	var citizen: Dictionary = assignment.get("citizen", {})
	var target_object_id := int(assignment.get("target_object_id", -1))
	var home := CityObjectSystem.get_city_object_by_id(target_object_id)

	if (
		home.is_empty()
		or CityObjectCatalog.get_city_object_resident_capacity(home) <= 0
		or not CityObjectSystem.city_object_supports_citizen_interior(home)
	):
		return false

	if int(citizen.get("home_object_id", -1)) != target_object_id:
		return false

	if not CityAssignmentSystem.get_city_object_resident_ids(home).has(citizen_id):
		return false

	return CityNavigationSystem.city_citizen_can_access_object_interior(citizen_id, home)

static func _commit_city_citizen_task_assignment(
	assignment: Dictionary
) -> bool:
	var citizen_id := int(assignment.get("citizen_id", -1))
	var citizen_index := int(assignment.get("citizen_index", -1))
	var citizen: Dictionary = assignment.get("citizen", {})
	var task_kind := str(assignment.get("task_kind", ""))
	var current_task := CityCitizens.make_city_citizen_task({
		"kind": task_kind,
		"source": str(assignment.get("task_source", "")),
		"phase": CityCitizens.CITY_CITIZEN_TASK_PHASE_PENDING,
		"priority": int(assignment.get("task_priority", 0)),
		"target_object_id": int(assignment.get("target_object_id", -1)),
		"work_order_id": int(assignment.get("work_order_id", -1)),
		"job_id": str(assignment.get("job_id", "")),
		"start_world_minute": SimulationClock.absolute_world_minutes,
		"target_tile": assignment.get(
			"assigned_target_tile",
			CityCitizens.INVALID_CITY_TILE_POSITION
		),
		"player_locked": bool(assignment.get("player_locked", false)),
		"food_resource_type": str(
			assignment.get("assigned_food_resource", WorldData.RESOURCE_NONE)
		),
		"food_requested_amount": int(
			assignment.get("assigned_food_requested_amount", 0)
		),
		"food_source_endpoint_kind": str(
			assignment.get(
				"assigned_food_endpoint_kind",
				CityCitizens.CITY_CITIZEN_HAUL_ENDPOINT_KIND_NONE
			)
		),
		"food_source_access_purpose": str(
			assignment.get(
				"assigned_food_access_purpose",
				CityObjectCatalog.CONTAINER_DIRECT_WITHDRAWAL_PURPOSE_NONE
			)
		),
	})

	citizen["current_task"] = current_task

	if task_kind == CityCitizens.CITY_CITIZEN_TASK_KIND_HAUL:
		citizen["current_haul"] = assignment.get(
			"assigned_haul",
			CityCitizens.make_city_citizen_haul()
		)
	else:
		CityCitizens.reset_city_citizen_haul_runtime_state(citizen)

	CityCitizenRegistrySystem.get_current_state().citizens[citizen_index] = citizen
	_add_city_active_task_id(citizen_id)
	mark_city_citizen_task_changed()
	return true

static func set_city_citizen_task_phase(
	citizen_id: int,
	task_phase: String
) -> bool:
	if (
		not CityCitizens.is_valid_city_citizen_task_phase(task_phase)
		or task_phase == CityCitizens.CITY_CITIZEN_TASK_PHASE_NONE
	):
		return false

	var citizen_index := CityCitizenRegistrySystem.get_city_citizen_index_by_id(
		citizen_id
	)

	if citizen_index < 0:
		return false

	var raw_citizen = CityCitizenRegistrySystem.get_current_state().citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return false

	var citizen: Dictionary = raw_citizen
	var raw_current_task = citizen.get("current_task", {})

	if not raw_current_task is Dictionary:
		return false

	var current_task: Dictionary = (
		raw_current_task.duplicate(true)
	)

	if (
		str(current_task.get("kind", ""))
		== CityCitizens.CITY_CITIZEN_TASK_KIND_NONE
	):
		return false

	if str(current_task.get("phase", "")) == task_phase:
		return true

	current_task["phase"] = task_phase
	citizen["current_task"] = current_task
	CityCitizenRegistrySystem.get_current_state().citizens[citizen_index] = citizen
	mark_city_citizen_task_changed()

	return true

static func set_city_citizen_task_target_object_id(
	citizen_id: int,
	target_object_id: int
) -> bool:
	if target_object_id <= 0:
		return false

	var citizen_index := CityCitizenRegistrySystem.get_city_citizen_index_by_id(citizen_id)

	if citizen_index < 0:
		return false

	var raw_citizen = CityCitizenRegistrySystem.get_current_state().citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return false

	var citizen: Dictionary = raw_citizen
	var raw_current_task = citizen.get("current_task", {})

	if not raw_current_task is Dictionary:
		return false

	var current_task: Dictionary = raw_current_task.duplicate(true)

	if (
		str(current_task.get("kind", ""))
		!= CityCitizens.CITY_CITIZEN_TASK_KIND_HAUL
	):
		return false

	if int(current_task.get("target_object_id", -1)) == target_object_id:
		return true

	current_task["target_object_id"] = target_object_id
	citizen["current_task"] = current_task
	CityCitizenRegistrySystem.get_current_state().citizens[citizen_index] = citizen
	mark_city_citizen_task_changed()
	return true

static func set_city_citizen_task_activity_state(
	values: Dictionary
) -> bool:
	if not values.has("citizen_id") or not values.has("target_tile"):
		push_error(
			"Citizen task activity state requires citizen_id and target_tile."
		)
		return false

	var raw_target_tile = values["target_tile"]
	var raw_previous_target_tile = values.get(
		"previous_target_tile",
		CityCitizens.INVALID_CITY_TILE_POSITION
	)

	if not raw_target_tile is Vector2i:
		push_error(
			"Citizen task activity target_tile must be Vector2i."
		)
		return false

	if not raw_previous_target_tile is Vector2i:
		push_error(
			"Citizen task activity previous_target_tile must be Vector2i."
		)
		return false

	var citizen_id := int(values["citizen_id"])
	var target_tile: Vector2i = raw_target_tile
	var previous_target_tile: Vector2i = raw_previous_target_tile
	var next_action_world_minute := int(
		values.get(
			"next_action_world_minute",
			CityCitizens.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
		)
	)
	var relocation_count := int(
		values.get("relocation_count", -1)
	)
	var citizen_index := CityCitizenRegistrySystem.get_city_citizen_index_by_id(
		citizen_id
	)

	if citizen_index < 0:
		return false

	var raw_citizen = CityCitizenRegistrySystem.get_current_state().citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return false

	var citizen: Dictionary = raw_citizen
	var raw_current_task = citizen.get(
		"current_task",
		{}
	)

	if not raw_current_task is Dictionary:
		return false

	var current_task: Dictionary = (
		raw_current_task.duplicate(true)
	)

	if (
		str(current_task.get("kind", ""))
		== CityCitizens.CITY_CITIZEN_TASK_KIND_NONE
	):
		return false
	var stored_relocation_count := maxi(
		int(current_task.get("relocation_count", 0)),
		0
	)
	var resolved_relocation_count := relocation_count

	if resolved_relocation_count < 0:
		resolved_relocation_count = stored_relocation_count
	if (
		current_task.get(
			"target_tile",
			CityCitizens.INVALID_CITY_TILE_POSITION
		) == target_tile
		and current_task.get(
			"previous_target_tile",
			CityCitizens.INVALID_CITY_TILE_POSITION
		) == previous_target_tile
		and int(
			current_task.get(
				"next_action_world_minute",
				CityCitizens.INVALID_CITY_CITIZEN_TASK_ACTION_WORLD_MINUTE
			)
		) == next_action_world_minute
		and stored_relocation_count == resolved_relocation_count
	):
		return true

	current_task["target_tile"] = target_tile
	current_task["previous_target_tile"] = (
		previous_target_tile
	)
	current_task["next_action_world_minute"] = (
		next_action_world_minute
	)
	current_task["relocation_count"] = (
		resolved_relocation_count
	)

	citizen["current_task"] = current_task
	CityCitizenRegistrySystem.get_current_state().citizens[citizen_index] = citizen
	mark_city_citizen_task_changed()

	return true

static func clear_city_citizen_task(
	citizen_id: int,
	requesting_source: String = CityCitizens.CITY_CITIZEN_TASK_SOURCE_NONE
) -> bool:
	if not CityCitizens.is_valid_city_citizen_task_source(
		requesting_source
	):
		return false

	var citizen_index := CityCitizenRegistrySystem.get_city_citizen_index_by_id(
		citizen_id
	)

	if citizen_index < 0:
		return false

	var raw_citizen = CityCitizenRegistrySystem.get_current_state().citizens[citizen_index]

	if not raw_citizen is Dictionary:
		return false

	var citizen: Dictionary = raw_citizen
	var raw_current_task = citizen.get("current_task", {})

	if raw_current_task is Dictionary:
		var current_task: Dictionary = raw_current_task

		if (
			bool(current_task.get("player_locked", false))
			and requesting_source
			!= CityCitizens.CITY_CITIZEN_TASK_SOURCE_PLAYER
		):
			return false

	var empty_task := CityCitizens.make_city_citizen_task()
	var active_reservation_id := (
		CityLogisticsSystem.get_city_haul_reservation_id_for_citizen(citizen_id)
	)

	if active_reservation_id > 0:
		CityLogisticsSystem.release_city_haul_reservation(active_reservation_id)

	if (
		raw_current_task is Dictionary
		and raw_current_task == empty_task
	):
		if _remove_city_active_task_id(citizen_id):
			mark_city_citizen_task_changed()
		return true

	var current_task_kind := CityCitizens.CITY_CITIZEN_TASK_KIND_NONE

	if raw_current_task is Dictionary:
		current_task_kind = str(
			raw_current_task.get(
				"kind",
				CityCitizens.CITY_CITIZEN_TASK_KIND_NONE
			)
		)

	if current_task_kind == CityCitizens.CITY_CITIZEN_TASK_KIND_PLAYER_COMMAND:
		CityWorkSystem.release_city_player_command_claim(
			int(raw_current_task.get("target_object_id", -1)),
			citizen_id
		)

	if current_task_kind == CityCitizens.CITY_CITIZEN_TASK_KIND_HAUL:
		if (
			CityCitizenInventorySystem.get_city_citizen_haul_cargo_amount(
				citizen_id
			) > 0
		):
			var raw_haul = citizen.get("current_haul", {})
			var current_haul := (
				CityCitizens.make_city_citizen_haul()
			)

			if raw_haul is Dictionary:
				current_haul = (
					CityCitizens.make_city_citizen_haul(
						raw_haul
					)
				)

			current_haul["phase"] = (
				CityCitizens.CITY_CITIZEN_HAUL_PHASE_RETARGETING
			)
			current_haul["reservation_id"] = (
				CityCitizens.INVALID_CITY_CITIZEN_HAUL_RESERVATION_ID
			)
			current_haul["destination_tile"] = (
				CityCitizens.INVALID_CITY_TILE_POSITION
			)
			citizen["current_haul"] = current_haul
		else:
			CityCitizens.reset_city_citizen_haul_runtime_state(
				citizen
			)

	citizen["current_task"] = empty_task
	CityCitizenRegistrySystem.get_current_state().citizens[citizen_index] = citizen
	_remove_city_active_task_id(citizen_id)
	mark_city_citizen_task_changed()

	return true
