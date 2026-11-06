---
title: Selecting rules
description: "Groups, stability, fix promises and the project rules."
---

`litany rules` lists every rule with its group, stability, fix promise and
default state; [the rules](/litany/reference/rules/) are the same list, here.
Choose what runs with `--select` and `--ignore`, or in
[the `litany` file](/litany/guide/configuration/).

## Groups

| Group | Detects | Severity | Default |
| --- | --- | --- | --- |
| `correctness` | code that is wrong | error | on |
| `suspicious` | code that is probably not what you meant | warning | on |
| `perf` | needless work | warning | on |
| `style` | a clearer spelling exists | warning | off |
| `pedantic` | opt-in strictness | warning | off |
| `restriction` | legitimate code your project chooses to refuse | warning | off, and outside `all` |

`restriction` rules flag code that is fine in general -- partiality,
`Obj.magic`, printing -- and some contradict each other, so adopt each by its
exact name.

## Stability

A new rule starts as `nursery`, off under everything but `nursery` or its
exact name, and becomes `stable` after review, keeping its name and group.

| Selection | Runs |
| --- | --- |
| `default` | stable `correctness`, `suspicious` and `perf` |
| `all` | every stable rule outside `restriction` |
| `all,restriction,nursery` | every rule |

## Fixes

The `fix` column is a promise its tests enforce: `never`, `sometimes` or
`always`. Whether a given fix is safe or unsafe is decided per finding; see
[fixing](/litany/guide/fixing/).

## Project rules

`unused-export` and `dead-code` look across modules. `unused-export` reports an
exported value no other unit references; `dead-code` reports every exported
value unreachable from a root. Both are `nursery`:

```console
$ litany check --select unused-export,dead-code
```

The roots are the exports of public libraries, unless
[`closed-world`](/litany/guide/configuration/#closed-world) is set; the top level
of executables and tests; and anything you mark with a reason:

```ocaml
val migrate : (string * int) list -> (string * int) list
[@@litany.root "run by the ops console"]
```

Their claim needs the whole project, so one skipped unit withholds their
reports for the run. `--explain-withheld` says which unit blocked which rule.

## Renamed rules

A renamed rule keeps its old name as an alias, in selection, configuration and
attributes, with a warning naming the new one.
