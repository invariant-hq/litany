(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"restricted-dependency" ~group:Rule.Restriction ~since:"1.0"
    ~fix:Rule.Never
    ~summary:"reference to a dependency forbidden by workspace policy"
    ~doc:
      {|A dependency the workspace has moved off — `Str` for `Re`, a bare
stdlib helper for the house wrapper — stays reachable forever, and the
policy against it lives in review comments until a linter carries it.
This rule is the configured deny-list: each forbid in the config names a
module or value and the replacement to use, and every reference
resolving to a forbidden declaration reports that replacement.

    (rule restricted-dependency
     (forbid Str
      (use "Re — Str answers matches through global state"))
     (forbid Stdlib.invalid_arg
      (use "Import.invalid_arg' — house messages carry module and function")))

    (* bad *)  let re = Str.regexp "a+"
    (* good *) let re = Re.compile Re.(rep1 (char 'a'))

A forbid path ending in a capitalized component forbids a module: a
single component (`Str`) is a compilation unit, and a dotted path
(`Stdlib.Obj`, `Vendor.Internal`) resolves by signature walk from its
head unit, through module aliases — any value reference reaching through
the forbidden module fires. A path ending in a lowercase or operator
component (`Stdlib.invalid_arg`, quoted `"Stdlib.(=)"`) forbids that
one value. Matching is by resolved declaration UID, never by spelling:
`open`s and aliases (`module R = Str`) fire, and a forbidden path that
does not resolve in the linted workspace matches nothing — never an
error — so one house config serves projects that lack the library
entirely. Mind the spelling of separately compiled libraries: `Str` is
its own compilation unit, so write `(forbid Str ...)` — `Stdlib.Str`
names no declaration and matches nothing. Operator paths must be quoted
so the config reader keeps them one atom: `(forbid "Stdlib.(=)" ...)`.

Why restrict this? Every forbidden name is legitimate OCaml — `Str`
ships with the distribution, `invalid_arg` is the stdlib's own
spelling — so no default may claim them as defects; which dependencies a
workspace bans is house policy, and the reason travels in the mandatory
`use` remedy so the finding argues its own case. Litany's own
`outdated-str-module` is this rule with a hard-coded list — it found a
real global-state race in field review. Resolution
by declaration UID makes this strictly sounder than path matching: a
rebound or shadowed name never matches, an alias always does. No fix:
every replacement is a migration.

Fires once per value reference resolving to a forbidden declaration —
forbids are tried in configured order, the first match reports — with
the forbid's `use` replacement verbatim in the message (`... is a
restricted module; use ...` for a module forbid, `... is a restricted
value; use ...` for a value forbid). Without a
`(rule restricted-dependency ...)` form, or with one holding no forbids,
the rule is inert: nothing is forbidden, nothing fires. Project-local
modules or values shadowing a forbidden spelling, same-named wrapper
modules declared in other units (`Re.Str`, its own declarations), later
uses of a value bound to a forbidden one (the binding's right-hand side
already fired), and a forbidden module's constructors and types
(references, not types, are the finding unit) deliberately do not fire.|}
    ~requires_options:true ()

(* One configured forbid: the spelled path, the identity pattern
   [Pat.reference] built from it at configure time (hoisted — one parse
   and one resolution per run, the pattern-construction discipline), and
   the finding message carrying the configured [use] replacement
   verbatim. *)

(* The message's noun follows the forbid's shape — [Pat.reference]'s own
   split: a capitalized last component is a module forbid, anything else
   a value forbid: one stdlib function is not a "dependency". *)
let noun spelled =
  let last =
    match String.rindex_opt spelled '.' with
    | Some i -> String.sub spelled (i + 1) (String.length spelled - i - 1)
    | None -> spelled
  in
  if last <> "" && match last.[0] with 'A' .. 'Z' -> true | _ -> false then
    "module"
  else "value"

type forbid = {
  spelled : string;
  pat : (Typedtree.expression, unit, unit) Pat.t;
  message : string;
}

(* Reference-level matching is the outdated-str-module mechanism; the
   deny-list is configuration where unsafe-partial-stdlib's is code.
   First match reports, so overlapping forbids (a module and one of its
   values) yield one finding per reference, in configured order. *)
let check forbids u (e : Typedtree.expression) =
  let rec first = function
    | [] -> []
    | f :: rest -> (
        match Pat.run f.pat u e () with
        | Some () -> [ Finding.v ~loc:e.exp_loc f.message ]
        | None -> first rest)
  in
  first forbids

(* The option schema: zero or more (forbid <path> (use "<replacement>"))
   forms — the payload's order is the matching order. The (use ...)
   remedy is mandatory: a ban that names no replacement is a config
   error, never a defaulted message. The reconfigured rule re-attaches
   the schema, so configuring twice works. *)
let rec with_forbids forbids =
  Rule.with_options schema (Rule.expr meta (check forbids))

and schema payload =
  let err at fmt =
    Printf.ksprintf (fun m -> Error (Rule.Options.v ~at m)) fmt
  in
  let shape = {|(forbid <Module.path> (use "<replacement>"))|} in
  let parse_use forbid_form spelled = function
    | Some use_form -> (
        match use_form.Rule.Sexp.desc with
        | Rule.Sexp.List
            [
              { Rule.Sexp.desc = Atom "use"; _ };
              { Rule.Sexp.desc = Atom replacement; _ };
            ] ->
            if replacement = "" then
              err use_form "forbid %s wants a non-empty replacement in (use …)"
                spelled
            else Ok replacement
        | Rule.Sexp.List ({ Rule.Sexp.desc = Atom other; _ } :: _) ->
            err use_form "unknown key %S inside forbid %s%s" other spelled
              (match Rule.suggest ~candidates:[ "use" ] other with
              | Some c -> Printf.sprintf " (did you mean %S?)" c
              | None -> " (keys: use)")
        | Rule.Sexp.Atom _ | Rule.Sexp.List _ ->
            err use_form {|forbid %s wants (use "<replacement>")|} spelled)
    | None ->
        err forbid_form
          {|forbid %s wants a (use "<replacement>") remedy — every ban names its replacement|}
          spelled
  in
  let parse_forbid acc form =
    match form.Rule.Sexp.desc with
    | Rule.Sexp.List ({ Rule.Sexp.desc = Atom "forbid"; _ } :: rest) -> (
        match rest with
        | ({ Rule.Sexp.desc = Atom spelled; _ } as path_atom) :: use_forms -> (
            if List.exists (fun f -> String.equal f.spelled spelled) acc then
              err path_atom "%s is forbidden twice" spelled
            else
              match Pat.reference spelled with
              | Error m ->
                  (* A bare (forbid Stdlib.(=) ...) splits at the paren in
                     the sexp reader, leaving a dot-final atom; name the
                     quoting remedy. *)
                  err path_atom "%s%s" m
                    (if String.ends_with ~suffix:"." spelled then
                       {| (operator paths must be quoted: "Stdlib.(=)")|}
                     else "")
              | Ok pat -> (
                  let use_form, extra =
                    match use_forms with
                    | [] -> (None, None)
                    | u :: extra -> (Some u, List.nth_opt extra 0)
                  in
                  match extra with
                  | Some x -> err x "expected %s and nothing more" shape
                  | None ->
                      Result.map
                        (fun replacement ->
                          {
                            spelled;
                            pat;
                            message =
                              Printf.sprintf "%s is a restricted %s; use %s"
                                spelled (noun spelled) replacement;
                          }
                          :: acc)
                        (parse_use form spelled use_form)))
        | { Rule.Sexp.desc = List _; _ } :: _ | [] ->
            err form "forbid wants a dotted path first: %s" shape)
    | Rule.Sexp.List ({ Rule.Sexp.desc = Atom other; _ } :: _) ->
        (* When nothing is near enough for a did-you-mean, state the closed
           vocabulary instead of leaving only what does not exist. *)
        err form "unknown option %S%s" other
          (match Rule.suggest ~candidates:[ "forbid" ] other with
          | Some c -> Printf.sprintf " (did you mean %S?)" c
          | None -> " (options: forbid)")
    | Rule.Sexp.Atom _ | Rule.Sexp.List _ -> err form "expected %s" shape
  in
  Result.map
    (fun acc -> with_forbids (List.rev acc))
    (List.fold_left
       (fun acc form -> Result.bind acc (fun acc -> parse_forbid acc form))
       (Ok []) payload)

let rule = with_forbids []
