extends RefCounted
class_name SettlementPresentationBinding

# Immutable, non-owning presentation identity for one exact registered
# settlement. This base deliberately knows nothing about a particular
# simulation implementation. Backend adapters advertise named capabilities;
# consumers must request the capability they actually need.

const CAPABILITY_CITY_DETAIL: StringName = &"city_detail"
const CAPABILITY_SETTLEMENT_WORLD: StringName = &"settlement_world"
const CAPABILITY_DETERMINISTIC_SEED: StringName = &"deterministic_seed"

var _settlement_context: SettlementSimulationContext
var _settlement_id: int = SettlementData.INVALID_SETTLEMENT_ID
var _polity_id: int = PolityData.INVALID_POLITY_ID
var _settlement_type: String = ""
var _backend_kind: String = SettlementSimulationContext.BACKEND_NONE
var _backend_state = null
var _generation: int = 0
var _highest_accepted_generation: int = 0

var settlement_context: SettlementSimulationContext:
	get:
		return _settlement_context
	set(_value):
		pass
var settlement_id: int:
	get:
		return _settlement_id
	set(_value):
		pass
var polity_id: int:
	get:
		return _polity_id
	set(_value):
		pass
var settlement_type: String:
	get:
		return _settlement_type
	set(_value):
		pass
var backend_kind: String:
	get:
		return _backend_kind
	set(_value):
		pass
var backend_state:
	get:
		return _backend_state
	set(_value):
		pass
var generation: int:
	get:
		return _generation
	set(_value):
		pass
var highest_accepted_generation: int:
	get:
		return _highest_accepted_generation
	set(_value):
		pass


func can_rebind(
	context: SettlementSimulationContext,
	binding_generation: int
) -> bool:
	return (
		context != null
		and _highest_accepted_generation == 0
		and _settlement_context == null
		and binding_generation > 0
		and WorldPoliticalState.is_registered_settlement_context(context)
		and _can_bind_backend_capabilities(context)
	)


func rebind(
	context: SettlementSimulationContext,
	binding_generation: int
) -> bool:
	if not can_rebind(context, binding_generation):
		return false

	_settlement_context = context
	_settlement_id = context.settlement_id
	_polity_id = context.polity_id
	_settlement_type = context.settlement_type
	_backend_kind = context.backend_kind
	_backend_state = context.local_state
	_generation = binding_generation
	_highest_accepted_generation = binding_generation
	_capture_backend_capabilities(context)
	return true


func reset() -> void:
	_settlement_context = null
	_settlement_id = SettlementData.INVALID_SETTLEMENT_ID
	_polity_id = PolityData.INVALID_POLITY_ID
	_settlement_type = ""
	_backend_kind = SettlementSimulationContext.BACKEND_NONE
	_backend_state = null
	_generation = 0
	_clear_backend_capabilities()
	# The high-water mark intentionally survives reset. A token is one-shot;
	# switching settlements or generations requires a fresh token.


func accepts_generation(binding_generation: int) -> bool:
	return (
		is_valid()
		and binding_generation > 0
		and binding_generation == generation
	)


func is_valid() -> bool:
	return (
		settlement_context != null
		and settlement_id > 0
		and polity_id > 0
		and SettlementData.is_valid_settlement_type(settlement_type)
		and generation > 0
		and highest_accepted_generation == generation
		and WorldPoliticalState.is_registered_settlement_context(
			settlement_context
		)
		and settlement_context.settlement_id == settlement_id
		and settlement_context.polity_id == polity_id
		and settlement_context.settlement_type == settlement_type
		and settlement_context.backend_kind == backend_kind
		and is_same(settlement_context.local_state, backend_state)
		and _is_backend_capability_snapshot_valid()
	)


func matches_context(context: SettlementSimulationContext) -> bool:
	return (
		is_valid()
		and context != null
		and is_same(settlement_context, context)
		and context.settlement_id == settlement_id
	)


func matches_binding(other: SettlementPresentationBinding) -> bool:
	return (
		is_valid()
		and other != null
		and other.is_valid()
		and is_same(self, other)
		and generation == other.generation
	)


func supports_backend_capability(capability: StringName) -> bool:
	return (
		is_valid()
		and capability != &""
		and _supports_backend_capability(capability)
	)


func get_backend_capability(capability: StringName):
	if not supports_backend_capability(capability):
		return null
	return _get_backend_capability(capability)


# Adapter hooks. They are intentionally narrow so adding a village or outpost
# backend does not require changing the settlement identity contract.
func _can_bind_backend_capabilities(
	_context: SettlementSimulationContext
) -> bool:
	return true


func _capture_backend_capabilities(
	_context: SettlementSimulationContext
) -> void:
	pass


func _clear_backend_capabilities() -> void:
	pass


func _is_backend_capability_snapshot_valid() -> bool:
	return true


func _supports_backend_capability(_capability: StringName) -> bool:
	return false


func _get_backend_capability(_capability: StringName):
	return null
