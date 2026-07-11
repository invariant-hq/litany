(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* The solver is a private support module of [litany_rules], deliberately not
   re-exported by the catalog module: the suite reaches it by its mangled name,
   the analogue of the unmangled [Litany.Digest0] access in [test/unit]. *)

open Windtrap
module Solver = Litany_rules__Dead_code_solver

let decl = Testable.make ~pp:Solver.Decl.pp ~equal:Solver.Decl.equal
let edge = Testable.make ~pp:Solver.Edge.pp ~equal:Solver.Edge.equal
let uid = Testable.make ~pp:Solver.Uid.pp ~equal:Solver.Uid.equal

(* Fixture spellings: [d name] declares [name] in unit [owner] (default "a"),
   [e user used] is a uses edge. *)

let d ?(owner = "a") ?(root = false) name =
  Solver.Decl.v ~uid:(Solver.Uid.v name) ~owner ~root

let e user used =
  Solver.Edge.v ~user:(Solver.Uid.v user) ~used:(Solver.Uid.v used)

let unreachable = Solver.unreachable

(* {1 Generators}

   Uids come from a small pool so graphs are dense enough to contain cycles;
   the owner is a deterministic function of the uid so duplicate declarations
   never conflict (owner conflicts get their own test). Edges occasionally
   name "ghost", a uid never declared, to exercise unknown-endpoint edges. *)

let owner_of name = if Hashtbl.hash name mod 2 = 0 then "alpha" else "beta"
let gen_name = Gen.(map (fun i -> Printf.sprintf "u%d" i) (int_range 0 7))

let gen_decl =
  let open Gen in
  let+ name = gen_name and+ root_die = int_range 0 3 in
  d ~owner:(owner_of name) ~root:(root_die = 0) name

let gen_edge =
  let open Gen in
  let gen_endpoint = frequency [ (7, gen_name); (1, constant "ghost") ] in
  let+ user = gen_endpoint and+ used = gen_endpoint in
  e user used

let pp_universe ppf (decls, edges) =
  let pp_list pp_item =
    Format.pp_print_list
      ~pp_sep:(fun ppf () -> Format.fprintf ppf ";@ ")
      pp_item
  in
  Format.fprintf ppf "@[<v>decls: @[%a@]@,edges: @[%a@]@]"
    (pp_list Solver.Decl.pp) decls (pp_list Solver.Edge.pp) edges

let gen_universe =
  Gen.with_pp pp_universe Gen.(pair (list gen_decl) (list gen_edge))

(* {1 Reference implementation}

   A naive O(decls * edges) fixpoint: same duplicate merge as the contract
   (root iff any duplicate is), then saturate reachability one edge at a time
   until nothing changes. Deliberately nothing like the solver's indexed
   traversal. *)

module String_map = Map.Make (String)

let reference_merge decls =
  List.fold_left
    (fun merged declaration ->
      let key = Solver.Uid.to_string (Solver.Decl.uid declaration) in
      String_map.update key
        (function
          | None -> Some declaration
          | Some previous ->
              if Solver.Decl.is_root declaration then Some declaration
              else Some previous)
        merged)
    String_map.empty decls

let reference_reachable ~decls ~edges =
  let merged = reference_merge decls in
  let reached = Hashtbl.create 16 in
  String_map.iter
    (fun key declaration ->
      if Solver.Decl.is_root declaration then Hashtbl.replace reached key ())
    merged;
  let changed = ref true in
  while !changed do
    changed := false;
    List.iter
      (fun edge ->
        let user = Solver.Uid.to_string (Solver.Edge.user edge) in
        let used = Solver.Uid.to_string (Solver.Edge.used edge) in
        if
          String_map.mem used merged && Hashtbl.mem reached user
          && not (Hashtbl.mem reached used)
        then begin
          Hashtbl.replace reached used ();
          changed := true
        end)
      edges
  done;
  (merged, reached)

let reference_unreachable ~decls ~edges =
  let merged, reached = reference_reachable ~decls ~edges in
  String_map.fold
    (fun key declaration dead ->
      if Hashtbl.mem reached key then dead else declaration :: dead)
    merged []
  |> List.sort Solver.Decl.compare

