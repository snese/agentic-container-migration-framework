#!/usr/bin/env bash
# scripts/discovery/validate-bundle.sh
#
# Validate one or more discovery-bundle.json files against
# schemas/discovery-bundle.schema.json using python3 + jsonschema.
#
# Usage:
#   ./validate-bundle.sh <bundle.json> [<bundle2.json> ...]
#   ./validate-bundle.sh --all-fixtures
#
# Exit code 0 if all bundles validate; 1 otherwise.
#
# Required: python3, python3 jsonschema module (>=3.0).
# Install on Debian/Ubuntu: sudo apt-get install python3-jsonschema
# Or via pip:                pip install --user jsonschema

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCHEMA="${REPO_ROOT}/schemas/discovery-bundle.schema.json"

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 not found." >&2
  exit 2
fi
if ! python3 -c 'import jsonschema' >/dev/null 2>&1; then
  echo "ERROR: python3 jsonschema module missing. Install: pip install jsonschema" >&2
  exit 2
fi
if [ ! -f "$SCHEMA" ]; then
  echo "ERROR: schema not found at $SCHEMA" >&2
  exit 2
fi

# Expand --all-fixtures to every fixture file in the repo.
files=()
for arg in "$@"; do
  case "$arg" in
    --all-fixtures)
      while IFS= read -r f; do files+=("$f"); done < <(
        find "${REPO_ROOT}/adapters/source" -type f -path '*/fixtures/*.json' | sort
      ) ;;
    -h|--help)
      cat <<EOF
Validate ACMF discovery bundles against the JSON schema.

Usage:
  $(basename "$0") <bundle.json> [<bundle2.json> ...]
  $(basename "$0") --all-fixtures
EOF
      exit 0 ;;
    *)
      files+=("$arg") ;;
  esac
done

if [ "${#files[@]}" -eq 0 ]; then
  echo "Usage: $(basename "$0") <bundle.json> [...]  |  --all-fixtures" >&2
  exit 2
fi

failed=0
for f in "${files[@]}"; do
  if [ ! -f "$f" ]; then
    printf '  ✗ %-70s (file not found)\n' "$f"
    failed=$((failed+1))
    continue
  fi
  if python3 - "$SCHEMA" "$f" <<'PYEOF'
import json, sys
import jsonschema
schema_path, bundle_path = sys.argv[1], sys.argv[2]
with open(schema_path) as fh: schema = json.load(fh)
with open(bundle_path) as fh: bundle = json.load(fh)
try:
    jsonschema.validate(instance=bundle, schema=schema)
except jsonschema.ValidationError as e:
    print(f"  ✗ {bundle_path}")
    print(f"    path: {' -> '.join(str(p) for p in e.absolute_path) or '(root)'}")
    print(f"    msg : {e.message}")
    sys.exit(1)
print(f"  ✓ {bundle_path}")
PYEOF
  then :; else failed=$((failed+1)); fi
done

if [ "$failed" -gt 0 ]; then
  echo
  echo "FAILED: $failed bundle(s) did not validate." >&2
  exit 1
fi

echo
echo "OK: ${#files[@]} bundle(s) validated."
