# Writing a rule

A rule is one OCaml value in one file, plus a registry entry and a fixture
directory. There is no scaffolder; add the three pieces by hand. This page
walks real tree code — `unsafe-obj-magic` for the minimal shape,
`needless-list-length` for the full test discipline — and then collects
what the project's own corpus reviews have taught about where rules go
wrong. The pitfalls below are not hypothetical: each one names the rule
that hit it.

## Specify before you implement

These conventions bind every rule:

- **Name** in the house grammar: kebab-case, defect first — `needless-`,
  `suspicious-`, `redundant-`, `unsafe-`, `manual-`, `quadratic-`,
  `invalid-`, `restricted-`, or a bare defect noun in the
  `trailing-whitespace` style. `restricted-` is reserved for rules whose
  defect is that a restricted thing was referenced or declared
  (`restricted-dependency`, `restricted-public-exception`) — a
  Restriction-group rule flagging a pattern keeps its defect-first name
  (`suspicious-file-exists-race`); prefix never encodes group. The name
  is the rule's identity forever; a later rename keeps the old name as a
  tombstone alias.
- **Group is policy.** `Correctness` renders as an error and is on by
  default; `Suspicious` and `Perf` warn, on; `Style` and `Pedantic` warn,
  off; `Restriction` warns, off, *and outside `all`* — house policy over
  legitimate code, cherry-picked by exact name. Pick the group for what
  the rule detects, not for how confident you are — confidence is what
  the stability tier is for.
- **Every new rule ships `Nursery`**, off regardless of group, until a
  reviewed corpus record graduates it (lifecycle below).
- **State the negatives in the spec, and give each one a fixture line.**
  A rule's doc has a "Fires ..." paragraph and a "deliberately do not
  fire" sentence; both halves are contract. Write at least as many
  negative cases as positive ones. Two negative classes hold for every
  typed rule and cost nothing to state: shadowing/rebinding (a local
  `let ( = ) ...` or `module List = struct ... end` resolves to the local
  UID and must not match) and alias transparency (`module L = List` and
  `open List` resolve through to the same UIDs and must match).
- **Never widen silently.** An implementation may narrow its spec when
  the tree forces it — record the narrowing and the resulting false
  negative in the rule's doc. Every batch to date has recorded its sound
  narrowings and widened nothing; keep that property.

## The rule file

`open Litany` is a rule file's single open. The SDK facade re-exports
litany's modules (`Rule`, `Pat`, `Unit`, `Source`, `Finding`, `Fix`,
`Span`) alongside the compiler's own `Typedtree`, `Parsetree`, `Asttypes`,
`Longident`, `Types`, `Location`, `Path`, `Ident`, `Predef`, and `Shape`.
Rules see the compiler's real trees, nothing wrapped.

`lib/rules/unsafe_obj_magic.ml`, complete apart from the license header:

```ocaml
open Litany

let meta =
  Rule.meta ~name:"unsafe-obj-magic" ~group:Rule.Restriction
    ~stability:Rule.Stability.Nursery ~since:"1.0" ~fix:Rule.Never
    ~summary:"use of Obj.magic"
    ~doc:
      {|`Obj.magic` bypasses the type system entirely: the checker accepts
any use at any type, and a mistake becomes memory corruption at run time,
not a compile error.

    (* bad *)  let id : 'a -> 'a = Obj.magic
    (* good *) a typed interface, a GADT, or a documented unsafe module
               boundary reviewed on its own

Why restrict this? Every real use is a deliberate kernel: the population
is specialist code where each use was justified and reviewed on its own —
corpus review found no `Obj.magic` kernels in application code at all.
"No `Obj.magic`" is a house ban a workspace adopts, not a universal
improvement the catalog can claim. So the rule is
`restriction`-tier policy: off even under `--select all`, cherry-picked by
exact name, with the reviewed boundary carrying its `[@litany.allow]`
justification.

Fires at every identifier expression whose resolved identity is
`Stdlib.Obj.magic` — direct calls, opened uses, and first-class references
alike, at the identifier itself. Shadowed same-spelling definitions, later
uses of a value bound to `Obj.magic` (the binding's right-hand side already
fired), other `Obj` members, and unresolved identities deliberately do not
fire. There is no automatic fix.|}
    ()

let magic = Pat.ident "Stdlib.Obj.magic"

let rule =
  Rule.expr meta @@ fun u e ->
  match Pat.run magic u e () with
  | Some () -> [ Finding.v ~loc:e.exp_loc "Obj.magic bypasses the type system" ]
  | None -> []
```

