# Litany design

The maintained design document and the project's constitution: the laws,
the unit contract, the adapters, the fix model, and the domain map, kept
current with the tree and standing on its own. The full history — rejected
alternatives, the design campaign, the milestone record — lives in git
history.

## The design in one paragraph

A litany **unit** is a source file paired with the `.cmt`/`.cmti` the
compiler emitted for it, admitted only when the compiler's own recorded
source digest matches the bytes on disk. Pure rules — written against the
real typedtree, with pattern combinators that match resolved declaration
identity, never spelling — map over admitted units. Diagnostics, fixes,
suppression audit, cross-module facts, caching, and editor delivery are
derived views of that one join. Build systems reach the core through
exactly one interface — the unit list plus optional roster — produced by
adapters. No adapter concept crosses into the core, and a finding's
validity never depends on who produced the artifact.

This design rejected a larger premise — trust no one about freshness, so
build an evidence bureaucracy (a discarded earlier design of this tool ran
to about 33k lines) — for a smaller one: the compiler already wrote the
proof. Digest equality settles staleness identically whoever ran the
build.

## Laws

Each law is a demand plus the failure it prevents.

1. **Join or die, loudly.** A `Unit.t` exists only under a freshness
   witness, and only after its cmt magic matches this litany's compiler.
   The magic is checked before any decode; a workspace of mismatched
   artifacts is a refusal naming both versions and the remedy. Prevents:
   findings against code the user already changed, and the silent
   nothing-reported run over artifacts the tool could not actually read
   (the failure mode dead_code_analyzer shipped: "ran fine, reported
   nothing").
2. **Identity, not spelling.** Semantic matching compares declaration UIDs;
   the SDK offers no name-string identifier comparison. Prevents: the
   false-match family that name-string comparison breeds — aliases,
   `open`, shadowing (camelot's `==` check is the recorded precedent).
3. **Report only owned bytes.** Findings anchor at non-ghost,
   offset-consistent locations in the unit's editable source, corroborated
   by the pre-PPX parse, or are dropped and counted. Prevents: diagnostics
   inside PPX output; carets and fixes at wrong offsets under textual
   preprocessors.
4. **Pure core.** `findings = f(units, roster, config)`; all IO in the
   driver. Prevents: the global-mutable-state architecture of prior OCaml
   linters; enables cache and parallelism as corollaries.
5. **Total order.** Output sorted by (path, byte offset, rule name);
   byte-identical across runs, parallelism, and cache states. Prevents: CI
   diff noise.
6. **Silence is enumerated and absence is quantified.** Every unit ×
   substrate is analyzed or is a listed skip with a reason. Absence claims
   quantify over a complete, named universe: project rules withhold on any
   fact-skip, messages name the workspace, public exports are roots.
   Prevents: silence indistinguishable from cleanliness; lying "unused"
   claims.
7. **Suppressions are audited when auditable.** Unmatched `allow`/`expect`
   are findings, gated on the named rule having run. Prevents: suppression
   rot and false audits.
8. **A fix never writes unverified bytes.** The editable-source digest is
   re-checked at write; the result is verified to reparse before any write
   happens — a failed reparse writes nothing, so there is nothing to roll
   back; convergence spans builds; Safe is proven by compiled goldens.
   Prevents: shipped corruption; "safe" as a vibe; linting trees that no
   longer match their artifacts.
9. **One declaration.** All rule metadata lives in `Rule.meta`; every
   surface derives from it; promises are checked. Prevents:
   triplicated-metadata drift.
10. **The engine walks once and owns traversal.** Rules subscribe; none can
    skip or re-enter. Prevents: per-rule walk scaling and silent coverage
    holes.

## The unit contract

The core consumes units and an optional roster; it spawns nothing and knows
no build system.

**Witnesses.** *Direct*: the digest the compiler recorded of the file it
read (`cmt_source_digest`, 16 bytes, no algorithm discriminator — MD5
before 5.5, BLAKE128 from it; a match under either admits) equals the
digest of the source-tree file the user edits.
`cmt_builddir`/`cmt_sourcefile` are never resolved as filesystem paths;
`_build` copies are never the anchor, except for generated units whose only
source is in `_build`. *Derived* (preprocessed units, where the compiler
read `<m>.pp.ml`): the digest matches the built pp file **and** build
currency holds — this run executed the build, or the run is inside dune
with the artifact a dependency of the invoking rule. Otherwise the unit
skips with `derived witness requires a build`. The editable source's digest
is captured at join time either way; it is the write baseline for fixes. A
unit is *preprocessed* iff its witness is Derived or its `cmt_args` carry
`-pp`/`-ppx`; fixes there downgrade Safe → Unsafe.

**Skips.** A unit that fails admission is a skip with an enumerated reason
(stale, missing source or artifact, wrong magic, unreadable or corrupt
artifact, derived-needs-build), counted and listed in the summary. The
magic number is checked before any decode. A workspace whose artifacts
*all* mismatch this litany's compiler escalates to a refusal naming both
versions, and the one-unit gate (`litany unit`) refuses rather than skips.
`Unit.t` has no other constructor: a typed finding on unverified code is
unrepresentable.

**Outcomes.** Per-unit outcomes are three: *linted* (findings + facts);
*facts-only* (generated units — ocamllex, menhir, `(rule)` outputs — join
fine, produce no findings in files the user cannot edit, and still run
project-rule `collect` so the universe stays complete); *fact-skip*.
Generated-unit classification reads named markers from the admitted bytes
themselves — a `.ml-gen` path (dune-generated alias modules), or a line
directive naming an `.mll`/`.mly` file — never content heuristics, so
every reclassification is auditable; line directives naming `.ml` files
(cppo, ppx) mark hand-written, editable sources that keep linting. This
stands in until build systems declare producers through the roster.

**Roster.** The trusted enumeration that unlocks project rules: the
complete unit list, per-unit library/visibility/kind, cmi search dirs.
Lanes without one run local rules only. Unknown visibility defaults to
public (a root), never to dead-code candidate.

## Adapters

The unit-list-plus-roster value has one serialization, the **unit file**:
csexp, `(litany-units 1)` header, one closed-schema `(unit ...)` form per
unit, with only `source` and `cmt`/`cmti` required. Csexp because paths are
bytes (atoms are length-prefixed raw bytes; JSON would force an escaping
convention) and because it is the ecosystem's machine format. The adapters:

- **dune** (built in, the default): spawn `dune build @check`, then one
  `dune describe workspace` — two subprocesses per check pass. The roster
  is the describe reply unioned with an artifact walk of the build
  directory (test-stanza artifacts do not appear in describe); library
  visibility comes from a tolerant scan of `dune` files for
  `(public_name ...)`.
- **unit file** (`litany check --units FILE`): any build system emits the
  file from its own rules; no dune, no build. Legitimate beside a watch
  server — the lock arbitrates dune-vs-dune, never litany's reads.
- **artifact walk** (`--cmt-root DIR`): pairs artifacts with sources by the
  Direct witness alone; no roster, local rules only.
- **in the build** (a user-written dune rule running `litany check`):
  litany detects the in-action vantage from where cwd actually is — a
  dune action runs inside its build context (`_build/<ctx>/...`), a
  sandboxed one inside `_build/.sandbox/<hash>/<ctx>`, and a `dune exec`
  child keeps the shell's source-workspace cwd (probed 2026-08-21; the
  last `_build` component decides, since a workspace can itself sit under
  an outer build tree). In an action it walks the enclosing context and
  pairs artifacts against the source tree the context mirrors — no dune
  subprocess ever: dune holds its own lock while an action runs. The
  rule's `(deps (alias_rec check))` edge is both the build and the
  freshness evidence (build currency holds, as for `litany unit` under
  `%{cmt:...}`); the walk asserts no completeness, so project rules
  withhold in-action. A sandboxed action (the dune 3.23 norm — every
  user rule is sandboxed there) stages no artifacts for alias deps
  (probed: the mirror holds only the directory skeleton), and the
  sandbox is not a read boundary, so the sandboxed vantage walks the
  *real* enclosing context against the real sources — same report, same
  paths, read-only (amended 2026-08-21; previously a refusal). A context
  that is missing or empty — the deps line absent — is a refusal naming
  that remedy, never a silent green. The report page's finding blocks
  are the grammar dune's diagnostic parser accepts, so a failing rule's
  findings are dune diagnostics and reach editors over dune RPC — the
  same page a terminal shows; there is no in-build format.
- **one unit in the build** (`litany unit`): the degenerate one-unit
  case; argv is the roster, and the invoking rule's `%{cmt:...}`
  dependency is the freshness engine.

Per-unit witnesses gate every lane identically, so a stale or wrong roster
costs skips, never findings. Running the build is adapter porcelain, not
architecture: the linter never drives a foreign build, and there is no
`(build-command ...)` config escape.

## Identity

`Pat`'s one semantic primitive: `Pat.ident "Stdlib.List.length"` matches an
identifier whose declaration UID (`Shape.Uid.t`, carried by the typedtree
on values, constructors, and labels) equals the UID the canonical name
denotes. Resolution happens once per run by **signature walking**: read the
defining compilation unit's `.cmi` and walk its signature by name,
descending submodules, hopping `Mty_alias` to the aliased unit, expanding
`Mty_ident`, descending functor results. Inside the defining unit itself,
use sites carry implementation UIDs, so each canonical UID with that unit's
name is extended by the unit's own `cmt_declaration_dependencies` reverse
image (Impl→Intf item pairs only). Per-node work is UID equality against a
1–2 element set; no `Env`/`Load_path` state is touched on the match path.

A name that fails to resolve matches nothing at check time and is a hard
error in the rule's own tests. Documented limits: module ascription mints
fresh UIDs (`module M : S = List` — `M.length` and `List.length` are
distinct identities, each nameable); all instances of a functor share the
functor body's interface UIDs.

## Rules

One value in one file. `Rule.meta` is the single declaration — name
(stable; renames leave tombstone aliases), group, stability, since, fix
promise, summary, doc — and `litany rules`, `litany explain`, config
validation, and selection all derive from it. Constructors fix the
callback's node type (`expr`, `pattern`, `binding`, `type_decl`,
`let_group`, `module_binding`, `export`, `attribute`, `parsed`, `source`,
`project`); callbacks are pure.

