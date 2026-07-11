(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Renderers: derived views of one report.

    Each renderer formats a [Engine.Report.t] for one consumer — humans
    ({!text}), dune's diagnostic parser ({!compiler}), editors and dashboards
    ({!json}), GitHub annotations ({!github}). Renderers are pure formatting:
    they read the report in its total order and may not reorder, filter, or
    depend on parallelism or cache state — the byte-determinism law is theirs
    too. Channel discipline (stdout vs stderr) and exit codes are the driver's;
    every contract here says what bytes go to the formatter, and the driver says
    where the formatter points. The dial a driver selects a renderer with is
    [Driver.format] — one constructor per renderer below. *)

(** {1:renderers Renderers} *)

val text :
  ?color:bool ->
  ?fixes:[ `Hint | `Applied of int | `Proposed of int ] ->
  ?notes_detail:bool ->
  source_of_path:(string -> Source.t option) ->
  Format.formatter ->
  Engine.Report.t ->
  unit
(** [text ~source_of_path ppf rep] formats [rep] for humans: per finding a
    location line, the message, the quoted source line with carets, and a fix
    line when a fix exists ([fix (safe): ...]); then one summary line — the
    selected-rule count first ([Engine.Report.rules_selected]: the denominator
    that keeps [0 findings] honest about how many rules looked), units, findings
    with the fixable count and the run's fix posture ([fixes]: [`Hint], the
    default, adds "run [litany check --fix]" as the fixable count's remedy; the
    driver passes [`Applied n] under [--fix], where the hint would advise what
    is already running — the fixable count still prints, followed by the
    applied-fix count, and [`Applied 0] prints "0 fixes applied": a fix pass
    that applied nothing must say so; [`Proposed n] is the corrections lane's
    same count with "proposed" for "applied" — fixes became dune corrections,
    and the page must not claim a source write the tree never saw), skips with
    reasons, facts-only counts, and the dropped, degraded, and
    suppressed-finding counts when non-zero (suppressed findings themselves are
    never rendered: [Engine.Report.suppressed] retains them) — then roster lines
    when project rules were blocked ([Engine.Report.project_rules]: the
    run-level blocks — not-capable, incomplete, ambiguous — hold for every rule
    and print once; a collect failure blocks one rule and prints per rule) and
    when kind-gated rules were structurally silent
    ([Engine.Report.withheld_rules], one line each), per-unit degradations,
    per-unit informational notes ([Engine.Report.notes]), and rule failures.
    Every count on the summary line is [Engine.Summary] — the same aggregation
    the json trailer serializes.

    [source_of_path] supplies a unit's source for excerpts, consulted with
    [Unit.path] values as carried by the findings — [None] degrades that finding
    to location and message, never an error. The driver must serve bytes it can
    vouch for: re-read and compare against the unit's witness digest, or a
    retained snapshot; on mismatch, return [None] and let the finding degrade
    rather than excerpt bytes the run never saw. Line-anchored
    (offset-inconsistent) findings render without carets by contract, and
    findings in units the report marks offsets-degraded
    ([Engine.Report.degradations] rows carrying [Offsets]) render location and
    message only — corroboration was waived there, so offsets may count
    preprocessed bytes and an excerpt would witness bytes the finding never
    touched; a resolution-degraded unit's offsets are fully verified, so its
    excerpts render as usual. [color] enables ANSI styling and defaults to
    [false]; the driver decides from the terminal. *)

val compiler : Format.formatter -> Engine.Report.t -> unit
(** [compiler ppf rep] formats [rep] in the exact grammar dune's vendored
    [ocamlc-loc] lexer accepts, validated against that lexer: per finding one
    block — [File "<path>", line L, characters A-B:] (or [lines L-M] for
    multi-line spans) directly followed by [Warning 0 [<rule-name>]: <msg>] for
    warnings or [Error: <msg> [<rule-name>]] for errors (the error form repeats
    the rule name in the message because dune discards the structured code
    there). Columns are the compiler's convention — 0-based
    [pos_cnum - pos_bol], end-exclusive — emitted verbatim.

    No excerpt or caret lines (a caret line without an excerpt is fatal to the
    whole stream), LF endings, no ANSI, nothing before the first block or after
    the last — a summary line would corrupt the last finding's message. Message
    continuation lines are indented and sanitized so none matches the flush-left
    header pattern; a forged header would truncate every later finding. A
    finding with a fix carries the promise as one more continuation line —
    [fix (<applicability>): <title>], the design doc's journey-(a)/(f)
    suggestion line, folded by the parser into the message so editors show it
    with the diagnostic. Related locations are emitted as an indented header
    plus indented message after the main message.

    The driver's obligations, without which dune ignores the output: emit to
    {e stderr} with stdout completely silent (dune gates on the concatenation
    [stdout ^ stderr] starting with [File ]), and exit non-zero when findings
    exist (dune parses only failing actions). Golden-tested byte-for-byte
    against the vendored parser. *)

val json : Format.formatter -> Engine.Report.t -> unit
(** [json ppf rep] formats [rep] as JSON Lines: one finding object per line in
    report order, then one trailer object
    [{"summary": {schema, rules_selected, findings, fixable, units, linted,
     facts_only, suppressed, skipped: [{path, reason}], failures: [{rule, path,
     message}], degraded: [{path, note}], notes: [{path, note}], dropped,
     roster, exit}}] — [schema] is the machine channel's version, [1] (additive
    keys do not bump it; a change to an existing key's meaning does). The scalar
    counts are [Engine.Summary], serialized field-for-field — the same
    aggregation the text page prints, so the machine channel carries the whole
    truth set: [rules_selected] the selection denominator, [units] the linted
    and facts-only units with the [linted]/[facts_only] split beside it,
    [suppressed] the directive-hidden count. [skipped] lists each skipped unit
    with its reason slug ([Unit.Skip.slug] — the summary vocabulary: [stale],
    [wrong-magic], …); [failures] is the isolated rule failures
    ([Engine.Report.failures]) — the records the exit-3 law rides on, so a
    consumer that never parses the text page still sees why the exit code
    hardened; [degraded] the per-unit degradation notes and [notes] the per-unit
    informational notes; [dropped] the emit contract's dropped-finding count;
    [roster] is [Engine.Report.project_rules] structured — one
    [{rule, state, …}] object per selected project rule, [state] one of [ran],
    [unavailable], [incomplete] (with [blocking: [{path, reason}]]), [ambiguous]
    (with [duplicates: [{name, paths}]]), or [collect-failed] (with [paths]) —
    and [exit] is [Engine.Report.exit_code]. Consumers read records; CI reads
    the trailer. Each line is one complete JSON value; nothing else is emitted —
    a clean report is the trailer line alone.

    A finding object carries [rule], [severity] ([error]/[warning]), [file],
    [line]/[col]/[end_line]/[end_col] (the compiler's own convention: 1-based
    lines, 0-based end-exclusive byte columns, verbatim), [message], and when
    present [fix] — [{title, applicability, edits: [{start, stop, text}]}], edit
    offsets in bytes of the editable source.

    JSON is UTF-8 and litany's paths and fix replacement text are raw bytes:
    every byte-string field ([file], [path], edit [text]) is emitted lossily
    (invalid sequences replaced by U+FFFD) and, when the original was not valid
    UTF-8, a sibling [<field>_bytes] hex field carries the exact bytes —
    reversible, no invented escaping. Messages and titles are rule-authored
    prose and are emitted lossily without a twin. *)

val github : Format.formatter -> Engine.Report.t -> unit
(** [github ppf rep] formats [rep] as GitHub workflow commands — one
    [::error file=…,line=…,col=…,endColumn=…,title=<rule>::<message>] line per
    finding ([::warning] for warning severity), values escaped per the
    workflow-command rules (properties escape [% CR LF : ,]; the message escapes
    [% CR LF]). Columns are 1-based on this surface; a multi-line span carries
    [endLine] and no columns (GitHub rejects columns across lines). A finding's
    fix is appended to the message as [fix (<applicability>): <title>]. No
    summary or trailer — annotations are the entire output. The driver
    auto-selects this renderer when [GITHUB_ACTIONS] is set. *)
