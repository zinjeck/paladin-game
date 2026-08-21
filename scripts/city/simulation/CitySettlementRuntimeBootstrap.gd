extends RefCounted
class_name CitySettlementRuntimeBootstrap

# Coordinates runtime repair and data-shape migrations for one explicit
# settlement. This service never owns gameplay data and never chooses a target
# through presentation state. Every mutation is routed through the state held
# by the supplied SettlementSimulationContext.

const FAILURE_NONE := "none"
const FAILURE_INVALID_CONTEXT := "invalid_context"
const FAILURE_UNREGISTERED_CONTEXT := "unregistered_context"
const FAILURE_MISSING_CITY_STATE := "missing_city_state"
const FAILURE_MISSING_CITY_WORLD := "missing_city_world"
const FAILURE_INVALID_CITY_WORLD := "invalid_city_world"
const FAILURE_INVALID_CITY_SEED := "invalid_city_seed"
const FAILURE_CITY_SEED_MISMATCH := "city_seed_mismatch"
const FAILURE_INVALID_RUNTIME_DATA := "invalid_runtime_data"
const FAILURE_FOUNDATION_RESET := "foundation_reset_failed"
const FAILURE_FOUNDATION_RECOVERY := "foundation_recovery_failed"
const FAILURE_STARTING_POPULATION := "starting_population_failed"
const FAILURE_PLAYER_CAPITAL_MIRROR := "player_capital_mirror_failed"


static func ensure_ready(
	settlement_context: SettlementSimulationContext
) -> Dictionary:
	var result := _make_result(settlement_context)

	if (
		settlement_context == null
		or not settlement_context.is_valid()
		or not settlement_context.supports_city_simulation()
	):
		return _fail(
			result,
			FAILURE_INVALID_CONTEXT,
			"City runtime bootstrap requires a valid city settlement context."
		)

	if not WorldPoliticalState.is_registered_settlement_context(
		settlement_context
	):
		return _fail(
			result,
			FAILURE_UNREGISTERED_CONTEXT,
			"City runtime bootstrap rejected a stale or unregistered context."
		)

	# Resolve the authoritative aggregate exactly once from the supplied context.
	# All remaining work retains this instance and passes it explicitly.
	var city_state: CitySettlementSimulationState = settlement_context.get_city_simulation_state()
	if city_state == null:
		return _fail(
			result,
			FAILURE_MISSING_CITY_STATE,
			"The settlement context has no city simulation state."
		)

	result["state_instance_id"] = city_state.get_instance_id()

	if city_state.city_world == null:
		return _fail(
			result,
			FAILURE_MISSING_CITY_WORLD,
			"The target settlement has no prepared city world."
		)

	if city_state.city_world.width <= 0 or city_state.city_world.height <= 0:
		return _fail(
			result,
			FAILURE_INVALID_CITY_WORLD,
			"The target settlement city world has invalid dimensions."
		)

	if city_state.city_seed == 0:
		return _fail(
			result,
			FAILURE_INVALID_CITY_SEED,
			"The target settlement has no valid city seed."
		)

	if (
		city_state.city_world.seed != 0
		and city_state.city_world.seed != city_state.city_seed
	):
		return _fail(
			result,
			FAILURE_CITY_SEED_MISMATCH,
			"The target settlement city world and city seed disagree."
		)

	if (
		city_state.is_city_founded()
		and not city_state.has_city_foundation_footprint()
	):
		if not WorldPoliticalState.reset_city_simulation_runtime_state(
			settlement_context.settlement_id
		):
			return _fail(
				result,
				FAILURE_FOUNDATION_RESET,
				"The invalid legacy foundation state could not be reset locally."
			)

		_record_change(result, "foundation_runtime_reset", 1)
		_add_warning(
			result,
			"Cleared invalid founded runtime data with no valid foundation footprint."
		)

	var runtime_error := _get_runtime_prerequisite_error(
		settlement_context,
		city_state
	)
	if not runtime_error.is_empty():
		return _fail(
			result,
			FAILURE_INVALID_RUNTIME_DATA,
			runtime_error
		)

	if city_state.is_city_founded():
		var foundation_result := _ensure_foundation_object(city_state)
		if not bool(foundation_result.get("success", false)):
			return _fail(
				result,
				FAILURE_FOUNDATION_RECOVERY,
				str(foundation_result.get(
					"error",
					"The target settlement foundation object could not be recovered."
				))
			)

		_record_change(
			result,
			"foundation_object_recovered",
			int(foundation_result.get("changed_count", 0))
		)

		if not _ensure_starting_population(city_state, result):
			return _fail(
				result,
				FAILURE_STARTING_POPULATION,
				"The founded settlement could not establish its starting population."
			)

	_record_change(
		result,
		"citizen_demographics",
		CityCitizenRegistrySystem
			.ensure_city_citizen_demographic_state_for_city_state(city_state)
	)
	_record_change(
		result,
		"citizen_spatial_state",
		CityCitizenSpatialSystem
			.ensure_city_citizen_spatial_state_for_city_state(
				city_state,
				city_state.city_world
			)
	)
	_record_change(
		result,
		"citizen_inventory_state",
		CityCitizenInventorySystem
			.ensure_city_citizen_inventory_state_for_city_state(city_state)
	)
	_record_change(
		result,
		"citizen_need_state",
		CitizenNeedsSystem.ensure_city_citizen_need_state_for_city_state(
			city_state
		)
	)
	_record_change(
		result,
		"citizen_task_state",
		CityCitizenTaskRuntimeSystem
			.ensure_city_citizen_task_state_for_city_state(city_state)
	)
	_record_change(
		result,
		"citizen_movement_state",
		CityCitizenMovementRuntimeSystem
			.ensure_city_citizen_movement_state_for_city_state(city_state)
	)
	_record_change(
		result,
		"citizen_assignment_state",
		CityAssignmentSystem
			.ensure_city_citizen_assignment_state_for_city_state(city_state)
	)
	_record_change(
		result,
		"workplace_staffing_state",
		CityEmploymentSystem.ensure_workplace_staffing_state_for_city_state(
			city_state
		)
	)

	if not _synchronize_player_capital_mirrors(
		settlement_context,
		city_state,
		result
	):
		return _fail(
			result,
			FAILURE_PLAYER_CAPITAL_MIRROR,
			"The explicit player-capital compatibility mirror could not be synchronized."
		)

	result["success"] = true
	result["failure_code"] = FAILURE_NONE
	return result