### The metadata

`Rule.meta` is the one declaration every surface derives from: `litany
rules`, `litany explain`, config validation, and selection. Fields:

- `~name` — the identity, per the naming convention above.
- `~group` — `Correctness | Suspicious | Perf | Style | Pedantic |
  Restriction`.
- `~stability` — `Nursery` for every new rule.
- `~since` — the release that will introduce it.
- `~fix` — `Never | Sometimes | Always`, a promise checked at test time
  and at run time. A `Never` rule whose callback returns a fix is a rule
  failure.
- `~doc` — markdown; the `litany explain` page. House shape: one
  paragraph of why, a `(* bad *)` / `(* good *)` block, a "Fires ..."
  paragraph stating the exact conditions, and a "deliberately do not
  fire" sentence naming the negatives. Restriction rules add a *Why
  restrict this?* paragraph — the rationale answers why a house bans it,
  not why it is bad — placed before the "Fires ..." contract: the
  rationale is the adoption-decision paragraph, and a reader paging
  through the tier reads it first.
- `?requires_options` — declare `true` on a rule that is inert until a
  config `(rule <name> ...)` form supplies its policy
  (`restricted-dependency`, `restricted-export-name`); the check driver
  warns when such a rule is selected unconfigured.
- `?kind_gated` — declare `true` on a rule whose callback gates on the
  roster's stanza kind or visibility and degrades to silence without
  them; the engine then reports the rule inactive in lanes whose roster
  carries no kind (the artifact walk), so structural silence is
  enumerated.

### The match

Constructors fix the callback's node type: `Rule.expr`, `Rule.pattern`,
`Rule.binding`, `Rule.type_decl`, `Rule.let_group`, `Rule.module_binding`,
`Rule.export` (one call per row of the unit's export index,
`Unit.exports` — signature-walk rules; findings still anchor in the
editable source, so a firing rule joins the row back to its
implementation declaration), `Rule.attribute` (pre-PPX parsetree),
`Rule.source` (text), `Rule.project` (cross-module
`collect`/`report`; `unused-export` and `dead-code` are its
consumers). Callbacks are pure: `Unit.t` (or `Source.t`) and the node in,
`Finding.t list` out. The engine owns traversal; a rule is called at every
node of its kind and must be cheap on the miss path.

`Pat` is the combinator library. `Pat.run p u x k` matches `x` and passes
captures (`__`) to `k`, returning `None` on no match; `|||` is
alternation; `drop` ignores a sub-value. Its one semantic primitive is
identity: `Pat.ident "Stdlib.List.length"` matches by resolved declaration
UID, so `module L = List` matches and a shadowing `let length` never does.
The SDK offers no name-string comparison on identifiers, because spelling
is not identity — a design law ([design.md](design.md), Laws).

A canonical name that does not resolve in the linted workspace matches
nothing — a rule mentioning `Base.Fn.id` must not error in a workspace
without Base. In the rule's own fixture, a name that does not resolve is a
hard test failure, so a typo is a failing test, not a silently dead rule.

### The fix

From `lib/rules/redundant_not_not.ml`, the standard shape for a
`Sometimes` promise:

```ocaml
let rule =
  Rule.expr meta @@ fun u e ->
  match Pat.run shape u e Fun.id with
  | None -> []
  | Some x ->
      let fix =
        Option.map
          (fun src ->
            Fix.safe_replace e.exp_loc src ~title:"drop the double negation")
          (Unit.splice u x)
      in
      [ Finding.v ?fix ~loc:e.exp_loc message ]
```

`Unit.splice u x` is the captured expression's original source text,
parenthesized unless atomic. It is `None` in preprocessed units or when
the location does not slice cleanly; the finding then ships without a fix,
which is what `Sometimes` permits.

When the replacement is built rather than spliced — an application, an
operator expression, an `if` — wrap it in `Unit.delimited u e`: the
location of a parenthesized `e` includes the author's parentheses, and a
non-self-delimiting replacement must restore them (the pitfall
"Delimiter-inclusive locations" below has the record).

