extends RefCounted
class_name CitySettlementRuntimeBootstrap

# Explicit, non-owning orchestration for one settlement's existing simulation
# owners. This service performs compatibility repair and state migration without
# discovering a target through the globally selected/presented city.

const FAILURE_NONE := ""
const FAILURE_INVALID_CONTEXT := "invalid_context"
const FAILURE_UNSUPPORTED_CONTEXT := "unsupported_context"
const FAILURE_STALE_CONTEXT := "stale_context"
const FAILURE_MISSING_CITY_WORLD := "missing_city_world"
const FAILURE_INVALID_CITY_WORLD := "invalid_city_world"
const FAILURE_INVALID_CITY_SEED := "invalid_city_seed"
const FAILURE_MISSING_DOMAIN_OWNER := "missing_domain_owner"
const FAILURE_INVALID_CITY_RUNTIME := "invalid_city_runtime"
const FAILURE_INVALID_FOUNDATION_FOOTPRINT := (
	"invalid_foundation_footprint"
)
const FAILURE_INVALID_FOUNDATION_IDENTITY := "invalid_foundation_identity"
const FAILURE_AMBIGUOUS_FOUNDATION_KEEP := "ambiguous_foundation_keep"
const FAILURE_OCCUPIED_FOUNDATION_OBJECT_ID := (
	"occupied_foundation_object_id"
)
const FAILURE_FOUNDATION_RECOVERY_FAILED := "foundation_recovery_failed"
const FAILURE_STARTING_POPULATION_CONFLICT := (
	"starting_population_conflict"
)
const FAILURE_STARTING_POPULATION_INITIALIZATION_FAILED := (
	"starting_population_initialization_failed"
)
const FAILURE_PLAYER_CAPITAL_MIRROR_SYNC_FAILED := (
	"player_capital_mirror_sync_failed"
)


