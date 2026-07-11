(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"suspicious-polymorphic-compare-on-opaque"
    ~group:Rule.Suspicious ~since:"1.0" ~fix:Rule.Never
    ~summary:"polymorphic comparison of a Set, Map, or Hashtbl value"
    ~doc:
      {|`Set.Make` and `Map.Make` build balanced trees whose shape depends on
insertion history, and `Hashtbl.t` is a mutable record of bucket arrays:
structural comparison sees those representations, not the values they
encode. Two equal sets can compare unequal, `<` orders trees
meaninglessly, and `=` on tables compares bucket layout — the functors
export `equal` and `compare` precisely because polymorphic comparison
cannot work.

    (* bad *)  if s1 = s2 then …
    (* good *) if IntSet.equal s1 s2 then …

Fires when `=`, `<>`, `<`, `>`, `<=`, `>=`, `compare`, `min`, or `max`
resolves to its `Stdlib` declaration with an operand — or `List.mem`,
`List.assoc`, `List.assoc_opt`, or `List.mem_assoc` with its compared
key — whose type proves an opaque head: `Hashtbl.t`, a `Set.Make` or
`Map.Make` instance reached across a compilation-unit boundary, or a
`list`, `array`, or `option` of one. The proof never guesses: shadowed
operators, the modules' own `equal`/`compare`, abbreviation heads
(`type cache = … Hashtbl.t`), physical equality, and partial or labeled
applications deliberately do not fire. Functor instances declared in the
linted unit itself and tuple components are recorded false negatives.
No fix: the remedy is the module's own
`equal`/`compare` or a key redesign the author must choose.|}
    ()

let comparison =
  Pat.(
    apply
      (idents
         [
           "Stdlib.(=)";
           "Stdlib.(<>)";
           "Stdlib.(<)";
           "Stdlib.(>)";
           "Stdlib.(<=)";
           "Stdlib.(>=)";
           "Stdlib.compare";
           "Stdlib.min";
           "Stdlib.max";
         ])
      (__ ^:: __ ^:: nil))

let membership =
  Pat.(
    apply
      (idents
         [
           "Stdlib.List.mem";
           "Stdlib.List.assoc";
           "Stdlib.List.assoc_opt";
           "Stdlib.List.mem_assoc";
         ])
      (__ ^:: drop ^:: nil))

(* The opaque heads, by declaration identity through the head unit's cmi:
   all instances of a functor application share the functor body's
   interface UIDs, so one canonical name covers every cross-unit
   [Set.Make]/[Map.Make] instance. A head declared in the linted unit
   itself carries no persistent root and stays clean — the recorded
   false negative until the matches_type local-alias hop lands. *)
let opaque_head =
  Pat.(
    typ "Stdlib.Hashtbl.t" ||| typ "Stdlib.Set.Make.t"
    ||| typ "Stdlib.Map.Make.t")

(* Predefined containers the polymorphic primitives walk into. *)
let container_paths = Predef.[ path_list; path_array; path_option ]

(* The proof walks visible structure only: no abbreviation expansion, no
   variable guessing — unknown heads stay clean. Tuple components await a
   version-stable Ttuple seam (the invalid-hashtable-key precedent). *)
let rec proves_opaque u ty =
  match Pat.run opaque_head u ty () with
  | Some () -> true
  | None -> (
      match Types.get_desc ty with
      | Types.Tconstr (p, args, _)
        when List.exists (Path.same p) container_paths ->
          List.exists (proves_opaque u) args
      | _ -> false)

let rule =
  Rule.expr meta @@ fun u e ->
  let proves (operand : Typedtree.expression) =
    proves_opaque u operand.exp_type
  in
  let fires =
    match Pat.run comparison u e (fun l r -> proves l || proves r) with
    | Some b -> b
    | None -> (
        match Pat.run membership u e proves with Some b -> b | None -> false)
  in
  if fires then
    [
      Finding.v ~loc:e.exp_loc
        "polymorphic comparison reads an opaque representation, not its \
         contents";
    ]
  else []
