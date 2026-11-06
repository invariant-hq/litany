---
title: Configuration
description: "The litany file: what runs, what each rule is told, and which reports are dropped by path."
---

litany runs without configuration. When you want some, write a file named
`litany` at the workspace root: the directory `--root` names, by default the
current one. Every form is optional:

```lisp
(litany-config 1)             ; optional version header

(lint
 (select default)             ; what runs
 (extend trailing-whitespace) ; add to select without replacing it
 (ignore needless-list-length)
 (closed-world false))        ; project rules: see below

(rule quadratic-string-concat-chain
 (max-segments 4))            ; the named rule's own options

(per-path
 (paths vendor/** third-party/*.ml)
 (ignore all)
 (reason "vendored code"))
```

An unknown form, key or rule is an error with its position, and a suggestion
where one is close. The run exits 2 and nothing runs. `litany unit` doesn't read
this file.

## Selection

`select`, `extend`, `ignore` and the flags `--select` and `--ignore` take:

- a rule's name;
- a group: `correctness`, `suspicious`, `perf`, `style`, `pedantic`,
  `restriction`, meaning its stable rules;
- `nursery`, `default` or `all`
  ([what they run](/litany/guide/selecting-rules/#stability)).

An exact name outranks a group, which outranks `all` and `default`; at equal
rank `ignore` wins. So `(select perf) (ignore needless-list-length)` runs the
other `perf` rules. A flag replaces the file's list for that run.

To keep a `restriction` rule out of tests, adopt it and ring them off:

```lisp
(lint (extend unsafe-partial-stdlib))
(per-path
 (paths test/** bench/**)
 (ignore unsafe-partial-stdlib)
 (reason "partiality is assertion-shaped in tests"))
```

## Rule options

Four rules take options, each documented on its own page:

| Rule | Options | With none |
| --- | --- | --- |
| [`quadratic-string-concat-chain`](/litany/reference/rules/quadratic-string-concat-chain/) | `(max-segments <n>)`, at least 2 | 2 |
| [`restricted-dependency`](/litany/reference/rules/restricted-dependency/) | `(forbid <path> (use "<replacement>"))`, any number | reports nothing |
| [`restricted-export-name`](/litany/reference/rules/restricted-export-name/) | `(forbid-suffix <s>)`, `(max-underscores <n>)` | reports nothing |
| [`wildcard-over-owned-variant`](/litany/reference/rules/wildcard-over-owned-variant/) | `(owned <library> ...)` | the unit's own library alone |

Options configure a rule; they never enable it, so select it as well. litany
warns about both mistakes, and the run goes on:

```text
litany: rule "quadratic-string-concat-chain" is configured but not selected
litany: rule "restricted-dependency" is selected but not configured; it reports nothing without a (rule restricted-dependency ...) form
```

A rule's options hold for the whole workspace and for every run: no flag sets
them, and `per-path` can only drop a rule's reports. To vary by file, scope a
forbid:

```lisp
(rule restricted-dependency
 (forbid Stdlib.print_endline
  (use "a formatter the caller hands in")
  (except test/** bin/**))
 (forbid Unix.gettimeofday
  (use "the clock the caller hands in")
  (only lib/**)))
```

### What a forbid matches

A forbid names a compilation unit, then the path inside it, and is matched by
what a reference resolves to, through aliases and `open`:

- `Unix.sleep` and `Str` are units of their own. The standard library's names
  start at `Stdlib`: `Stdlib.List.hd`, `Stdlib.Printf`. An operator is quoted:
  `"Stdlib.(=)"`.
- A capitalised last component forbids a whole module, and a lowercase one that
  value. A module's constructors and types don't fire.

**A forbid that resolves to nothing matches nothing, and says nothing**, so one
configuration can serve projects without that library. A misspelt name is
silent too: `List.hd` for `Stdlib.List.hd` bans nothing. So try each new forbid
once on a use of it. Names resolve in the opam switch litany is installed in,
which is why it belongs in the project's.

## Ignoring by path

`per-path` drops reports, not analysis: matching units still build and run.
`(ignore all)` drops every report there, including the suppression audits. It
is also the only way to silence a text rule such as `trailing-whitespace`.

Globs are anchored at the workspace root and must match the whole path. `*`
and `?` stay within one component. `**` must be a whole component: `vendor/**`
matches `vendor/x.ml` and `vendor/a/x.ml`, and `a/**/b.ml` matches `a/b.ml`.

## closed-world

By default a public library's exports are roots for the
[project rules](/litany/guide/selecting-rules/#project-rules), since users
outside the workspace may call them. `(closed-world true)` says the workspace
is everything, so they are reported too. Set it in an application, not in a
published library.
