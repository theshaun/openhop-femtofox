#!/usr/bin/env bash
# Re-compile bytecode for the repeater package before the service starts.
# Cheap and idempotent: Python only rewrites .pyc when source mtime changed,
# so this is a near-no-op on steady-state boots but guarantees a fresh .pyc
# after any in-place upgrade (pip install -U, git pull + pip install, etc.).
set -euo pipefail

VENV=/opt/openhop_repeater/venv
PY="${VENV}/bin/python"

# Locate the installed repeater package (path varies by Python version).
PKG_DIR="$(${PY} - <<'EOF' 2>/dev/null
import repeater, os
print(os.path.dirname(repeater.__file__))
EOF
)"

if [[ -n "${PKG_DIR}" && -d "${PKG_DIR}" ]]; then
    exec "${PY}" -OO -m compileall -q "${PKG_DIR}"
else
    echo "[openhop-compile] repeater package not found, skipping" >&2
    exit 0
fi
