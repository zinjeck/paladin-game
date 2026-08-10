extends RefCounted
class_name CityWorkplaceState

# Settlement-owned invalidation state for mutable workplace projections.
# Staffing policy, production progress/status, and completed-workplace
# registration remain authoritative on their focused systems and object
# records; this state owns only their settlement-local observer version.

var workplace_version: int = 0