static func _get_runtime_prerequisite_error(
	settlement_context: SettlementSimulationContext,
	city_state: CitySettlementSimulationState
) -> String:
	var runtime_data := city_state.city_runtime_data
	for boolean_key in ["founded", "can_build"]:
		if runtime_data.has(boolean_key) and not runtime_data[boolean_key] is bool:
			return (
				"The target settlement runtime field "
				+ boolean_key
				+ " is not boolean."
			)

	if runtime_data.has("id"):
		var runtime_id_value = runtime_data["id"]
		if (
			not runtime_id_value is int
			or runtime_id_value != settlement_context.settlement_id
		):
			return "The target settlement runtime identity does not match its context."

	if runtime_data.has("city_world_seed"):
		var runtime_seed_value = runtime_data["city_world_seed"]
		if (
			not runtime_seed_value is int
			or runtime_seed_value != city_state.city_seed
		):
			return "The target settlement runtime seed does not match its city state."

	if runtime_data.has("city_map_size"):
		var runtime_map_size = runtime_data["city_map_size"]
		if (
			not runtime_map_size is Vector2i
			or runtime_map_size
			!= Vector2i(city_state.city_world.width, city_state.city_world.height)
		):
			return "The target settlement runtime map size does not match its city world."

	if not city_state.is_city_founded():
		return ""

	for required_key in [
		"id",
		"city_world_seed",
		"city_map_size",
		"primary_culture_id",
	]:
		if not runtime_data.has(required_key):
			return (
				"The founded target settlement is missing runtime field "
				+ required_key
				+ "."
			)

	var primary_culture_value = runtime_data["primary_culture_id"]
	if (
		not primary_culture_value is int
		or not WorldData.has_culture_id(primary_culture_value)
	):
		return "The founded target settlement has an invalid primary culture."

	return ""


