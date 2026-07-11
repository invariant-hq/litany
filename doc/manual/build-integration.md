# Build integration

Every lane feeds the same core, and the same digest admission gates every
join: a stale artifact is a listed skip in every lane, never a stale
finding.

| Lane | Command | Needs dune | Project metadata |
| --- | --- | --- | --- |
| dune (default) | `litany check` | yes, spawned | full roster |
| in the build | `litany check` as a rule's action (one user-written stanza) | is a dune rule | none — context walk, local rules only |
| one unit | `litany unit` | any build system's rule | argv is the roster |
| unit file | `litany check --units FILE` | no | whatever the file supplies |
| artifact walk | `litany check --cmt-root DIR` | no | none — local rules only, kind-gated rules inactive |

## In the build: findings in your editor

Litany ships no generated build files. In-dune integration is one rule
you write yourself, under whatever alias you like (`lint` here):

```lisp
(rule
 (alias lint)
 (deps (alias_rec check))
 (action (run litany check)))
```

`dune build @lint` then runs the whole check inside the build:

```
$ dune build @lint
File "lib/inventory.ml", line 5, characters 17-40:
Warning 0 [needless-list-length]: comparison through List.length is a needless emptiness test
  fix (safe): compare with []
$ echo $?
1
```

The deps line is the whole contract. `(alias_rec check)` builds every
`.cmt` under the stanza's directory tree before the action runs and makes
the rule depend on them, so dune is both the build and the freshness
engine: the rule re-runs exactly when an artifact changed, and litany
never spawns dune from inside dune (the parent holds the project lock; a
child dune would deadlock against it). The report is scoped like the
deps: a rule at the workspace root lints the whole workspace; a rule in
a subdirectory's `dune` lints that subtree only, matching what its
`(alias_rec ...)` line keeps fresh — a wider report would depend on
whatever unrelated build history happens to sit in `_build`. Litany
detects the in-action vantage from its working directory — a dune action
runs inside the build context — walks that scope for artifacts, and
pairs them with
the real source tree the context mirrors, so findings anchor at editable
source paths. Per-unit digest witnesses gate every join exactly as in
every other lane; anything stale in the context is a counted skip.

Sandboxing changes none of this. At `(lang dune 3.23)` every user rule
is sandboxed — the action runs in a staged mirror under
`_build/.sandbox` — but the sandbox is not a read boundary and stages no
artifacts for alias deps, so litany detects the sandboxed vantage and
walks the real build context against the real sources: the same report,
the same paths, on any dune language version, with no sandbox clause in
the stanza.

Inside an action the default report format is `compiler` — the exact
grammar dune's diagnostic parser accepts from a failing action — so
findings land as ordinary dune diagnostics and reach editors over dune
RPC: add `@lint` to your watch invocation (`dune build @default @lint
-w`) and litany findings appear in VS Code, Emacs, and Vim as compiler
warnings, with no litany-side editor code and no plugin. Findings exit 1
and the rule fails: that is the design — the alias is a gate. An explicit
`--format` still wins.

The workspace `litany` config file is read as usual, from the workspace
root the context mirrors, so the rule means what your checkout's config
says.

### `--fix` in the build

The writing variant is the corrections stanza — `--fix` in the action,
`(corrections produce)` on the rule; it requires `(lang dune 3.23)`:

```lisp
(rule
 (alias lint)
 (deps (alias_rec check))
 (corrections produce)
 (action (run litany check --fix)))
```

Inside a dune action litany never writes a source. Under this stanza
each file's fixes run the same pipeline as everywhere else — the editable source's
digest is re-checked against the admission-time witness, the fixes are
applied in memory, and the result must reparse ([fixing.md](fixing.md))
— and the fixed bytes are written as `<path>.corrected` files inside the
action's sandbox. Dune pairs each with the source it corrects, shows the
change as a diff anchored at that source, fails the build, and registers
a promotion; `dune promote` is what actually writes your tree:

```
$ dune build @lint
fix lib/inventory.ml: 1 proposed
pass 1: 1 fix proposed (1 file)
1 correction proposed — dune shows each as a diff and fails the build; dune promote applies and the next build re-lints (without (corrections produce) in the rule, dune discards corrections silently)
...
File "lib/inventory.ml", line 1, characters 0-0:
--- lib/inventory.ml
+++ _build/default/lib/inventory.ml.corrected
@@ -5 +5 @@
-let is_empty t = List.length t.stock = 0
+let is_empty t = t.stock = []
$ dune promote
Promoting _build/default/lib/inventory.ml.corrected to lib/inventory.ml.
```

