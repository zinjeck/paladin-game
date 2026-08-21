extends Node

signal settlement_registry_reset

# Authoritative runtime registry for polity and settlement identity plus each
# settlement's local simulation state. City settlements use instance-owned
# CitySettlementSimulationState as their only simulation backend.

const PolityDataScript = preload(
	"res://scripts/world/simulation/PolityData.gd"
)
const SettlementDataScript = preload(
	"res://scripts/world/simulation/SettlementData.gd"
)
const SettlementSimulationContextScript = preload(
	"res://scripts/world/simulation/SettlementSimulationContext.gd"
)
const CitySettlementSimulationStateScript = preload(
	"res://scripts/city/simulation/CitySettlementSimulationState.gd"
)
const CityObjectStateScript = preload(
	"res://scripts/city/simulation/CityObjectState.gd"
)
const CityResourceAccountingStateScript = preload(
	"res://scripts/city/simulation/CityResourceAccountingState.gd"
)
const CityCitizenRegistryStateScript = preload(
	"res://scripts/city/simulation/CityCitizenRegistryState.gd"
)
const CityAssignmentStateScript = preload(
	"res://scripts/city/simulation/CityAssignmentState.gd"
)
const CityWorkplaceStateScript = preload(
	"res://scripts/city/simulation/CityWorkplaceState.gd"
)
const CityCitizenSpatialStateScript = preload(
	"res://scripts/city/simulation/CityCitizenSpatialState.gd"
)
const CityCitizenMovementRuntimeStateScript = preload(
	"res://scripts/city/simulation/CityCitizenMovementRuntimeState.gd"
)
const CityCitizenTaskRuntimeStateScript = preload(
	"res://scripts/city/simulation/CityCitizenTaskRuntimeState.gd"
)
const CityCitizenDecisionRuntimeStateScript = preload(
	"res://scripts/city/simulation/CityCitizenDecisionRuntimeState.gd"
)
const CityWorkStateScript = preload(
	"res://scripts/city/simulation/CityWorkState.gd"
)
const CityLogisticsStateScript = preload(
	"res://scripts/city/simulation/CityLogisticsState.gd"
)
const CityConstructionStateScript = preload(
	"res://scripts/city/simulation/CityConstructionState.gd"
)
const CityNavigationStateScript = preload(
	"res://scripts/city/simulation/CityNavigationState.gd"
)

var polities_by_id: Dictionary = {}
var settlements_by_id: Dictionary = {}
var settlement_backend_kind_by_id: Dictionary = {}
var settlement_city_state_by_id: Dictionary = {}
var next_polity_id: int = 1
var next_settlement_id: int = 1

var player_polity_id: int = PolityDataScript.INVALID_POLITY_ID
var active_settlement_id: int = SettlementDataScript.INVALID_SETTLEMENT_ID

var _foundation_world_fingerprint: String = ""


func reset_state() -> void:
	_reset_registered_settlement_state()
	settlement_registry_reset.emit()


func _reset_registered_settlement_state() -> void:
	polities_by_id.clear()
	settlements_by_id.clear()
	settlement_backend_kind_by_id.clear()
	settlement_city_state_by_id.clear()
	next_polity_id = 1
	next_settlement_id = 1
	player_polity_id = PolityDataScript.INVALID_POLITY_ID
	active_settlement_id = SettlementDataScript.INVALID_SETTLEMENT_ID
	_foundation_world_fingerprint = ""


func _capture_foundation_transaction_state() -> Dictionary:
	return {
		"polities_by_id": polities_by_id.duplicate(false),
		"settlements_by_id": settlements_by_id.duplicate(false),
		"settlement_backend_kind_by_id": (
			settlement_backend_kind_by_id.duplicate(false)
		),
		"settlement_city_state_by_id": (
			settlement_city_state_by_id.duplicate(false)
		),
		"next_polity_id": next_polity_id,
		"next_settlement_id": next_settlement_id,
		"player_polity_id": player_polity_id,
		"active_settlement_id": active_settlement_id,
		"foundation_world_fingerprint": _foundation_world_fingerprint,
	}


