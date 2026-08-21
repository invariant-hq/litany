# Rules

`litany rules` lists the catalog, one rule per line — name, group,
stability, fix promise, default state, summary:

```
$ litany rules
dead-code                                 suspicious   nursery  never      off  exported value unreachable from any root
disable-all-warnings                      suspicious   stable   never      on   a warning attribute disables every warning
eta-reducible-forwarding                  pedantic     nursery  never      off  binding that only forwards its arguments
ignored-result                            restriction  stable   never      off  result or option value is discarded by a wildcard binding
invalid-function-comparison               suspicious   stable   never      on   structural comparison with a function operand
invalid-hashtable-key                     suspicious   stable   never      on   polymorphic Hashtbl operation on a value proved functional
...
80 rules · 30 on by default (stable correctness, suspicious, perf) · 10 restriction (cherry-picked; outside all) · 12 nursery
```

The table derives from the same declarations the engine runs, so it cannot
drift from behavior.

## Groups are policy

The group is the semantic category of what a rule detects, and policy
follows from it:

| Group | Detects | Severity | Default |
| --- | --- | --- | --- |
| `correctness` | code that is wrong | error | on |
| `suspicious` | code that is probably not what you meant | warning | on |
| `perf` | needless work | warning | on |
| `style` | a clearer spelling exists | warning | off |
| `pedantic` | opt-in strictness | warning | off |
| `restriction` | legitimate code, restricted by house policy | warning | off — and outside `all` |

Severity is never per-finding data; it is the group's, applied at render
time. No severity escalation surface exists yet.

`restriction` is different in kind from the tiers above it: a pedantic
finding claims almost any code improves without it, while a restriction
finding flags code that is fine in general — partiality, `Obj.magic`,
printing — and is a finding only because the workspace adopted the
policy. Each rule's doc answers *Why restrict this?* rather than *Why is
this bad?*. Restriction rules are cherry-picked by exact name; a bare
whole-group `restriction` in select/extend works but warns once
([configuration.md](configuration.md)).

## Stability

- `stable` — graduated; eligible for the default set per its group.
- `nursery` — where new rules start. Off regardless of group under every
  selection token except `nursery` or the exact name. A nursery rule
  graduates on corpus evidence — a reviewed run over real code — without
  changing its name or group.

The default set is exactly the stable `correctness`, `suspicious`, and
`perf` rules; `all` is every stable rule outside `restriction`. The full
catalog is `--select all,restriction,nursery`:

```
$ litany check --select all,restriction,nursery 2>&1 | tail -1
80 rules selected · 1 unit · 5 findings (1 fixable — run `litany check --fix`) · 0 skipped
```

## Fix promise

