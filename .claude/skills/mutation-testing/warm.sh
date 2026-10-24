#!/usr/bin/env bash
# Runs the mutation pass over the last commit in warm VMs (warm.exs, beside this file) and writes
# muex's JSON report. Run from the project root:
#
#   bash .claude/skills/mutation-testing/warm.sh OUT_DIR [WORKERS] [SINCE]
#
# OUT_DIR holds each worker's results and log, and the report, OUT_DIR/muex.json. WORKERS is 8
# unless given; SINCE is HEAD~1. The files are the lib/ files the commit changed, as the skill's
# muex command names them. A worker whose mutant times out exits 3 and a fresh one carries on its
# slice; any other failure stops the pass, with the worker's log to read.
set -u

out=$1
workers=${2:-8}
since=${3:-HEAD~1}
here=$(dirname "$0")
files=$(git diff --name-only --diff-filter=d "$since" HEAD -- 'lib/*.ex' | paste -sd, -)

if [ -z "$files" ]; then
  echo "no lib/ file changed since $since: nothing to mutate"
  exit 0
fi

mkdir -p "$out"
MIX_ENV=test mix compile || exit 1

for slice in $(seq 0 $((workers - 1))); do
  (
    while true; do
      MIX_ENV=test mix run --no-start "$here/warm.exs" slice "$slice" "$workers" "$out" "$since" "$files" \
        >> "$out/worker_$slice.log" 2>&1
      status=$?
      [ "$status" -eq 3 ] || exit "$status"
      echo "restarted after a timeout" >> "$out/worker_$slice.log"
    done
  ) &
done

failed=0
for job in $(jobs -p); do
  wait "$job" || failed=1
done

if [ "$failed" -ne 0 ]; then
  echo "a worker failed; see $out/worker_*.log" >&2
  exit 1
fi

MIX_ENV=test mix run --no-start "$here/warm.exs" report "$out" "$since" "$files"
