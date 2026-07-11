# RFC 0001: Litany

- Status: discussion — once committed, prefer a new RFC over substantial
  rewrites.
- Created: 2026-08-18
- Supersedes: [RFC 0001](0001-design.md) and Designs 01–10 under `doc/design/`
- Campaign record: two audits, four independent whole-system designs (three
  blind to RFC 0001's rationale), four adversarial lens reviews, one fold —
  see Rationale for why the designs' convergence is the evidence.

## Summary

A Litany **unit** is a source file paired with the `.cmt`/`.cmti` the compiler
emitted for it, admitted only when the compiler's own recorded source digest
matches the bytes on disk. Pure rules — written against the real typedtree,
with pattern combinators that match resolved declaration identity, never
spelling — map over admitted units. Diagnostics, fixes, suppression audit,
cross-module facts, caching, and editor delivery are all derived views of that
one join.

Build systems reach the core through exactly one interface: the **unit
file** — an enumeration of `(source, cmt)` pairs plus optional roster
metadata — produced by **adapters**. The dune adapter is built in (zero
config: it can run the build for you and constructs the unit list itself);
any other build system (Bazel, Make, nix) emits the same file from its own
rules; a bare artifact walk is the adapter of last resort; and `litany unit`
inside the build is the degenerate one-unit case. No adapter concept crosses
into the core; a finding's validity never depends on who produced the
artifact.

The estimate is ~11–16k lines of engine and tooling replacing today's 33k —
with fixes, caching, parallelism, and cross-module analysis included, all four
absent from the WIP — and its fixture harness replaces 60k lines of
hand-built tests. A typed rule with a safe fix is ~40 lines including its
documentation; today it is 153 lines with no fix.

## Motivation

RFC 0001 produced a coherent design and 32,996 lines of implementation for 15
rules with, by its own README, "no fixes, persistent cache, parallel
execution, cross-module or complete-project analysis" (`README.md:9-15`). The
audit found the cost concentrated in three places:

- **~7,000 lines of capture** — Candidate/Artifact/Inventory chains, a
  describe-twice equality dance, `dune ocaml-merlin` probing, path mappings —
  to establish freshness facts that the compiler's recorded source digest
  settles in one comparison (audit: `lib/runner/` + `lib/typed_runner/`, §8).
- **6,243 lines (audited) of per-compiler-minor façade** that also caps
  expressiveness: the snapshot's expression view has 8 constructors, so rules
  cannot see `match`, `if`, tuples, records, or constructors at all
  (`lib/typed_runner/ocaml_55_typed.ml:1757-1765`), and every rule pays a
  ~27-line metadata-and-resolver tax before its first line of logic.
- **44 public evidence/identity nouns** where the architecture document
  promises five (`doc/architecture.md:12-33`), including two different modules
  named `Unit`, eight ID types, and three "snapshot" concepts.

Meanwhile the shipped default (`--build=none`) runs zero typed rules on a
fresh checkout, and the tool hard-refuses to run under dune
(`lib/runner/dune_process.ml:279-282`) while dune offers exactly the two hooks
a linter wants: `%{cmt:m}` dependency macros (lang 3.21+,
`_ref/dune/src/dune_lang/pform.ml:658-666`) and an RPC diagnostics channel
that republishes compiler-style stderr from failing actions into every editor
via ocaml-lsp (`_ref/dune/src/dune_engine/process.ml:528-556`,
ocaml-lsp `src/dune.ml:182-235`).

Doing nothing means shipping a linter that is simultaneously the most
defensive and the least capable tool in its class: rules that cannot match a
`match` expression, no fixes, no editor story, and a per-compiler-minor
maintenance bill larger than most linters' whole engines.

The root cause is one premise: *trust no one about freshness, so build an
evidence bureaucracy*. The replacement premise: **the compiler already wrote
the proof**. Every `.cmt` records a digest of the exact bytes the compiler
compiled; equality with the bytes on disk is the entire staleness question,
and it holds or fails identically whoever ran the build. RFC 0001's
build-neutrality was the right instinct attached to the wrong mechanism —
this design keeps the neutrality (in the unit contract) and deletes the
bureaucracy (digest trust replaces all of it).

## Guide-level explanation

Written as if Litany 1.0 has shipped.

### Using Litany

Install it in your switch (`opam install litany`) and run it at the root of
any dune project:

```
$ litany check
lib/inventory.ml:42:6 warning needless-list-length
  `List.length` walks the whole list to test emptiness
    42 |   if List.length xs = 0 then restock t else t
       |      ^^^^^^^^^^^^^^^^^^
  fix (safe): xs = []

214 units · 1 finding (1 fixable — run `litany check --fix`) · 0 skipped
$ echo $?
1
```

There is nothing to configure first. The dune adapter builds what it needs
(`dune build @check` — no linking, incremental; `--no-build` skips it), asks
dune for the project layout, and checks every unit it can admit in the
default context. The default rule set is curated for a near-zero
false-positive budget: `correctness` rules are errors, `suspicious` and
`perf` rules are warnings, and `style`/`pedantic` rules are off until you ask
for them. Exit codes are stable: 0 clean, 1 findings, 2 Litany could not run
(config error, build failure, version mismatch), 3 internal error.

Litany is not dune-only. Any build system that can name `(source, cmt)`
pairs can drive it:

```
$ litany check --units litany.units             # Bazel/Make/nix emit this (csexp)
$ litany check --cmt-root _build/default        # bare artifact walk
```

The same digest admission rule gates every lane, so a stale artifact is a
listed skip everywhere, never a stale finding.

`litany check --fix` applies every fix marked **safe** — safe means the edit
preserves behavior, and each safe fix ships with a fixture whose fixed output
is compiled in Litany's own CI. `--fix --unsafe` opts into fixes that may
change behavior (each says how). Litany never writes bytes it has not
re-verified, and never leaves a file it cannot reparse.

Configuration, when you want it, is one file with a closed schema — a
`litany` file at the workspace root, in the dune-style s-expression
syntax every OCaml developer already writes (amended 2026-08-19 from
TOML; see Rationale):

```lisp
; litany
(lint
 (select default)             ; groups or rule names; default | all
 (extend style unused-export)
 (ignore needless-identity-function)
 (closed-world false))        ; public-library exports stay dead-code roots

(rule line-length
 (max 100))

(per-path
 (paths vendor/**)
 (ignore all)
 (reason "vendored code"))
```

A typo is an error with a position and a suggestion, never a silent
fallback: `litany:4: unknown rule "styel" (did you mean "style"?)`.

To silence one finding you annotate the code, with a reason:

```ocaml
let same = (a == b) [@litany.allow "suspicious-physical-equality: identity is the point"]
```

An `allow` that no longer matches anything is itself a finding
(`unused-allow`), so suppressions cannot rot — the audit rules are in the
reference. In tests and fixtures, `[@litany.expect "rule: reason"]`
additionally *requires* the finding and fails when it disappears. File scope
is the floating form, `[@@@litany.allow "rule: reason"]`.

Findings appear in your editor without any editor plugin. `litany lint-rules`
generates, per library, dune rules of the form:

```lisp
(rule
 (alias lint)
 (action (run litany unit inventory --cmt %{cmt:inventory} --source %{dep:inventory.ml})))
```

`litany unit` lints one unit, spawns nothing, needs no lock and no roster —
its argv is the roster — and prints findings in the compiler's own report
format, exiting non-zero when there are any. Because dune parses that format
from failing actions and serves it over RPC, `dune build @default @lint -w`
shows Litany findings in VS Code, Emacs, and Vim as ordinary warnings, with
dune itself as the incremental engine: only modules whose `.cmt` changed are
re-linted. (Add `@lint` to your existing watch invocation — a second watch
server cannot take dune's lock.)

Everything else is discoverable from the binary: `litany rules` lists the
catalog with groups and defaults, `litany explain needless-list-length`
prints a rule's full documentation, and both are generated from the same
declarations the engine runs, so they cannot drift.

### Writing a rule

A rule is one OCaml value in one file. `open Litany` re-exports the
compiler's `Typedtree`, `Parsetree`, `Location`, `Path`, and `Shape.Uid`
alongside Litany's own modules, so the examples below compile warning-free
with that single open, and a third-party rule library depends only on
`litany` in its dune stanza — the compiler-libs pin is Litany's, stated once.

Here is the complete `needless-list-length` — types resolved, both operand
orders, shadowing handled, with a safe fix:

```ocaml
(* rules/needless_list_length.ml *)
open Litany

let meta =
  Rule.meta ~name:"needless-list-length" ~group:Perf ~since:"1.0" ~fix:Sometimes
    ~summary:"List.length used only to test emptiness"
    ~doc:{|`List.length xs = 0` walks the whole list to answer a constant-time
question. Compare with `[]` instead.

    (* bad *)  if List.length xs = 0 then …
    (* good *) if xs = [] then …

Fires only when both the comparison operator and `List.length` resolve to
their `Stdlib` declarations, so shadowed or rebound names never match.|}

let length_of x = Pat.(apply1 (ident "Stdlib.List.length") x)

let empty ~op =
  Pat.(apply2 (ident op) (length_of __) (int 0)
   ||| apply2 (ident op) (int 0) (length_of __))

let rule =
  Rule.expr meta @@ fun unit expr ->
  let hit op repl = Pat.run (empty ~op) expr (fun xs -> (xs, repl)) in
  let found =
    match hit "Stdlib.(=)" " = []" with
    | Some _ as h -> h
    | None -> hit "Stdlib.(<>)" " <> []"
  in
  match found with
  | None -> []
  | Some (xs, repl) ->
      let fix =
        Option.map
          (fun src ->
            Fix.safe_replace expr.exp_loc (src ^ repl) ~title:"compare with []")
          (Unit.atom unit xs)
      in
      [ Finding.v ?fix ~loc:expr.exp_loc
          "`List.length` walks the whole list to test emptiness" ]
```

What the pieces are: `Pat.run p x k` matches the typed expression `x` and
passes captures (`__`) to `k`, returning `None` on no match. `Pat.ident
"Stdlib.List.length"` matches an identifier whose **resolved declaration
UID** equals the one that name denotes — so `module L = List` matches, a
local `let length` never does, and there is no separate "is it a list?"
check because if the callee *is* `Stdlib.List.length` the type checker
already proved the argument is a list. `Unit.atom` is the expression's
original source text wrapped in parentheses unless it is syntactically
atomic; it returns `None` in preprocessed units or when the location does
not slice cleanly, in which case the finding ships without a fix.

Rules see the compiler's own trees; nothing is wrapped. Syntax-only rules
use `Rule.attribute`/`Rule.parsed` over the pre-PPX parsetree; text rules
use `Rule.source`. Cross-module rules add a per-unit `collect` and a
whole-project `report` (see the reference).

Testing is a miniature real dune project, and the assertion language is the
product's own `expect`:

```
rules/fixtures/needless-list-length/
  dune-project  lib/dune
  lib/cases.ml          ; expectations are [@litany.expect …]
  lib/cases.fixed.ml    ; golden after --fix; must compile
```

```ocaml
(* lib/cases.ml *)
let is_empty xs = (List.length xs = 0) [@litany.expect "needless-list-length: fires"]
let reversed xs = (0 <> List.length xs) [@litany.expect "needless-list-length: reversed"]

(* negatives — must stay silent: *)
module List = struct let length _ = 0 end
let shadowed xs = List.length xs = 0
let not_emptiness xs = Stdlib.List.length xs = 2
```

A rule is added by hand: the rule module, its registry entry, and its
fixture directory, per the layout above (no scaffolder — amended
2026-08-19; dev workflows are never public CLI, and scaffolding tooling
was cut entirely). Fixture directories are `data_only_dirs`, and the suites copy
each to a temporary directory and builds there, so the enclosing workspace
and any watch server are untouched). Rule tests are ordinary dune tests (amended 2026-08-19; formerly specced
as a `litany test` subcommand — there is no harness product): each rule's
test directory holds a hand-written `dune` file, a test suite over shared
helpers in an ordinary test-support library, and a compiled fixture. The
suite builds the fixture, runs the real engine with only that rule selected — an unfulfilled `expect` or an
unexpected finding fails — applies fixes, diffs against the `.fixed` golden,
and **compiles it**. Inside fixtures, fixes for `expect`ed findings are
applied to produce that diff; everywhere else, `--fix` never touches a
suppressed or expected finding. `litany corpus` runs the catalog over a
pinned set of real opam packages (`corpus.toml`) and diffs findings between
revisions; a nursery rule graduates only with a reviewed corpus diff.

## Reference-level explanation

### The unit contract

The core consumes **units** and, optionally, a **roster**; it spawns nothing
and knows no build system.

A unit is `(source path, source bytes, cmt bytes [, cmti bytes])`, admitted
only under a **freshness witness**:

- *Direct*: the digest of the source-tree file the user edits equals
  `cmt_source_digest` — the 16-byte digest the compiler recorded of the file
  it read (`ocaml/file_formats/cmt_format.ml`, save path). The algorithm is
  compiler-version-dependent with no in-record discriminator — MD5 before
  the 5.5.0 release, BLAKE128 from it — so the check accepts a match under
  either (spike C: 0/1,388 real artifacts matched as BLAKE128, 1,226 as
  MD5; an accidental 16-byte match is negligible). The source path is
  always adapter-supplied; `cmt_builddir`/`cmt_sourcefile` are never
  resolved as filesystem paths (spike C: build-path prefix mapping makes
  `cmt_builddir` fictitious — `/workspace_root` — in 100% of real
  artifacts). `_build` copies are never the witness anchor, except for
  generated units whose only source is in `_build`.
- *Derived* (preprocessed units, where the compiler read `<m>.pp.ml`): the
  digest matches the built `.pp.ml`, **and** build-currency holds by one of:
  (i) this run executed the build successfully; (ii) the run is inside dune
  with the check alias among the invoking rule's dependencies; (iii)
  `--trust-build` was passed, explicitly trusting the build system's
  editable→pp tracking (CI whose previous step built). Condition (ii) is
  detected via the `INSIDE_DUNE` environment variable dune sets for actions;
  that the check alias is among the deps is the generated rule's contract —
  trusted, not observed. Without one of these, Derived units skip with
  reason `derived witness requires a build`. The
  editable source's digest is also captured at join time — it is the write
  baseline for fixes.

A unit is *preprocessed* iff its witness is Derived **or** its `cmt_args`
contain `-ppx` or `-pp` (dune's `staged_pps` compiles the editable source
under `-ppx`, so such units carry a Direct witness but a post-PPX tree).

A unit that fails admission is a **skip** with a reason (stale, no artifact,
unreadable artifact, parse error, modified during run), listed in the
summary. (Generated units are not admission failures — they admit normally
and become the *facts-only* outcome; see Cross-module rules.) Corrupt artifacts (decode failure after a good magic number)
are skips, not crashes. `Unit.t` has no other constructor, so a typed
finding on unverified code is unrepresentable.

A roster, when an adapter can supply one, is the trusted enumeration that
unlocks project rules: the complete unit list, per-unit library ownership
and stanza kind, and library visibility (public or not); the library
dependency graph is an optional extra, required only by the planned
cone-scoped refinement. Lanes without a roster run local rules only.

### Adapters and the unit file

The core consumes one value — the unit list plus optional roster — and the
**unit file** is that value's serialization: canonical s-expressions
(csexp), one `(litany-units 1)` version header followed by one form per
unit —

```
(unit (source lib/foo.ml) (cmt _build/default/lib/.foo.objs/byte/Foo.cmt)
      (cmti …) (pp-source …) (library foo) (public true) (kind lib))
```

— where only `source` and `cmt`/`cmti` are required and unknown fields are
errors. Csexp, not JSON, because paths are bytes: csexp atoms are
length-prefixed raw bytes, so any filename round-trips losslessly, while
JSON strings must be valid UTF-8 and would force an escaping convention;
and because csexp is the ecosystem's machine format — `dune describe`
offers exactly sexp/csexp, and the merlin configuration protocol is csexp —
so Litany already carries the parser and a dozen lines emit it from any
language. Adapters produce it. Built-in adapters construct the value in
memory and can dump it (`litany units --save FILE`; `--dump` pretty-prints
as sexp for humans); `litany check --units FILE` consumes one from any
producer. A unit file that supplies `library`/`public`/`kind` for every
unit is a full roster: project rules work outside dune. Per-unit witnesses
still gate every join, so a stale or wrong unit file costs only skips,
never findings.

**dune** (the built-in default). `litany check` spawns `dune build @check` (skipped by
`--no-build`; `@check` materializes `.cmt`/`.cmti` for libraries and
executables without linking, `_ref/dune/src/dune_rules/check_rules.ml:3-28`),
then `dune describe workspace --format csexp --lang 0.1 --with-deps` once.
Two subprocesses per check pass. The roster is the union of the describe
reply and an **artifact walk** of the context's build directory for
`.cmt`/`.cmti` files belonging to no described module — necessary because
`(test)` stanzas do not appear in `describe workspace`
(`_ref/dune/bin/describe/describe_workspace.ml:592-601` matches only
executables and libraries) even though `@check` builds their artifacts;
walked-only units join under the ordinary witness and are counted
(`n units via artifact walk`). Library visibility does not come from
describe (its `Lib` record has no such field); Litany reads `(public_name
…)` from the workspace's `dune` files with a tolerant s-expression scan,
validated against the roster by library name — and an unknown visibility
defaults to **public** (root), never to dead-code candidate. A `describe`
field for tests and visibility is a tracked upstream ask. Build failure:
dune's own errors stream through, then exit 2 — lint presupposes a building
project. A running watch server: `dune build` forwards to it, but `dune
describe` cannot take the lock — the run refuses with the remedy (use the
lint alias; or `litany units --save FILE` while the server is stopped, then
`litany check --no-build --units FILE` — stale entries surface as skips).
`@check` exists only in merlin-enabled contexts; a context without it is
named in the refusal.

**artifact walk** (built in, adapter of last resort). `litany check --cmt-root DIR` pairs artifacts with
sources by the Direct witness alone. No roster: local rules only, and the
summary says `roster: none (project rules unavailable)`.

**inside the build**. `litany unit <name> --cmt PATH --source PATH` lints
one unit: no subprocesses, no lock, no roster, always the `compiler` output
format, exit 1 on findings. `litany lint-rules` generates the per-module
`(rule (alias lint) …)` stanzas with `%{cmt:…}` dependencies
(`_ref/dune/src/dune_lang/pform.ml:658-666` — the pform declares the cmt as
a rule dependency, so dune's scheduler is the incremental engine and
freshness is held by dune itself). Regenerating the stanzas when modules are
added is the project's task, wired as a promotion rule by `lint-rules`.
Incremental cost per save is one process per changed module (~50–150 ms;
canonical-UID resolutions are memoized in the shared cache keyed by
defining-cmi digest).

### The engine

The core is a pure function: `findings = f(units, roster, config)`. All IO
lives in the driver. Per unit, the engine makes **one traversal** per
substrate (one `Tast_iterator` walk of the typedtree; one walk of its own
parse of the source for parsed/attribute rules; one pass over lines for text
rules), dispatching every subscribed rule at each node. Rules never own
traversal.

The **emit contract** enforces source ownership. A finding is kept only if
its location is (a) non-ghost, (b) inside the unit's own editable source
file, (c) **offset-consistent** — its `(pos_lnum, pos_bol, pos_cnum)` agrees
with the anchor file's actual line index; textual preprocessors like cppo
emit `#` line directives that rewrite names and lines while `pos_cnum` keeps
counting pp-file bytes (`ocaml/parsing/lexer.mll:342-352`), and such
locations degrade to line-anchored findings without carets, their fixes to
Display — and (d) corroborated by a node span in the engine's own pre-PPX
parse (already built for suppression matching), which stops PPXes that copy
user locations onto generated code. Findings are deduplicated by (rule,
location, message); dropped findings are counted. This is the entire PPX
story from a rule's point of view: generated nodes cannot produce
diagnostics, and no rule ever checks for them. Because the cmt stores the
*post-expansion* typedtree, typed rules do see real, expanded code —
including inside PPX-using modules, which the WIP excluded wholesale. Fixes
in preprocessed units are automatically downgraded (Safe → Unsafe).

Units whose editable source does not parse as OCaml (cppo sources and kin)
run typed rules only, with a summary note that parsed rules and attribute
suppression are unavailable there.

### `Pat` and identity

`Pat` is a continuation-style typed-pattern combinator library in the mold
of zanuda's `Tast_pattern` (itself modelled on ppxlib's `Ast_pattern`;
`_ref/zanuda/src/pattern/Tast_pattern.mli`): `('matched, 'k, 'result) t`
values with `__` capture, `drop`, `|||` alternation, and constructors
mirroring `Typedtree` shapes. In 1.0, `Pat` covers typed trees; parsed
rules match raw `Parsetree` directly, and parsetree combinators land later.