static func ensure_ready(
	settlement_context: SettlementSimulationContext
) -> Dictionary:
	var result := _make_result()

	if settlement_context == null or not settlement_context.is_valid():
		return _fail(
			result,
			FAILURE_INVALID_CONTEXT,
			"City runtime bootstrap requires a valid settlement context."
		)

	result["settlement_id"] = settlement_context.settlement_id

	if not settlement_context.supports_city_simulation():
		return _fail(
			result,
			FAILURE_UNSUPPORTED_CONTEXT,
			"Settlement "
			+ str(settlement_context.settlement_id)
			+ " does not own a City simulation backend."
		)

	# Resolve the requested authority exactly once from the supplied context.
	var raw_city_state = settlement_context.get_city_simulation_state()
	if not raw_city_state is CitySettlementSimulationState:
		return _fail(
			result,
			FAILURE_UNSUPPORTED_CONTEXT,
			"Settlement context did not expose its City simulation state."
		)

	var city_state: CitySettlementSimulationState = raw_city_state
	result["state_instance_id"] = city_state.get_instance_id()

	var registered_state = WorldPoliticalState.get_city_simulation_state(
		settlement_context.settlement_id
	)
	if not is_same(registered_state, city_state):
		return _fail(
			result,
			FAILURE_STALE_CONTEXT,
			"Settlement context no longer matches the registered City state."
		)

	var missing_owner := _get_missing_domain_owner_name(city_state)
	if not missing_owner.is_empty():
		return _fail(
			result,
			FAILURE_MISSING_DOMAIN_OWNER,
			"City runtime is missing its " + missing_owner + " owner."
		)

	if not city_state.city_world is WorldData:
		return _fail(
			result,
			FAILURE_MISSING_CITY_WORLD,
			"City runtime bootstrap requires the target settlement's world."
		)

	var city_world: WorldData = city_state.city_world
	if (
		city_world.width <= 0
		or city_world.height <= 0
		or city_world.tiles.size() != city_world.height
	):
		return _fail(
			result,
			FAILURE_INVALID_CITY_WORLD,
			"Target City world has invalid dimensions or row storage."
		)

	if (
		city_state.city_seed == 0
		or city_world.seed == 0
		or city_state.city_seed != city_world.seed
	):
		return _fail(
			result,
			FAILURE_INVALID_CITY_SEED,
			"Target City seed must be nonzero and match its City world."
		)

	if city_state.is_city_founded() and not city_state.has_city_foundation_footprint():
		if not _is_exact_player_capital_target(
			settlement_context,
			city_state
		):
			return _fail(
				result,
				FAILURE_INVALID_FOUNDATION_FOOTPRINT,
				"Founded settlement has no valid foundation footprint; "
				+ "automatic reset is restricted to the exact player capital."
			)

		if not WorldPoliticalState.reset_city_simulation_runtime_state(
			settlement_context.settlement_id
		):
			return _fail(
				result,
				FAILURE_INVALID_FOUNDATION_FOOTPRINT,
				"Could not reset the exact invalid player-capital runtime."
			)

		_record_change(result, "legacy_foundation_reset", 1)
		_record_warning(
			result,
			"Reset invalid legacy player-capital state with no foundation footprint."
		)

		missing_owner = _get_missing_domain_owner_name(city_state)
		if not missing_owner.is_empty():
			return _fail(
				result,
				FAILURE_MISSING_DOMAIN_OWNER,
				"Targeted reset did not restore the " + missing_owner + " owner."
			)

	if city_state.is_city_founded():
		var runtime_error := _get_founded_runtime_error(
			settlement_context,
			city_state,
			city_world
		)
		if not runtime_error.is_empty():
			return _fail(
				result,
				FAILURE_INVALID_CITY_RUNTIME,
				runtime_error
			)

		if not _ensure_foundation_keep(city_state, result):
			return result

		if not _ensure_starting_population(city_state, result):
			return result

	_run_explicit_state_migrations(city_state, city_world, result)

	if _is_exact_player_capital_target(settlement_context, city_state):
		var mirror_before := [
			WorldData.player_city_founded,
			WorldData.player_city_foundation_top_left,
			WorldData.player_city_foundation_size,
		]
		if not WorldData.synchronize_player_city_mirrors_for_city_state(
			settlement_context,
			city_state
		):
			return _fail(
				result,
				FAILURE_PLAYER_CAPITAL_MIRROR_SYNC_FAILED,
				"Could not synchronize the exact player-capital compatibility mirrors."
			)

		var mirror_after := [
			WorldData.player_city_founded,
			WorldData.player_city_foundation_top_left,
			WorldData.player_city_foundation_size,
		]
		if mirror_before != mirror_after:
			_record_change(result, "player_capital_mirrors", 1)

	result["success"] = true
	return result


static func _make_result() -> Dictionary:
	return {
		"success": false,
		"settlement_id": -1,
		"state_instance_id": 0,
		"changed_domains": {},
		"changed_count": 0,
		"warnings": [],
		"errors": [],
		"failure_code": FAILURE_NONE,
	}


static func _fail(
	result: Dictionary,
	failure_code: String,
	error_message: String
) -> Dictionary:
	result["success"] = false
	result["failure_code"] = failure_code
	var errors: Array = result.get("errors", [])
	errors.append(error_message)
	result["errors"] = errors
	return result


static func _record_warning(result: Dictionary, warning: String) -> void:
	var warnings: Array = result.get("warnings", [])
	warnings.append(warning)
	result["warnings"] = warnings


static func _record_change(
	result: Dictionary,
	domain: String,
	changed_count: int
) -> void:
	if changed_count <= 0:
		return

	var changed_domains: Dictionary = result.get("changed_domains", {})
	changed_domains[domain] = (
		int(changed_domains.get(domain, 0)) + changed_count
	)
	result["changed_domains"] = changed_domains
	result["changed_count"] = int(result.get("changed_count", 0)) + changed_count


