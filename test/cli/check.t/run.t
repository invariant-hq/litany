The walk adapter of last resort: litany check --cmt-root DIR pairs the
artifacts under DIR with editable sources under the current directory. The
fixture library was compiled by dune before this test ran (its artifacts are
cram deps), so every implementation unit joins under the Direct witness; the
interface-only gamma has no cmt to admit, and the generated alias module's
only source is its build-tree copy.

The fixture is copied (dereferencing the sandbox's links) before anything
mutates it: the stale scenario below edits a file in place, and dep copies
must never be written through.

(Under a GitHub Actions job litany check auto-selects the github report
format; this cram pins the text page, so the selector is unset for the
whole session.)

  $ unset GITHUB_ACTIONS

Version metadata is available without running a check (the version is
pinned at the first release — dev until then).

  $ litany --version
  dev

  $ cp -RL ../fixture proj && chmod -R u+w proj && cd proj
  $ cp -R . ../proj-before

The default check runs the launch catalog over every admitted unit and
prints the report — findings first (this fixture is clean), then one
summary line. A clean run exits 0. Rule findings are exercised by
test/rules/check.t.

  $ litany check --cmt-root .
  30 rules selected · 3 units · 0 findings · 1 skipped (missing-artifact 1) · 1 facts-only
  roster: suspicious-exit-in-library withheld (kind-gated; no unit in this lane carries a stanza kind)
  roster: suspicious-str-formatter withheld (kind-gated; no unit in this lane carries a stanza kind)

A plain check is read-only (pinned by bytes): the workspace
after it is identical to the copy taken before. The result cache under
.litany-cache is litany's own store, not workspace bytes.

  $ diff -r --exclude=.litany-cache ../proj-before .

The M2 admission listing lives behind --list-units.

  $ litany check --cmt-root . --list-units
  unit alpha.ml (direct)
  unit beta.ml (direct)
  unit fix_cli.ml-gen (direct, generated: path ends in .ml-gen)
  skip gamma.mli (missing artifact — no cmt to admit for this unit)
  summary: 4 entries, 3 admitted, 1 skipped (missing-artifact 1)
  roster: none (project rules unavailable)

Editing a source after the build makes its digest disagree with the one the
compiler recorded: the unit is stale, counted, and never linted — in the run
and in the listing alike.

  $ printf '(* edited after the build *)\n' >> beta.ml
  $ litany check --cmt-root .
  30 rules selected · 2 units · 0 findings · 2 skipped (stale 1, missing-artifact 1) · 1 facts-only
  roster: suspicious-exit-in-library withheld (kind-gated; no unit in this lane carries a stanza kind)
  roster: suspicious-str-formatter withheld (kind-gated; no unit in this lane carries a stanza kind)
  $ litany check --cmt-root . --list-units
  unit alpha.ml (direct)
  skip beta.ml (stale — the source changed since the compiler read it)
  unit fix_cli.ml-gen (direct, generated: path ends in .ml-gen)
  skip gamma.mli (missing artifact — no cmt to admit for this unit)
  summary: 4 entries, 2 admitted, 2 skipped (stale 1, missing-artifact 1)
  roster: none (project rules unavailable)

An artifact written by another compiler generation is refused at its magic
number, before any decode. The version this litany reads varies with the
toolchain, so it is masked here.

  $ printf 'Caml1999T099-not-a-real-artifact' > junk.cmt
  $ litany check --cmt-root . --list-units | sed 's/this litany reads OCaml [0-9.]*/this litany reads OCaml X.Y/'
  unit alpha.ml (direct)
  skip beta.ml (stale — the source changed since the compiler read it)
  unit fix_cli.ml-gen (direct, generated: path ends in .ml-gen)
  skip gamma.mli (missing artifact — no cmt to admit for this unit)
  skip junk.ml (built with magic "Caml1999T099"; this litany reads OCaml X.Y)
  summary: 5 entries, 2 admitted, 3 skipped (stale 1, wrong-magic 1, missing-artifact 1)
  roster: none (project rules unavailable)
  $ litany check --cmt-root .
  30 rules selected · 2 units · 0 findings · 3 skipped (stale 1, wrong-magic 1, missing-artifact 1) · 1 facts-only
  roster: suspicious-exit-in-library withheld (kind-gated; no unit in this lane carries a stanza kind)
  roster: suspicious-str-formatter withheld (kind-gated; no unit in this lane carries a stanza kind)

An uncaught renderer failure follows the internal-error exit contract:
with stdout closed the report
write raises, and the CLI exits 3 — internal error, never a silent 0.

  $ litany check --cmt-root . 1>&- 2>/dev/null
  [3]

A missing walk root is a refusal, not a listing.

  $ litany check --cmt-root does-not-exist
  litany: does-not-exist does not exist or cannot be read. Pass --cmt-root a directory holding .cmt artifacts.
  [2]

The exit contract, as cmdliner documents it. --help=plain: the default help
format is terminal-dependent, plain is not.

  $ litany check --help=plain | sed -n '/^EXIT STATUS/,/^SEE ALSO/p'
  EXIT STATUS
         litany check exits with:
  
         0   the run completed with no findings.
  
         1   the run completed with findings.
  
         2   refusal: adapter error or unusable invocation.
  
         3   internal error: a rule failed.
  
  SEE ALSO