The exit contract shifts with the transport: when at least one
correction was written the action exits 0, because dune processes
corrections only from actions that exit 0 — a nonzero exit would
silently drop them — and the diffs themselves fail the build, so
findings still gate. The promoted sources stale their artifacts; the
next `dune build @lint` rebuilds, re-runs the rule, and the loop settles
when the tree is clean. In watch mode that happens unprompted.

**The version story is one sentence:** in-dune fixing requires
`(lang dune 3.23)` and `(corrections produce)` on the rule; on older
dune, run `litany check --fix` from the terminal. Litany never writes a
source from inside dune, at any version — the single-writer principle
holds universally in-dune, with dune's own promotion as the writer — so
at an unsandboxed action vantage (which is what an older dune language
means; 3.23 sandboxes every user rule) `--fix` refuses and names both
lanes:

```
litany: refusing --fix: in-dune fixing requires (lang dune 3.23) and (corrections produce) on the rule — dune then shows fixes as diffs and dune promote applies them; on older dune, run litany check --fix from the terminal instead
```

Read-only reporting is untouched by the gate: the report rule works on
every dune language version.

**The one silent-drop hazard.** Litany cannot see the invoking stanza,
so it cannot tell whether the rule carries `(corrections produce)`. A
sandboxed `--fix` action without the field still writes its corrected
files — and dune discards them at teardown without a word: the build
goes green with the fixes dropped and the sources untouched. That is why
the proposal note above always names the field; if your fix rule builds
green while findings remain, that line is telling you what is missing.

**Honest limits.** The in-action roster is an artifact walk of the build
context, not a full roster: project (cross-module) rules —
`unused-export`, `dead-code` — withhold there, exactly as under
`--cmt-root`. Run `litany check` from the terminal or CI, where litany
drives the build and assembles the full roster, for the cross-module
claims.

## `litany unit`: one unit, inside the build

The per-module gate, usable from any build system's rules (under dune the
whole-workspace rule above is the lane; this command is for build systems
that wire one rule per compilation unit):

```
$ litany unit inventory --cmt _build/default/lib/.inventory.objs/byte/inventory.cmt --source lib/inventory.ml
File "lib/inventory.ml", line 5, characters 17-40:
Warning 0 [needless-list-length]: comparison through List.length is a needless emptiness test
  fix (safe): compare with []
$ echo $?
1
```

Its argv is the roster: no subprocess, no lock, no workspace query. The
report is compiler-format on stderr, stdout silent, exit 1 on findings —
the shape dune's diagnostic parser requires. The default rule set runs
and the workspace `litany` file is deliberately **not** read: a
per-module build rule must mean the same thing on every checkout.
Attribute suppression works as everywhere. A unit that cannot be admitted
is a refusal (exit 2) naming the skip, because a one-unit gate that
silently skipped would read as clean.

## Unit files: any build system

The unit file is the one interface a foreign build system targets. Litany
can emit its own roster as one:

```
$ litany units --save litany.units
$ litany check --no-build --units litany.units
lib/inventory.ml:5:18 warning needless-list-length
  ...
30 rules selected · 1 unit · 1 finding (1 fixable — run `litany check --fix`) · 0 skipped
```

`litany units --dump` (the default action) prints the same document as
human-readable sexps; reading a dump is a working introduction to the
format:

```
$ litany units
(litany-units 1)
(cmi-dirs _build/default/lib/.inventory.objs/byte)
(unit (source lib/inventory.ml) (cmt _build/default/lib/.inventory.objs/byte/inventory.cmt) (library inventory) (public false) (kind lib))
```

`litany check --units FILE` consumes one from any producer — Bazel, Make,
or nix rules emit it themselves. No dune is spawned and no build runs, so
this lane also works beside a running dune watch server: capture the file
once while the server is stopped, then `litany check --no-build --units
FILE`. Per-unit witnesses still gate every join; a stale or wrong file
costs skips, never findings.

### Format, for producers

Canonical s-expressions (csexp: atoms are length-prefixed raw bytes, so
any path round-trips; `--save` writes csexp, one form per line). In order:

1. `(litany-units 1)` — required header.
2. `(complete false)` — optional; state it when the file is not the
   producer's whole universe (project rules need completeness).
3. `(cmi-dirs <dir>...)` — optional; directories searched for the `.cmi`
   files of dependencies (identity resolution).
4. One `(unit ...)` form per unit. Fields, all `(key value)` atom pairs,
   in canonical order `source cmt cmti pp-source library public kind`:
   `source` plus at least one of `cmt`/`cmti` are required; `pp-source`
   names the built preprocessed file for units the compiler read through a
   preprocessor; `public` is `true`/`false`; `kind` is `lib`/`exe`/`test`.

The schema is closed: unknown forms or fields, duplicates, and duplicate
`source` values are errors, refused with a byte offset. A unit file that
supplies `library`/`public`/`kind` for every unit is a full roster.

## Artifact walk

```
$ litany check --cmt-root _build/default
```

Pairs `.cmt` artifacts under DIR with sources under the workspace root by
the digest witness alone. No ownership metadata, so local rules only; the
admission listing says `roster: none (project rules unavailable)`. Rules
gated on a unit's stanza kind or visibility are silent in this lane too —
the walk carries no roster metadata to gate on — and the summary
enumerates them, one line per selected kind-gated rule, so their zero
findings never read as a clean corpus:

```
roster: restricted-global-mutable-state withheld (kind-gated; no unit in this lane carries a stanza kind)
```

A store whose artifacts *all* carry another compiler generation's magic
number is a refusal naming both versions, not an all-skipped success — an
all-foreign store must never read as clean in CI:

```
$ litany check --cmt-root store-5.5
litany: artifacts were built by OCaml 5.5; this litany reads 5.4 — install litany in this switch
```

A mixed store keeps its counted per-unit skips; `--list-units` lists the
per-unit reasons either way.

## The result cache

`litany check` caches per-unit results by default, so an unchanged unit
replays instead of re-analyzing. The key covers everything that can
change a unit's result: the artifact and source digests, the unit's
roster metadata and interface source, the `litany` file, build currency,
the selected rules, and the litany binary itself. A changed component is
a miss and a recompute — never a stale replay — and a corrupt entry
counts as a miss and heals on the next store. Output never varies with
cache state: pages are byte-identical warm or cold.

| Control | Effect |
| --- | --- |
| `--cache-dir DIR` | store under `DIR` |
| `LITANY_CACHE_DIR` | store under it when no flag is given |
| neither | `$XDG_CACHE_HOME/litany`, else `~/.cache/litany` |
| `--no-cache` | run uncached |
| `--cache-stats` | one diagnostic line on stderr after the run |

```
$ litany check --cache-stats 2>&1 | tail -1
litany: cache: 0 hits, 1 misses, 1 stored, 0 evicted
$ litany check --cache-stats 2>&1 | tail -1
litany: cache: 1 hits, 0 misses, 0 stored, 0 evicted
```

A unit the compiler read through a preprocessor recomputes every run: its
built `pp` file is not a key component. Every run ends with a sweep —
entries unread for 30 days are evicted, and cache directories of deleted
workspaces are collected. There is no clean command; the sweep is the
maintenance, and `rm -r` on the cache directory is always safe.

## Parallel workers

`litany check -j N` (`--jobs N`) analyzes units with `N` worker
processes; the default is the machine's core estimate. Workers shard
units, never traversal, and the page is byte-identical for every `-j` —
worker count is unobservable in the output. A worker that dies mid-run
costs its shard as counted skips naming the signal, never a silent hole:

```
litany: worker lost (killed by SIGKILL); 1 unit of its shard skipped
30 rules selected · 2 units · 0 findings · 1 skipped (unreadable 1)
```

`--fix` runs single-process this release — the write lane and
build-spanning convergence are serial by design — and says so when given
a larger `-j`.

## CI

`litany check` exits 1 on findings, so it works directly as a CI gate. On
GitHub Actions the `github` format is auto-selected (when `GITHUB_ACTIONS`
is set and no `--format` is given), so findings land as workflow
annotations:

```
::warning file=lib/inventory.ml,line=5,col=18,endColumn=41,title=needless-list-length::comparison through List.length is a needless emptiness test fix (safe): compare with []
```

CI never applies fixes: applying requires typing `--fix` — into a shell
or into a rule's action — and CI types neither. Bots that post suggested
changes consume the `json` format, which carries each finding's fix.

