extends Node

# Authoritative runtime registry for polity and settlement identity plus each
# settlement's local simulation state. WorldData remains the compatibility
# execution workspace while city systems are migrated, but it is no longer the
# only place where a city's mutable state can live.

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
const CityWorkStateScript = preload(
	"res://scripts/city/simulation/CityWorkState.gd"
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
var _unbound_city_work_state: CityWorkState = CityWorkStateScript.new()


func reset_state() -> void:
	polities_by_id.clear()
	settlements_by_id.clear()
	settlement_backend_kind_by_id.clear()
	settlement_city_state_by_id.clear()
	next_polity_id = 1
	next_settlement_id = 1
	player_polity_id = PolityDataScript.INVALID_POLITY_ID
	active_settlement_id = SettlementDataScript.INVALID_SETTLEMENT_ID
	_foundation_world_fingerprint = ""
	_unbound_city_work_state = CityWorkStateScript.new()


func synchronize_foundation_with_world_data() -> bool:
	if not WorldData.has_active_world_save() or WorldData.official_world == null:
		if not _foundation_world_fingerprint.is_empty():
			reset_state()
		return false

	var fingerprint := _build_foundation_world_fingerprint()
	if fingerprint == _foundation_world_fingerprint:
		return _has_live_foundation_registry()

	# Some low-level simulation/bootstrap paths can create local work before the
	# political registry exists. Preserve that pre-context state exactly once
	# when the first City settlement adopts the current city simulation. Never
	# carry it across an already-live political registry into another world.
	var should_adopt_unbound_work_state := not _has_live_foundation_registry()
	var unbound_work_state_to_adopt: CityWorkState = _unbound_city_work_state

	reset_state()

	var founding_culture_id := WorldData.get_official_founding_culture_id()
	var founding_name := WorldData.get_official_city_name().strip_edges()
	if founding_culture_id <= 0 or founding_name.is_empty():
		return false

	var player_polity := create_polity({
		"name": founding_name,
		"polity_type": PolityDataScript.POLITY_TYPE_CHIEFDOM,
		"primary_culture_id": founding_culture_id,
	})
	if player_polity.is_empty():
		reset_state()
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
		reset_state()
		return false

	if not set_polity_capital(
		int(player_polity["id"]),
		int(capital["id"])
	):
		reset_state()
		return false

	player_polity_id = int(player_polity["id"])
	active_settlement_id = int(capital["id"])

	# Founding begins with the already-live city workspace populated by the
	# existing generation/session flow. Capture those references rather than
	# replacing them with a blank state. Future settlement switches can then
	# restore this exact city independently of every other city settlement.
	var capital_state: CitySettlementSimulationState = get_city_simulation_state(
		active_settlement_id
	)
	if capital_state == null:
		reset_state()
		return false
	if should_adopt_unbound_work_state:
		capital_state.work_state = unbound_work_state_to_adopt
	capital_state.capture_from_world_data()

	_foundation_world_fingerprint = fingerprint
	return validate_registry_integrity()


func create_polity(values: Dictionary) -> Dictionary:
	var polity_values := values.duplicate(true)
	var requested_id := int(
		polity_values.get("id", PolityDataScript.INVALID_POLITY_ID)
	)
	var polity_id := requested_id
	if polity_id <= 0:
		polity_id = next_polity_id
	polity_values["id"] = polity_id

	var polity := PolityDataScript.make_polity(polity_values)
	if polity.is_empty() or polities_by_id.has(polity_id):
		return {}

	polities_by_id[polity_id] = polity
	next_polity_id = maxi(next_polity_id, polity_id + 1)
	return polity.duplicate(true)


func create_settlement(values: Dictionary) -> Dictionary:
	var settlement_values := values.duplicate(true)
	var requested_id := int(
		settlement_values.get(
			"id",
			SettlementDataScript.INVALID_SETTLEMENT_ID
		)
	)
	var settlement_id := requested_id
	if settlement_id <= 0:
		settlement_id = next_settlement_id
	settlement_values["id"] = settlement_id

	var polity_id := int(
		settlement_values.get(
			"polity_id",
			SettlementDataScript.INVALID_POLITY_ID
		)
	)
	var raw_polity = polities_by_id.get(polity_id)
	if not raw_polity is Dictionary:
		return {}

	var settlement_type := str(
		settlement_values.get("settlement_type", "")
	)
	var parent_city_id := int(
		settlement_values.get(
			"parent_city_id",
			SettlementDataScript.INVALID_SETTLEMENT_ID
		)
	)
	if settlement_type == SettlementDataScript.SETTLEMENT_TYPE_VILLAGE:
		if not _is_valid_parent_city_for_settlement(
			parent_city_id,
			polity_id
		):
			return {}
	elif (
		parent_city_id > 0
		and not _is_valid_parent_city_for_settlement(
			parent_city_id,
			polity_id
		)
	):
		return {}

	var settlement := SettlementDataScript.make_settlement(
		settlement_values
	)
	if settlement.is_empty() or settlements_by_id.has(settlement_id):
		return {}

	var backend_kind := str(
		values.get(
			"simulation_backend_kind",
			SettlementSimulationContextScript.BACKEND_NONE
		)
	)
	if not SettlementSimulationContextScript.is_valid_backend_kind(
		backend_kind
	):
		return {}

	settlements_by_id[settlement_id] = settlement
	settlement_backend_kind_by_id[settlement_id] = backend_kind
	if (
		backend_kind
		== SettlementSimulationContextScript.BACKEND_CITY_SETTLEMENT_STATE
	):
		settlement_city_state_by_id[settlement_id] = (
			CitySettlementSimulationStateScript.new()
		)

	var polity: Dictionary = raw_polity
	var settlement_ids: Array = polity.get("settlement_ids", []).duplicate()
	if not settlement_ids.has(settlement_id):
		settlement_ids.append(settlement_id)
		settlement_ids.sort()
	polity["settlement_ids"] = settlement_ids
	polities_by_id[polity_id] = polity

	next_settlement_id = maxi(next_settlement_id, settlement_id + 1)
	return settlement.duplicate(true)


func set_polity_capital(polity_id: int, settlement_id: int) -> bool:
	var raw_polity = polities_by_id.get(polity_id)
	var raw_settlement = settlements_by_id.get(settlement_id)
	if not raw_polity is Dictionary or not raw_settlement is Dictionary:
		return false

	var settlement: Dictionary = raw_settlement
	if (
		int(settlement.get("polity_id", -1)) != polity_id
		or str(settlement.get("settlement_type", ""))
		!= SettlementDataScript.SETTLEMENT_TYPE_CITY
	):
		return false

	var polity: Dictionary = raw_polity
	polity["capital_settlement_id"] = settlement_id
	polities_by_id[polity_id] = polity
	return true


func set_active_settlement(settlement_id: int) -> bool:
	if settlement_id == active_settlement_id:
		return settlements_by_id.has(settlement_id)

	if settlement_id > 0 and not settlements_by_id.has(settlement_id):
		return false

	_capture_active_city_workspace()
	active_settlement_id = settlement_id
	_apply_active_city_workspace()
	return true


func set_settlement_simulation_backend(
	settlement_id: int,
	backend_kind: String
) -> bool:
	if (
		not settlements_by_id.has(settlement_id)
		or not SettlementSimulationContextScript.is_valid_backend_kind(
			backend_kind
		)
	):
		return false

	var previous_backend_kind := str(
		settlement_backend_kind_by_id.get(
			settlement_id,
			SettlementSimulationContextScript.BACKEND_NONE
		)
	)
	if previous_backend_kind == backend_kind:
		return true

	if settlement_id == active_settlement_id:
		_capture_active_city_workspace()

	settlement_backend_kind_by_id[settlement_id] = backend_kind

	if (
		backend_kind
		== SettlementSimulationContextScript.BACKEND_CITY_SETTLEMENT_STATE
		and not settlement_city_state_by_id.has(settlement_id)
	):
		var city_state := CitySettlementSimulationStateScript.new()

		# Only the old legacy backend can legitimately mean that the current
		# WorldData workspace belongs to this same settlement. BACKEND_NONE may
		# leave another city's compatibility workspace loaded, so copying it here
		# would silently clone that city's population/resources into this one.
		if (
			settlement_id == active_settlement_id
			and previous_backend_kind
			== SettlementSimulationContextScript.BACKEND_LEGACY_CITY_WORLD_DATA
		):
			city_state.capture_from_world_data()

		settlement_city_state_by_id[settlement_id] = city_state

	if settlement_id == active_settlement_id:
		_apply_active_city_workspace()

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


func get_city_simulation_state(
	settlement_id: int
) -> CitySettlementSimulationState:
	var raw_state = settlement_city_state_by_id.get(settlement_id)
	if raw_state is CitySettlementSimulationState:
		return raw_state
	return null


func get_active_city_simulation_state() -> CitySettlementSimulationState:
	return get_city_simulation_state(active_settlement_id)


# Compatibility owner for code paths that run before a settlement context is
# established (primarily low-level tests and reset/setup code). Runtime city
# work always resolves to the active settlement state once one exists.
func get_current_city_work_state() -> CityWorkState:
	var active_city_state: CitySettlementSimulationState = (
		get_active_city_simulation_state()
	)
	if (
		active_city_state != null
		and active_city_state.work_state is CityWorkState
	):
		return active_city_state.work_state
	return _unbound_city_work_state


# WorldData still owns the legacy city-session reset entry point while local
# subsystems are extracted. Keep that entry point generic: it asks the local
# ownership registry to reset extracted state without knowing its internals.
func reset_extracted_city_state() -> void:
	get_current_city_work_state().reset_all()


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


func get_active_settlement_context():
	if not _has_live_foundation_registry():
		synchronize_foundation_with_world_data()

	var settlement := get_active_settlement()
	if settlement.is_empty():
		return null

	var settlement_id := int(settlement["id"])
	var backend_kind := str(
		settlement_backend_kind_by_id.get(
			settlement_id,
			SettlementSimulationContextScript.BACKEND_NONE
		)
	)
	var local_state = null
	if (
		backend_kind
		== SettlementSimulationContextScript.BACKEND_CITY_SETTLEMENT_STATE
	):
		local_state = get_city_simulation_state(settlement_id)

	return SettlementSimulationContextScript.new({
		"settlement_id": settlement_id,
		"polity_id": int(settlement["polity_id"]),
		"settlement_type": str(settlement["settlement_type"]),
		"is_capital": is_settlement_capital(settlement_id),
		"backend_kind": backend_kind,
		"local_state": local_state,
	})


func is_settlement_capital(settlement_id: int) -> bool:
	var settlement := get_settlement(settlement_id)
	if settlement.is_empty():
		return false

	var polity_id := int(settlement["polity_id"])
	var polity := get_polity(polity_id)
	return (
		not polity.is_empty()
		and int(polity.get("capital_settlement_id", -1)) == settlement_id
	)


func validate_registry_integrity() -> bool:
	for raw_polity_id in polities_by_id.keys():
		var polity_id := int(raw_polity_id)
		var raw_polity = polities_by_id[raw_polity_id]
		if (
			not raw_polity is Dictionary
			or not PolityDataScript.is_valid_polity_record(raw_polity)
		):
			return false

		var polity: Dictionary = raw_polity
		for raw_settlement_id in polity.get("settlement_ids", []):
			var settlement_id := int(raw_settlement_id)
			var settlement := get_settlement(settlement_id)
			if (
				settlement.is_empty()
				or int(settlement.get("polity_id", -1)) != polity_id
			):
				return false

		var capital_settlement_id := int(
			polity.get("capital_settlement_id", -1)
		)
		if capital_settlement_id > 0:
			var capital := get_settlement(capital_settlement_id)
			if (
				capital.is_empty()
				or int(capital.get("polity_id", -1)) != polity_id
				or str(capital.get("settlement_type", ""))
				!= SettlementDataScript.SETTLEMENT_TYPE_CITY
			):
				return false

	for raw_settlement_id in settlements_by_id.keys():
		var settlement_id := int(raw_settlement_id)
		var raw_settlement = settlements_by_id[raw_settlement_id]
		if (
			not raw_settlement is Dictionary
			or not SettlementDataScript.is_valid_settlement_record(
				raw_settlement
			)
		):
			return false

		var settlement: Dictionary = raw_settlement
		var polity_id := int(settlement.get("polity_id", -1))
		if not polities_by_id.has(polity_id):
			return false

		var settlement_type := str(
			settlement.get("settlement_type", "")
		)
		var parent_city_id := int(
			settlement.get(
				"parent_city_id",
				SettlementDataScript.INVALID_SETTLEMENT_ID
			)
		)
		if settlement_type == SettlementDataScript.SETTLEMENT_TYPE_VILLAGE:
			if not _is_valid_parent_city_for_settlement(
				parent_city_id,
				polity_id
			):
				return false
		elif (
			parent_city_id > 0
			and not _is_valid_parent_city_for_settlement(
				parent_city_id,
				polity_id
			)
		):
			return false

		var backend_kind := str(
			settlement_backend_kind_by_id.get(
				settlement_id,
				SettlementSimulationContextScript.BACKEND_NONE
			)
		)
		if not SettlementSimulationContextScript.is_valid_backend_kind(
			backend_kind
		):
			return false

		if (
			backend_kind
			== SettlementSimulationContextScript.BACKEND_CITY_SETTLEMENT_STATE
		):
			if settlement_type != SettlementDataScript.SETTLEMENT_TYPE_CITY:
				return false
			var city_state = get_city_simulation_state(settlement_id)
			if city_state == null:
				return false
		else:
			if settlement_city_state_by_id.has(settlement_id):
				return false

	return true


func _is_valid_parent_city_for_settlement(
	parent_city_id: int,
	polity_id: int
) -> bool:
	if parent_city_id <= 0:
		return false

	var parent_city := get_settlement(parent_city_id)
	return (
		not parent_city.is_empty()
		and int(parent_city.get("polity_id", -1)) == polity_id
		and str(parent_city.get("settlement_type", ""))
		== SettlementDataScript.SETTLEMENT_TYPE_CITY
	)


func _capture_active_city_workspace() -> void:
	var active_city_state = get_city_simulation_state(active_settlement_id)
	if active_city_state == null:
		return
	if not active_city_state.is_bound_to_world_data_workspace():
		return
	active_city_state.capture_from_world_data()


func _apply_active_city_workspace() -> void:
	var active_city_state = get_city_simulation_state(active_settlement_id)
	if active_city_state == null:
		return
	active_city_state.apply_to_world_data()


func _build_foundation_world_fingerprint() -> String:
	return str(
		WorldData.official_world,
		"|",
		WorldData.official_world.seed,
		"|",
		WorldData.official_selected_region_top_left,
		"|",
		WorldData.official_region_size,
		"|",
		WorldData.get_official_city_name(),
		"|",
		WorldData.get_official_founding_culture_id()
	)


func _has_live_foundation_registry() -> bool:
	if (
		player_polity_id <= 0
		or active_settlement_id <= 0
		or not polities_by_id.has(player_polity_id)
		or not settlements_by_id.has(active_settlement_id)
	):
		return false

	var player_polity := get_polity(player_polity_id)
	var active_settlement := get_settlement(active_settlement_id)
	if player_polity.is_empty() or active_settlement.is_empty():
		return false

	return (
		int(player_polity.get("capital_settlement_id", -1)) > 0
		and int(active_settlement.get("polity_id", -1)) > 0
	)
