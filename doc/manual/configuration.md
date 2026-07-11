# Configuration

Litany runs without configuration. When you want some, it is one file with
a closed schema: a file named `litany` at the workspace root (the directory
`--root` names, default `.`), written in dune-style s-expressions — `;`
comments, bare and `"quoted"` atoms, parenthesized forms.

An unknown form, unknown key, duplicate, or malformed value is an error
with a position and a suggestion. The run exits 2 and nothing runs; there
is no silent fallback:

```
$ litany check
litany: litany:1:8: unknown key "selct" in (lint ...) (did you mean "select"?)
$ litany check
litany: litany:1:15: unknown rule or group "styel" (did you mean "style"?)
```

## The complete schema

```lisp
(litany-config 1)             ; optional version header; first form if present

(lint
 (select default)             ; rule names, group names, nursery, all, default
 (extend trailing-whitespace) ; add to select without replacing it
 (ignore needless-list-length)
 (closed-world false))        ; project-rule root policy (see below)

(rule quadratic-string-concat-chain
 (max-segments 4))            ; options are the named rule's own

(per-path
 (paths vendor/** third-party/*.ml)
 (ignore all)
 (reason "vendored code"))
```

Every form is optional; an absent file means the defaults. `(lint ...)`
may appear once, `(rule <name> ...)` at most once per rule, and
`(per-path ...)` any number of times.

## Selection: `select`, `extend`, `ignore`

The selection vocabulary, used everywhere a rule set is named (file and
flags):

- a rule name (`needless-list-length`) or a former name (tombstone alias);
- a group name: `correctness`, `suspicious`, `perf`, `style`, `pedantic`,
  `restriction`. A group token selects its *stable* rules;
- `nursery` — the stability tier. Nursery rules are off under every group
  and set except this one;
- `default` — the default set: stable `correctness`, `suspicious`, and
  `perf` rules;
- `all` — every stable rule outside `restriction`. The full catalog is
  `all,restriction,nursery`.

An unselected rule does not run at all; selection happens before analysis.
To silence one finding while the rule keeps running, use an attribute
instead ([suppression.md](suppression.md)).

Precedence between `select` and `ignore` is by specificity: an exact rule
name outranks a group or tier, which outranks `all`/`default`; at equal
specificity `ignore` wins. So `(select perf) (ignore needless-list-length)`
runs the other perf rules, and `--select all --ignore style` is every
stable rule outside `style`.

The file's three lists resolve as follows: the effective select is
`select` (or `default` when only `extend` is given) plus `extend`; the
effective ignore is `ignore`. The flags — `--select` and `--ignore`,
repeatable and comma-separated — override the file wholesale, each
independently: a given `--select` replaces the file's `select` and
`extend` together; a given `--ignore` replaces the file's `ignore`; an
absent flag leaves the file's list in force. The file still validates
first — a flag does not turn config errors off.

The audit rules `unused-allow` and `unfulfilled-expect` are engine-owned
hygiene, not selection vocabulary:

```
litany: litany:1:15: "unused-allow" is engine-owned hygiene, not a selectable rule
```

### The tier ladder, and cherry-picking `restriction`

The selection tokens *are* the tier ladder — there is no separate profile
mechanism, and `litany check --select …` switches tiers per invocation
with no file at all:

| Spelling | Runs |
| --- | --- |
| `correctness` | only what is wrong |
| `default` | the default set: stable `correctness`, `suspicious`, `perf` |
| `default` plus `(extend style)` | house idiom on top |
| `all` | every stable rule outside `restriction` |
| `all,restriction,nursery` | the full catalog — the audit spelling |

`restriction` rules differ in kind from everything above them: they flag
*legitimate* code that a workspace has chosen to restrict — partiality,
`Obj.magic`, printing from libraries. A pedantic finding claims almost
any code improves without it; a restriction finding is a finding only
because your house said so. The tier is therefore cherry-picked:

- restriction rules are off by default *and outside `all`* — an audit
  that has not adopted a policy never drowns in its contract-true noise;
- adopt each policy by exact name — `(extend unsafe-partial-stdlib)` —
  which warns nothing;
- a bare whole-group `restriction` in `select`/`extend` (file or flag)
  still works, uniformly with every group token, but warns once, stating
  what the token did — a group token covers stable rules only, and every
  restriction rule is stable, so the token enables all ten at once:

