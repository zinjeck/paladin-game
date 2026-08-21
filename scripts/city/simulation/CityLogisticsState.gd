extends RefCounted
class_name CityLogisticsState

# Settlement-owned mutable logistics state for one CITY.
#
# This object owns only the physical ground-pile registry and atomic hauling
# reservation registries/counters. CityLogisticsSystem owns the behavior and
# receives this state through an explicit registered settlement owner.
#
# Keep this class a small state container rather than a second simulation brain.

var ground_piles: Array = []
var ground_pile_index_by_id: Dictionary = {}
var next_ground_pile_id: int = 1
var ground_pile_version: int = 0

var haul_reservations: Dictionary = {}
var haul_reservation_id_by_citizen_id: Dictionary = {}
var haul_source_reserved_amount_by_key: Dictionary = {}
var haul_destination_reserved_amount_by_key: Dictionary = {}
var next_haul_reservation_id: int = 1
var haul_reservation_version: int = 0