func _restore_foundation_transaction_state(snapshot: Dictionary) -> void:
	var restored_polities: Dictionary = snapshot["polities_by_id"]
	var restored_settlements: Dictionary = snapshot["settlements_by_id"]
	var restored_backend_kinds: Dictionary = snapshot[
		"settlement_backend_kind_by_id"
	]
	var restored_city_states: Dictionary = snapshot[
		"settlement_city_state_by_id"
	]
	polities_by_id.clear()
	polities_by_id.merge(restored_polities, true)
	settlements_by_id.clear()
	settlements_by_id.merge(restored_settlements, true)
	settlement_backend_kind_by_id.clear()
	settlement_backend_kind_by_id.merge(restored_backend_kinds, true)
	settlement_city_state_by_id.clear()
	settlement_city_state_by_id.merge(restored_city_states, true)
	next_polity_id = int(snapshot["next_polity_id"])
	next_settlement_id = int(snapshot["next_settlement_id"])
	player_polity_id = int(snapshot["player_polity_id"])
	active_settlement_id = int(snapshot["active_settlement_id"])
	_foundation_world_fingerprint = str(
		snapshot["foundation_world_fingerprint"]
	)


func synchronize_foundation_with_world_data() -> bool:
	if not WorldData.has_active_world_save() or WorldData.official_world == null:
		if not _foundation_world_fingerprint.is_empty():
			reset_state()
		return false

	var founding_culture_id := WorldData.get_official_founding_culture_id()
	var founding_name := WorldData.get_official_city_name().strip_edges()
	if (
		not WorldData.has_official_founding_identity()
		or founding_culture_id <= 0
		or founding_name.is_empty()
	):
		return false

	var fingerprint := _build_foundation_world_fingerprint()
	if fingerprint == _foundation_world_fingerprint:
		return validate_registry_integrity()

	var previous_state := _capture_foundation_transaction_state()

	# Build a fresh registered owner. City preparation installs its generated
	# world into that owner through the explicit settlement context after this
	# registry transaction succeeds; no pre-context gameplay state is adopted.
	# Do not emit a reset signal until commit, so a failed rebuild is externally
	# atomic as well as retryable inside this registry.
	_reset_registered_settlement_state()

	var player_polity := create_polity({
		"name": founding_name,
		"polity_type": PolityDataScript.POLITY_TYPE_CHIEFDOM,
		"primary_culture_id": founding_culture_id,
	})
	if player_polity.is_empty():
		_restore_foundation_transaction_state(previous_state)
		return false

	var capital := create_settlement({
		"name": founding_name,
		"settlement_type": SettlementDataScript.SETTLEMENT_TYPE_CITY,
		"polity_id": int(player_polity["id"]),
		"world_region_top_left": WorldData.official_selected_region_top_left,
		"world_region_center": WorldData.official_selected_region_center,
		"world_region_size": WorldData.official_region_size,
		"simulation_backend_kind": (
			SettlementSimulationContextScript
			.BACKEND_CITY_SETTLEMENT_STATE
		),
	})
	if capital.is_empty():
		_restore_foundation_transaction_state(previous_state)
		return false

	if not set_polity_capital(
		int(player_polity["id"]),
		int(capital["id"])
	):
		_restore_foundation_transaction_state(previous_state)
		return false

	player_polity_id = int(player_polity["id"])
	var capital_settlement_id := int(capital["id"])
	active_settlement_id = capital_settlement_id

	var capital_state: CitySettlementSimulationState = (
		get_city_simulation_state(capital_settlement_id)
	)
	if capital_state == null:
		_restore_foundation_transaction_state(previous_state)
		return false

	if not validate_registry_integrity():
		_restore_foundation_transaction_state(previous_state)
		return false

	_foundation_world_fingerprint = fingerprint
	settlement_registry_reset.emit()
	return true


func create_polity(values: Dictionary) -> Dictionary:
	var polity_values := values.duplicate(true)
	polity_values["id"] = next_polity_id
	polity_values["accepted_culture_ids"] = polity_values.get(
		"accepted_culture_ids",
		[]
	)
	polity_values["settlement_ids"] = polity_values.get(
		"settlement_ids",
		[]
	)
	polity_values["capital_settlement_id"] = polity_values.get(
		"capital_settlement_id",
		PolityDataScript.INVALID_SETTLEMENT_ID
	)
	polity_values["ruler_citizen_id"] = polity_values.get(
		"ruler_citizen_id",
		PolityDataScript.INVALID_CITIZEN_ID
	)

	var polity := PolityDataScript.make_polity(polity_values)
	if polity.is_empty():
		return {}

	var polity_id: int = polity["id"]
	polities_by_id[polity_id] = polity
	next_polity_id = polity_id + 1
	return polity.duplicate(true)