The `fix` column is a promise enforced in the rule's tests: `never` (no
fix, ever), `sometimes` (a fix when it can be constructed safely — for
example, when the operand's source text slices cleanly), `always`. Whether
a given fix is safe or unsafe is per-finding; see [fixing.md](fixing.md).

## `litany explain`

One rule's documentation — header, policy line, then the full rule doc:

```
$ litany explain needless-list-length
needless-list-length — List.length compared with 0 or 1 to test emptiness
perf · warning · stable · since 1.0 · fix: sometimes · on by default

Comparing `List.length` with a constant zero or one to ask "is this
list empty?" walks the whole list to answer a constant-time question.

    (* bad *)  if List.length xs = 0 then …
    (* good *) if xs = [] then …

Fires only when `List.length` and the comparison operator both resolve to
their `Stdlib` declarations and the relation is logically equivalent to
emptiness or non-emptiness ...
```

Every rule page states what it fires on and what it deliberately does not
fire on. Both halves are contract: each named negative has a fixture line
in the rule's test suite.

Unknown names get a suggestion, never a guess:

```
$ litany explain needless-list-lenght
litany: unknown rule "needless-list-lenght" (did you mean "needless-list-length"?)
```

## Identity, not spelling

Rules match resolved declarations, not names. `Pat.ident
"Stdlib.List.length"` fires on `module L = List` and opened uses alike,
and never on a local `let length` or a shadowing `module List`: the
typedtree records which declaration each identifier denotes, and litany
compares that. There is consequently no "unless you aliased it" fine print
anywhere in the catalog.

## Project rules

`unused-export` and `dead-code` are cross-module rules: every admitted
unit contributes export and dependency facts, and one report runs over
the whole workspace. Both are nursery, so ordinary selection gates them —
there is no dedicated flag. On a workspace whose `lib/legacy.ml` no other
unit references:

```
$ litany check --select unused-export,dead-code
File "lib/legacy.mli", line 1, characters 0-56:
1 | val migrate : (string * int) list -> (string * int) list
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Warning 0 [dead-code]: migrate is never used in this workspace
File "lib/legacy.mli", line 1, characters 0-56:
1 | val migrate : (string * int) list -> (string * int) list
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Warning 0 [unused-export]: migrate is exported but never used by another unit in this workspace

2 rules selected · 3 units · 2 findings · 0 skipped
```

- **`unused-export`** reports an exported value no *other* unit
  references. The claim is non-transitive: whether the users are
  themselves alive is not part of it.
- **`dead-code`** solves reachability — forward closure from the roots —
  and reports every exported value outside the closure, dead islands
  (mutual recursion included) whole.

Findings anchor at the declaration — the `.mli` line when the unit has
one. `litany explain unused-export` and `litany explain dead-code` state
each rule's exact claim and its recorded conservatisms.

### Roots

A root is never a candidate. The roots are:

- exports of public (or unknown-visibility) libraries — external
  consumers exist outside any universe litany can enumerate. `(closed-world
  true)` in the config file removes this default; see
  [configuration.md](configuration.md);
- the top level of executables and tests;
- declarations annotated with a reason:

```ocaml
val migrate : (string * int) list -> (string * int) list
[@@litany.root "run by the ops console"]
```

### The withhold gate

A project rule's claim is universally quantified — "no other unit uses
this" — so it runs only over the complete universe. One skipped roster
unit withholds every project report for the run; findings are never
emitted over a partial universe. The summary names the blockers, and
`--explain-withheld` spells out which skip blocked which rule:

```
$ litany check --no-build --select unused-export,dead-code --explain-withheld
2 rules selected · 2 units · 0 findings · 1 skipped (stale 1)
roster: project rules withheld (lib/legacy.ml: stale — the source changed since the compiler read it)
withheld dead-code: blocked by lib/legacy.ml (stale — the source changed since the compiler read it)
withheld unused-export: blocked by lib/legacy.ml (stale — the source changed since the compiler read it)
```

A rebuild restores the universe, and the flag also answers when nothing
was withheld:

```
$ litany check --select unused-export,dead-code --explain-withheld | tail -1
withheld: nothing — dead-code, unused-export ran over the complete universe
```

Lanes without a full roster — the artifact walk, or a unit file without
ownership metadata — never run project rules; the admission listing says
`roster: none (project rules unavailable)`. See
[build-integration.md](build-integration.md).

## Renames

A renamed rule keeps its former names as tombstone aliases. The old name
still works in selection, configuration, and `allow`/`expect` attributes,
with a rename warning naming the new spelling.

## Per-rule options

A rule may declare options, set in the config file's `(rule <name> ...)`
form and documented on its `explain` page. Three rules take options:

- `quadratic-string-concat-chain (max-segments <n>)` — n ≥ 2, default 2,
  the number of tolerated `^` segments;
- `restricted-dependency (forbid <path> (use "<replacement>")) ...` — the
  configured deny-list; each ban names its replacement, and the remedy
  appears verbatim in the finding;
- `restricted-export-name (forbid-suffix <s>) (max-underscores <n>)` —
  the export naming policy.

See [configuration.md](configuration.md).
