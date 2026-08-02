from __future__ import annotations

import base64
import gzip
import hashlib
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PAYLOAD_DIR = ROOT / "ci" / "atomic_render_cleanup_payload"
PATCH_SHA256 = "fd96f94fd0972942bd212ff677988a50b9b6bf7da77fd6bfd5339ce05424ef59"

part_paths = sorted(PAYLOAD_DIR.glob("part*.txt"))
if len(part_paths) != 6:
    raise RuntimeError(f"Expected 6 payload parts, found {len(part_paths)}")

encoded = "".join(
    part_path.read_text(encoding="utf-8").strip()
    for part_path in part_paths
)
patch = gzip.decompress(base64.b64decode(encoded))
actual_sha256 = hashlib.sha256(patch).hexdigest()

if actual_sha256 != PATCH_SHA256:
    raise RuntimeError(
        "Atomic render cleanup checksum mismatch: "
        f"expected {PATCH_SHA256}, got {actual_sha256}"
    )

patch_path = ROOT / "ci" / ".atomic_render_cleanup.patch"
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

print("Applied atomic session and redraw cleanup.")