static func _is_exact_player_capital_target(
	settlement_context: SettlementSimulationContext,
	city_state: CitySettlementSimulationState
) -> bool:
	if (
		settlement_context == null
		or city_state == null
		or not settlement_context.is_player_polity
		or not settlement_context.is_capital
		or settlement_context.polity_id != WorldPoliticalState.player_polity_id
		or settlement_context.settlement_id
		!= WorldPoliticalState.get_player_capital_settlement_id()
	):
		return false

	return is_same(
		WorldPoliticalState.get_city_simulation_state(
			settlement_context.settlement_id
		),
		city_state
	)


static func _get_missing_domain_owner_name(
	city_state: CitySettlementSimulationState
) -> String:
	var owners := {
		"object state": city_state.object_state,
		"resource-accounting state": city_state.resource_accounting_state,
		"citizen registry": city_state.citizen_registry_state,
		"assignment state": city_state.assignment_state,
		"workplace state": city_state.workplace_state,
		"citizen spatial state": city_state.citizen_spatial_state,
		"citizen movement runtime": city_state.citizen_movement_runtime_state,
		"citizen task runtime": city_state.citizen_task_runtime_state,
		"citizen decision runtime": city_state.citizen_decision_runtime_state,
		"work state": city_state.work_state,
		"logistics state": city_state.logistics_state,
		"construction state": city_state.construction_state,
		"navigation state": city_state.navigation_state,
	}

	for owner_name in owners:
		if owners[owner_name] == null:
			return str(owner_name)

	return ""


static func _get_founded_runtime_error(
	settlement_context: SettlementSimulationContext,
	city_state: CitySettlementSimulationState,
	city_world: WorldData
) -> String:
	var runtime_data := city_state.city_runtime_data
	var runtime_seed = runtime_data.get("city_world_seed")
	var runtime_map_size = runtime_data.get("city_map_size")
	var culture_id_value = runtime_data.get(
		"primary_culture_id",
		WorldData.INVALID_CULTURE_ID
	)
	if (
		not runtime_seed is int
		or int(runtime_seed) != city_state.city_seed
	):
		return "Founded City runtime seed does not match its target state."
	if (
		not runtime_map_size is Vector2i
		or runtime_map_size != Vector2i(city_world.width, city_world.height)
	):
		return "Founded City runtime map size does not match its target world."
	if (
		not culture_id_value is int
		or not WorldData.has_culture_id(culture_id_value)
	):
		return "Founded City runtime has no valid primary culture."

	var runtime_settlement_id = runtime_data.get(
		"id",
		settlement_context.settlement_id
	)
	if (
		not runtime_settlement_id is int
		or int(runtime_settlement_id) != settlement_context.settlement_id
	):
		return "Founded City runtime identity does not match its context."

	return ""


