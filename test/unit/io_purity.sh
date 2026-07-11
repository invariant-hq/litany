#!/bin/sh
# The engine is a function: findings are computed from admitted units, the
# roster, and the resolved configuration, and every ambient effect — process
# spawning, directory walking, cache traffic, source writes, environment
# reads, clocks, exits — belongs to the driver and its named IO edges (the
# build-system adapter, the result cache, the atomic writer, the fix
# applier, the progress meter). Engine-side modules touch the world in
# exactly one way: the documented demand-gated substrate reads — the unit
# loader reading the sources it digests and decoding artifacts on first
# demand, and identifier resolution probing for cmi files — and those reads
# only read. No engine-side module ever writes, removes, renames, spawns, or
# consults the environment; no engine-side module outside the two substrate
# readers performs any IO at all. This check freezes that discipline the way
# the catalog's namespace check freezes its facade: by grep over the
# sources, run on every runtest.
#
# Files are classified by basename:
#   - IO edge (skipped, their business is IO): driver, adapter, cache,
#     write, apply, progress.
#   - Substrate readers (read-only IO allowed): unit, naming.
#   - Everything else in lib/: no IO calls at all.

io_calls='\b(Unix\.|Sys\.|In_channel\.|Out_channel\.|open_in|open_out|really_input|input_line|Filename\.temp_|Digest\.[A-Z0-9]+\.file|at_exit\b|Stdlib\.exit)'
write_calls='\b(Unix\.|Out_channel\.|open_out|Filename\.temp_|at_exit\b|Stdlib\.exit|Sys\.(remove|rename|command|getenv|getcwd|mkdir|rmdir|readdir|chdir|time|argv|executable_name))'

status=0
for f in "$@"; do
  base=$(basename "$f")
  case "$base" in
  driver.ml | adapter.ml | cache.ml | write.ml | apply.ml | progress.ml)
    continue
    ;;
  unit.ml | naming.ml)
    pat="$write_calls"
    label="write, spawn, or environment IO (substrate readers only read)"
    ;;
  *)
    pat="$io_calls"
    label="IO (engine modules perform none)"
    ;;
  esac
  hits=$(grep -nE "$pat" "$f")
  if [ -n "$hits" ]; then
    echo "$f calls $label:" >&2
    echo "$hits" >&2
    status=1
  fi
done
exit $status