Its one semantic primitive is identity: `Pat.ident "Stdlib.List.length"`
matches an identifier whose `val_uid` (every `Types.value_description`
carries its declaration `Shape.Uid.t`; constructors and labels carry
`cstr_uid`/`lbl_uid`) equals the UID that canonical name denotes. Canonical
names are resolved once per run by **signature walking** (mechanism chosen
by spike A, 12/12 against measured use-site uids): read the defining
compilation unit's `.cmi` — located via the roster's include dirs and the
toolchain's stdlib directory — and walk `cmi_sign` items by name:
`Sig_value` yields `val_uid`, `Sig_module` descends through
`Mty_signature`, hops `Mty_alias` to the aliased unit's cmi, expands
`Mty_ident` via `Sig_modtype`, and descends `Mty_functor` results for
functor-body names (`Stdlib.List.length` resolves through `stdlib.mli`'s
`module List = List` into `Stdlib__List`'s cmi). This yields exactly the
interface uid use sites carry, works for units with or without an `.mli`,
and needs only `.cmi` files — which installed dependencies always have.
One refinement is load-bearing: *inside* the defining unit itself, use
sites carry implementation uids, so when linting unit U each canonical uid
with `comp_unit = U` is extended with U's own `cmt_declaration_dependencies`
reverse image — only `Definition_to_declaration` pairs whose two sides are
both `Item`s of U with `Impl`→`Intf` provenance (the filter matters:
ascriptions record cross-unit pairs that must not be admitted). No global
`Env` or `Load_path` state is touched; nothing runs per node; per-node work
is a UID equality against a 1–2 element set. A name that fails to resolve
makes its pattern match nothing at check time (a workspace without `Base`
must not error on a rule mentioning `Base.*`) and is a hard error in
the rule's tests: every `Pat.ident` literal must resolve in its
fixture, so a typo is a failing test, not a silently dead rule.

Documented limits of the matching relation (spike-verified): a module
*ascription* (`module M : S = List`) mints fresh UIDs — `M.length` and
`List.length` are distinct identities, each nameable, neither matching the
other; all instances of a functor application share the functor body's
interface UIDs, so a canonical name into a functor body matches every
instance. (`Shape_reduce` over `cmt_impl_shape` was the draft mechanism and
is rejected on spike evidence: it yields implementation uids that never
match use sites without a bridge, needs `.cmt`s installed dependencies
lack, needs a synthetic-application hack for functor paths, and resolves
*through* ascriptions to the wrong identity.)

The SDK deliberately offers **no** name-string comparison on identifiers:
spelling is not identity (camelot's `==`-by-spelling is the canonical
counterexample). `Pat` is also the version-churn concentrator: it is the
one module that destructures compiler trees wholesale, so a compiler minor
is absorbed mostly inside it (see release mechanics).

### Rules and metadata

```ocaml
Rule.meta :
  name:string ->            (* kebab-case; stable forever; renames leave a
                               tombstone alias in ~renamed_from, honored by
                               config validation and allow/expect matching,
                               with a rename warning *)
  group:Group.t ->          (* Correctness | Suspicious | Perf | Style
                               | Pedantic — the semantic category *)
  ?stability:Stability.t -> (* Stable (default) | Nursery: off regardless of
                               group; graduates by corpus evidence without
                               changing name or group *)
  since:string ->
  fix:Fix.availability ->   (* None | Sometimes | Always — a promise enforced
                               in the rule tests and at registry construction; a
                               fix:None rule whose callback returns a fix is a
                               rule failure *)
  summary:string ->
  doc:string ->             (* markdown; the docs page and `explain` text *)
  Rule.meta
```

Constructors fix the callback type: `Rule.expr`, `Rule.pattern`,
`Rule.binding`, `Rule.attribute`, `Rule.parsed`, `Rule.source`,
`Rule.project`. Callbacks are pure — they receive the `Unit.t` (or
`Source.t`) and the node, and return `Finding.t list`.

**Group is policy** (clippy's law): `Correctness` → error, on by default;
`Suspicious`, `Perf` → warning, on; `Style`, `Pedantic` → warning, off.
Severity is the group's at render time; config may escalate. `select =
["nursery"]` selects by stability tier; group names select by category.

Registration is one list, `Litany_rules.all`. Duplicate names abort at
startup. `litany rules`, `litany explain`, the docs site, config validation,
and JSON metadata all derive from the declarations.

Third parties extend by recompiling — the SDK carries no process entry
(`bin/` is the composition root; amendment 2026-08-19): the mechanism is a
custom executable in the style of `Litany.main ~rules:(Litany_rules.all @
My_rules.all)` in a five-line executable; their rule names render as
`org/rule-name`. No dynlink (rejected — see Rationale); recompilation is
what keeps the binary-digest cache key honest.

Per-rule options: a rule may declare a typed options schema in its meta;
config keys under `[lint.per-rule.<name>]` are validated against it and the
decoded value is passed at rule construction.

### Diagnostics and output

```ocaml
type Finding.t = {
  rule : string;
  loc : Location.t;              (* gated by the emit contract *)
  message : string;
  related : (Location.t * string) list;
  fix : Fix.t option;
}
```

Severity comes from the rule's group (post-config). Renderers:

- `text` (default): the pretty form shown in the guide — location line,
  message, quoted source with carets, fix line, one summary line.
- `compiler`: the exact grammar dune's `ocamlc-loc` parser accepts,
  validated by spike B against the vendored parser (26 cases): blocks of
  `File "<path>", line L, characters A-B:` (`lines L-M` for multi-line
  spans) directly followed by `Warning 0 [<rule-name>]: <msg>` or
  `Error: <msg>` — **no excerpt or caret lines** (a caret line without an
  excerpt is fatal to the whole stream; excerpts are discarded by the
  parser anyway — `compiler` is a wire format, `text` keeps the pretty
  excerpts). Emitted to **stderr with stdout completely silent** (dune
  gates on the concatenation `stdout ^ stderr` starting with `File `), LF
  endings, no ANSI, nothing before the first block or after the last (a
  summary line corrupts the last finding's message), and the process exits
  non-zero when findings exist (dune parses only failing actions). Columns
  are the compiler's own convention — 0-based `pos_cnum - pos_bol`,
  end-exclusive, emitted verbatim (dune applies no adjustment). Message
  continuation lines are indented and sanitized so none matches the
  flush-left header pattern (a forged header truncates every later
  finding: the parser stops at the first malformed block). Error-severity
  findings repeat the rule name inside the message text (`Error: <msg>
  [<rule-name>]`) because dune discards the structured code on the error
  form before editors see it. Related locations (M9) are emitted as an
  indented header plus indented message after the main message, which
  parses into the report's `related` list. Golden-tested byte-for-byte
  against the vendored `ocamlc-loc`, including the three negative cases
  (leading text, caret-only line, trailing summary).
- `json`: JSON Lines — for editors and dashboards, where JSON is the
  lingua franca; paths whose bytes are not valid UTF-8 are emitted in an
  explicit reversible encoding (a `path_bytes` hex field beside the lossy
  `file`), so the unit-file byte argument does not recur here — one finding
  object per line, then one trailer object
  `{"summary": {findings, fixable, units, skipped: [{path, reason}],
  roster}}`. Editors and dashboards consume records; CI consumes the
  trailer.
- `github`: workflow annotations, auto-selected when `GITHUB_ACTIONS` is
  set.

Ordering and byte-determinism are Law 5; no renderer may depend on
parallelism or cache state.

### Fixes

```ocaml
type Fix.t = {
  title : string;
  applicability : Safe | Unsafe | Display;
  edits : (span * string) list;      (* byte-range replace/insert/delete,
                                        against the editable source *)
}
```

Constructors make safety explicit (`Fix.safe_replace`, `Fix.unsafe_…`; the
bare constructor defaults to Unsafe — safety is earned). Findings suppressed
by `allow` or required by `expect` are excluded from `--fix` (the `litany
test` harness is the sole exception, where expected findings' fixes produce
the `.fixed` golden).

Application is one pass per analysis: filter by requested applicability,
sort edits, drop overlapping fixes deterministically (first by span, then
rule name), apply atomically per file (temp-file + rename), reparse — if the
result does not parse, roll the file back and report a fixer bug. Each write
is preceded by a re-check of the editable source's digest captured at join
time; a fix computed against bytes that changed is discarded, not written.

Because typed findings derive from cmts, a fixed file's artifacts are stale
by construction, so **convergence spans builds, not memory**: after any pass
that applied a fix, `--fix` re-runs the build, re-joins, re-lints, and
repeats, applying deferred conflict losers on later passes (capped at 3
passes initially; the cap is a measured dial, not a law — leftovers are
reported `not applied (needs another pass)`, never looped silently). Under
`--fix --no-build` exactly one pass runs. If a post-fix build fails, Litany
stops, prints the build error and the list of applied fixes, and exits 2
with `files were modified; git diff shows the applied fixes` — it never
silently rolls back and never lints a tree that no longer matches its
artifacts.

Compile-preservation is a test-time theorem, not a runtime hope: every
`Always`-fix rule's fixture has a `.fixed` golden that must build in CI.

### Suppression

Two attribute forms plus config selection:

- `[@litany.allow "rule: reason"]` on any expression/item; floating
  `[@@@litany.allow "rule: reason"]` scopes to the rest of the file.
- `[@litany.expect "rule: reason"]` — same scoping, and *requires* at least
  one matching finding.

Reasons are mandatory. Matching is by span containment against the engine's
own pre-PPX parse of the source, so suppression works even when a PPX
rewrites the node away. Hygiene is engine-owned: an unmatched `allow` yields
`unused-allow` (with a safe deletion fix); an unmatched `expect` yields
`unfulfilled-expect`. Both audits are gated on the named rule actually
having run on that unit — enabled, joined, not failed — because absence of
a finding is only evidence when the rule looked (the staticcheck U1000
lesson). Tombstone aliases are accepted with a rename warning.

Config `per-path.ignore` is *selection of reports*, never of analysis: it
is not audited, needs no per-site reason, and — crucially — ignored units
still join and still run project-rule `collect` (see below). Text rules are
suppressed only this way. Precedence collapses to lexical scope: innermost
attribute wins; config is the outer ring.

### Cross-module rules

One constructor, same architecture:

```ocaml
Rule.project : Rule.meta ->
  collect:(Unit.t -> 'fact list) ->      (* pure; per unit; cached *)
  report:('fact list -> Finding.t list) ->  (* once, deterministic order *)
  Rule.t
```

Facts must be Marshal-safe (no closures, no custom blocks); the rule tests
round-trips every fixture's facts through Marshal, so an unmarshalable fact
fails the rule's own tests, not a user's run. There is no codec API — the
cache key includes the binary digest, so a schema change invalidates by
construction. Identity is the compiler's: `Unit.exports`, `Unit.uses`, and
`Unit.deps` are engine accessors over `cmt_uid_to_decl`,
`cmt_declaration_dependencies`, and the shape-reduced occurrence tables —
the UID bridge dead_code_analyzer proved, minus its first-match joins.
`Shape.Uid.t` is the stable cross-unit key that staticcheck had to invent
`objectpath` for; OCaml records it for free.

- **Per-unit outcomes are three**, not two: *linted* (findings + facts),
  *facts-only* (generated units — ocamllex, menhir, `(rule)` outputs — whose
  cmt joins perfectly well: no findings in files the user cannot edit, but
  `collect` runs, so the universe stays complete), and *fact-skip* (no
  admissible artifact). The summary distinguishes the three.
- **Roots are explicit** and computed from roster metadata: exports of
  public libraries, executable entry modules, and `[@litany.root "reason"]`
  annotations. Public-library exports are roots, never candidates — external
  consumers exist outside every universe Litany can enumerate. Unknown
  visibility means public. `closed-world = true` (or
  `--assume-closed-world`) opts a workspace out.
- **Transitivity** lives in the rule: the built-in `dead-code` rule's
  `report` runs reanalyze's collect-then-solve reachability with
  provisional-dead cycle handling. `unused-export` is deliberately
  non-transitive — fewer, harder findings first.
- **Honesty**: a project rule's claim is universally quantified, so project
  rules run only when no roster unit is a *fact-skip*. When withheld, the
  summary names the blocking units and reasons, and `litany check
  --explain-withheld` prints which skip blocked which rule; a permanent
  fact-skip (a `(bin_annot false)` directory) is called out as such with the
  remedy. Messages name the universe: "never used **in this workspace**".
  There is no "probably unused". A planned refinement (not 1.0):
  cone-scoped withholding — withhold a finding only when a fact-skip lies in
  the subject's reverse-dependency cone, computable from the roster's
  `--with-deps` graph.

### Cache and parallelism

Per-unit results (findings + facts + skip status) are content-addressed in
`$XDG_CACHE_HOME/litany/<workspace-digest>/`, keyed by (cmt digest, source
digest, resolved-config fingerprint, selected-rule set, **binary digest** —
a digest of the Litany executable itself, so any recompile invalidates;
this is the one salt, and every other section that mentions the cache means
this key). Every semantic input is in the key, so a wrong cached "clean" is
structurally impossible. No mtimes anywhere.

`<workspace-digest>` is BLAKE128 of the workspace root's realpath; each
workspace directory stores that realpath in a marker file. Entries record a
last-read stamp; at the end of a run Litany opportunistically deletes
entries unread for 30 days and workspace directories whose marker path no
longer exists (ruff's policy). `litany cache clean` forces it; `--cache-dir
DIR` / `LITANY_CACHE_DIR` override the location (the documented CI recipe
persists it with `actions/cache`); `--no-cache` disables reads and writes.

Parallelism shards units across workers; the pure core makes the merge a
canonical sort. The engine touches no compiler-libs global state on the
match path (`Pat` compares UIDs recorded in the tree; canonical UIDs are
resolved once up front; nothing calls `Env`/`Load_path` per node) — whether
workers are domains or processes is an implementation decision behind a
benchmark and a test that fails on any global-state access. Compiler-libs
decode remains confined to one unit at a time per worker either way.

Watch mode is dune's: the lint alias under `dune build @lint -w`. No
daemon.

### Failure semantics

Four concepts carry every failure: **refusal** (exit 2, nothing runs, one
actionable message — refusal aborts before rules run, so during a run, rule
failure dominates findings: 3 > 1), **skip** (per-unit, reason enumerated),
**rule failure** (isolated to one rule × unit, run continues, exit 3),
**findings** (exit 1). Rows marked `—` are non-failures, shown for
contrast; *facts-only* is a per-unit outcome, not a failure.

| Situation | Concept | The user sees |
|---|---|---|
| Build fails | refusal | dune's own errors, then `litany: build failed; nothing checked.` |
| Stale artifact (`--no-build`) | skip | `skipped lib/foo.ml (stale — run dune build @check)` |
| Unreadable/corrupt artifact | skip | `skipped lib/foo.ml (unreadable artifact — rebuild)` |
| cmt magic mismatch | refusal | `artifacts were built by OCaml 5.6; this litany reads 5.5 — install litany in this switch` (checked before any decode; both versions named) |
| PPX'd unit without build-currency | skip | `skipped lib/foo.ml (derived witness requires a build — build first, or pass --trust-build)` |
| PPX-generated code | — | nothing: unowned locations are dropped and counted |
| Generated unit (ocamllex …) | facts-only | counted in summary; no findings; project rules unaffected |
| Rule raises | rule failure | `internal: rule 'x' failed on lib/y.ml (…) — please report`; everything else completes |
| Editable source not valid OCaml (cppo) | — | typed rules run; summary notes parsed rules and attribute suppression unavailable for that unit |
| Fix conflict | — | loser deferred to the next build-and-relint pass; leftovers reported `not applied (needs another pass)` |
| Post-fix build failure | refusal | build error + list of applied fixes + `files were modified; git diff shows the applied fixes` |
| Config error | refusal | `litany:4: unknown rule "styel" (did you mean "style"?)` |
| dune missing | refusal | `dune not found — use --units or --cmt-root for artifacts built elsewhere` |
| Watch server holds the lock | refusal | `dune describe cannot run beside a watch server — use the lint alias, or litany units --save` |
| Context without `@check` | refusal | `context 'X' has no @check (not merlin-enabled) — lint the default context` |

### Compiler-version support

**Support window: the last three OCaml minors** (today: 5.3, 5.4, 5.5).

**Mechanism: one package, one branch, one release** — the zanuda/reanalyze
model, not merlin's. The version-churn surface is deliberately
concentrated (`Pat` internals, the loader, the resolver, and any in-tree
rule matching raw constructors), and inside those modules
version-conditional compilation (`[%%if ocaml_version …]`) absorbs the
per-minor deltas; the opam bound spans the whole window. A single release
then compiles against whichever supported compiler the user's switch has —
zanuda ships exactly this shape today, one release with the bound
`>= 4.14.2 < 5.0 | >= 5.3 < 5.4 | >= 5.5` and five conditional sites in
its pattern module (`_ref/zanuda/src/pattern/Tast_pattern.ml`,
`zanuda.opam`). Merlin cannot do this because it vendors a whole forked
compiler frontend per minor and therefore needs a branch and a
version-suffixed release per compiler (`merlin-lib.opam` pins one minor;
tags like `v5.5-503`); Litany's ~2–3k-line churn surface does not force
that. What single-source multi-version does *not* mean: one binary reading
every version's artifacts — an installed Litany links one compiler-libs
and reads that compiler's artifacts only; opam installs the right build
per switch by construction, which is the property that matters.

CI builds and runs the fixture suite on every minor in the window (one
cached switch each); the corpus job likewise. Fixtures are compiled by
each leg's own compiler, so magic and digest-algorithm differences are
exercised, not simulated.

**Recurring cost statement.** Typical minor: 200–600 changed lines behind
`[%%if]`, 1–2 engineer-weeks (evidence: zanuda's 2–6 conditional sites per
minor); restructuring minors (the 5.2 `Texp_function`-class changes) can
cost 4–8 weeks. Corpus CI: one cached opam switch per windowed minor
(~2 GB cache each; 30–90 min cold, <10 min warm), nightly and on release —
never per-PR. Dropping the oldest minor when a new one enters the window
deletes its `[%%if]` branches and its CI leg — single-branch support means
no backport multiplication. The release checklist records changed-lines
and elapsed engineer-days per minor in `doc/maintenance-ledger.md`.
**Escape hatches (chosen policy, not derived):** a minor that cannot be
absorbed single-source gets a frozen merlin-style branch + version-
suffixed release for the *old* window instead of contorting the shared
tree; if the ledger shows two consecutive minors above 4 weeks, the next
RFC evaluates vendoring a frozen compiler frontend for the reading side
(the merlin/ocamlformat model) — a façade retrofit stays off the table
once third-party rules exist against raw `Typedtree`.

### Concept census

- **User (9):** rule, group (+ nursery stability tier), finding, fix,
  allow/expect, root (`[@litany.root]`, cross-module only), the `litany` config file
  (including `closed-world` and per-path tables), skip (plus facts-only, a
  per-unit outcome rather than a failure), exit codes.
- **Rule author (7 Litany nouns):** `Rule` (+`Rule.meta`), `Pat`, `Unit`,
  `Source`, `Finding`, `Fix`, facts (`'fact` in `Rule.project`).
  Re-exported, not wrapped: `Typedtree`, `Parsetree`, `Location`, `Path`,
  `Shape.Uid`.
- **Engine-internal (6):** unit contract (witness), roster, adapter (the
  unit file is its serialization),
  substrate (typed/parsed/text — what a traversal walks), cache entry,
  worker.

The WIP's 44 public nouns and 8 ID types reduce to these because the
freshness proof moved from checked evidence chains to a constructor that
cannot be called without the proof.

### Size and order

Estimates re-derived against measured reference code (zanuda's
`Tast_pattern` is 1,320 + 332 lines for typed-only partial coverage; ruff's
fix applier 416 + its convergence loop; ruff's ecosystem-diff tool 2,028;
the WIP's own strict-TOML config was 954):

| Component | est. lines |
|---|---|
| driver + CLI (six subcommands) | 700–1,000 |
| dune adapter (describe decode, visibility scan, build spawn, walk) | 700–900 |
| unit-file + artifact-walk adapters | 300–400 |
| unit loader (cmt read, magic, witnesses) + canonical-name resolver | 900–1,250 |
| `Pat` (typed set; parsed rules match raw `Parsetree` in 1.0) | 1,700–2,400 |
| engine (traversals, dispatch, emit contract, ordering) | 800–1,200 |
| `Unit` accessors (exports/uses/deps over UID tables) | 400–700 |
| diagnostics + renderers (text, compiler, json, github) | 700–1,100 |
| fix core (types, single-file apply, reparse-rollback) | ~400 |
| `--fix` loop (build-spanning convergence, conflicts) | ~300 |
| suppression + audit | 600–900 |
| config file (slice 2) | 700–1,000 |
| project rules + built-in dead-code | 1,000–1,600 |
| cache + workers | 800–1,200 |
| test-support library | 300–500 |
| corpus runner | 800–1,200 |
| **engine + tooling total** | **≈ 11–16k** |
| ~20 launch rules × 40–60 lines | 800–1,200 |

Minimum shippable slice, each step shipping alone:

1. `litany check` (dune adapter + `--cmt-root`) + typed/parsed/source
   rules + `Pat` + text output + CLI selection (`--select`/`--ignore`; no
   config file yet) + suppression with audit + fix core (required by
   the `.fixed` golden rules and the fix promise check) + `litany
   test` + the first ~10 rules — beats the WIP's shipped surface.
2. `litany check --fix` (build-spanning loop) + the `litany` config file.
3. `compiler`/`json` formats + `litany unit` + `litany lint-rules` (editor
   delivery) + the unit-file adapter contract (`--units`, `units --save`).
4. Cache + parallel workers.
5. `Rule.project` + `unused-export` + `dead-code`.
6. Corpus tooling + docs site. Per-rule options land with the first rule
   that needs them.

## Laws

1. **Join or die, loudly.** A `Unit.t` exists only under a freshness
   witness, and only after its cmt magic matches this Litany's compiler —
   mismatch is a refusal naming both versions and the remedy, checked
   before any decode. Prevents: findings against code the user already
   changed; dead_code_analyzer's "ran fine, reported nothing".
2. **Identity, not spelling.** Semantic matching compares declaration UIDs;
   the SDK offers no name-string identifier comparison. Prevents: the
   camelot `==` bug family (aliases, `open`, shadowing).
3. **Report only owned bytes.** Findings anchor at non-ghost,
   offset-consistent locations in the unit's editable source, corroborated
   by the pre-PPX parse, or are dropped and counted. Prevents: diagnostics
   inside PPX output; carets and fixes at wrong offsets under textual
   preprocessors.
4. **Pure core.** findings = f(units, roster, config); all IO in the
   driver. Prevents: the global-mutable-state architecture of every prior
   OCaml linter; enables cache and parallelism as corollaries.
5. **Total order.** Output sorted by (path, byte offset, rule name);
   byte-identical across runs, parallelism, and cache states. Prevents: CI
   diff noise.
6. **Silence is enumerated and absence is quantified.** Every unit ×
   substrate is analyzed or is a listed skip with a reason; absence claims
   quantify over a complete, named universe — project rules withhold on any
   fact-skip (facts-only units keep the universe complete), messages name
   the workspace, public exports are roots. Prevents: silence
   indistinguishable from cleanliness; lying "unused" claims.
7. **Suppressions are audited when auditable.** Unmatched `allow`/`expect`
   are findings, gated on the rule having run. Prevents: suppression rot
   and false audits.
8. **A fix never writes unverified bytes.** Editable-source digest
   re-checked at write; reparse-or-rollback; convergence spans builds; Safe
   proven by compiled goldens. Prevents: shipped corruption; "safe" as a
   vibe; linting trees that no longer match their artifacts.
9. **One declaration.** All rule metadata lives in `Rule.meta`; every
   surface derives from it; promises are checked. Prevents:
   triplicated-metadata drift.
10. **The engine walks once and owns traversal.** Rules subscribe; none can
    skip or re-enter. Prevents: per-rule walk scaling and silent coverage
    holes.

## Drawbacks

- **Typed linting needs artifacts, and rich analysis needs a roster.** The
  dune adapter supplies both; the unit-file lane requires build-system
  cooperation; the bare walk gets local rules only. Non-dune users are
  served by contract now, but the batteries are dune's.
- **A three-minor support window on one branch.** Every change must
  compile and pass fixtures on three compilers; `[%%if]` branches live in
  the churn modules until a minor ages out. Cost, metric, and escape
  hatches are in Compiler-version support; the façade alternative was not
  cheaper — it audited a 6.2k-line adapter per minor instead, and blinded
  rules.
- **Recompile-to-extend.** No installable third-party rule packages without
  building a custom binary; forecloses a casual-rule ecosystem until a
  declarative layer exists.
- **Trust in the build system's editable→pp tracking for preprocessed
  units.** The Derived witness's editable→pp link is the build's guarantee,
  not Litany's; mitigations are the emit contract and build-currency.
- **The break is total.** ~33k lines and ten design documents are
  superseded, not amended. The laws survive; the code mostly does not.
- **Created vs destroyed, netted:** created — a 3-minor CI/corpus matrix,
  corpus infra + pin upkeep, ~20 fixture projects, the tombstone registry,
  cache GC support surface (2–4 engineer-weeks/year typical, with
  occasional 4–8-week minors). Destroyed — the audited 6.2k-line per-minor façade
  audit, the 6,989-line capture pipeline, 60,710 lines of hand-assembled
  graph tests, and the 2,085-line triple-documented re-export surface.

## Rationale and alternatives

Three blind designs and one informed design were produced independently
after a shared factual audit. All four converged, without contact, on: the
digest-join input model, direct compiler-libs exposure behind a
`Tast_pattern`-style library, release-per-minor, one-declaration metadata,
ruff's fix loop with clippy's compile-proof, two audited suppression
attributes, the staticcheck facts model with `Shape.Uid` identity, the
staticcheck cache key, fixture-projects-through-the-production-path, and
dune-RPC editor delivery. That convergence — from lenses as different as
"invent the surface first" and "derive from laws" — is the primary evidence
for this RFC. The lens reviews then repaired the mechanisms (the
build-spanning fix loop, the roster union, the per-unit editor lane, the
three-outcome honesty gate) without moving any of those decisions.

**Input model.** *Strongest alternative: RFC 0001's build-neutral capture
architecture.* Its instinct — any producer, no trust — was right, and this
design keeps it **as the unit contract**: digest admission is
producer-independent, and the unit-file lane serves non-dune builds by
contract. What is rejected is the mechanism: ~7,000 lines of evidence
bureaucracy re-deriving what one digest comparison and one roster answer,
and a shipped default that ran no typed rules. A first version of this RFC
made "Litany drives dune" the architecture; review correctly demoted it —
running the build is adapter porcelain (merlint's `--build`, `cargo
clippy`'s wrapping, inverted), not the design. *Also rejected: merlin-lib
in-process typing* (works on unsaved/broken code) — it re-does typing the
build paid for, needs the same per-file flag discovery, is non-reentrant,
self-declares instability, and recovered trees are untrustworthy exactly
when trust is the product; it remains the right substrate for a future
interactive LSP mode, which a core that consumes `Typedtree` however
produced does not foreclose. *Also rejected: living only inside the build*
(clippy's shape, per-module lint rules as the sole mode) — it forfeits
whole-workspace fixes, project rules, and suppression audit, which need the
whole findings set; it survives as the `litany unit` lane.

**Rule API.** *Strongest alternative: the compiler-independent façade* (the
WIP's bet). Its promise — third-party rule source survives compiler bumps —
is real but small: the binary is compiler-pinned regardless (it
deserializes cmt internals), and opam rebuilds tools per switch as a matter
of course. Its measured costs were disqualifying: the audited 6.2k adapter lines per
minor, an 8-constructor expression view under which most of OCaml is
invisible, and a 27-line per-rule tax. *Also rejected: YAML/structural
patterns as the primary language* — spelling is not identity (camelot;
ast-grep's own honesty about being untyped); ast-grep's ergonomic floor and
paired valid/invalid test contract are kept as the bar, and a declarative
layer compiling into `Pat` is a named future possibility. *Also rejected:
dynlink plugins* — no ABI story (zanuda ships them with no duplicate-id or
version checks), and an unsalted foreign rule set would poison the cache;
recompilation is the extension model that keeps both honest.

**Cross-module architecture.** *Strongest alternative: a global
collect-into-tables-then-solve engine* (reanalyze — proven to find real
transitive deadness). Rejected as the architecture because global tables
compose with nothing: no per-unit cache, no parallel scan, no third-party
project rules, no honesty gate. The fixpoint is kept — as one rule's
`report` function. *Also rejected:* RFC 0001's provider-qualified
`Project_semantics` + boundary token — its laws were right and are kept
(Laws 2, 6) but the ambiguity it defends against (multiple providers for
one unit name) cannot arise inside one build context, so the machinery
priced a problem the unit contract deleted; and building on `ocaml-index`
output — merlin-shaped occurrence data, lossy for rule-defined facts,
though noted as a possible fast path for `Unit.uses`.

**Config format (amended 2026-08-19).** The draft's `litany.toml`
followed field convention (ruff/staticcheck/clippy); the maintainer
applied this design's own law — derive from the OCaml ecosystem's facts —
and chose dune-style s-expressions in a root `litany` file instead: zero
new syntax for the audience (every OCaml developer writes dune files),
zero new dependency (litany already maintains s-expression code for the
describe decoder and the csexp unit file), comments and nesting native,
and the upstream `(lint (litany))` dune-stanza future becomes a
relocation instead of a translation. Consciously given up: TOML
familiarity for cross-ecosystem users and third-party TOML tooling. The
closed schema, unknown-key-fatal errors, positions + did-you-mean, and
typed per-rule options are format-independent and unchanged.

**Smaller rejections.** Numeric E-codes (names are identity; no 800-rule
namespace pressure); five suppression forms (two attributes + config cover
every anchoring need that paid rent); a daemon (dune watch + cache carry
incrementality); severity as per-finding data (severity is group policy);
mtimes anywhere (digests exist); JSON as the unit-file format (JSON
strings cannot carry arbitrary path bytes without an escaping convention;
the ecosystem's machine format is csexp); Marshal as the unit-file format
(the ocaml-index model — a magic number plus marshalled OCaml values,
`_ref/merlin/src/index-format/index_format.ml:129-137` — right for a
same-version tool pair, unwritable by foreign build systems).

## Non-goals

- Replacing compiler warnings or ocamlformat; no layout rules beyond the
  text substrate.
- Re-implementing OCaml typing, name resolution, or exhaustiveness.
- An editor server in 1.0 (the dune-RPC channel is the 1.0 editor story).
- Multi-context merging (one context per run; matrices are CI's loop).
- Analyzing projects that do not compile.
- Baseline/adopt-brownfield ratchet files in 1.0 (future possibility).

## Unresolved questions

All during implementation; none block acceptance.

- Workers: domains vs processes, decided by the no-global-state test plus a
  benchmark on a 500-module corpus. The architecture is identical either
  way.
- Resolver hardening: `Mty_ident` chains crossing units and recursive
  modules are shallowly exercised by spike A; validate against a large
  external library (e.g. Base) in M2 fixtures.
- Per-rule options: schema representation and validation mechanics.
- Exact `Pat` combinator inventory for 1.0 (drive it from the launch
  rules; zanuda's is the floor).
- Type printing in rule messages: `Printtyp` touches global state; either
  provide a confined `Unit.show_type` or keep 1.0 messages type-free.

## Future possibilities

Nothing here is a reason to accept this RFC, nor a commitment.

- **`litany lsp`**: the same engine as a library behind an LSP server with
  lazy code actions; merlin-lib as an unsaved-buffer typing provider for
  it.
- **A declarative pattern layer** compiling to `Pat` — ast-grep's authoring
  floor with resolved identity. Sharpened 2026-08-19: this layer should be
  designed as the *refactoring surface*, not merely a rule-authoring
  convenience — one-off, user-expressed rewrites (`litany rewrite`) are the
  same engine (typed match + safe apply + promotion review) under a
  different lifecycle, and the format's real requirements (rewrite
  templates, typed capture splicing, interactive preview) come from that
  use. Durable migrations need no new machinery — they are ordinary rules
  (the pyupgrade/clippy-deprecated model), shippable in org packs today.
  Full design-campaign treatment when taken up; not a 1.0 concern.
- **Baseline/ratchet mode**: record current findings, fail only on new
  ones — absent in every reference linter; would make brownfield adoption
  one command.
- **Upstream dune asks**: a `(lint (litany))` stanza; `describe workspace`
  fields for `(test)` stanzas and library visibility.
- **Cone-scoped withholding** for project rules (per-finding universes from
  the reverse-dependency graph).
- **Parsetree combinators in `Pat`**; **`ocaml-index` as a fast path** for
  `Unit.uses`; **SARIF output**; a **fix-preview TUI**; **dead-code family
  growth** (unused constructors/fields/optional arguments as additional
  project rules on the same facts).