`Fix.safe_replace` claims behavior preservation. That claim is proven by a
compiled golden in the rule's suite (below), and it is falsifiable — see
the pitfalls. Use `Fix.unsafe_*` whenever the rewrite could change
behavior; the bare constructor defaults to Unsafe for a reason.

## Registration

Three additions, all in `lib/rules/`:

1. the module pair `my_rule.ml` / `my_rule.mli` (the mli exposes
   `val rule : Litany.Rule.t`);
2. `module My_rule = My_rule` in `litany_rules.ml` and `.mli`;
3. `My_rule.rule` in `Litany_rules.all`.

Duplicate names abort at startup. Third parties do the same thing out of
tree: depend on `litany` and build a custom composition root passing
`Litany_rules.all @ My_rules.all`. Extension is by recompilation; there is
no dynlink. The complete composition root — some 25 lines against
`Litany.Driver` and a stock adapter, plus a two-stanza `dune` file — is
the recipe in [build-integration](../manual/build-integration.md), "A
custom binary".

## The fixture and its suite

Each rule has a directory under `test/rules/`. The layout of
`test/rules/needless_list_length/`:

```
needless_list_length/
  dune                       ; the (test) stanza, fixture artifacts as deps
  test_needless_list_length.ml
  fixtures/
    dune                     ; builds the fixture as a library, plus the golden
    fix_nll.ml               ; the cases: positives marked, negatives plain
    fix_nll.fixed.ml         ; golden after --fix; must compile
```

The fixture is a real compiled library. The suite consumes its `.cmt`
through the production loader, so admission, identity resolution, and the
emit contract are exercised, not mocked. Positives carry a `(* FIRE *)`
marker on the finding's start line; the fixture is its own expectation:

```ocaml
let p1 = List.length xs = 0 (* FIRE *)

(* Shadowed identities never match. *)
let n11 =
  let module List = struct
    let length _ = 0
  end in
  List.length xs = 0
```

The suite (windtrap plus the shared `test/rules/support/` helpers) asserts
three things, engine end to end:

```ocaml
let () =
  Windtrap.run "needless-list-length"
    [
      test "declares its one metadata record" (fun () -> ...);
      test "fires exactly on the marked emptiness comparisons" (fun () ->
          Support.check_markers rule ~message:"..." ~source ~cmt);
      test "fixes round-trip to the compiled golden" (fun () ->
          Support.check_fixed rule ~source ~cmt
            ~golden:"fixtures/fix_nll.fixed.ml");
    ]
```

`check_markers` fails on any unmarked finding and on any unfired marker —
no rule failures, nothing dropped, findings exactly on the marked lines.
`check_fixed` applies the fixes and diffs against the golden. The golden's
compile leg is a plain dune rule in `fixtures/dune`: the `.fixed.ml` bytes
are copied to a module of their own and built as a library, so `dune
runtest` proves the fixed output compiles. A safe fix is a test-time
theorem, not a runtime hope. `check_fixed` plans at the Safe level by
default; a rule with Unsafe cells adds a `~unsafe:true` round-trip against
a second golden (`fix_rbc.unsafe.ml`, copied and compiled by the same
fixture rule) — an Unsafe fix may change behavior, never fail to compile.

Run one suite with `dune runtest test/rules/needless_list_length`, or
everything with `dune runtest`.

Two fixture mechanics worth knowing:

- ocamlformat moves a trailing comment after `=`, `with`, or `function`
  onto its own line, which silently detaches a `(* FIRE *)` marker from
  its anchor line. Place markers inside the binding head
  (`let rec map4 (* FIRE *) f l = ...`) where the shape requires it.
- A fixture negative that is deliberately a partial match carries
  `[@@warning "-8"]` scoped to that one binding. The shape is the point
  of the fixture; do not restructure it to appease the warning.

## Pitfalls on record

Each entry names the rule that hit it. Read the entry before writing a
rule in the same family.

### Ghost anchors: the sugar marks your node ghost

