(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"restricted-export-name" ~group:Rule.Restriction ~since:"1.0"
    ~fix:Rule.Never
    ~summary:"exported name breaking the configured naming policy"
    ~doc:
      {|An exported name is API surface forever: a prime-suffixed `parse'`
or a five-underscore `total_count_of_all_things` in an interface makes
every consumer spell the house's least readable habit. Inside a
function those names are the author's business; on the export surface
they are policy, and this rule is that policy's closed vocabulary —
enumerated options, never a user-supplied regex (a regex option would
be a second pattern language smuggled through configuration).

    (rule restricted-export-name
     (forbid-suffix ')
     (max-underscores 3))

    (* bad *)  val parse' : string -> t
    (* good *) val parse_exn : string -> t

Why restrict this? Every condemned spelling is legitimate OCaml —
`f'` is idiomatic mathematics, long underscored names are a taste — so
no default may claim them as defects; which spellings a house bans is
policy, cherry-picked, never in `all`. Litany's export index makes
these checks one walk over resolved exports instead of a text scan. No
fix: renaming an export is an interface decision.

Fires once per exported name — a value or type of the unit's export
surface — that a configured restriction condemns: `(forbid-suffix <s>)`
condemns a name ending in `<s>`, `(max-underscores <n>)` a name
carrying more than `<n>` underscores. Restrictions are tried in
configured order and the first condemning one reports, its option named
in the message. The export surface is the seam's: the unit's interface
when it has one, the implementation's own inferred signature when it
does not — so an `.mli` decides what is exported, and an ml-only unit
exports every root declaration, executables and tests included: their
root names are surface to their own readers, and the tier keeps the
rule opt-in. Findings anchor at the implementation's matching root
declaration (`let`, `external`, or `type`), never in the `.mli`.

Without a `(rule restricted-export-name ...)` form, or with one holding
no restrictions, the rule is inert. Names the interface hides, local
bindings and type abbreviations inside functions or nested modules,
module names, a forbidden suffix occurring mid-name, and names at the
underscore limit deliberately do not fire. Recorded false negatives, in
the safe direction: exported members of submodules (the export surface
joins interface to implementation at the unit's root only) and exports
satisfied by `include` (no root declaration to anchor at).|}
    ~requires_options:true ()

(* One configured restriction. The closed vocabulary: a literal suffix
   test and an underscore count — enumerated options only, never a
   user-supplied regex. Configured order is trial order. *)
type restriction = Forbid_suffix of string | Max_underscores of int

let underscores name =
  String.fold_left (fun n c -> if Char.equal c '_' then n + 1 else n) 0 name

(* [condemn rs name] is the first configured restriction's verdict on
   [name] — the message names the condemning option verbatim. *)
let condemn restrictions name =
  List.find_map
    (function
      | Forbid_suffix s when String.ends_with ~suffix:s name ->
          Some
            (Printf.sprintf
               "%s ends with %S, forbidden in exported names by (forbid-suffix \
                %s)"
               name s s)
      | Max_underscores n when underscores name > n ->
          Some
            (Printf.sprintf
               "%s carries %d underscores, over the (max-underscores %d) limit \
                for exported names"
               name (underscores name) n)
      | Forbid_suffix _ | Max_underscores _ -> None)
    restrictions

(* [anchor u kind name] is the name's location in the implementation's
   root declaration of [name] — the missing-printer seam: findings
   anchor in the editable source, joined by name at the unit's root
   (module-level linking's own nominal rule), the last declaration
   winning exactly as the signature's row does. [None] — an
   [include]-satisfied export — stays silent, a recorded false
   negative. *)
let anchor u kind name =
  List.fold_left
    (fun acc (item : Typedtree.structure_item) ->
      match (kind, item.Typedtree.str_desc) with
      | Unit.Export.Value, Typedtree.Tstr_value (_, vbs) ->
          List.fold_left
            (fun acc (vb : Typedtree.value_binding) ->
              match Pat.bound_var vb.Typedtree.vb_pat with
              | Some (n, _) when String.equal n.Location.txt name ->
                  Some n.Location.loc
              | Some _ | None -> acc)
            acc vbs
      | Unit.Export.Value, Typedtree.Tstr_primitive vd
        when String.equal vd.Typedtree.val_name.Location.txt name ->
          Some vd.Typedtree.val_name.Location.loc
      | Unit.Export.Type, Typedtree.Tstr_type (_, ds) ->
          List.fold_left
            (fun acc (d : Typedtree.type_declaration) ->
              if String.equal d.Typedtree.typ_name.Location.txt name then
                Some d.Typedtree.typ_name.Location.loc
              else acc)
            acc ds
      | ( ( Unit.Export.Value | Unit.Export.Type | Unit.Export.Module
          | Unit.Export.Exception ),
          _ ) ->
          acc)
    None (Unit.implementation u).Typedtree.str_items

let check restrictions u x =
  match restrictions with
  | [] -> []
  | _ :: _ -> (
      match Unit.Export.kind x with
      | Unit.Export.Module | Unit.Export.Exception -> []
      | (Unit.Export.Value | Unit.Export.Type) as kind -> (
          let name = Unit.Export.name x in
          (* Dotted rows are submodule members: outside the root surface
             this rule claims (recorded false negative). *)
          if String.contains name '.' then []
          else
            match condemn restrictions name with
            | None -> []
            | Some message -> (
                match anchor u kind name with
                | Some loc -> [ Finding.v ~loc message ]
                | None -> [])))

(* The option schema: zero or more of the two closed forms, tried in
   configured order. The reconfigured rule re-attaches the schema, so
   configuring twice works. *)
let rec with_restrictions restrictions =
  Rule.with_options schema (Rule.export meta (check restrictions))

and schema payload =
  let err at fmt =
    Printf.ksprintf (fun m -> Error (Rule.Options.v ~at m)) fmt
  in
  let keys = [ "forbid-suffix"; "max-underscores" ] in
  let shape = "(forbid-suffix <suffix>) or (max-underscores <count>)" in
  let parse_form acc form =
    match form.Rule.Sexp.desc with
    | Rule.Sexp.List [ { Rule.Sexp.desc = Atom "forbid-suffix"; _ }; arg ] -> (
        match arg.Rule.Sexp.desc with
        | Rule.Sexp.Atom "" -> err arg "forbid-suffix wants a non-empty suffix"
        | Rule.Sexp.Atom s ->
            if
              List.exists
                (function
                  | Forbid_suffix s' -> String.equal s s'
                  | Max_underscores _ -> false)
                acc
            then err arg "suffix %S is forbidden twice" s
            else Ok (Forbid_suffix s :: acc)
        | Rule.Sexp.List _ ->
            err arg
              "forbid-suffix wants one suffix atom: (forbid-suffix <suffix>)")
    | Rule.Sexp.List [ { Rule.Sexp.desc = Atom "max-underscores"; _ }; arg ]
      -> (
        match arg.Rule.Sexp.desc with
        | Rule.Sexp.Atom s -> (
            match int_of_string_opt s with
            | Some n when n >= 0 ->
                if
                  List.exists
                    (function
                      | Max_underscores _ -> true | Forbid_suffix _ -> false)
                    acc
                then err arg "max-underscores is set twice"
                else Ok (Max_underscores n :: acc)
            | Some _ | None ->
                err arg "max-underscores wants a non-negative count, not %S" s)
        | Rule.Sexp.List _ ->
            err arg
              "max-underscores wants one count atom: (max-underscores <count>)")
    | Rule.Sexp.List ({ Rule.Sexp.desc = Atom key; _ } :: _)
      when List.mem key keys ->
        err form "%s wants exactly one argument: %s" key shape
    | Rule.Sexp.List ({ Rule.Sexp.desc = Atom other; _ } :: _) ->
        (* When nothing is near enough for a did-you-mean, state the closed
           vocabulary instead of leaving only what does not exist. *)
        err form "unknown option %S%s" other
          (match Rule.suggest ~candidates:keys other with
          | Some c -> Printf.sprintf " (did you mean %S?)" c
          | None -> Printf.sprintf " (options: %s)" (String.concat ", " keys))
    | Rule.Sexp.Atom _ | Rule.Sexp.List _ -> err form "expected %s" shape
  in
  Result.map
    (fun acc -> with_restrictions (List.rev acc))
    (List.fold_left
       (fun acc form -> Result.bind acc (fun acc -> parse_form acc form))
       (Ok []) payload)

let rule = with_restrictions []
