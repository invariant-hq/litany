(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"suspicious-file-exists-race" ~group:Rule.Restriction
    ~since:"1.0" ~fix:Rule.Never
    ~summary:"exists check guarding a filesystem operation on the same path"
    ~doc:
      {|`if Sys.file_exists p then <operate on p>` is two non-atomic steps:
the world can change between them — a concurrent test run, an `at_exit`
cleanup, a watch loop — so the guard buys nothing (the guarded
operation can still raise) while adding a race window. The principled
form performs the operation and matches its exception; the ops this
rule watches each have a crisp one-errno rewrite (`ENOENT`/`EEXIST`).

    (* bad *)  if Sys.file_exists path then Sys.remove path
    (* good *) (try Sys.remove path with Sys_error _ -> ())

Why restrict this? The race is real but widely tolerated: in
single-process test cleanup it never fires, so a report there is
robustness pedantry, while the same shape in library code (a `finally`
cleanup whose unguarded `Sys.remove` masks the body's result) earns
its keep. Whether the exception-matching discipline is worth demanding
everywhere is house policy, so the rule sits in the `restriction`
tier: off even under `--select all`, cherry-picked by workspaces that
adopt it.

Fires, in non-preprocessed units, on an `if` whose condition is a
`Sys.file_exists E` probe — bare, under `not`, or as the left conjunct
of `&&` with a `Sys.is_directory` refinement — when either arm applies
`Sys.remove`, `Sys.mkdir`, `Sys.rename`, `Unix.unlink`, `Unix.mkdir`,
or `Unix.rmdir` (by resolved identity) to a path argument whose source
slice equals `E`'s after whitespace normalization, `E` itself being
syntactically pure: an identifier, a constant, or a constructor of
pure parts. Anchored at the condition, one finding per `if`. An
operation under a `try` — or under a `match` with an `exception` case
on its scrutinee — is tolerated: a handled operation is the remedy,
not the defect. Guarded reads (`Sys.readdir`), a computed or impure
path expression (`Filename.concat dir f` refuses the purity test —
identical slices could denote different files), operations on a
different path, operations deferred inside a function or `lazy`,
operations under a nested exists-guard (the inner `if` reports
itself), operations past a `let` that rebinds an identifier of the
probed path (the spelling now names a different file, so slice
equality would lie — the rebinding subtree is skipped whole), platform
probes, and existence checks used as values deliberately do not fire;
each is a recorded false negative in the safe direction. No fix: the
remedy restructures control flow around the operation's exception.|}
    ()

let message =
  "the exists check races with the guarded operation; perform it and handle \
   the exception"

(* The guard shapes, each capturing the probed path expression [E]:
   [Sys.file_exists E], [not (Sys.file_exists E)] (the arms swap), and
   [Sys.file_exists E && Sys.is_directory _] (the refinement conjunct).
   Functions returning the pattern: the guard is hoisted at two
   continuation types (the dispatch shape and the nested-guard probe). *)
let file_exists () = Pat.(apply (ident "Stdlib.Sys.file_exists") (__ ^:: nil))

let guard () =
  Pat.(
    file_exists ()
    ||| apply (ident "Stdlib.not") (file_exists () ^:: nil)
    ||| apply (ident "Stdlib.(&&)")
          (file_exists ()
          ^:: apply (ident "Stdlib.Sys.is_directory") (drop ^:: nil)
          ^:: nil))

let shape = Pat.(if_ (as__ (guard ())) __ __)
let nested_guard = Pat.(if_ (guard ()) drop drop)

(* The v1 operation set — the ops with crisp one-errno rewrites — with
   their path-argument positions: unary path, path-then-permission, and
   rename's two paths (either may be the probed one). Exact arities:
   a partial application performs nothing and never matches. *)
let op_path =
  Pat.(
    apply
      (idents [ "Stdlib.Sys.remove"; "Unix.unlink"; "Unix.rmdir" ])
      (__ ^:: nil))

let op_path_perm =
  Pat.(
    apply (idents [ "Stdlib.Sys.mkdir"; "Unix.mkdir" ]) (__ ^:: drop ^:: nil))

let op_rename = Pat.(apply (ident "Stdlib.Sys.rename") (__ ^:: __ ^:: nil))

let op_paths u (e : Typedtree.expression) =
  match Pat.run op_path u e (fun p -> [ p ]) with
  | Some ps -> ps
  | None -> (
      match Pat.run op_path_perm u e (fun p -> [ p ]) with
      | Some ps -> ps
      | None -> (
          match
            Pat.run op_rename u e
              (fun (a : Typedtree.expression) (b : Typedtree.expression) ->
                [ a; b ])
          with
          | Some ps -> ps
          | None -> []))

(* Syntactic purity of the probed path (the rule's claim is that the
   two evaluations denote the same path, so an impure [E] refuses —
   identical slices of two calls could denote different files).
   Identifiers, constants, and constructors of pure
   parts; any application, dereference, or field read refuses. *)
let rec pure (e : Typedtree.expression) =
  match e.exp_desc with
  | Typedtree.Texp_ident _ | Typedtree.Texp_constant _ -> true
  | Typedtree.Texp_construct (_, _, args) -> List.for_all pure args
  | _ -> false

(* The identifiers the probed slice spells (unqualified last components —
   the names a local [let] could shadow). Slice equality reads spelling,
   so a rebinding of any of these between guard and op defeats the
   same-path claim; [arm_races] treats such a [let] as a boundary. *)
let rec probe_idents acc (e : Typedtree.expression) =
  match e.exp_desc with
  | Typedtree.Texp_ident (p, _, _) -> Path.last p :: acc
  | Typedtree.Texp_construct (_, _, args) ->
      List.fold_left probe_idents acc args
  | _ -> acc

let match_cases = Pat.(match_ drop __)

(* Does [arm] contain an op-set application on a slice-equal path, with
   no handler and no deferral on the way? The walk is the handler
   carve-out: a [Texp_try] subtree is skipped whole (body and handlers
   alike — no try on the path from the arm root), a
   [match] carrying an [exception] case has a handled scrutinee (only
   its cases are walked), and functions and [lazy] defer the operation
   out of the guarded window. A nested exists-guarded [if] is a
   boundary too: it reports itself, keeping one finding per guard. So is
   a [let] rebinding an identifier of the probed slice: past it, the
   spelling names a different value, so slice equality would compare two
   different files — the whole subtree is skipped, the binding's own
   right-hand side included (a recorded false negative in the safe
   direction). *)
let arm_races u ~target ~shadow arm =
  let slice_eq (arg : Typedtree.expression) =
    match Normalized_slice.slice u arg.exp_loc with
    | Some s -> String.equal (Normalized_slice.normalize s) target
    | None -> false
  in
  let found = ref false in
  let default = Tast_iterator.default_iterator in
  let iterator =
    {
      default with
      Tast_iterator.expr =
        (fun sub (x : Typedtree.expression) ->
          if not !found then
            match x.exp_desc with
            | Typedtree.Texp_try _ | Typedtree.Texp_function _
            | Typedtree.Texp_lazy _ ->
                ()
            | Typedtree.Texp_let (_, vbs, _)
              when List.exists
                     (fun (vb : Typedtree.value_binding) ->
                       List.exists
                         (fun id -> List.mem (Ident.name id) shadow)
                         (Typedtree.pat_bound_idents vb.Typedtree.vb_pat))
                     vbs ->
                ()
            | Typedtree.Texp_ifthenelse _
              when Option.is_some (Pat.run nested_guard u x (fun _ -> ())) ->
                ()
            | Typedtree.Texp_apply _ ->
                if List.exists slice_eq (op_paths u x) then found := true
                else default.expr sub x
            | Typedtree.Texp_match _ -> (
                match Pat.run match_cases u x Fun.id with
                | Some cases
                  when List.exists
                         (fun (c : Typedtree.computation Typedtree.case) ->
                           Option.is_some
                             (snd (Typedtree.split_pattern c.c_lhs)))
                         cases ->
                    List.iter
                      (fun (c : Typedtree.computation Typedtree.case) ->
                        Option.iter (sub.expr sub) c.c_guard;
                        sub.expr sub c.c_rhs)
                      cases
                | Some _ | None -> default.expr sub x)
            | _ -> default.expr sub x);
    }
  in
  iterator.expr iterator arm;
  !found

let rule =
  Rule.expr meta @@ fun u e ->
  if Unit.preprocessed u then []
  else
    (* Constructor-head gate: only conditionals can match, so every
       other node misses for one variant test. *)
    match e.exp_desc with
    | Typedtree.Texp_ifthenelse _ -> (
        match
          Pat.run shape u e
            (fun
              (cond : Typedtree.expression)
              (path : Typedtree.expression)
              (then_arm : Typedtree.expression)
              (else_arm : Typedtree.expression option)
            -> (cond, path, then_arm, else_arm))
        with
        | None -> []
        | Some (cond, path, then_arm, else_arm) -> (
            if not (pure path) then []
            else
              match Normalized_slice.slice u path.exp_loc with
              | None -> []
              | Some s ->
                  let target = Normalized_slice.normalize s in
                  let shadow = probe_idents [] path in
                  if
                    arm_races u ~target ~shadow then_arm
                    ||
                    match else_arm with
                    | Some a -> arm_races u ~target ~shadow a
                    | None -> false
                  then [ Finding.v ~loc:cond.exp_loc message ]
                  else []))
    | _ -> []
