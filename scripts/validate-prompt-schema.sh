#!/usr/bin/env bash
# validate-prompt-schema.sh
# Cross-validates that every required top-level schema key has a corresponding
# section/mention in the discovery prompt, and vice versa.
#
# Exit code: 0 when contract holds, 1 on any mismatch.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA="$ROOT/schemas/discovery-bundle.schema.json"
# The active discovery prompt. The framework was renamed Anthos -> GKE Enterprise
# on VMware; the file path reflects that. The contract doc records this alias.
PROMPT="$ROOT/prompts/discovery/gke-enterprise-vmware.prompt.md"

if [ ! -f "$SCHEMA" ]; then
  echo "ERROR: schema not found at $SCHEMA" >&2
  exit 2
fi
if [ ! -f "$PROMPT" ]; then
  echo "ERROR: prompt not found at $PROMPT" >&2
  exit 2
fi

# Aliases: keys in the schema that are described in the prompt under a
# different word. Format: "schema_key=prompt_substring". The prompt must contain
# either the key itself OR one of its aliases (case-insensitive).
declare -A ALIASES=(
  [schema_version]="schema"
  [generated_at]="iso-8601"
  [generated_by]="kiro-cli"
  [scope]="discovery scope"
  [external_dependencies]="external dependencies"
  [crds]="crd"
  [vmware]="vmware"
  [utilization]="utilization"
  [traffic]="traffic"
)

prompt_lc="$(tr '[:upper:]' '[:lower:]' < "$PROMPT")"

contains() {
  # case-insensitive substring search in the lowercased prompt
  local needle_lc
  needle_lc="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$prompt_lc" in
    *"$needle_lc"*) return 0 ;;
    *) return 1 ;;
  esac
}

echo "=== Prompt ↔ schema contract check ==="
echo "Schema: ${SCHEMA#"$ROOT"/}"
echo "Prompt: ${PROMPT#"$ROOT"/}"
echo

mismatches=0

# 1. Every schema-required key must appear in the prompt (or via alias).
echo "[1/2] Schema-required keys → prompt mentions"
while IFS= read -r key; do
  [ -z "$key" ] && continue
  if contains "$key"; then
    echo "  OK   $key"
    continue
  fi
  alias="${ALIASES[$key]:-}"
  if [ -n "$alias" ] && contains "$alias"; then
    echo "  OK   $key (alias: \"$alias\")"
    continue
  fi
  echo "  MISS $key — not mentioned in prompt"
  mismatches=$((mismatches + 1))
done < <(jq -r '.required[]' "$SCHEMA")
echo

# 2. Every "Output: bundle.<field>" reference in the prompt must map to a real
#    top-level schema property (or a dotted sub-path whose root is a property).
echo "[2/2] Prompt bundle.<field> references → schema properties"
mapfile -t schema_props < <(jq -r '.properties | keys[]' "$SCHEMA")
declare -A is_prop=()
for p in "${schema_props[@]}"; do is_prop[$p]=1; done

# Extract candidate field paths: bundle.foo, bundle.foo.bar, bundle.foo[].
# Skip filename references (e.g., "discovery-bundle.json",
# "discovery-bundle.schema.json") by anchoring on a non-identifier prefix and
# filtering out tokens that end in known file extensions.
mapfile -t prompt_refs < <(
  grep -oE '(^|[^a-zA-Z0-9_-])bundle\.[a-zA-Z_][a-zA-Z0-9_.]*' "$PROMPT" \
    | sed -E 's/^[^b]*//' \
    | grep -vE '\.(json|ya?ml|md|txt)$' \
    | sort -u || true
)

if [ "${#prompt_refs[@]}" -eq 0 ]; then
  echo "  (no bundle.<field> references found in prompt)"
else
  for ref in "${prompt_refs[@]}"; do
    root="${ref#bundle.}"
    root="${root%%.*}"
    root="${root%%[*}"
    if [ -n "${is_prop[$root]:-}" ]; then
      echo "  OK   $ref → schema.properties.$root"
    else
      echo "  MISS $ref — root \"$root\" is not a schema property"
      mismatches=$((mismatches + 1))
    fi
  done
fi
echo

if [ "$mismatches" -gt 0 ]; then
  echo "FAIL: $mismatches contract mismatch(es) detected"
  exit 1
fi
echo "PASS: prompt ↔ schema contract holds"
