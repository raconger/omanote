#!/usr/bin/env bash
# List (and optionally search) a flat folder of notes.
# Usage: list.sh <notesDir> [query]
# Prints one row per matching note: "<mtimeEpoch>\t<fileName>\t<snippet>",
# most recently modified first. A note matches when the query is a
# case-insensitive substring of its filename or its content.

set -uo pipefail

notes_dir=${1:-}
query=${2:-}

[[ -n "$notes_dir" && -d "$notes_dir" ]] || exit 0

mtime_of() {
  stat -f '%m' "$1" 2>/dev/null || stat -c '%Y' "$1" 2>/dev/null
}

snippet_of() {
  grep -m 1 -v '^[[:space:]]*$' "$1" 2>/dev/null | tr '\t\r\n' '   ' | cut -c1-160
}

shopt -s nullglob nocaseglob
files=("$notes_dir"/*.md "$notes_dir"/*.markdown "$notes_dir"/*.txt)
shopt -u nullglob nocaseglob

for file in "${files[@]}"; do
  [[ -f "$file" ]] || continue
  base=$(basename -- "$file")

  if [[ -n "$query" ]]; then
    if ! printf '%s' "$base" | grep -qiF -- "$query"; then
      grep -qiF -- "$query" "$file" 2>/dev/null || continue
    fi
  fi

  mtime=$(mtime_of "$file")
  [[ -n "$mtime" ]] || mtime=0
  printf '%s\t%s\t%s\n' "$mtime" "$base" "$(snippet_of "$file")"
done | sort -t $'\t' -k1,1nr
