extends "res://scripts/settlements/presentation/SettlementPresentationBinding.gd"
class_name CityPresentationBinding

# City-detail adapter for the settlement-neutral identity token. Only this
# adapter validates and exposes CitySettlementSimulationState, WorldData, and
# the city seed. Generic settlement presenters should type the base and request
# a named capability instead of assuming every settlement is a city.

var _city_state: CitySettlementSimulationState
var _city_world: WorldData
var _city_seed: int = 0

var settlement_state: CitySettlementSimulationState:
	get:
		return _city_state
	set(_value):
		pass
var world: WorldData:
	get:
		return _city_world
	set(_value):
		pass
var seed: int:
	get:
		return _city_seed
	set(_value):
		pass

# Read-only compatibility aliases for existing city-specific presenters.
var city_state: CitySettlementSimulationState:
	get:
		return settlement_state
var city_world: WorldData:
	get:
		return world
var city_seed: int:
	get:
		return seed


func _can_bind_backend_capabilities(
	context: SettlementSimulationContext
) -> bool:
	if (
		context == null
		or not context.supports_detailed_simulation()
		or context.settlement_type != SettlementData.SETTLEMENT_TYPE_CITY
		or context.backend_kind
		!= SettlementSimulationContext.BACKEND_CITY_SETTLEMENT_STATE
	):
		return false

	var raw_state = context.get_detailed_simulation_state()
	if (
		not raw_state is CitySettlementSimulationState
		or not raw_state.city_world is WorldData
		or raw_state.city_world.width <= 0
		or raw_state.city_world.height <= 0
		or raw_state.city_seed <= 0
	):
		return false
	return true


func _capture_backend_capabilities(
	context: SettlementSimulationContext
) -> void:
	_city_state = context.get_detailed_simulation_state()
	_city_world = _city_state.city_world
	_city_seed = _city_state.city_seed


func _clear_backend_capabilities() -> void:
	_city_state = null
	_city_world = null
	_city_seed = 0


func _is_backend_capability_snapshot_valid() -> bool:
	return (
		_city_state != null
		and _city_world != null
		and _city_seed > 0
		and settlement_context != null
		and settlement_context.supports_detailed_simulation()
		and is_same(
			settlement_context.get_detailed_simulation_state(),
			_city_state
		)
		and is_same(_city_state.city_world, _city_world)
		and _city_state.city_seed == _city_seed
	)


func _supports_backend_capability(capability: StringName) -> bool:
	return capability in [
		CAPABILITY_CITY_DETAIL,
		CAPABILITY_SETTLEMENT_WORLD,
		CAPABILITY_DETERMINISTIC_SEED,
	]


func _get_backend_capability(capability: StringName):
	match capability:
		CAPABILITY_CITY_DETAIL:
			return _city_state
		CAPABILITY_SETTLEMENT_WORLD:
			return _city_world
		CAPABILITY_DETERMINISTIC_SEED:
			return _city_seed
	return null
