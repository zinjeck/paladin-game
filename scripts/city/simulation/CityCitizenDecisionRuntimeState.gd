extends RefCounted
class_name CityCitizenDecisionRuntimeState

# Settlement-owned mutable citizen decision-scheduler runtime for one CITY.
#
# CitizenDecisionSystem owns scheduler behavior and policy. This data-only owner
# preserves pending work, scan progress, and deterministic idle-choice history
# when another settlement becomes active.

var pending_decision_ids: Array[int] = []
var pending_decision_id_lookup: Dictionary = {}
var runtime_initialized: bool = false
var work_shift_was_active: bool = false
var observed_assignment_version: int = -1
var recovery_scan_cursor: int = 0
var idle_scan_cursor: int = 0
var idle_anchor_tile_by_citizen_id: Dictionary = {}
var next_idle_decision_minute_by_citizen_id: Dictionary = {}
var idle_choice_sequence_by_citizen_id: Dictionary = {}
var autonomous_haul_scan_cursor: int = 0
var critical_food_scan_cursor: int = 0
var normal_food_scan_cursor: int = 0