func create_settlement(values: Dictionary) -> Dictionary:
	var settlement_values := values.duplicate(true)
	var polity_id := int(
		settlement_values.get("polity_id", PolityDataScript.INVALID_POLITY_ID)
	)
	if not polities_by_id.has(polity_id):
		push_error(
			"WorldPoliticalState cannot create a settlement for an unknown polity."
		)
		return {}

	var backend_kind := str(
		settlement_values.get(
			"simulation_backend_kind",
			SettlementSimulationContextScript.BACKEND_NONE
		)
	)
	if not _is_valid_backend_kind(backend_kind):
		push_error(
			"WorldPoliticalState received an unknown settlement simulation backend."
		)
		return {}

	settlement_values.erase("simulation_backend_kind")
	settlement_values["id"] = next_settlement_id
	settlement_values["parent_city_id"] = settlement_values.get(
		"parent_city_id",
		SettlementDataScript.INVALID_SETTLEMENT_ID
	)
	settlement_values["governor_citizen_id"] = settlement_values.get(
		"governor_citizen_id",
		SettlementDataScript.INVALID_CITIZEN_ID
	)

	var settlement := SettlementDataScript.make_settlement(settlement_values)
	if settlement.is_empty():
		return {}
	if not _is_settlement_parent_relationship_valid(settlement):
		push_error(
			"WorldPoliticalState received an invalid settlement parent-city relationship."
		)
		return {}
	if (
		backend_kind
		== SettlementSimulationContextScript.BACKEND_CITY_SETTLEMENT_STATE
		and str(settlement["settlement_type"])
		!= SettlementDataScript.SETTLEMENT_TYPE_CITY
	):
		push_error(
			"Only city settlements may own a city-settlement simulation backend."
		)
		return {}

	var settlement_id: int = settlement["id"]
	settlements_by_id[settlement_id] = settlement
	settlement_backend_kind_by_id[settlement_id] = backend_kind

	if (
		backend_kind
		== SettlementSimulationContextScript.BACKEND_CITY_SETTLEMENT_STATE
	):
		settlement_city_state_by_id[settlement_id] = (
			CitySettlementSimulationStateScript.new()
		)

	next_settlement_id = settlement_id + 1

	var polity: Dictionary = polities_by_id[polity_id]
	var settlement_ids: Array = polity.get("settlement_ids", []).duplicate()
	if not settlement_ids.has(settlement_id):
		settlement_ids.append(settlement_id)
	polity["settlement_ids"] = settlement_ids
	polities_by_id[polity_id] = polity

	return settlement.duplicate(true)


func set_polity_capital(polity_id: int, settlement_id: int) -> bool:
	if not polities_by_id.has(polity_id):
		return false
	if not settlements_by_id.has(settlement_id):
		return false

	var settlement: Dictionary = settlements_by_id[settlement_id]
	if int(settlement.get("polity_id", PolityDataScript.INVALID_POLITY_ID)) != polity_id:
		return false
	if (
		str(settlement.get("settlement_type", ""))
		!= SettlementDataScript.SETTLEMENT_TYPE_CITY
	):
		return false

	var polity: Dictionary = polities_by_id[polity_id]
	var settlement_ids: Array = polity.get("settlement_ids", [])
	if not settlement_ids.has(settlement_id):
		return false

	polity["capital_settlement_id"] = settlement_id
	polities_by_id[polity_id] = polity
	return true


func set_active_settlement(settlement_id: int) -> bool:
	if not settlements_by_id.has(settlement_id):
		return false
	if settlement_id == active_settlement_id:
		return true

	active_settlement_id = settlement_id
	return true


func set_settlement_simulation_backend(
	settlement_id: int,
	backend_kind: String
) -> bool:
	if not settlements_by_id.has(settlement_id):
		return false
	if not _is_valid_backend_kind(backend_kind):
		return false

	var settlement: Dictionary = settlements_by_id[settlement_id]
	if (
		backend_kind
		== SettlementSimulationContextScript.BACKEND_CITY_SETTLEMENT_STATE
		and str(settlement.get("settlement_type", ""))
		!= SettlementDataScript.SETTLEMENT_TYPE_CITY
	):
		return false

	settlement_backend_kind_by_id[settlement_id] = backend_kind

	if (
		backend_kind
		== SettlementSimulationContextScript.BACKEND_CITY_SETTLEMENT_STATE
		and not settlement_city_state_by_id.has(settlement_id)
	):
		settlement_city_state_by_id[settlement_id] = (
			CitySettlementSimulationStateScript.new()
		)

	return true


