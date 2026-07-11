#!/bin/sh
# The one-library layout makes the engine reachable from a rule: [litany] is
# one wrapped library, so [open Litany] puts the driver machinery in scope
# under its short name (Engine, Driver, Render, ...) alongside the SDK. The
# engine-unreachable invariant is therefore namespace discipline, not a link
# boundary. This check freezes the discipline for the in-tree catalog: no
# catalog implementation names a driver-machinery module, whether by the
# short name [open Litany] binds or through the [Litany.] path — rules see
# the SDK (Span, Fix, Finding, Source, Unit, Pat, Rule) and the compiler's
# own modules, nothing else. Qualified spellings under an SDK module
# ([Rule.Sexp.desc]) are not reaches past the facade and do not count.
# Interface doc comments are out of scope (odoc cross-references need the
# full names — the invariant is about what code links, not what
# documentation cites), so the check covers *.ml.
internal='Adapter|Apply|Cache|Config_file|Digest0|Driver|Dune_describe|Engine|Naming|Progress|Render|Roster|Sexp|Suggest|Suppress|Write'
status=0
for f in "$@"; do
  hits=$(grep -nE "(^|[^A-Za-z0-9_.])($internal)\.|\bLitany\.($internal)\b" "$f")
  if [ -n "$hits" ]; then
    echo "$f names driver machinery outside the SDK facade:" >&2
    echo "$hits" >&2
    status=1
  fi
done
exit $status