let shuffle seed items =
  let state = Random.State.make [| seed |] in
  let array = Array.of_list items in
  for i = Array.length array - 1 downto 1 do
    let j = Random.State.int state (i + 1) in
    let swapped = array.(i) in
    array.(i) <- array.(j);
    array.(j) <- swapped
  done;
  Array.to_list array

(* {1 Suites} *)

let facts =
  group "facts"
    [
      test "uid round-trips its spelling and orders like strings" (fun () ->
          equal string "Foo.bar" (Solver.Uid.to_string (Solver.Uid.v "Foo.bar"));
          equal uid (Solver.Uid.v "x") (Solver.Uid.v "x");
          is_true ~msg:"compare compatible with equal"
            (Solver.Uid.compare (Solver.Uid.v "x") (Solver.Uid.v "x") = 0);
          is_true ~msg:"strict order"
            (Solver.Uid.compare (Solver.Uid.v "a") (Solver.Uid.v "b") < 0));
      test "decl exposes its three fields" (fun () ->
          let declaration = d ~owner:"lib" ~root:true "Lib.main" in
          equal uid (Solver.Uid.v "Lib.main") (Solver.Decl.uid declaration);
          equal string "lib" (Solver.Decl.owner declaration);
          is_true ~msg:"root" (Solver.Decl.is_root declaration));
      test "decl compares by owner, then uid, then root flag" (fun () ->
          is_true ~msg:"owner first"
            (Solver.Decl.compare (d ~owner:"a" "z") (d ~owner:"b" "a") < 0);
          is_true ~msg:"uid second" (Solver.Decl.compare (d "a") (d "b") < 0);
          is_true ~msg:"root last"
            (Solver.Decl.compare (d "a") (d ~root:true "a") < 0);
          equal decl (d ~root:true "a") (d ~root:true "a"));
      test "edge exposes both endpoints and compares by user, then used"
        (fun () ->
          let uses = e "f" "g" in
          equal uid (Solver.Uid.v "f") (Solver.Edge.user uses);
          equal uid (Solver.Uid.v "g") (Solver.Edge.used uses);
          equal edge (e "f" "g") (e "f" "g");
          is_true ~msg:"user first"
            (Solver.Edge.compare (e "a" "z") (e "b" "a") < 0);
          is_true ~msg:"used second"
            (Solver.Edge.compare (e "a" "a") (e "a" "b") < 0));
    ]

let reachability =
  group "reachability"
    [
      test "the empty universe has the empty solution" (fun () ->
          equal (list decl) [] (unreachable ~decls:[] ~edges:[]));
      test "a root is never reported, an unrooted decl always is" (fun () ->
          equal (list decl)
            [ d "b" ]
            (unreachable ~decls:[ d ~root:true "a"; d "b" ] ~edges:[]));
      test "uses are transitive from explicit roots" (fun () ->
          equal (list decl)
            [ d "d" ]
            (unreachable
               ~decls:[ d ~root:true "a"; d "b"; d "c"; d "d" ]
               ~edges:[ e "a" "b"; e "b" "c" ]));
      test "an empty root set leaves every declaration unreachable" (fun () ->
          equal (list decl)
            [ d "a"; d "b" ]
            (unreachable
               ~decls:[ d "a"; d "b" ]
               ~edges:[ e "a" "b"; e "b" "a" ]));
      test "reachability is directed: using a root confers nothing" (fun () ->
          equal (list decl)
            [ d "b" ]
            (unreachable
               ~decls:[ d ~root:true "a"; d "b" ]
               ~edges:[ e "b" "a" ]));
      test "a diamond reaches its join once and completely" (fun () ->
          equal (list decl) []
            (unreachable
               ~decls:[ d ~root:true "top"; d "left"; d "right"; d "join" ]
               ~edges:
                 [
                   e "top" "left";
                   e "top" "right";
                   e "left" "join";
                   e "right" "join";
                 ]));
    ]