**Group is policy**: `Correctness` → error, on by default; `Suspicious` and
`Perf` → warning, on; `Style` and `Pedantic` → warning, off; `Restriction`
→ warning, off *and outside `all`* — legitimate code restricted by house
policy, cherry-picked by exact name (a bare whole-group `restriction` in
select/extend warns; the full-catalog audit spells
`all,restriction,nursery`). Severity is the group's, applied at render
time. Stability is orthogonal: `Nursery` rules are off regardless of group
and graduate on corpus evidence without changing name or group — a
`Restriction` rule graduates on precision, desirability being the adopting
workspace's call.

Registration is one list (`Litany_rules.all`); duplicate names abort at
startup. Third parties extend by recompiling — a custom composition root
passing `Litany_rules.all @ My_rules.all`. No dynlink: there is no ABI
story, and an unsalted foreign rule set would poison the
binary-digest-keyed cache.

Cross-module rules are one constructor: `Rule.project ~collect ~report`,
where `collect` runs per unit (pure, cacheable) and `report` runs once over
all facts. Facts must be Marshal-safe; identity is the compiler's
`Shape.Uid.t`. A project rule's claim is universally quantified, so project
rules run only when no roster unit is a fact-skip; public-library exports
are roots (`closed-world` opts out); messages name the universe. Both
in-tree project rules (`unused-export`, `dead-code`) register through this
constructor.