func get_polity(polity_id: int) -> Dictionary:
	var raw_polity = polities_by_id.get(polity_id)
	if not raw_polity is Dictionary:
		return {}
	return (raw_polity as Dictionary).duplicate(true)


func get_settlement(settlement_id: int) -> Dictionary:
	var raw_settlement = settlements_by_id.get(settlement_id)
	if not raw_settlement is Dictionary:
		return {}
	return (raw_settlement as Dictionary).duplicate(true)


func get_player_polity() -> Dictionary:
	return get_polity(player_polity_id)


func get_active_settlement() -> Dictionary:
	return get_settlement(active_settlement_id)


func get_presented_settlement_id() -> int:
	# Presentation/session identity only. City gameplay systems must resolve
	# owners through an explicit settlement ID or context instead.
	return active_settlement_id


func get_city_simulation_state(settlement_id: int):
	var raw_state = settlement_city_state_by_id.get(settlement_id)
	if raw_state is CitySettlementSimulationState:
		return raw_state
	return null


func get_player_capital_settlement_id() -> int:
	var player_polity := get_player_polity()
	if player_polity.is_empty():
		return SettlementDataScript.INVALID_SETTLEMENT_ID

	var capital_settlement_id := int(
		player_polity.get(
			"capital_settlement_id",
			SettlementDataScript.INVALID_SETTLEMENT_ID
		)
	)
	if not settlements_by_id.has(capital_settlement_id):
		return SettlementDataScript.INVALID_SETTLEMENT_ID
	return capital_settlement_id


func has_city_world_for_settlement(settlement_id: int) -> bool:
	var city_state = get_city_simulation_state(settlement_id)
	return city_state != null and city_state.city_world != null


func store_city_world_for_settlement(
	settlement_id: int,
	city_world,
	city_seed: int
) -> bool:
	var city_state = get_city_simulation_state(settlement_id)
	if city_state == null or city_world == null:
		return false
	city_state.city_world = city_world
	city_state.city_seed = city_seed
	return true


func clear_city_world_for_settlement(settlement_id: int) -> bool:
	var city_state = get_city_simulation_state(settlement_id)
	if city_state == null:
		return false
	city_state.city_world = null
	city_state.city_seed = 0
	return true


func reset_city_simulation_runtime_state(settlement_id: int) -> bool:
	var city_state = get_city_simulation_state(settlement_id)
	if city_state == null:
		return false

	# Preserve the settlement owner plus its generated world/seed while replacing
	# every mutable simulation sub-owner. This makes an explicit-settlement reset
	# independent of whichever settlement happens to be active for presentation.
	city_state.city_runtime_data = {}
	city_state.object_state = CityObjectStateScript.new()
	city_state.resource_accounting_state = (
		CityResourceAccountingStateScript.new()
	)
	city_state.citizen_registry_state = (
		CityCitizenRegistryStateScript.new()
	)
	city_state.assignment_state = CityAssignmentStateScript.new()
	city_state.workplace_state = CityWorkplaceStateScript.new()
	city_state.citizen_spatial_state = CityCitizenSpatialStateScript.new()
	city_state.citizen_movement_runtime_state = (
		CityCitizenMovementRuntimeStateScript.new()
	)
	city_state.citizen_task_runtime_state = (
		CityCitizenTaskRuntimeStateScript.new()
	)
	city_state.citizen_decision_runtime_state = (
		CityCitizenDecisionRuntimeStateScript.new()
	)
	city_state.work_state = CityWorkStateScript.new()
	city_state.logistics_state = CityLogisticsStateScript.new()
	city_state.construction_state = CityConstructionStateScript.new()
	city_state.navigation_state = CityNavigationStateScript.new()
	return true


