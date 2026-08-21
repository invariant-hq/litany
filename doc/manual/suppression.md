# Suppression

Two attributes, both with a mandatory reason, in the payload form
`"rule-name: reason"`:

- `[@litany.allow "rule: reason"]` — hides matching findings in its scope.
- `[@litany.expect "rule: reason"]` — hides them *and requires at least
  one*; it fails, as a finding, when the expected finding disappears. For
  tests and fixtures.

Attach either to any expression or item. The floating form scopes to the
rest of the file:

```ocaml
[@@@litany.allow "suspicious-physical-equality: interned atoms, identity is the point"]
```

A suppressed finding still counts, and the summary says so:

```ocaml
let check t =
  (if List.length t.stock = 0 then restock t else t)
  [@litany.allow "needless-list-length: benchmarking the walk itself"]
```

```
$ litany check
30 rules selected · 1 unit · 0 findings · 0 skipped · 1 suppressed
```

## The audits

A directive that hides nothing is itself a finding, so suppressions cannot
rot. An unmatched `allow` yields `unused-allow`, with a safe deletion fix:

```
$ litany check
File "lib/inventory.ml", line 7, characters 2-70:
7 |   [@litany.allow "needless-list-length: benchmarking the walk itself"]
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Warning 0 [unused-allow]: allow "needless-list-length" matched no finding
  fix (safe): delete the unused allow
```

An unmatched `expect` yields `unfulfilled-expect`. It wants the finding
back, not the attribute gone, so it ships no fix:

```
$ litany check
File "lib/inventory.ml", line 7, characters 2-71:
7 |   [@litany.expect "needless-list-length: the fixture must keep firing"]
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Warning 0 [unfulfilled-expect]: expect "needless-list-length" matched no finding
```

Both audits are gated on the named rule actually having *run* on that
unit — selected, joined, not failed — because the absence of a finding is
only evidence when the rule looked. A directive naming a known rule that
did not run this invocation is inert, not audited. Syntactic facts are
audited unconditionally: an unknown rule name (with a did-you-mean hint),
an engine-owned audit name, a text rule (attributes never cover those; see
below), and a malformed payload (for example a missing `:` — the reason is
not optional).

The auditors answer to no directive: nothing suppresses `unused-allow` or
`unfulfilled-expect`, and no rule may take their names.

## Semantics

- **Matching is byte-span containment** against litany's own pre-PPX parse
  of the source. A directive covers the findings whose location its scope
  contains, so suppression works even when a PPX rewrites the node away.
  The innermost covering directive wins.
- **Scope** is the attributed expression or item; floating `[@@@...]`
  covers from its position to the end of the file.
- **Former rule names** (tombstone aliases) match, with a rename note in
  the summary.
- **Text rules** (`trailing-whitespace`, `missing-final-newline`) are
  never attribute-suppressed; their findings are not tied to a parse node.
  Configuration's `per-path` selects their reports away instead
  ([configuration.md](configuration.md)).
- **In a unit whose source does not parse** (cppo and kin), attribute
  suppression is unavailable; typed rules still run and the summary notes
  the degradation.

## Interaction with `--fix`

Findings hidden by `allow` or required by `expect` are excluded from fix
application everywhere — `--fix` at the shell and inside the build alike.
If you do not want a safe fix, you do not want the finding: write the
`allow` and the edit disappears with it. The one exception is litany's own rule test
suites, where an `expect`ed finding's fix produces the `.fixed` golden.

## Suppression vs. selection

| Instrument | Granularity | Audited | Rule still runs |
| --- | --- | --- | --- |
| `--ignore` / config `ignore` | rule, whole run | no | no |
| config `per-path` | rules × paths | no | yes (reports dropped) |
| `[@litany.allow]` | one construct | yes (`unused-allow`) | yes |
| `[@litany.expect]` | one construct, finding required | yes (`unfulfilled-expect`) | yes |