```
litany: restriction rules are independent house policies, and some contradict each other — adopt each by exact name; the group token enables 10 of 10 restriction rules (group tokens cover stable rules only; nursery members need "nursery" or their exact name)
```

Two restriction rules are configured policies with no built-in list:
`restricted-dependency` (a deny-list with mandatory replacements) and
`restricted-export-name` (the export naming policy); see the per-rule
options section below and each rule's `litany explain` page for the
copyable config block.

A common adoption shape: enforce a policy in library code and keep tests
assertion-shaped with a `per-path` ring:

```lisp
; adopt the policy in lib/, keep tests assertion-shaped
(lint (extend unsafe-partial-stdlib))
(per-path
 (paths test/** bench/**)
 (ignore unsafe-partial-stdlib)
 (reason "partiality is assertion-shaped in tests"))
```

Restriction findings render as warnings like every non-correctness
group's; there is no severity-escalation surface yet
([rules.md](rules.md)).

## Per-rule options: `(rule <name> ...)`

A rule that takes options declares their schema itself; the config file
keeps them opaque and the owning rule validates them, with the same
positioned errors:

```
litany: litany:1:51: option "max-segments" wants an integer, not "zero"
litany: litany:1:28: rule "needless-list-length" takes no options
```

Options reconfigure a rule; they never enable it — selection is separate.
An unselected rule's options still validate, and a `(rule X …)` form whose
rule ends the run unselected warns — configured-but-silent is otherwise
invisible:

```
litany: rule "quadratic-string-concat-chain" is configured but not selected
```

The mirror trap warns too: a rule that is inert until configured, selected
with no `(rule …)` form, runs and reports nothing —

```
litany: rule "restricted-dependency" is selected but not configured; it reports nothing without a (rule restricted-dependency ...) form
```

Each rule's options are documented on its `litany explain` page. Three
rules take options:

- `quadratic-string-concat-chain (max-segments <n>)` — n ≥ 2, default 2,
  the number of tolerated `^` segments;
- `restricted-dependency (forbid <path> (use "<replacement>")) ...` — the
  configured deny-list; each ban names its replacement, and the remedy
  appears verbatim in the finding;
- `restricted-export-name (forbid-suffix <s>) (max-underscores <n>)` —
  the export naming policy.

## Per-path report selection: `(per-path ...)`

`per-path` drops reports by path. It selects *reports*, never analysis:
matching units still build, join, and run every selected rule — only their
findings are not reported. Unit counts do not move, and nothing is counted
dropped. It is not audited and needs no per-site reason; `(reason ...)`
documents intent.

- `(paths <glob>...)` — at least one glob (grammar below).
- `(ignore <token>...)` — the selection vocabulary, plus one widening:
  `all` here drops *every* report on matching paths, audit findings
  included, so that ignoring a path does not leave the auditors reporting
  on it. A group token here covers the group's *stable* rules —
  cherry-picked nursery rules, today the whole `restriction` tier, must
  be named exactly.

Text-substrate rules (for example `trailing-whitespace`) are silenced only
this way; attributes cannot cover them.

### Glob grammar

Anchored, workspace-relative, byte-wise. This is a small litany grammar,
not gitignore:

- The whole canonical relative path must match; no implicit leading or
  trailing `**`.
- `*` matches zero or more bytes within one component; `?` exactly one
  such byte; `/` matches only the separator.
- `**` is legal only as a complete component. Non-final, it matches zero
  or more components; final, one or more. `a/**/b.ml` matches `a/b.ml`;
  `vendor/**` matches `vendor/x.ml` and `vendor/a/x.ml`, not `vendor`
  itself.
- Case-sensitive; dots are not special; no escapes.

## `closed-world`

The root policy for the project rules `unused-export` and `dead-code`. By
default a public library's exports are roots and never reported: external
consumers exist outside any universe litany can enumerate. `(closed-world
true)` declares this workspace the whole universe, so public exports
become ordinary candidates. Set it in a final application repository, not
in a published library. The key is part of the result-cache key, so
flipping it recomputes rather than replaying stale findings. The rules,
their roots, and the withhold gate are in [rules.md](rules.md).

## Precedence summary

Innermost wins, and config is the outer ring: an attribute on the code
beats everything; `per-path` drops reports after analysis;
`select`/`ignore` (flags over file) decide what runs at all.