func found_city_settlement(settlement_id: int, values: Dictionary) -> bool:
	var settlement := get_settlement(settlement_id)
	var city_state = get_city_simulation_state(settlement_id)
	if (
		settlement.is_empty()
		or str(settlement.get("settlement_type", ""))
		!= SettlementDataScript.SETTLEMENT_TYPE_CITY
		or city_state == null
		or city_state.city_world == null
	):
		return false

	for key in ["city_world_seed", "city_map_size"]:
		if not values.has(key):
			return false

	var city_map_size_value = values.get("city_map_size")
	var foundation_top_left_value = values.get(
		"foundation_top_left",
		Vector2i(-1, -1)
	)
	var foundation_size_value = values.get(
		"foundation_size",
		Vector2i.ZERO
	)
	if (
		not city_map_size_value is Vector2i
		or not foundation_top_left_value is Vector2i
		or not foundation_size_value is Vector2i
	):
		return false

	var city_world_seed := int(values["city_world_seed"])
	var city_map_size: Vector2i = city_map_size_value
	var foundation_top_left: Vector2i = foundation_top_left_value
	var foundation_size: Vector2i = foundation_size_value
	var foundation_object := _get_exact_city_foundation_object(
		city_state,
		foundation_top_left,
		foundation_size
	)
	if (
		city_world_seed == 0
		or city_map_size.x <= 0
		or city_map_size.y <= 0
		or city_map_size != Vector2i(
			city_state.city_world.width,
			city_state.city_world.height
		)
		or foundation_top_left.x < 0
		or foundation_top_left.y < 0
		or foundation_size.x <= 0
		or foundation_size.y <= 0
		or foundation_object.is_empty()
		or (
			city_state.city_seed != 0
			and city_state.city_seed != city_world_seed
		)
	):
		return false

	var polity := get_polity(int(settlement.get(
		"polity_id",
		PolityDataScript.INVALID_POLITY_ID
	)))
	if polity.is_empty():
		return false

	var runtime_data: Dictionary = city_state.city_runtime_data
	var primary_culture_id: int = WorldData.INVALID_CULTURE_ID
	if values.has("primary_culture_id"):
		var explicit_culture_value = values["primary_culture_id"]
		if (
			not explicit_culture_value is int
			or not WorldData.has_culture_id(explicit_culture_value)
		):
			return false
		primary_culture_id = explicit_culture_value
	elif runtime_data.has("primary_culture_id"):
		var local_culture_value = runtime_data["primary_culture_id"]
		if (
			not local_culture_value is int
			or not WorldData.has_culture_id(local_culture_value)
		):
			return false
		primary_culture_id = local_culture_value
	else:
		var polity_culture_value = polity.get(
			"primary_culture_id",
			WorldData.INVALID_CULTURE_ID
		)
		if (
			not polity_culture_value is int
			or not WorldData.has_culture_id(polity_culture_value)
		):
			return false
		primary_culture_id = polity_culture_value

	var desired_foundation := {
		"id": settlement_id,
		"name": str(settlement.get("name", "")),
		"primary_culture_id": primary_culture_id,
		"city_world_seed": city_world_seed,
		"city_map_size": city_map_size,
		"foundation_top_left": foundation_top_left,
		"foundation_size": foundation_size,
		"foundation_object_id": int(foundation_object["id"]),
		"foundation_object_owner": str(foundation_object["owner"]),
		"founded": true,
	}
	var was_founded := bool(runtime_data.get("founded", false))
	if was_founded and not _city_foundation_matches(
		runtime_data,
		desired_foundation
	):
		return false
	if (
		not was_founded
		and city_state.citizen_registry_state.starting_population_initialized
	):
		return false

	var previous_runtime_data := runtime_data.duplicate(true)
	var previous_city_seed: int = city_state.city_seed
	if not was_founded:
		runtime_data.merge(desired_foundation, true)
		runtime_data["can_build"] = bool(values.get("can_build", true))
	city_state.city_seed = city_world_seed

	CityCitizenRegistrySystem.initialize_starting_city_population_for_city_state(
		city_state
	)
	if not city_state.citizen_registry_state.starting_population_initialized:
		runtime_data.clear()
		runtime_data.merge(previous_runtime_data, true)
		city_state.city_seed = previous_city_seed
		return false

	return true