## Output formats

`litany check --format FMT`:

| Format | Channel | Shape |
| --- | --- | --- |
| `text` (default) | stdout | the human page: location, message, excerpt with carets, fix line, one summary line |
| `compiler` | stderr, stdout silent | the exact grammar dune's diagnostic parser accepts; no excerpts, no summary; the default inside a dune action |
| `json` | stdout | JSON Lines: one finding object per line, then one summary trailer object |
| `github` | stdout | workflow annotations; auto-selected under `GITHUB_ACTIONS` |

```
$ litany check --format json
{"rule":"needless-list-length","severity":"warning","file":"lib/inventory.ml","line":5,"col":17,"end_line":5,"end_col":40,"message":"comparison through List.length is a needless emptiness test","fix":{"title":"compare with []","applicability":"safe","edits":[{"start":78,"stop":101,"text":"t.stock = []"}]}}
{"summary":{"findings":1,"fixable":1,"units":1,"skipped":[],"roster":"ran"}}
```

Positions: `text` and `github` use 1-based columns; `compiler` and `json`
use the compiler's own convention (0-based, end-exclusive). `json` edits
are byte offsets into the source. Paths whose bytes are not valid UTF-8
get a reversible `path_bytes` hex twin beside the lossy `file`.

Both auto-selections are defaults, not mandates: inside a dune action the
default is `compiler` (and it outranks the `GITHUB_ACTIONS` selection — a
dune action inside a workflow job still answers to dune), while `--fix`,
`--list-units`, and `--explain-withheld` keep the text surface. An
explicit `--format` always wins.

The three machine formats render the report page only: they refuse `--fix`
and `--list-units`, and anything else the run prints (build forwarding,
rename warnings) keeps its own channel. Pair `compiler` with
`--no-build`/`--units` when stderr must hold nothing but the report.
Output order is total and byte-deterministic across runs: sorted by path,
byte offset, rule name.

## A custom binary: extending the catalog

Litany extends by recompilation — no dynlink, which keeps the result
cache's binary-digest key honest. A rule pack is an ordinary library
written against `open Litany` (see
[rule-authoring](../dev/rule-authoring.md)); a custom binary passes the
extended catalog where the stock composition root passes the built-in one.
The whole binary is this file (compiles as written against the `litany` +
`litany_rules` pair):

```ocaml
(* main.ml — the whole custom binary: the stock catalog plus your rules. *)
let () =
  let root = "." in
  let rules = Litany_rules.all @ My_rules.all in
  let progress = Litany.Progress.v ~enabled:true ~jobs:1 in
  let code =
    match Litany.Adapter.Dune.roster ~progress ~root () with
    | Error e -> Litany.Driver.refuse "%a" Litany.Adapter.Dune.pp_error e
    | Ok roster ->
        let cache =
          Litany.Driver.Result_cache.setup ~cache_dir:None ~no_cache:false
            ~root ~rules
        in
        let rebuild () = Litany.Adapter.Dune.roster ~progress ~root () in
        let code =
          Litany.Driver.run_check ~progress ~rebuild:(Some rebuild)
            ~format:Litany.Driver.Text ~jobs:None ~cache roster
            ~build_current:true ~rules ~catalog:rules ~keep:None ~fix:None
            ~explain_withheld:false
        in
        Option.iter
          (fun c -> Litany.Driver.Result_cache.finish c ~stats:false)
          cache;
        code
  in
  exit code
```

with the two-stanza build:

```
(executable
 (name main)
 (libraries litany litany_rules my_rules))

; the rule pack, in its own directory: [litany] is its only dependency
(library
 (name my_rules)
 (libraries litany))
```

Flags, selection, the config file, and the other subcommands are the stock
`bin/`'s value-add; none of them is required. `Litany.Driver.run_check` is
the whole run — the engine pass, the admission listing's skips, the report
page, the exit code under the 0/1/2/3 contract — and each argument shown is
the stock binary's default. To lint an artifact store without dune, swap
the roster call for `Litany.Adapter.Walk.roster ~cmt_root ~source_root`
and pass `~rebuild:None ~build_current:false` — the walk lane runs one
pass over existing artifacts. For the
full CLI instead, copy `bin/` from the litany tree: the catalog is spelled
at exactly one site (`Cli_common.catalog`), so the copy's whole delta is
that line.