static func _ensure_foundation_keep(
	city_state: CitySettlementSimulationState,
	result: Dictionary
) -> bool:
	var runtime_data := city_state.city_runtime_data
	var top_left_value = runtime_data.get("foundation_top_left")
	var size_value = runtime_data.get("foundation_size")
	var object_id_value = runtime_data.get("foundation_object_id")
	var owner_value = runtime_data.get("foundation_object_owner")
	var expected_size := CityObjectCatalog.get_city_object_size_for_type(
		CityObjectCatalog.CITY_OBJECT_CITY_CENTER
	)

	if (
		not top_left_value is Vector2i
		or not size_value is Vector2i
		or not object_id_value is int
		or int(object_id_value) <= 0
		or not owner_value is String
		or str(owner_value).strip_edges().is_empty()
		or size_value != expected_size
	):
		_fail(
			result,
			FAILURE_INVALID_FOUNDATION_IDENTITY,
			"Founded City runtime has invalid Keep identity metadata."
		)
		return false

	var top_left: Vector2i = top_left_value
	var size_tiles: Vector2i = size_value
	if not _rectangle_fits_world(top_left, size_tiles, city_state.city_world):
		_fail(
			result,
			FAILURE_INVALID_FOUNDATION_IDENTITY,
			"Founded City Keep footprint is outside its target world."
		)
		return false

	var foundation_object_id: int = object_id_value
	var foundation_owner: String = owner_value
	var keep_count := 0
	var exact_keep: Dictionary = {}

	for raw_city_object in city_state.object_state.objects:
		if (
			not raw_city_object is Dictionary
			or str(raw_city_object.get("type", ""))
			!= CityObjectCatalog.CITY_OBJECT_CITY_CENTER
		):
			continue

		keep_count += 1
		if (
			int(raw_city_object.get("id", -1)) == foundation_object_id
			and str(raw_city_object.get("owner", "")) == foundation_owner
			and raw_city_object.get("top_left") == top_left
			and raw_city_object.get("size") == size_tiles
		):
			exact_keep = raw_city_object

	if keep_count > 0:
		if keep_count != 1 or exact_keep.is_empty():
			_fail(
				result,
				FAILURE_AMBIGUOUS_FOUNDATION_KEEP,
				"Existing City Keep does not match the target foundation identity."
			)
			return false

		var index_before := city_state.object_state.object_index_by_id.duplicate()
		var indexed_keep := CityObjectSystem.get_city_object_by_id_for_city_state(
			city_state,
			foundation_object_id
		)
		if indexed_keep.is_empty():
			_fail(
				result,
				FAILURE_AMBIGUOUS_FOUNDATION_KEEP,
				"Exact City Keep could not be resolved through its target registry."
			)
			return false
		if index_before != city_state.object_state.object_index_by_id:
			_record_change(result, "foundation_object_index", 1)
		return true

	if not CityObjectSystem.get_city_object_by_id_for_city_state(
		city_state,
		foundation_object_id
	).is_empty():
		_fail(
			result,
			FAILURE_OCCUPIED_FOUNDATION_OBJECT_ID,
			"Saved City Keep ID is occupied by another target-local object."
		)
		return false

	var recovered_keep := (
		CityObjectSystem.register_recovered_city_foundation_object_for_city_state(
			city_state,
			{
				"object_type": CityObjectCatalog.CITY_OBJECT_CITY_CENTER,
				"top_left": top_left,
				"size_tiles": size_tiles,
				"object_owner": foundation_owner,
				"city_world": city_state.city_world,
			}
		)
	)
	if recovered_keep.is_empty():
		_fail(
			result,
			FAILURE_FOUNDATION_RECOVERY_FAILED,
			"Could not recover the target settlement's missing City Keep."
		)
		return false

	_record_change(result, "foundation_keep", 1)
	return true


static func _rectangle_fits_world(
	top_left: Vector2i,
	size_tiles: Vector2i,
	city_world: WorldData
) -> bool:
	return (
		top_left.x >= 0
		and top_left.y >= 0
		and size_tiles.x > 0
		and size_tiles.y > 0
		and top_left.x + size_tiles.x <= city_world.width
		and top_left.y + size_tiles.y <= city_world.height
	)


static func _ensure_starting_population(
	city_state: CitySettlementSimulationState,
	result: Dictionary
) -> bool:
	var registry_state := city_state.citizen_registry_state
	if registry_state.starting_population_initialized:
		return true

	if not registry_state.citizens.is_empty():
		_fail(
			result,
			FAILURE_STARTING_POPULATION_CONFLICT,
			"Unmarked starting population cannot be created over existing citizens."
		)
		return false

	var created_count := (
		CityCitizenRegistrySystem.initialize_starting_city_population_for_city_state(
			city_state
		)
	)
	if (
		created_count != CityCitizenRegistrySystem.STARTING_CITY_POPULATION
		or not registry_state.starting_population_initialized
	):
		_fail(
			result,
			FAILURE_STARTING_POPULATION_INITIALIZATION_FAILED,
			"Starting population initialization failed without committing a partial registry."
		)
		return false

	_record_change(result, "starting_population", created_count)
	return true