The parser marks the `Texp_function` node of the `let f x = match x with
...` sugar ghost, and the emit contract drops ghost findings — a rule that
anchors there loses its own spec positives. `needless-fun-match` and
`redundant-match-bool` anchor at the match expression when the function
node is ghost, and `function`-form rules fall back to the first case's
pattern — the standing precedent. If your rule anchors
at a whole `Texp_function`, test the sugared spelling first.

### Sugar folding: the node you match is not the node you read

Two recorded shapes. `let lift f = function ...` folds the value parameter
into the same `Texp_function` node, so a pattern expecting an empty
parameter list (`fun_cases nil`) refuses the spec's own positive — match
with `fun_cases drop`. And
`let () = e in body` compiles to a one-case `Texp_match`, so a rule
looking for `let`-spines must also strip guard-less single-value-case
matches (verified with `-dtypedtree`).

### Elaborated code: matches on code the user never wrote

The typechecker's elaboration of `?(x = default)` produces a match that
is invisible in source. `manual-option-value` fired on class
optional-argument defaults (`Tcl_fun` elaboration) in ppxlib — three
corpus false positives — and its Safe fix there rewrote the default into
`Option.value nop ~default:nop`, which parses (the applier's reparse gate
passes) but does not typecheck. The
`let`-level sugar was already guarded; the class path was not. Guard every
match-shape rule against `*opt*`/ghost elaboration scrutinees, and treat
"reparses" as a weaker property than "compiles".

### The Safe label is falsifiable

`--fix` on litany's own tree reproduced a live behavior flip: with
`let ( <> ) _ _ = false` in scope, `needless-list-length`'s rewrite of
`List.length xs > 0` to `xs <> []` compiles and computes the opposite
value. The class is cross-operator
splicing — a fix that introduces an identifier the match never proved
resolves to Stdlib at the fix site. Those cells were demoted to
`Fix.unsafe_replace` across `needless-list-length`,
`redundant-boolean-comparison`, and `redundant-if-bool`; same-operator
cells stay Safe because the spliced spelling was resolved at the fix
site. The rule for authors: a Safe fix may only splice text whose
resolution the match itself established, and every demotion gets a
shadowed-splice fixture negative stating the reason.

### Delimiter-inclusive locations: the replacement must restore the pair

The parser gives a delimited expression the location of its delimiters
too: in `check (o = None)` the comparison's span covers `(o = None)`, and
`check begin o = None end` relocates the same way. A fix that replaces
that whole span with text that is not self-delimiting — an application
(`Option.is_none o`), an operator expression (`xs = []`, `c || e`), an
`if` — drops the author's pair, and the result re-associates:
`check Option.is_none o` parses as `(check Option.is_none) o`, a type
error the applier's reparse gate cannot see because the text *does*
reparse. Two instances escaped compiled goldens and were caught in live
dogfooding on the same day (`redundant-option-comparison`,
`needless-list-length`): no golden had the rewritten expression in
argument position. The rule for authors: every replacement of an
expression's whole location goes through `Unit.delimited u e text`, which
restores a parenthesis pair exactly when `e`'s slice was delimited
(`Unit.parenthesized`) and `text` is not atomic — a bare `Unit.splice`
result passes through unchanged, so self-delimiting rewrites pay nothing.
And every fix-emitting fixture carries the rewrite in argument or
operator position (`f (<original>)`, `not (<original>)`, a cons cell), so
the compiled golden proves the pair. The seam is in `Unit`, not `Fix`:
`Fix.safe_replace` takes a location because rules also replace keyword
gaps and case arms, where no expression exists to consult.

### Trailing-open operands: the pair the author never wrote

The sibling case has no delimiters to restore. An `if`, `match`, `let`,
or `fun` may legally sit unparenthesized as the *right* operand of an
infix operator — `a && if c then true else e` parses, the `if` extending
to the end of the expression. A rule that replaces that node with an
infix expression re-associates silently: `manual-boolean-operator`'s
`c || e` made it `a && c || e`, which is `(a && c) || e`, a behavior
change that compiles. `Unit.delimited` cannot see it — the slice was
never delimited — and applications are immune (they bind tightest, so a
spliced application in that position stays whole). The rule for authors:
a fix whose replacement is an infix expression must ask whether the
replaced node is an application's trailing argument (the parent context
the callback does not carry; recover it with the `Tast_iterator` walk
`redundant-option-comparison`'s `link_operand` models, deciding by
physical identity) and add the pair itself when it is — and must not
add it elsewhere: `let b = if c then true else e` takes the bare
rewrite. The fixture carries the shape under `&&` with a truth table
the fixture's own `runtest` leg executes on the golden, so the compiled
golden proves the semantics, not only the parse.

