---
title: Suppression
description: "Silencing one finding with a reason, and the audits that keep suppressions honest."
---

Two attributes, each with a mandatory reason, on any expression or item:

- `[@litany.allow "rule: reason"]` hides the rule's findings in its scope.
- `[@litany.expect "rule: reason"]` also requires at least one, for tests and
  fixtures.

The floating form covers the rest of the file:

```ocaml
[@@@litany.allow "suspicious-physical-equality: interned atoms, identity is the point"]
```

A directive covers the findings inside its span, even when a PPX rewrites the
node away, and the innermost wins. A hidden finding is never fixed: if you
don't want a safe fix, write the `allow`.

## The audits

A directive that hides nothing is a finding: `unused-allow`, with a safe fix
that deletes it, or `unfulfilled-expect`. Neither can be suppressed. Both apply
only where the named rule actually ran on that unit, since a rule that didn't
look proves nothing. An unknown rule name or a missing reason is always
reported.

## What attributes can't cover

- Text rules (`trailing-whitespace`, `missing-final-newline`) aren't tied to a
  node; use [`per-path`](/litany/guide/configuration/#ignoring-by-path).
- In a unit whose source doesn't parse, such as one using cppo, attributes are
  unavailable. Typed rules still run, and the summary says so.

## Choosing an instrument

| Instrument | Covers | Audited | Rule still runs |
| --- | --- | --- | --- |
| `--ignore`, `ignore` | a rule, everywhere | no | no |
| `per-path` | rules on some paths | no | yes, reports dropped |
| `[@litany.allow]` | one construct | yes | yes |
| `[@litany.expect]` | one construct, finding required | yes | yes |
