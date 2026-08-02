from __future__ import annotations

import base64
import gzip
import hashlib
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MARKER = ROOT / "ci" / ".intensive_cleanup_applied"
EXPECTED_SHA256 = "c93d89498fc5c3d44c7da2542be7eaf976b2a2c7d17c97c897fd93486f6300a6"

if MARKER.exists():
    print("Intensive cleanup already applied.")
    raise SystemExit(0)

payload_dir = ROOT / "ci" / "intensive_cleanup_payload"
part_paths = sorted(payload_dir.glob("part*.txt"))

if len(part_paths) != 6:
    raise RuntimeError(f"Expected 6 cleanup payload parts, found {len(part_paths)}")

encoded = "".join(
    part_path.read_text(encoding="utf-8").strip()
    for part_path in part_paths
)
patch = gzip.decompress(base64.b64decode(encoded))
actual_sha256 = hashlib.sha256(patch).hexdigest()

if actual_sha256 != EXPECTED_SHA256:
    raise RuntimeError(
        "Cleanup patch checksum mismatch: "
        f"expected {EXPECTED_SHA256}, got {actual_sha256}"
    )

patch_path = ROOT / "ci" / ".intensive_cleanup.patch"
patch_path.write_bytes(patch)

try:
    subprocess.run(
        ["git", "apply", "--check", str(patch_path)],
        cwd=ROOT,
        check=True,
    )
    subprocess.run(
        ["git", "apply", str(patch_path)],
        cwd=ROOT,
        check=True,
    )
finally:
    patch_path.unlink(missing_ok=True)

MARKER.write_text("Applied intensive cleanup.\n", encoding="utf-8")
print("Applied intensive cleanup patch.")