### PPX-copied locations

The emit contract's fourth gate — corroboration by a pre-PPX node span —
exists because PPXes copy user locations onto generated code. Without it,
generated nodes report diagnostics at plausible-looking user spans —
zanuda's `[@@deriving]` false findings are the cautionary tale that
shaped this gate. Litany needs no per-rule guard,
and dropped findings are counted, so a fixture that expects a finding
inside PPX output fails loudly rather than silently passing.

### Identity corner cases: predef constructors and re-exported aliases

Match `[]`, `(::)`, `true`, `false`, `Some`, `None` through the
constructor description's result-type head (`Path.same` against
`Predef.path_list` and kin), never through the spelled `Longident` — a
user variant redefining `(::)` has its own result type and must not
match. One recorded limit: a re-exported constructor
alias with a manifest equation (`type 'a t = 'a list = [] | (::) of ...`,
stdlib's own `List.t`) makes later `[]`/`(::)` uses resolve to the alias's
constructors, which mutes predef-identity gates exactly on stdlib- and
base-style trees. `manual-list-exists` fired on a fresh compile of
stdlib's textbook `exists` recursion and not on stdlib itself —
probe-bisected to the alias line. The
fix direction — identity modulo manifest equations — is understood, not
landed; state the limit in the rule doc if your rule is in this family.

### Letter-correct and worthless: actionability is the bar

Two rules on record fired with zero false positives per spec and zero
acceptable findings. `manual-case-guard`: 18 production hits on litany's
own tree, 0 of 18 actionable — every `when`-guard rewrite duplicated a
non-trivial pattern, re-evaluated an effectful condition, or tripled a
3-way chain. `manual-format-quoting`: 0 of 57
sampled findings acceptable across two corpora — debug-dump formats pinned
by golden output, the compiler locus grammar (`File \"%s\", line %d`)
that litany's own adapter parses, and embedded-language quoting where `%S`
would apply OCaml escaping to XML. FP rate has
discriminated nothing in any corpus review to date; the specs are tight
and the matchers honor them. What discriminates is whether a maintainer would
take the change. Write the spec with a concrete accept in mind, and
expect a would-act judgment, not an FP count, at graduation.

### Generated code owns the volume

In the dependency corpus, two menhir-generated `parser.ml` files
contributed 57,292 of 60,603 findings — 94.5%.
`used-underscore-binding` alone produced 40,343 findings, of which about
four were hand-written code worth reading. Until generated inputs are
gated, a rule's corpus number is a statement about menhir, not about the
rule. For review, the standing method: when one file contributes more
than 20% of a rule's findings, add a stratified second sample excluding
it — the main sample of a menhir-dominated rule is thirty copies of one
fact.

### One site, many findings

`quadratic-string-concat-chain` reported every interior node of a chain:
a 9-segment concatenation produced 7 findings on one
line. Report the outermost matching node
only; that containment fix cut the rule's
corpus count from 607 to 120 without changing what it detects. The same
class, since fixed: `outdated-str-module` once reported per reference —
91-finding walls on Str-heavy trees — and now collapses to one finding
per referenced declaration per unit, anchored at the first use with the
count in the message. Decide the reporting unit — expression, line,
declaration cluster, or outermost node — as part of the spec.

### A zero is not precision

Three recorded ways a rule reports nothing while measuring nothing:

- **Resolver muting.** One version-incompatible `stdlib.cmi` on the walk
  path made every canonical-name rule return nothing — no failure, no
  degradation, exit 0; verified with an A/B repro.
- **Gate silence.** Roster-kind-gated rules (`suspicious-exit-in-library`,
  `suspicious-print-debugging`) are structurally idle on every
  `--cmt-root` corpus, because the walk lane has no roster.
- **Population absence.** Compiler warnings 10 and 39 are on by default,
  so released code contains neither shape; the corresponding rules can
  only ever fire on working trees.

Before citing a zero as evidence of precision, verify it: grep the
corpus for the raw shape, or bisect a probe compile until the shape is
proven present and unmatched (or genuinely absent).

## The lifecycle: nursery, corpus review, graduate

New rules ship `Nursery` and are off under every selection token except
`nursery` and the exact name. Graduation to `Stable` changes neither name
nor group, so it is invisible to configuration; what it requires is a
reviewed corpus record. Records live in git history — the review lands
with its evidence in the graduating commit — and each graduation adds one
CHANGES line; there is no records directory to maintain.

The standing corpora behind the evidence sentences in rule docs
("zero FPs over 91 sightings"): **litany's own tree** (the dogfood lane);
the **dependency corpus**, a ~180-package store of litany's own
dependency closure built by dune; and a **large application codebase**.

The corpus-review method, as practiced:

1. **Run the corpus lanes** (see
   [compiler-support.md](compiler-support.md)):
   `--select all,restriction,nursery`, read-only over existing
   artifacts, per-project roots — store-mode
   walks over multi-project trees are engine evidence, not rule
   evidence. Run twice; require byte-identical output and body count
   equal to summary count.
2. **Sample ≥ 30 or exhaustively**, with the method recorded. The
   practiced deterministic method: order rows by `md5(row)` and take the
   first 30 — reproducible without seed bookkeeping. Stratify when one
   file exceeds 20% of a rule's findings.
3. **Open every sampled site in source** and classify it against the
   rule's own `~doc` — the spec is the contract being tested, so a rule
   correct on its spec but noisy on the corpus is marked as such, not
   miscounted as a false positive.
4. **Judge would-act**, quoted: would the code's own maintainer take the
   change? The verdict vocabulary is GRADUATE, HOLD with a named
   narrowing, or DEMOTE.
5. **Trial the fixes** if the rule promises any: apply on a real tree;
   the result must reparse, compile, and survive a human diff review.
   The fix-application trial is what found the unsound-splice class.
6. **Record the batch** with its repro appendix (binary commit, exact
   commands, sample method) in the commit that acts on the verdicts, so
   the record travels in git history. The practiced regression check —
   re-running the pre-change binary over the same corpus as an A/B
   control — is the model for verifying that a narrowing did what its
   verdict intended and nothing else moved.

What has actually discriminated, in yield order: adversarial probe fixtures pinned to suspected
holes found the semantic FPs that volume never surfaced; the fix trial
found the unsound Safe cells; would-act judgment separated letter-correct
from worth-shipping; marker reconciliation validated every suite while
surfacing nothing new. A clean run is a hygiene signal, not graduation
evidence — silence must not graduate a rule.

When a review narrows a rule, the narrowing lands as a fixture line with
a comment stating the reason. The fixture is the rule's behavioral
record.

## The compiler-warning boundary

The catalog has been reviewed rule by rule against the compiler's
warnings 1–75, and the policy that review wrote down is a requirement,
not a convention: **a rule must be silent wherever a
default-enabled compiler warning fires; a rule may duplicate a
default-disabled warning only when its contract names the value-add**
(fix, cross-unit reach, config-independence, declaration-site judgment).

The catalog already practices both halves. Every rule adjacent to an
always-on warning is engineered to fire only where that warning is
structurally silent, and says so in its contract —
`suspicious-ignored-partial-application` refuses warning 5's territory
outright, `ignored-result` polices the one discard position warning 10
never sees, `suspicious-sequence-ignored-value`'s Tvar guard is its
stated no-duplicate boundary. The two true duplicates both cover
default-off warnings with the value-add named:
`suspicious-rec-without-recursion` (warning 39) ships the mechanical
delete-`rec` fix the compiler cannot offer, and
`suspicious-unused-module-binding` (warning 60) is the only channel
through which anyone sees a judgment that is off in every mainstream
default. A new rule near a warning's concern states its side of this
boundary in its `~doc`, the way those four do.

One standing caveat from the same review: if the compiler ever promotes
warnings 39, 60, or 41 into dune's default set,
`suspicious-rec-without-recursion` and
`suspicious-ambiguous-constructors` lose most of their case and
`suspicious-unused-module-binding` part of it — re-examine all three
whenever the default warning set moves.