static func _run_explicit_state_migrations(
	city_state: CitySettlementSimulationState,
	city_world: WorldData,
	result: Dictionary
) -> void:
	var fingerprint_before := _get_city_maintenance_fingerprint(city_state)
	var reported_count := (
		CityCitizenSpatialSystem
		.ensure_city_citizen_spatial_state_for_city_state(
			city_state,
			city_world
		)
	)
	_record_migration_change(
		result,
		city_state,
		"citizen_spatial",
		reported_count,
		fingerprint_before
	)

	fingerprint_before = _get_city_maintenance_fingerprint(city_state)
	reported_count = (
		CityCitizenRegistrySystem
		.ensure_city_citizen_demographic_state_for_city_state(city_state)
	)
	_record_migration_change(
		result,
		city_state,
		"citizen_demographics",
		reported_count,
		fingerprint_before
	)

	fingerprint_before = _get_city_maintenance_fingerprint(city_state)
	reported_count = (
		CityCitizenInventorySystem
		.ensure_city_citizen_inventory_state_for_city_state(city_state)
	)
	_record_migration_change(
		result,
		city_state,
		"citizen_inventory",
		reported_count,
		fingerprint_before
	)

	fingerprint_before = _get_city_maintenance_fingerprint(city_state)
	reported_count = (
		CitizenNeedsSystem
		.ensure_city_citizen_need_state_for_city_state(city_state)
	)
	_record_migration_change(
		result,
		city_state,
		"citizen_needs",
		reported_count,
		fingerprint_before
	)

	fingerprint_before = _get_city_maintenance_fingerprint(city_state)
	reported_count = (
		CityCitizenTaskRuntimeSystem
		.ensure_city_citizen_task_state_for_city_state(city_state)
	)
	_record_migration_change(
		result,
		city_state,
		"citizen_tasks",
		reported_count,
		fingerprint_before
	)

	fingerprint_before = _get_city_maintenance_fingerprint(city_state)
	reported_count = (
		CityCitizenMovementRuntimeSystem
		.ensure_city_citizen_movement_state_for_city_state(city_state)
	)
	_record_migration_change(
		result,
		city_state,
		"citizen_movement",
		reported_count,
		fingerprint_before
	)

	fingerprint_before = _get_city_maintenance_fingerprint(city_state)
	reported_count = (
		CityAssignmentSystem
		.ensure_city_citizen_assignment_state_for_city_state(city_state)
	)
	_record_migration_change(
		result,
		city_state,
		"citizen_assignments",
		reported_count,
		fingerprint_before
	)

	fingerprint_before = _get_city_maintenance_fingerprint(city_state)
	reported_count = (
		CityEmploymentSystem
		.ensure_workplace_staffing_state_for_city_state(city_state)
	)
	_record_migration_change(
		result,
		city_state,
		"workplace_state",
		reported_count,
		fingerprint_before
	)


static func _record_migration_change(
	result: Dictionary,
	city_state: CitySettlementSimulationState,
	domain: String,
	reported_count: int,
	fingerprint_before: int
) -> void:
	if fingerprint_before == _get_city_maintenance_fingerprint(city_state):
		return

	_record_change(result, domain, maxi(reported_count, 1))


static func _get_city_maintenance_fingerprint(
	city_state: CitySettlementSimulationState
) -> int:
	var owner_fingerprints: Array = []
	for owner in [
		city_state.object_state,
		city_state.resource_accounting_state,
		city_state.citizen_registry_state,
		city_state.assignment_state,
		city_state.workplace_state,
		city_state.citizen_spatial_state,
		city_state.citizen_movement_runtime_state,
		city_state.citizen_task_runtime_state,
		city_state.citizen_decision_runtime_state,
		city_state.work_state,
		city_state.logistics_state,
		city_state.construction_state,
		city_state.navigation_state,
	]:
		owner_fingerprints.append(_get_script_state_fingerprint(owner))

	return hash([
		city_state.city_seed,
		city_state.city_runtime_data,
		owner_fingerprints,
	])


static func _get_script_state_fingerprint(owner: Object) -> int:
	var values: Array = []
	for property in owner.get_property_list():
		var usage := int(property.get("usage", 0))
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue

		var property_name = property.get("name")
		values.append([property_name, owner.get(property_name)])

	return hash(values)
