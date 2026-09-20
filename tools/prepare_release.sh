#!/usr/bin/env bash
# Prepare the next Field Journal draft release after a merge to main.
# Decides the version, prepends CHANGELOG.md, updates FieldJournal.toc,
# commits those files, and creates a GitHub Release draft. Publishing that
# draft is what uploads to Wago.io (see .github/workflows/publish-release.yml).
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

lua_bin="${LUA_BIN:-lua5.1}"
if ! command -v "$lua_bin" >/dev/null 2>&1; then
  lua_bin="lua"
fi

if [ -z "${GITHUB_REPOSITORY:-}" ] || [ -z "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]; then
  echo "GITHUB_REPOSITORY and GH_TOKEN/GITHUB_TOKEN are required." >&2
  exit 1
fi

git fetch --tags origin main
git checkout -B main origin/main

toc_version="$(awk -F':[[:space:]]*' '/^## Version:/{print $2; exit}' FieldJournal.toc | tr -d '\r')"
if [ -z "$toc_version" ]; then
  echo "Could not read ## Version from FieldJournal.toc" >&2
  exit 1
fi

last_tag="$(git tag --list 'v*' --sort=-v:refname | head -n 1 || true)"
last_tag_version="${last_tag#v}"

if [ -n "$last_tag" ]; then
  user_commits="$(git log "${last_tag}..HEAD" --format='%s' | grep -v '^chore: prepare release' || true)"
  if [ -z "$user_commits" ]; then
    echo "No new user commits since ${last_tag}; skipping draft release."
    if [ -n "${GITHUB_OUTPUT:-}" ]; then
      echo "version=" >> "$GITHUB_OUTPUT"
    fi
    exit 0
  fi
fi

version="$("$lua_bin" tools/release_version.lua next-version "$toc_version" "$last_tag_version")"
echo "TOC version=${toc_version} last_tag=${last_tag:-<none>} next_version=${version}"

if git rev-parse "refs/tags/v${version}" >/dev/null 2>&1; then
  echo "Tag v${version} already exists; refusing to create a duplicate draft." >&2
  exit 1
fi

notes_args=(-f "tag_name=v${version}" -f "target_commitish=$(git rev-parse HEAD)")
if [ -n "$last_tag" ]; then
  notes_args+=(-f "previous_tag_name=${last_tag}")
fi

notes_file="$(mktemp)"
trap 'rm -f "$notes_file"' EXIT
gh api "repos/${GITHUB_REPOSITORY}/releases/generate-notes" "${notes_args[@]}" --jq .body > "$notes_file"
if [ ! -s "$notes_file" ]; then
  echo "GitHub generated empty release notes." >&2
  exit 1
fi

"$lua_bin" tools/release_version.lua apply FieldJournal.toc CHANGELOG.md "$version" "$notes_file"

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add FieldJournal.toc CHANGELOG.md
if git diff --cached --quiet; then
  echo "Version ${version} produced no file changes." >&2
  exit 1
fi

git commit -m "chore: prepare release ${version}"
git push origin HEAD:main

gh release create "v${version}" \
  --draft \
  --title "Field Journal ${version}" \
  --notes-file "$notes_file" \
  --target "$(git rev-parse HEAD)"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "version=${version}" >> "$GITHUB_OUTPUT"
fi

echo "Created draft release v${version}. Publish it to upload to Wago.io."
