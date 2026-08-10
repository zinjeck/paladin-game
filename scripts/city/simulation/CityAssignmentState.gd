extends RefCounted
class_name CityAssignmentState

# Settlement-owned invalidation state for bidirectional citizen relationships.
#
# The relationships themselves remain authoritative exactly where they
# physically belong: home_object_id/job_object_id on citizen records and
# resident_ids/assigned_worker_ids on completed object records. This state is
# deliberately not a second relationship ledger.

var assignment_version: int = 0
