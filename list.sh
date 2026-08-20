#!/usr/bin/env bash
# List (and optionally search) a flat folder of notes.
# Usage: list.sh <notesDir> [query]
# Prints one row per matching note: "<mtimeEpoch>\t<fileName>\t<snippet>",
# most recently modified first. A note matches when the query is a
# case-insensitive substring of its filename or its content.

set -uo pipefail

# A cancelled search (the QML side kills and reruns list.sh on every new
# query) must actually stop the file-scan loop and the `sort` at the end of
# its pipe, not just the top-level shell — otherwise the old scan keeps
# running in the background, competing for CPU with the new one and holding
# its own stdout open until it finishes on its own. The loop below runs as
# an explicit background job so this trap has something concrete to kill.
trap 'jobs -p | xargs -r kill -TERM 2>/dev/null; exit 143' TERM

notes_dir=${1:-}
query=${2:-}
query_lower=${query,,}

[[ -n "$notes_dir" && -d "$notes_dir" ]] || exit 0

snippet_of() {
  grep -m 1 -v '^[[:space:]]*$' "$1" 2>/dev/null | tr '\t\r\n' '   ' | cut -c1-160
}

shopt -s nullglob nocaseglob
files=("$notes_dir"/*.md "$notes_dir"/*.markdown "$notes_dir"/*.txt)
shopt -u nullglob nocaseglob

[[ ${#files[@]} -gt 0 ]] || exit 0

# Filtering happens in two passes so a large vault doesn't fork a process per
# file per keystroke: filename matching is a pure-bash substring check (no
# fork at all), and content matching for the remaining candidates is one
# batched `grep -l` instead of one `grep` per file.
matched=()
if [[ -n "$query" ]]; then
  content_candidates=()
  for file in "${files[@]}"; do
    base=${file##*/}
    if [[ "${base,,}" == *"$query_lower"* ]]; then
      matched+=("$file")
    else
      content_candidates+=("$file")
    fi
  done
  if [[ ${#content_candidates[@]} -gt 0 ]]; then
    while IFS= read -r file; do
      matched+=("$file")
    done < <(grep -liF -- "$query" -- "${content_candidates[@]}" 2>/dev/null)
  fi
else
  matched=("${files[@]}")
fi

[[ ${#matched[@]} -gt 0 ]] || exit 0

# Batch-stat mtimes in one process instead of one `stat` per file.
mtimes=$(stat -c '%Y %n' -- "${matched[@]}" 2>/dev/null) \
  || mtimes=$(stat -f '%m %N' -- "${matched[@]}" 2>/dev/null)

declare -A mtime_by_path
while IFS=' ' read -r mtime path; do
  [[ -n "$path" ]] || continue
  mtime_by_path["$path"]=$mtime
done <<< "$mtimes"

{
  for file in "${matched[@]}"; do
    base=${file##*/}
    mtime=${mtime_by_path[$file]:-0}
    printf '%s\t%s\t%s\n' "$mtime" "$base" "$(snippet_of "$file")"
  done
} | sort -t $'\t' -k1,1nr &
wait $!
