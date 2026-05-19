#!/usr/bin/env bash
# scripts/discovery/lib/common.sh
#
# Shared helpers for ACMF Phase 1 self-export scripts.
#   - logging
#   - skipped/warnings JSON arrays (compatible with discovery-bundle schema)
#   - dependency check helpers
#   - argv parsing helpers
#
# Sourced by:
#   - gke-enterprise-vmware-export.sh
#   - gke-export.sh
#   - aks-export.sh
#   - openshift-export.sh
#   - rancher-export.sh
#
# This file is intentionally side-effect-free until the caller invokes
# acmf::common::init.

# Bash 4+ is required (associative arrays, set -u behavior we rely on).
# shellcheck disable=SC2034

acmf::common::log() {
  echo "[acmf-export] $*" >&2
}

acmf::common::warn() {
  local msg="$1"
  jq --arg m "$msg" '. += [$m]' "$ACMF_WARN_FILE" \
    > "$ACMF_WARN_FILE.tmp" && mv "$ACMF_WARN_FILE.tmp" "$ACMF_WARN_FILE"
  acmf::common::log "WARN: $msg"
}

acmf::common::skip() {
  local cmd="$1" reason="$2"
  jq --arg c "$cmd" --arg r "$reason" \
    '. += [{command:$c, reason:$r}]' "$ACMF_SKIPPED_FILE" \
    > "$ACMF_SKIPPED_FILE.tmp" && mv "$ACMF_SKIPPED_FILE.tmp" "$ACMF_SKIPPED_FILE"
  acmf::common::log "SKIP [$cmd]: $reason"
}

acmf::common::require() {
  command -v "$1" >/dev/null 2>&1
}

acmf::common::need_val() {
  # acmf::common::need_val FLAG VALUE
  if [[ -z "${2:-}" || "${2:0:2}" == "--" ]]; then
    echo "error: $1 requires a value" >&2
    exit 2
  fi
}

# Initialise shared tmp files. Caller must export ACMF_TMPDIR.
acmf::common::init() {
  ACMF_TMPDIR="${ACMF_TMPDIR:-$(mktemp -d -t acmf-export-XXXXXX)}"
  ACMF_SKIPPED_FILE="$ACMF_TMPDIR/skipped.json"
  ACMF_WARN_FILE="$ACMF_TMPDIR/warnings.json"
  echo "[]" > "$ACMF_SKIPPED_FILE"
  echo "[]" > "$ACMF_WARN_FILE"
  export ACMF_TMPDIR ACMF_SKIPPED_FILE ACMF_WARN_FILE
}

acmf::common::generated_at() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}
