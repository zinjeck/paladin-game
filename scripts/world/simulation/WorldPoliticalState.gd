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
var _unbound_city_work_state = CityWorkStateScript.new()


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
	var unbound_work_state_to_adopt = _unbound_city_work_state

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
	var capital_state = get_city_simulation_state(active_settlement_id)
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
			"Only city settlements may own the current city simulation backend."
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

	_capture_active_city_workspace()
	active_settlement_id = settlement_id
	_apply_active_city_workspace()

	# CitizenDecisionSystem still carries process-local cursors while its state
	# is migrated in a later pass. Resetting those cursors on a settlement switch
	# prevents one city's scheduler history from leaking into another city.
	CitizenDecisionSystem.reset_runtime_state()
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

	var previous_backend_kind := str(
		settlement_backend_kind_by_id.get(
			settlement_id,
			SettlementSimulationContextScript.BACKEND_NONE
		)
	)

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


func get_city_simulation_state(settlement_id: int):
	var raw_state = settlement_city_state_by_id.get(settlement_id)
	if raw_state is CitySettlementSimulationState:
		return raw_state
	return null


func get_active_city_simulation_state():
	return get_city_simulation_state(active_settlement_id)


# Compatibility owner for code paths that run before a settlement context is
# established (primarily low-level tests and reset/setup code). Runtime city
# work always resolves to the active settlement state once one exists.
func get_current_city_work_state():
	var active_city_state = get_active_city_simulation_state()
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
	if not synchronize_foundation_with_world_data():
		return null

	var settlement := get_active_settlement()
	if settlement.is_empty():
		return null

	var polity_id := int(
		settlement.get("polity_id", PolityDataScript.INVALID_POLITY_ID)
	)
	var polity := get_polity(polity_id)
	if polity.is_empty():
		return null

	var settlement_id := int(settlement["id"])
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
		"is_capital": (
			int(polity.get(
				"capital_settlement_id",
				PolityDataScript.INVALID_SETTLEMENT_ID
			)) == settlement_id
		),
		"backend_kind": backend_kind,
		"local_state": get_city_simulation_state(settlement_id),
	})


func capture_active_settlement_state() -> void:
	_capture_active_city_workspace()


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


func _capture_active_city_workspace() -> void:
	if active_settlement_id == SettlementDataScript.INVALID_SETTLEMENT_ID:
		return
	if not settlement_backend_kind_by_id.has(active_settlement_id):
		return
	if (
		str(settlement_backend_kind_by_id[active_settlement_id])
		!= SettlementSimulationContextScript.BACKEND_CITY_SETTLEMENT_STATE
	):
		return

	var city_state = get_city_simulation_state(active_settlement_id)
	if city_state != null:
		city_state.capture_from_world_data()


func _apply_active_city_workspace() -> void:
	if active_settlement_id == SettlementDataScript.INVALID_SETTLEMENT_ID:
		return
	if not settlement_backend_kind_by_id.has(active_settlement_id):
		return
	if (
		str(settlement_backend_kind_by_id[active_settlement_id])
		!= SettlementSimulationContextScript.BACKEND_CITY_SETTLEMENT_STATE
	):
		return

	var city_state = get_city_simulation_state(active_settlement_id)
	if city_state != null:
		city_state.apply_to_world_data()


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


func _has_live_foundation_registry() -> bool:
	return (
		polities_by_id.has(player_polity_id)
		and settlements_by_id.has(active_settlement_id)
	)


func _is_valid_backend_kind(backend_kind: String) -> bool:
	return (
		backend_kind == SettlementSimulationContextScript.BACKEND_NONE
		or backend_kind
		== SettlementSimulationContextScript.BACKEND_LEGACY_CITY_WORLD_DATA
		or backend_kind
		== SettlementSimulationContextScript.BACKEND_CITY_SETTLEMENT_STATE
	)


func _build_foundation_world_fingerprint() -> String:
	var world_instance_id: int = 0
	if WorldData.official_world != null:
		world_instance_id = WorldData.official_world.get_instance_id()

	# Only immutable founding/world identity belongs in this key. A local city
	# seed changes when another settlement becomes active and must never make the
	# political registry think a new world was loaded.
	return "%s:%s:%s:%s:%s:%s:%s" % [
		world_instance_id,
		WorldData.official_world.seed,
		WorldData.official_selected_region_top_left.x,
		WorldData.official_selected_region_top_left.y,
		WorldData.official_region_size,
		WorldData.get_official_city_name(),
		WorldData.get_official_founding_culture_id(),
	]