func _get_exact_city_foundation_object(
	city_state: CitySettlementSimulationState,
	foundation_top_left: Vector2i,
	foundation_size: Vector2i
) -> Dictionary:
	var foundation_count := 0
	var exact_foundation: Dictionary = {}
	for raw_city_object in city_state.object_state.objects:
		if not raw_city_object is Dictionary:
			continue
		var city_object: Dictionary = raw_city_object
		if str(city_object.get("type", "")) != "city_center":
			continue

		foundation_count += 1
		if (
			city_object.get("top_left") == foundation_top_left
			and city_object.get("size") == foundation_size
		):
			exact_foundation = city_object

	if foundation_count != 1 or exact_foundation.is_empty():
		return {}

	var foundation_object_id_value = exact_foundation.get("id")
	var foundation_object_owner_value = exact_foundation.get("owner")
	if (
		not foundation_object_id_value is int
		or foundation_object_id_value <= 0
		or not foundation_object_owner_value is String
		or foundation_object_owner_value.strip_edges().is_empty()
	):
		return {}

	var object_index_value = city_state.object_state.object_index_by_id.get(
		foundation_object_id_value
	)
	if (
		not object_index_value is int
		or object_index_value < 0
		or object_index_value >= city_state.object_state.objects.size()
		or not is_same(
			city_state.object_state.objects[object_index_value],
			exact_foundation
		)
	):
		return {}

	return exact_foundation


func _city_foundation_matches(
	runtime_data: Dictionary,
	desired_foundation: Dictionary
) -> bool:
	for raw_key in desired_foundation.keys():
		var key := str(raw_key)
		if (
			not runtime_data.has(key)
			or runtime_data[key] != desired_foundation[key]
		):
			return false
	return true


func get_polity_snapshot() -> Array[Dictionary]:
	var polity_snapshot: Array[Dictionary] = []
	var polity_ids := polities_by_id.keys()
	polity_ids.sort()

	for raw_polity_id in polity_ids:
		var polity := get_polity(int(raw_polity_id))
		if not polity.is_empty():
			polity_snapshot.append(polity)

	return polity_snapshot


func get_settlement_snapshot() -> Array[Dictionary]:
	var settlement_snapshot: Array[Dictionary] = []
	var settlement_ids := settlements_by_id.keys()
	settlement_ids.sort()

	for raw_settlement_id in settlement_ids:
		var settlement := get_settlement(int(raw_settlement_id))
		if not settlement.is_empty():
			settlement_snapshot.append(settlement)

	return settlement_snapshot


func is_registered_settlement_context(
	settlement_context: SettlementSimulationContext
) -> bool:
	if settlement_context == null or not settlement_context.is_valid():
		return false

	var settlement_id := settlement_context.settlement_id
	var raw_settlement = settlements_by_id.get(settlement_id)
	if not raw_settlement is Dictionary:
		return false

	var settlement: Dictionary = raw_settlement
	var polity_id := int(
		settlement.get("polity_id", PolityDataScript.INVALID_POLITY_ID)
	)
	var raw_polity = polities_by_id.get(polity_id)
	if not raw_polity is Dictionary:
		return false

	var polity: Dictionary = raw_polity
	var backend_kind := str(
		settlement_backend_kind_by_id.get(
			settlement_id,
			SettlementSimulationContextScript.BACKEND_NONE
		)
	)
	var registered_state = settlement_city_state_by_id.get(settlement_id)
	var is_player_polity := polity_id == player_polity_id
	var is_capital := int(polity.get(
		"capital_settlement_id",
		PolityDataScript.INVALID_SETTLEMENT_ID
	)) == settlement_id

	return (
		int(settlement.get("id", SettlementDataScript.INVALID_SETTLEMENT_ID))
		== settlement_id
		and str(settlement.get("settlement_type", ""))
		== settlement_context.settlement_type
		and polity_id == settlement_context.polity_id
		and backend_kind == settlement_context.backend_kind
		and is_player_polity == settlement_context.is_player_polity
		and is_capital == settlement_context.is_capital
		and is_same(registered_state, settlement_context.local_state)
	)


func get_settlement_context(settlement_id: int):
	var settlement := get_settlement(settlement_id)
	if settlement.is_empty():
		return null

	var polity_id := int(
		settlement.get("polity_id", PolityDataScript.INVALID_POLITY_ID)
	)
	var polity := get_polity(polity_id)
	if polity.is_empty():
		return null

	settlement_id = int(settlement["id"])
	var backend_kind := str(
		settlement_backend_kind_by_id.get(
			settlement_id,
			SettlementSimulationContextScript.BACKEND_NONE
		)
	)

	return SettlementSimulationContextScript.new({
		"settlement_id": settlement_id,
		"polity_id": polity_id,
		"settlement_type": str(settlement["settlement_type"]),
		"is_player_polity": polity_id == player_polity_id,
		"is_capital": (
			int(polity.get(
				"capital_settlement_id",
				PolityDataScript.INVALID_SETTLEMENT_ID
			)) == settlement_id
		),
		"backend_kind": backend_kind,
		"local_state": get_city_simulation_state(settlement_id),
	})


