#!/usr/bin/env bash
# Upload one packaged zip to Wago Addons as a Forever-flavor version.
# Requires WAGO_API_KEY, the zip path, and release metadata (label + notes).
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

zip_path="${1:-}"
label="${2:-}"
notes_file="${3:-}"

if [ -z "$zip_path" ] || [ ! -f "$zip_path" ]; then
  echo "Usage: tools/publish_wago.sh <zip> <label> <notes-file>" >&2
  exit 1
fi
if [ -z "$label" ] || [ -z "$notes_file" ] || [ ! -s "$notes_file" ]; then
  echo "Release label and a non-empty notes file are required." >&2
  exit 1
fi
if [ -z "${WAGO_API_KEY:-}" ]; then
  echo "WAGO_API_KEY is not set." >&2
  exit 1
fi

project_id="$(awk -F':[[:space:]]*' '/^## X-Wago-ID:/{print $2; exit}' FieldJournal.toc | tr -d '\r')"
if [ -z "$project_id" ]; then
  echo "FieldJournal.toc is missing ## X-Wago-ID." >&2
  exit 1
fi

case "$label" in
  *alpha*) stability="alpha" ;;
  *beta*)  stability="beta" ;;
  *)       stability="stable" ;;
esac

game_json="$(curl -fsSL https://addons.wago.io/api/data/game)"
forever_patch="$(printf '%s' "$game_json" | jq -r '.live_patches.supported_forever_patches // .patches.forever[0] // empty')"
if [ -z "$forever_patch" ]; then
  echo "Could not read a Forever patch from https://addons.wago.io/api/data/game" >&2
  exit 1
fi
echo "Uploading ${label} (${stability}) to Wago project ${project_id} for Forever ${forever_patch}"

metadata="$(jq -n \
  --arg label "$label" \
  --arg stability "$stability" \
  --arg changelog "$(cat "$notes_file")" \
  --arg patch "$forever_patch" \
  '{label:$label, stability:$stability, changelog:$changelog, supported_forever_patches:[$patch]}')"

curl -f -X POST \
  -H "Authorization: Bearer ${WAGO_API_KEY}" \
  -H "Accept: application/json" \
  -F "metadata=${metadata}" \
  -F "file=@${zip_path}" \
  "https://addons.wago.io/api/projects/${project_id}/version"

echo
echo "Wago upload of ${label} succeeded."