## The engine

One traversal per substrate — one `Tast_iterator` walk of the typedtree,
one walk of the engine's own pre-PPX parse for parsed/attribute rules, one
pass over lines for text rules — with kind-indexed dispatch (per-node cost
is O(rules subscribed to that kind)) and demand-gated substrates (no source
re-parse when no parsed rule is selected).

The emit contract (Law 3) is four gates: the location is non-ghost, inside
the unit's editable source, offset-consistent (locations skewed by `#` line
directives degrade to line-anchored findings, their fixes to Display), and
corroborated by a node span in the pre-PPX parse — which stops PPXes that
copy user locations onto generated code. That is the entire PPX story: the
cmt stores the post-expansion tree, so typed rules see real expanded code,
and generated nodes cannot produce diagnostics. Findings dedup by (rule,
location, message); drops are counted; order is total (Law 5). A rule
callback that raises fails that rule on that unit only; everything else
completes and the exit becomes 3. A rule whose meta promises `fix:Never`
and returns a fix fails the same way — promises are checked per finding.

## Suppression

Two attribute forms, reasons mandatory: `[@litany.allow "rule: reason"]`
and `[@litany.expect "rule: reason"]`; the floating `[@@@...]` form scopes
to the rest of the file. Matching is byte-span containment against the
pre-PPX parse; the innermost directive wins; config is the outer ring.
Hygiene is engine-owned: `unused-allow` (with a safe deletion fix) and
`unfulfilled-expect`, both gated on the named rule having run on that unit.
Syntactic defects (unknown name, audit name, text rule, malformed payload)
audit unconditionally. Config `per-path.ignore` is selection of reports,
never of analysis: units still join and still run `collect`; it is not
audited. Text rules are suppressed only that way.