func is_settlement_capital(settlement_id: int) -> bool:
	var settlement := get_settlement(settlement_id)
	if settlement.is_empty():
		return false

	var polity := get_polity(int(settlement["polity_id"]))
	return (
		not polity.is_empty()
		and int(polity.get(
			"capital_settlement_id",
			PolityDataScript.INVALID_SETTLEMENT_ID
		)) == settlement_id
	)


func validate_registry_integrity() -> bool:
	if polities_by_id.is_empty() or settlements_by_id.is_empty():
		return false
	if not polities_by_id.has(player_polity_id):
		return false
	if not settlements_by_id.has(active_settlement_id):
		return false

	for raw_polity in polities_by_id.values():
		if not raw_polity is Dictionary:
			return false
		var polity: Dictionary = raw_polity
		if not PolityDataScript.is_valid_polity_record(polity):
			return false

		var polity_id := int(polity["id"])
		for raw_settlement_id in polity.get("settlement_ids", []):
			var settlement_id := int(raw_settlement_id)
			if not settlements_by_id.has(settlement_id):
				return false
			var settlement: Dictionary = settlements_by_id[settlement_id]
			if int(settlement.get("polity_id", -1)) != polity_id:
				return false

	for raw_settlement in settlements_by_id.values():
		if not raw_settlement is Dictionary:
			return false
		var settlement: Dictionary = raw_settlement
		if not SettlementDataScript.is_valid_settlement_record(settlement):
			return false
		var settlement_id := int(settlement["id"])
		if not polities_by_id.has(int(settlement["polity_id"])):
			return false
		if not _is_settlement_parent_relationship_valid(settlement):
			return false
		if not settlement_backend_kind_by_id.has(settlement_id):
			return false

		var backend_kind := str(
			settlement_backend_kind_by_id[settlement_id]
		)
		if not _is_valid_backend_kind(backend_kind):
			return false
		if (
			backend_kind
			== SettlementSimulationContextScript.BACKEND_CITY_SETTLEMENT_STATE
			and (
				str(settlement["settlement_type"])
				!= SettlementDataScript.SETTLEMENT_TYPE_CITY
				or get_city_simulation_state(settlement_id) == null
			)
		):
			return false

	return true


func _is_settlement_parent_relationship_valid(
	settlement: Dictionary
) -> bool:
	var settlement_type := str(settlement.get("settlement_type", ""))
	var parent_city_id := int(
		settlement.get(
			"parent_city_id",
			SettlementDataScript.INVALID_SETTLEMENT_ID
		)
	)

	if parent_city_id == SettlementDataScript.INVALID_SETTLEMENT_ID:
		return settlement_type != SettlementDataScript.SETTLEMENT_TYPE_VILLAGE
	if not settlements_by_id.has(parent_city_id):
		return false

	var parent_city: Dictionary = settlements_by_id[parent_city_id]
	return (
		str(parent_city.get("settlement_type", ""))
		== SettlementDataScript.SETTLEMENT_TYPE_CITY
		and int(parent_city.get("polity_id", PolityDataScript.INVALID_POLITY_ID))
		== int(settlement.get("polity_id", PolityDataScript.INVALID_POLITY_ID))
	)


func _is_valid_backend_kind(backend_kind: String) -> bool:
	return (
		backend_kind == SettlementSimulationContextScript.BACKEND_NONE
		or backend_kind
		== SettlementSimulationContextScript.BACKEND_CITY_SETTLEMENT_STATE
	)


func _build_foundation_world_fingerprint() -> String:
	var world_instance_id: int = 0
	if WorldData.official_world != null:
		world_instance_id = WorldData.official_world.get_instance_id()

	# Only immutable founding/world identity belongs in this key. A
	# settlement-local city seed must never make the political registry think a
	# new world was loaded.
	return "%s:%s:%s:%s:%s:%s:%s" % [
		world_instance_id,
		WorldData.official_world.seed,
		WorldData.official_selected_region_top_left.x,
		WorldData.official_selected_region_top_left.y,
		WorldData.official_region_size,
		WorldData.get_official_city_name(),
		WorldData.get_official_founding_culture_id(),
	]
