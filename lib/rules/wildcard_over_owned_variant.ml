(*---------------------------------------------------------------------------
   Copyright (c) 2026 Hypha Technologies Ltd.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"wildcard-over-owned-variant" ~group:Rule.Restriction
    ~stability:Rule.Stability.Nursery ~since:"1.1" ~fix:Rule.Never
    ~summary:"a wildcard arm in a match over a variant the code owns"
    ~doc:
      {|A match over a variant the code owns names every case, so a
constructor added later is a compile error at every match that should
handle it -- warning 8 asks for it -- where a `_` arm takes it silently
into whatever the arm does.

    (* bad *)  match s with Open -> "open" | _ -> "closed"
    (* good *) match s with Open -> "open" | Done | Dropped -> "closed"

Why restrict this? A match over another library's variant ends in a
catch-all, since a variant grows in a minor release, so a wildcard is
not a defect in itself; which variants a house owns is its own to say.

    (rule wildcard-over-owned-variant
     (owned app_core app_http))

Fires at a guard-less `_` value arm of a `match` whose other arms name a
constructor of a variant declared in the same compilation unit, in
another module of the same wrapped library, or in a library the
`(owned <library> ...)` option names. A variant of any other library,
the predefined ones (`option`, `list`, `bool`), an extensible variant,
which has no last case to name, a guarded wildcard, a wildcard nested in
a pattern (`Some _`), an `exception _` arm, and a match whose arms name
no constructor deliberately do not fire. A module alias names the module
it aliases: `module E = Either` owns nothing. Recorded
false negatives, in the safe direction: `function` matches, and a
library built unwrapped. No fix: only the author knows what each case
should do.|}
    ()

(* The wrapper a wrapped library gives its modules: [Lib__Mod] is module
   [Mod] of library [lib], and [Lib] its own top. *)
let wrapper unit_name =
  let n = String.length unit_name in
  let rec find i =
    if i + 1 >= n then unit_name
    else if Char.equal unit_name.[i] '_' && Char.equal unit_name.[i + 1] '_'
    then String.sub unit_name 0 i
    else find (i + 1)
  in
  find 0

(* What a module of this unit is an alias of, if it is one. *)
let aliased u id =
  let found = ref None in
  let default = Tast_iterator.default_iterator in
  let iterator =
    {
      default with
      module_binding =
        (fun sub (mb : Typedtree.module_binding) ->
          (match (mb.mb_id, mb.mb_expr.mod_desc) with
          | Some bound, Tmod_ident (target, _) when Ident.same bound id ->
              found := Some target
          | _ -> ());
          default.module_binding sub mb);
    }
  in
  iterator.structure iterator (Unit.implementation u);
  !found

let rec owned ~libraries u path =
  match Path.head path with
  | id when not (Ident.global id) -> (
      match aliased u id with
      | Some target -> owned ~libraries u target
      | None -> true)
  | id ->
      let head = wrapper (Ident.name id) in
      String.equal head (wrapper (Unit.name u))
      || List.exists
           (fun lib -> String.equal head (String.capitalize_ascii lib))
           libraries

(* The variant a match is over, from a constructor one of its arms names:
   a [.cmt] keeps each environment as a summary alone, so the scrutinee's
   type is not looked up. *)
let rec variant (p : Typedtree.value Typedtree.general_pattern) =
  match p.pat_desc with
  | Tpat_construct (_, cd, _, _) -> (
      match (cd.cstr_tag, Types.get_desc cd.cstr_res) with
      | Cstr_extension _, _ -> None
      | _, Tconstr (path, _, _) -> Some path
      | _ -> None)
  | Tpat_or (a, b, _) -> (
      match variant a with Some _ as v -> v | None -> variant b)
  | Tpat_alias (q, _, _, _, _) -> variant q
  | _ -> None

let check ~libraries u (e : Typedtree.expression) =
  match e.exp_desc with
  | Texp_match (_, cases, _, _) -> (
      let arms =
        List.filter_map
          (fun (c : Typedtree.computation Typedtree.case) ->
            match Typedtree.split_pattern c.c_lhs with
            | Some v, _ -> Some (v, c.c_guard)
            | None, _ -> None)
          cases
      in
      match List.find_map (fun (v, _) -> variant v) arms with
      | Some path when owned ~libraries u path ->
          List.filter_map
            (fun ((v : Typedtree.value Typedtree.general_pattern), guard) ->
              match (v.pat_desc, guard) with
              | Tpat_any, None ->
                  Some
                    (Finding.v ~loc:v.pat_loc
                       (Printf.sprintf
                          "a wildcard arm over %s, a variant this code owns: \
                           name every case"
                          (Path.name path)))
              | _ -> None)
            arms
      | Some _ | None -> [])
  | _ -> []

(* The option schema: (owned <library> ...), the libraries besides the
   unit's own whose variants the code owns. *)
let rec with_libraries libraries =
  Rule.with_options schema (Rule.expr meta (check ~libraries))

and schema payload =
  let err at fmt =
    Printf.ksprintf (fun m -> Error (Rule.Options.v ~at m)) fmt
  in
  let parse_form acc form =
    match form.Rule.Sexp.desc with
    | Rule.Sexp.List ({ Rule.Sexp.desc = Atom "owned"; _ } :: []) ->
        err form "owned wants one library or more: (owned <library> ...)"
    | Rule.Sexp.List ({ Rule.Sexp.desc = Atom "owned"; _ } :: libs) ->
        List.fold_left
          (fun acc (lib : Rule.Sexp.t) ->
            Result.bind acc (fun acc ->
                match lib.desc with
                | Rule.Sexp.Atom "" -> err lib "owned wants a library name"
                | Rule.Sexp.Atom name when List.mem name acc ->
                    err lib "library %S is owned twice" name
                | Rule.Sexp.Atom name -> Ok (name :: acc)
                | Rule.Sexp.List _ ->
                    err lib "owned wants library names: (owned <library> ...)"))
          (Ok acc) libs
    | Rule.Sexp.List ({ Rule.Sexp.desc = Atom other; _ } :: _) ->
        err form "unknown option %S (options: owned)" other
    | Rule.Sexp.Atom _ | Rule.Sexp.List _ ->
        err form "expected (owned <library> ...)"
  in
  Result.map
    (fun acc -> with_libraries (List.rev acc))
    (List.fold_left
       (fun acc form -> Result.bind acc (fun acc -> parse_form acc form))
       (Ok []) payload)

let rule = with_libraries []