let islands =
  group "dead islands"
    [
      test "a disconnected mutually recursive island is reported whole"
        (fun () ->
          equal (list decl)
            [ d "even"; d "odd" ]
            (unreachable
               ~decls:[ d ~root:true "main"; d "even"; d "odd" ]
               ~edges:[ e "even" "odd"; e "odd" "even" ]));
      test "the same island is live once a root reaches into it" (fun () ->
          equal (list decl) []
            (unreachable
               ~decls:[ d ~root:true "main"; d "even"; d "odd" ]
               ~edges:[ e "even" "odd"; e "odd" "even"; e "main" "even" ]));
      test "a self-recursive declaration cannot keep itself alive" (fun () ->
          equal (list decl)
            [ d "loop" ]
            (unreachable
               ~decls:[ d ~root:true "main"; d "loop" ]
               ~edges:[ e "loop" "loop" ]));
      test "an island dangling off a dead chain stays dead" (fun () ->
          equal (list decl)
            [ d "chain"; d "x"; d "y" ]
            (unreachable
               ~decls:[ d ~root:true "main"; d "chain"; d "x"; d "y" ]
               ~edges:[ e "chain" "x"; e "x" "y"; e "y" "x" ]));
    ]

let universe_hygiene =
  group "universe hygiene"
    [
      test "duplicate declarations merge, root winning" (fun () ->
          equal (list decl)
            [ d "b" ]
            (unreachable
               ~decls:[ d "a"; d ~root:true "a"; d "a"; d "b" ]
               ~edges:[]));
      test "duplicate edges are deduplicated" (fun () ->
          equal (list decl) []
            (unreachable
               ~decls:[ d ~root:true "a"; d "b" ]
               ~edges:[ e "a" "b"; e "a" "b"; e "a" "b" ]));
      test "an owner conflict on one uid is a caller bug" (fun () ->
          raises_match (Exn.invalid_arg ~substring:"declared by both")
            (fun () ->
              unreachable
                ~decls:[ d ~owner:"alpha" "x"; d ~owner:"beta" "x" ]
                ~edges:[]));
      test "edges naming undeclared uids are ignored" (fun () ->
          (* ghost -> b must not resurrect b; b -> ghost must not report
             ghost. *)
          equal (list decl)
            [ d "b" ]
            (unreachable
               ~decls:[ d ~root:true "a"; d "b" ]
               ~edges:[ e "ghost" "b"; e "b" "ghost"; e "a" "ghost" ]));
    ]

let properties =
  group "properties"
    [
      prop "soundness: no reported declaration is reachable from a root"
        gen_universe (fun (decls, edges) ->
          let _, reached = reference_reachable ~decls ~edges in
          List.iter
            (fun declaration ->
              let key = Solver.Uid.to_string (Solver.Decl.uid declaration) in
              is_false
                ~msg:
                  (Format.asprintf "%a is reachable yet reported" Solver.Decl.pp
                     declaration)
                (Hashtbl.mem reached key);
              is_false ~msg:"a root was reported"
                (Solver.Decl.is_root declaration))
            (unreachable ~decls ~edges));
      prop "agrees with the naive fixpoint reference" gen_universe
        (fun (decls, edges) ->
          equal (list decl)
            (reference_unreachable ~decls ~edges)
            (unreachable ~decls ~edges));
      prop "determinism: input order never changes the answer"
        Gen.(pair gen_universe (pair int int))
        (fun ((decls, edges), (decl_seed, edge_seed)) ->
          equal (list decl)
            (unreachable ~decls ~edges)
            (unreachable ~decls:(shuffle decl_seed decls)
               ~edges:(shuffle edge_seed edges)));
      prop "the report is sorted and duplicate-free" gen_universe
        (fun (decls, edges) ->
          let rec strictly_sorted = function
            | first :: (second :: _ as rest) ->
                Solver.Decl.compare first second < 0 && strictly_sorted rest
            | [ _ ] | [] -> true
          in
          is_true ~msg:"strictly sorted by Decl.compare"
            (strictly_sorted (unreachable ~decls ~edges)));
    ]

let () =
  run "dead-code-solver"
    [ facts; reachability; islands; universe_hygiene; properties ]