static func _make_result(
	settlement_context: SettlementSimulationContext
) -> Dictionary:
	var settlement_id := SettlementData.INVALID_SETTLEMENT_ID
	if settlement_context != null:
		settlement_id = settlement_context.settlement_id

	return {
		"success": false,
		"settlement_id": settlement_id,
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


static func _add_warning(result: Dictionary, warning_message: String) -> void:
	var warnings: Array = result.get("warnings", [])
	warnings.append(warning_message)
	result["warnings"] = warnings


static func _record_change(
	result: Dictionary,
	domain: String,
	changed_count: int
) -> void:
	if changed_count <= 0:
		return

	var changed_domains: Dictionary = result.get("changed_domains", {})
	changed_domains[domain] = int(changed_domains.get(domain, 0)) + changed_count
	result["changed_domains"] = changed_domains
	result["changed_count"] = int(result.get("changed_count", 0)) + changed_count


static func _ensure_starting_population(
	city_state: CitySettlementSimulationState,
	result: Dictionary
) -> bool:
	var registry_state := city_state.citizen_registry_state
	if registry_state.starting_population_initialized:
		return true

	var created_count := (
		CityCitizenRegistrySystem
			.initialize_starting_city_population_for_city_state(city_state)
	)
	if not registry_state.starting_population_initialized:
		return false

	_record_change(result, "starting_population", created_count)
	return true


static func _ensure_foundation_object(
	city_state: CitySettlementSimulationState
) -> Dictionary:
	var top_left = city_state.city_runtime_data.get(
		"foundation_top_left",
		Vector2i(-1, -1)
	)
	var size_tiles = city_state.city_runtime_data.get(
		"foundation_size",
		Vector2i.ZERO
	)
	var foundation_object_id_value = city_state.city_runtime_data.get(
		"foundation_object_id"
	)
	var foundation_object_owner_value = city_state.city_runtime_data.get(
		"foundation_object_owner"
	)
	if (
		not top_left is Vector2i
		or not size_tiles is Vector2i
		or not foundation_object_id_value is int
		or foundation_object_id_value <= 0
		or not foundation_object_owner_value is String
		or foundation_object_owner_value.strip_edges().is_empty()
	):
		return {
			"success": false,
			"error": "The target foundation identity is malformed.",
		}

	var foundation_object_id: int = foundation_object_id_value
	var foundation_object_owner: String = foundation_object_owner_value
	var foundation_count := 0
	var exact_foundation_exists := false

	for raw_city_object in city_state.object_state.objects:
		if (
			not raw_city_object is Dictionary
			or str(raw_city_object.get("type", ""))
			!= CityObjectCatalog.CITY_OBJECT_CITY_CENTER
		):
			continue

		foundation_count += 1
		exact_foundation_exists = (
			exact_foundation_exists
			or (
				int(raw_city_object.get("id", -1)) == foundation_object_id
				and str(raw_city_object.get("owner", ""))
				== foundation_object_owner
				and raw_city_object.get("top_left") == top_left
				and raw_city_object.get("size") == size_tiles
			)
		)

	if foundation_count > 0:
		if foundation_count == 1 and exact_foundation_exists:
			return {"success": true, "changed_count": 0}
		return {
			"success": false,
			"error": "Existing City Keep identity is ambiguous or conflicts with the saved foundation.",
		}

	if not CityObjectSystem.get_city_object_by_id_for_city_state(
		city_state,
		foundation_object_id
	).is_empty():
		return {
			"success": false,
			"error": "The saved foundation object ID is occupied by another object.",
		}

	var foundation_object := (
		CityObjectSystem.register_recovered_city_foundation_object_for_city_state(
			city_state,
			{
				"object_type": CityObjectCatalog.CITY_OBJECT_CITY_CENTER,
				"top_left": top_left,
				"size_tiles": size_tiles,
				"object_owner": foundation_object_owner,
				"city_world": city_state.city_world,
			}
		)
	)
	if foundation_object.is_empty():
		return {
			"success": false,
			"error": "The missing City Keep could not be recovered safely.",
		}

	return {"success": true, "changed_count": 1}


static func _synchronize_player_capital_mirrors(
	settlement_context: SettlementSimulationContext,
	city_state: CitySettlementSimulationState,
	result: Dictionary
) -> bool:
	if not settlement_context.is_player_polity or not settlement_context.is_capital:
		return true

	var mirrors_before := [
		WorldData.player_city_founded,
		WorldData.player_city_foundation_top_left,
		WorldData.player_city_foundation_size,
	]
	if not WorldData.synchronize_player_city_mirrors_for_settlement(
		settlement_context,
		city_state
	):
		return false

	var mirrors_after := [
		WorldData.player_city_founded,
		WorldData.player_city_foundation_top_left,
		WorldData.player_city_foundation_size,
	]
	if mirrors_before != mirrors_after:
		_record_change(result, "player_capital_compatibility_mirrors", 1)

	return true