## Fixes

`Fix.t` is a titled edit list in byte-span coordinates against the editable
source, with earned applicability: constructors make safety explicit, and
the bare form defaults to Unsafe. Safe means behavior-preserving, proven by
a compiled `.fixed` golden in the rule's own suite — the clippy theorem, as
a test.

**The write model** (amended 2026-08-21, superseding the single-writer
refusal; re-amended the same day — see the corrections lane below).
Every write is Law-8-guarded — re-check the join-time digest at write,
verify the result reparses before writing (a failed reparse writes
nothing), atomic temp+rename — and that guard, not an ownership rule, is
what keeps writes honest. `--fix` writes the real sources directly at
the terminal lanes (the shell dune adapter, `--units`, `--cmt-root`,
`--no-build`): the digest guard arbitrates litany-vs-editor, the lock
arbitrates dune-vs-dune. Inside dune litany never writes a source, at
any dune version. The refusing vantages are detected from where cwd
actually is (never guessed from `INSIDE_DUNE`'s value): a `dune exec`
child writes a tree its parent re-takes the moment it exits — refused
toward the installed binary or the in-build rule — and an in-dune
`--fix` outside the corrections lane is refused toward that lane or the
terminal (below).

**The corrections lane** (amended 2026-08-21, same day, replacing the
sandboxed refusal — probed against dune nightly 2026-08-20; final shape
by maintainer decision the same day: the legacy in-dune direct-write
lane is dropped — "inside dune, correction is only supported on dune
3.23 with (corrections produce); we don't need to support legacy dune
versions"). Dune lang 3.23 sandboxes every user rule (`(sandbox none)`
is refused) and gives rules `(corrections produce)`: `<path>.corrected`
files written anywhere under the sandbox are paired at teardown with the
files they shadow; dune diffs each against the source, fails the build,
and registers promotion. Inside a sandboxed action `--fix` therefore
never writes a source: the Law-8 pipeline runs in memory (digest
re-check against the real source bytes, apply, reparse-verify —
`Apply.correct`) and the fixed bytes land at
`<sandbox mirror>/<source path>.corrected`, so *inside dune the
single-writer principle holds universally, restored through dune's own
promotion flow* — `dune promote` is the tree's one writer, and the
direct-write lane remains for the terminal lanes alone. An unsandboxed
action vantage means a pre-3.23 dune language (3.23 sandboxes every
user rule), and `--fix` there refuses naming both fixing lanes — the
3.23 corrections stanza, or the terminal — while read-only reporting
works unchanged on every version. Why the exit contract shifts in the
corrections lane: dune processes corrections only from actions that
exit 0 (probed — an exit-1 action's corrections are silently dropped),
so a run that wrote at least one correction exits 0 whatever the report
says; the diffs themselves fail the build, so findings still gate, and
a run that wrote none keeps the normal exit law. Litany cannot observe
whether the invoking stanza carries `(corrections produce)` (probed: no
environment difference), and without the field dune discards leftover
`.corrected` files silently — a green build with the fixes dropped — so
the proposal note always names the field. A sandboxed action with an
explicit roster (`--cmt-root`/`--units`) still refuses `--fix`: those
paths are authored against the action's own directory and cannot be
mirrored into the context-relative pairing corrections require, while a
direct write would land in the discarded staged copy.

Because typed findings derive from cmts, a fixed file's artifacts are stale
by construction, so **convergence spans builds**: `--fix` re-runs the
build, re-joins, re-lints, and applies deferred overlap losers
(deterministic order: span, then rule name), capped at 3 passes. One-pass
lanes say so per lane: `--units`, `--cmt-root`, and `--no-build` say
"rebuild and re-run to converge"; the corrections lane — where litany
cannot rebuild, but the enclosing build is the loop — converges through
`dune promote`: promotion stales the artifacts, the next build re-runs
the rule and re-lints (a watch server converges unprompted). Convergence
must observe progress: each pass's finding multiset
is fingerprinted, and a pass that reproduces an earlier pass's fingerprint
stops the loop naming the repeat — applied fixes that resolved nothing, or
antagonistic fixes undoing each other — instead of burning the cap and
advising a re-run that can never converge; a fix whose output is
byte-identical to its input is a fixer bug at the applier. A post-fix build
failure stops with the applied-fix list and the
exact stderr line `files were modified; git diff shows the applied fixes`
(exit 2 — the line, not a fourth exit code, is the disambiguator).

**The promotion lane is removed** (maintainer decision, 2026-08-21). The
earlier design carried in-build fixes through dune promotion: per-module
generated rules emitting `.litany-corrected` proposals plus `(diff)`
stanzas, produced and maintained by a `lint-rules` generator. Dune's
promotion demands static per-file targets, so a generator — with its
self-regeneration channel, its promote-against-the-tree-you-just-built
staleness caveat (promotion has no freshness check), and a generated file
per directory — was the standing cost of that channel. Direct writes
under Law 8 are the smaller honest design: the guard promotion lacked is
exactly the guard the direct write already has, and the user-written
one-stanza rule replaces the whole generated surface. Law 8 is
unchanged. (Same day, promotion returned by another door: dune 3.23's
`(corrections produce)` is promotion *without* static targets or any
generated surface — the corrections lane above — so what this decision
removed was the generator, not promotion itself; the one user-written
stanza carries both.)

## Diagnostics and output

`Finding.t` = rule, location, message, optional fix.
Renderers are derived views: `text` (the report page — per finding an
ocamlc-shaped block in the exact grammar dune's `ocamlc-loc` parser
accepts: `File "…", line L, characters A-B:`, the quoted line with carets
between header and severity line as ocamlc prints them, `Warning 0
[<rule>]: …`, the fix line as an indented continuation; then one summary
line and the roster lines, which dune's parser folds into the last
finding's message — golden-tested against the vendored parser; humans
and dune read the same bytes, so there is no separate compiler format),
`json` (JSON Lines plus a summary trailer; non-UTF-8 path bytes get a
reversible hex twin), `github` (annotations, auto-selected under
`GITHUB_ACTIONS`).

### Failures and refusals

The exit contract: **0** clean, **1** findings, **2** refusal (the run
could not happen), **3** internal (a rule failed). Four failure concepts
carry everything: **refusal** (exit 2, nothing runs, one actionable
message — refusal aborts before rules run, so during a run, rule failure
dominates findings: 3 > 1), **skip** (per-unit, reason enumerated),
**rule failure** (isolated to one rule × unit, run continues, exit 3),
**findings** (exit 1). Per-unit trouble is a skip; whole-run trouble is a
refusal; the wrong-magic skip escalates to a refusal when every roster
unit skips under one same foreign magic (both versions named), and the
one-unit gate (`litany unit`) refuses rather than skips. Rows marked `—`
are non-failures, shown for contrast; *facts-only* is a per-unit outcome,
not a failure.

| Situation | Concept | The user sees |
|---|---|---|
| Build fails | refusal | dune's own errors, then litany states nothing was checked |
| Stale artifact (`--no-build`) | skip | skipped, `stale — the source changed since the compiler read it`, with the rebuild remedy |
| Unreadable/corrupt artifact | skip | skipped, unreadable artifact, rebuild remedy |
| cmt magic mismatch | skip → refusal | counted per-unit skips naming both versions; all-units-same-magic escalates to a refusal with the install-in-this-switch remedy |
| Preprocessed unit without build currency | skip | `derived witness requires a build` — build first, or pass `--trust-build` |
| PPX-generated code | — | nothing: unowned locations are dropped and counted |
| Generated unit (ocamllex, menhir, `(rule)`) | facts-only | counted in the summary; no findings; project rules unaffected |
| Rule raises | rule failure | the rule and unit named, a please-report message; everything else completes |
| Editable source not valid OCaml (cppo) | — | typed rules run; the summary notes parsed rules and attribute suppression unavailable for that unit |
| Fix conflict | — | loser deferred to the next build-and-relint pass; leftovers reported not applied |
| Post-fix build failure | refusal | the build error, the applied-fix list, and the exact stderr line `files were modified; git diff shows the applied fixes` |
| Config error | refusal | position-labeled message with a did-you-mean suggestion |
| dune missing | refusal | points at `--units` / `--cmt-root` for artifacts built elsewhere |
| Watch server holds the dune lock | refusal | points at linting through the server or `litany units --save` |
| Context without `@check` | refusal | names the non-merlin-enabled context |

## Cache and parallelism

Per-unit results are content-addressed, keyed by (cmt digest, source
digest, resolved config fingerprint, selected-rule set, binary digest).
Every semantic input is in the key, so a wrong cached "clean" is
structurally impossible; the binary digest is the one salt; no mtimes
anywhere. The cache is advisory — a cache failure only costs
recomputation — and is wired into `litany check` (`--cache-dir`,
`--cache-stats`). Parallelism is sharding over the pure core with one
canonical merge: forked worker processes (`-j`/`--jobs`, default the core
count); report bytes do not vary with cache state or worker count. Watch
mode is dune's; no daemon.

Processes were chosen over domains by benchmark on a 4,300-cmt corpus
with the full catalog, and the verdict was availability, not speed: the
domains prototype crashed on every attempt at two or more workers (7/7
runs), because the emit contract's corroboration parse runs compiler-libs'
`Lexer`/`Docstrings`, which keep module-global state in every compiler in
the support window — concurrent parses interleave that state (the lexer's
comment-location stack asserts; `Docstrings`' global tables would corrupt
silently). Concurrent *decode* is empirically clean (~18,000 concurrent
cmt and ~17,300 cmi decodes, zero corruption, zero crashes), so the hazard
is the parser front end, not `Cmt_format.read` — a domains lane would need
a global parse lock plus a per-minor audit of compiler-libs globals,
strangling exactly the phase that must scale. The processes lane measured
3.95× on the parallel phase at 8 workers, a 4–10 ms k-way merge on ~53k
findings (<0.2% of the run), per-shard crash isolation, and byte-identical
merged output across every worker count, mechanism, and run.

## Domains

Two libraries + bin:
`litany` — one wrapped library, every domain except the catalog as one
module `Litany.<Domain>` — and `litany_rules`, the catalog. The library's
own module (`litany.ml`) is its interface, so every domain is reachable
under one path and file names carry no prefix. Three membership laws govern
the namespace:

- every module is a domain noun — never a `util`/`common` catch-all. Two
  domains are named around the compiler's own globals rather than
  shadowing them inside the wrapper: `naming` (canonical names and their
  resolution) and `config_file` (the `litany` file);
- the facade (`litany.ml`) is the only aggregate, and its SDK section holds
  a module iff a rule author is meant to see it under `open Litany`; the
  driver machinery sits in a second, unpromised section because one wrapped
  library has no other way to expose it to `bin/` and the suites;
- driver modules carry no rule-author compatibility promise, and a rule that
  names one is out of contract — frozen by grep in `test/rules/`, the way
  the `Litany_*` spelling used to be. A helper shared by the driver and
  `bin/` earns a domain of its own or stays duplicated — "both sides use
  it" is not a membership law (`Litany.Driver.under_build` is the watched
  precedent).

| Module | Central type | One sentence |
| --- | --- | --- |
| `span` | `Span.t` | Half-open byte ranges — the coordinate system of edits, slicing, suppression containment. |
| `fix` | `Fix.t` | Titled edit lists with earned applicability (`Safe`/`Unsafe`/`Display`) and the `availability` promise. |
| `apply` | `plan`, `outcome` | Single-file fix application: pure planning and patching under an IO shell that verifies before it writes. |
| `finding` | `Finding.t` | One diagnostic at one owned location; carries the dedup key and the total order. |
| `source` | `Source.t` | The editable source snapshot: bytes, line index, slicing, offset-consistency. |
| `naming` | `Name.t`, `Resolver.t` | Canonical names resolved to declaration UIDs by signature walking over `.cmi`s. |
| `roster` | `Roster.t`, `Entry.t` | The adapter-supplied enumeration of units, with ownership metadata, completeness, and the cmi search path. |
| `unit` | `Unit.t`, `Witness.t`, `Skip.t` | The admitted join of source and artifact; the loader; the skip taxonomy; demand-gated substrates. |
| `pat` | `('m,'k,'r) Pat.t` | CPS typed-pattern combinators; `ident` by resolved UID is the one semantic primitive. |
| `rule` | `Rule.t`, `meta` | One declaration per rule; kind-fixing constructors; `Group`/`Stability`/`Severity` policy; selection. |
| `suppress` | `Directive.t` | Compiled `[@litany.allow]`/`[@litany.expect]` policy for one unit: harvest, scope, match, audit inputs. |
| `rules` | (catalog) | The built-in catalog: one module per rule plus `Litany_rules.all`. |
| `engine` | `Report.t` | The pure core: one traversal per substrate, kind-indexed dispatch, emit contract, total order, exit codes. |
| `render` | (formatters) | Three derived views of one report: `text` (the page humans and dune both read), `json`, `github`. |
| `adapter` | (per-adapter) | How build systems reach the core: `Dune`, `Walk`, and the `Unit_file` codec. |
| `config_file` | `Config_file.t`, `Glob.t` | The `litany` file: positioned dune-style sexp reader, closed schema, per-path globs. |
| `cache` | (handles) | The content-addressed result cache. |
| `sexp` | `Sexp.t`, `Error.t` | Positioned s-expressions — the config surface's neutral payload, owned by neither `config` nor `rule`. |
| `progress` | `Progress.t` | The run's meter: one rewritten line on standard error, terminal-only and advisory. |
| `driver` | (the check run) | The check driver: engine pass, `--fix` convergence, cache wiring (`Result_cache`), process workers (`Parallel`), the exit contract. |
| `litany` | (facade) | The rule-author SDK: `open Litany` re-exports litany's modules and the compiler's trees. |
| `suggest` | (functions) | The did-you-mean edit-distance metric. |
| `write` | (functions) | Atomic file publication (temp + rename). |

`Litany.Digest0` and `Litany.Dune_describe` are test-reachable internals
(plain comments, not odoc — no promise); the seven compiler-version seam
targets are aliased nowhere in the facade, so nothing outside the library
can name them.

`bin/` is the composition root — thin composition only: the five public
commands (`check`, `rules`, `explain`, `unit`, `units`), one
`Cli_*` module each, cmdliner terms, flag validation, adapter selection.
The run itself is `Litany.Driver`. Dev workflows (fixtures, corpus triage)
are never public CLI.

**The progress line.** A check spends its wall clock in three stretches —
`dune build @check`, `dune describe workspace`, then one pass over every
unit — and every one of them used to be silent, which reads as a hang. The
`progress` domain draws one rewritten line on standard error naming the
stretch and, once the roster is known, dune's own counted shape
(`Done: 36% (4/11, 7 left) (jobs: 8) | [1.4s] [2.9/s]`). Three properties
make it safe to add to a tool whose output is pinned by goldens: it draws
only when standard error is a terminal (so pipes, cram sandboxes, and CI
logs are byte-identical with and without it), it draws on standard error
only (the report page is standard output's, always), and no engine-side
code knows it exists — the engine takes a `progress` callback and calls it
once per entry, and the parallel lane's workers report over one shared
non-blocking pipe whose ticks the parent drains between shard reads. The
meter is the driver's and the adapter's, like the clock; `--no-progress`
and `LITANY_NO_PROGRESS` turn it off in a terminal that wants none.

**Single homes.** Each of these has exactly one implementation; never
re-spell it at a call site: `Litany.Write.atomic` (temp + rename
publication), `Litany.Suggest.suggest` (the did-you-mean metric),
`Litany.Apply.correct` (fix verification: digest re-check, then
reparse-or-nothing), the catalog's `Normalized_slice` (normalized
source-slice equality) and `List_recursion` (the manual-list family's
recursion view), and the catalog listing spelled once at
`Cli_common.catalog`.

## Dependency DAG

The module-level DAG inside the one `litany` library (an edge is a
module reference, not a library boundary).
Arrows point at dependencies; `[C]` marks `compiler-libs.common` edges.

```
bin ──> driver, adapter, config_file, engine, render, roster, progress,
        rules + the facade                                              [C]
litany (facade) ──> span, fix, finding, source, unit, pat, rule [C]
rules ──> litany (facade)
driver ──> engine, render, apply, adapter, cache, roster, rule, unit,
           naming, progress                                             [C]
engine ──> rule, unit, roster, finding, source, suppress, span
apply ──> fix, span, write                     [C: Parse; unix]
suppress ──> span, suggest                     [C: Parsetree]
render ──> engine, source
adapter ──> roster, progress                   [unix]
rule ──> sexp, finding, fix, source, suggest, unit [C: Typedtree, Parsetree]
config_file ──> sexp, suggest
pat ──> unit, naming                           [C: Typedtree]
unit ──> source, naming, roster                [C: Typedtree, Parsetree]
naming ──> (leaf)                              [C: Shape.Uid; cmi decode inside]
finding ──> fix; fix ──> span; source ──> span [C: Location]
cache ──> write; span, roster, sexp, suggest, write, progress ──> (leaves)
```

No cycles. `engine` and `render` are driver machinery, not SDK vocabulary,
but one wrapped library cannot hide them: they are members of `Litany` like
every other domain, so `open Litany` does put them in scope. The
engine-unreachable invariant is namespace discipline, not a link boundary
(an accepted cost of the one-library layout). For the in-tree catalog the
discipline is frozen as a `runtest` check in `test/rules/` — it now greps
for the short names and the `Litany.` path rather than the retired
`Litany_*` spelling; every catalog rule is written against the facade's SDK
section alone, exactly as a third-party rule would be.

## Compiler-version support

The last three OCaml minors, one branch, one release. The window policy,
the seam mechanism (version-selected copy modules, chosen over `[%%if]`
conditional compilation), the seam ledger, and the corpus discipline are
in [compiler-support.md](compiler-support.md).

## Status (this tree)

As of 2026-08-21: the five commands, the full check lanes (dune,
`--units`, `--cmt-root`, and the in-action lane — read-only on every
dune version, `--fix` as dune corrections at the 3.23 sandboxed
vantage, version-gate and explicit-roster refusals elsewhere in-dune),
the config file, suppression and its audits, the `--fix` convergence
loop, and the four output formats are implemented, and the catalog is
80 rules. The
content-addressed result cache is live in `litany check` (on by default;
`--cache-dir`, `--no-cache`, `--cache-stats`, `LITANY_CACHE_DIR`, the XDG
fallback, sweep on run end), as are process workers (`-j`/`--jobs`), with
pages byte-identical across worker counts and cache states. Project
analysis is live: both project rules (`unused-export`, `dead-code`) are
registered and run under ordinary selection, the withhold gate and
`--explain-withheld` are wired, `[@litany.root]` and the config's
`closed-world` key are consumed, and facts-only units keep the fact
universe complete. The wrong-magic escalation arm is implemented in the
driver: a run whose roster units all skip wrong-magic under one same
foreign magic refuses (exit 2) naming both versions, pinned in
`test/cli/magic.t`; every mixed store keeps its counted per-unit skips.

## Non-goals

- Replacing compiler warnings or ocamlformat; no layout rules beyond the
  text substrate.
- Re-implementing OCaml typing, name resolution, or exhaustiveness.
- An editor server in 1.0 (the dune-RPC channel is the 1.0 editor story).
- Multi-context merging (one context per run; matrices are CI's loop).
- Analyzing projects that do not compile.
- Baseline/adopt-brownfield ratchet files in 1.0 (a future possibility).
- Interfaces as a rule substrate: `.mli` items are not dispatched to
  rules; revisiting that would require a module-type rule kind, not an
  extension of the current constructors.

## Decisions on record

Standing decisions that shape the tree; each is stated in full here.

- **Config is dune-style s-expressions** in a root `litany` file, not
  TOML.
- **No scaffolder, no `litany test`, no `litany corpus` subcommands.** Dev
  workflows are never public CLI. Rule tests are ordinary dune tests;
  corpus runs are ordinary driver invocations, their records kept in git
  history with one CHANGES line per rule graduation.
- **The seam mechanism** is version-selected copy modules under
  `enabled_if`, not `[%%if]` conditional compilation (`ppx_optcomp` is not
  in the lock).
- **`--trust-build`** asserts build currency for Derived witnesses on the
  `--units`, `--cmt-root`, and dune lanes — for CI runs where the build
  demonstrably just ran. Without it: this run built, or inside dune with
  the cmt a rule dependency.
- **`Pat.run` takes the `Unit.t`**: identity resolution is per-unit, never
  global.
- **The five public commands** are `check`, `rules`, `explain`, `unit`,
  `units`. (`lint-rules` and the generated promotion lane were removed
  with the write-model amendment — see Fixes.)
- **The closed-world assumption is config-only** — `(lint (closed-world
  true))` in the `litany` file, no command-line twin. The world assumption
  is a workspace property, not a per-run choice, and it participates in
  the cache key.
- **Two libraries + bin.** The per-domain library swarm merged into one
  `litany` plus `litany_rules` — flat and `(wrapped false)` at first, then
  wrapped, once dropping the `litany_` file prefix made the wrapper the only
  namespace left; `bin/`'s thick
  middle became `Litany.Driver`; an earlier plan for a separate
  `litany_cli` extension library was reversed in favor of the documented
  thin-bin recipe ([build-integration.md](../manual/build-integration.md),
  A custom binary). The engine-unreachable invariant weakened to namespace
  discipline (see Dependency DAG).
- **The 5.3 CI leg is an open task.** The committed workflow runs a 5.5.0
  leg only — the 5.4.1 leg fell to the 5.5 re-lock's raised bound
  ([compiler-support.md](compiler-support.md)). The 5.3 seams exist
  in-tree, untested by CI — a standing deviation from the window policy's
  leg-per-windowed-minor, open until the leg lands or the window moves
  past 5.3.
