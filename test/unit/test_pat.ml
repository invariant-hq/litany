(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* The combinators against a real compiled fixture: expressions are fished
   out of the loaded unit's typedtree by their source slice, and matching
   goes through [Pat.run] under the unit's own scope — the same path a rule
   takes. *)

open Windtrap
module Pat = Litany.Pat
module Source = Litany.Source

let source = "fixtures/pat/fix_pat.ml"
let cmt = "fixtures/pat/.fix_pat.objs/byte/fix_pat.cmt"

let unit_ =
  lazy
    (let resolver =
       Litany.Naming.Resolver.create
         ~cmi_dirs:[ Filename.dirname cmt; Config.standard_library ]
     in
     match
       Litany.Unit.load ~resolver ~build_current:true
         (Litany.Roster.Entry.v ~source ~cmt ())
     with
     | Ok u -> u
     | Error sk -> failf "fixture did not load: %a" Litany.Unit.Skip.pp sk)

let exprs u =
  let acc = ref [] in
  let default = Tast_iterator.default_iterator in
  let iterator =
    {
      default with
      Tast_iterator.expr =
        (fun sub e ->
          acc := e :: !acc;
          default.expr sub e);
    }
  in
  iterator.structure iterator (Litany.Unit.implementation u);
  List.rev !acc

let slice u (e : Typedtree.expression) =
  match Litany.Span.of_location e.exp_loc with
  | sp -> Option.value ~default:"" (Source.slice (Litany.Unit.source u) sp)
  | exception Invalid_argument _ -> ""

(* [find s] is the unique expression whose source slice is exactly [s]. *)
let find s =
  let u = Lazy.force unit_ in
  match List.filter (fun e -> String.equal (slice u e) s) (exprs u) with
  | [ e ] -> e
  | [] -> failf "no expression slices to %S" s
  | es -> failf "%d expressions slice to %S" (List.length es) s

let run p x k = Pat.run p (Lazy.force unit_) x k

(* [count p] is how many expressions of the fixture [p] matches. *)
let count p =
  let u = Lazy.force unit_ in
  List.length (List.filter (fun e -> run p e () <> None) (exprs u))

(* [pats u] is every value pattern of the loaded unit, in traversal
   order — the nodes a pattern rule would be dispatched at. *)
let pats u =
  let acc = ref [] in
  let default = Tast_iterator.default_iterator in
  let iterator =
    {
      default with
      Tast_iterator.pat =
        (fun (type k) sub (p : k Typedtree.general_pattern) ->
          (match Typedtree.classify_pattern p with
          | Typedtree.Value -> acc := (p : Typedtree.pattern) :: !acc
          | Typedtree.Computation -> ());
          default.pat sub p);
    }
  in
  iterator.structure iterator (Litany.Unit.implementation u);
  List.rev !acc

let find_pat s =
  let u = Lazy.force unit_ in
  let slice_pat (p : Typedtree.pattern) =
    match Litany.Span.of_location p.pat_loc with
    | sp -> Option.value ~default:"" (Source.slice (Litany.Unit.source u) sp)
    | exception Invalid_argument _ -> ""
  in
  match List.filter (fun p -> String.equal (slice_pat p) s) (pats u) with
  | [ p ] -> p
  | [] -> failf "no pattern slices to %S" s
  | ps -> failf "%d patterns slice to %S" (List.length ps) s

let ident_tests =
  group "ident"
    [
      test "matches every canonical use and nothing else" (fun () ->
          (* [len] and [empty] each apply List.length. *)
          equal int 2 (count (Pat.ident "Stdlib.List.length"));
          equal int 2 (count (Pat.ident "Stdlib.max"));
          equal int 1 (count (Pat.ident "Stdlib.(=)")));
      test "an unresolved name matches nothing" (fun () ->
          equal int 0 (count (Pat.ident "Nowhere_at_all.thing")));
      test "a malformed name raises at construction" (fun () ->
          raises_match (Exn.invalid_arg ~substring:"Pat.ident") (fun () ->
              Pat.ident "not-a-name"));
      test "idents is any-of over canonical names" (fun () ->
          (* max matches twice, (=) once — the union, left-biased. *)
          equal int 3 (count (Pat.idents [ "Stdlib.max"; "Stdlib.(=)" ]));
          raises_match (Exn.invalid_arg ~substring:"Pat.idents") (fun () ->
              Pat.idents []));
    ]

let apply_tests =
  group "apply"
    [
      test "an exact one-argument shape matches and captures" (fun () ->
          let u = Lazy.force unit_ in
          let e = find "List.length xs" in
          let got =
            run
              Pat.(apply (ident "Stdlib.List.length") (__ ^:: nil))
              e
              (fun x -> slice u x)
          in
          equal (option string) (Some "xs") got);
      test "captures compose left to right, callee first" (fun () ->
          let u = Lazy.force unit_ in
          let e = find "max 1 2" in
          let got =
            run
              Pat.(apply (as__ (ident "Stdlib.max")) (__ ^:: __ ^:: nil))
              e
              (fun callee l r -> (slice u callee, slice u l, slice u r))
          in
          equal
            (option (triple string string string))
            (Some ("max", "1", "2"))
            got);
      test "an exact argument shape refuses a partial application" (fun () ->
          let e = find "max 1" in
          equal (option bool) None
            (run
               Pat.(apply (ident "Stdlib.max") (drop ^:: drop ^:: nil))
               e true);
          (* the same node is a one-argument application *)
          equal (option bool) (Some true)
            (run Pat.(apply (ident "Stdlib.max") (drop ^:: nil)) e true));
      test "labeled arguments are refused" (fun () ->
          let e = find "lab ~x:1" in
          equal (option bool) None (run Pat.(apply drop (drop ^:: nil)) e true));
    ]

let apply_list_tests =
  group "apply with a whole-list capture"
    [
      test "captures the callee's captures, then the arguments in order"
        (fun () ->
          let u = Lazy.force unit_ in
          let e = find "add3 1 2 3" in
          let got =
            run
              Pat.(apply __ __)
              e
              (fun f args -> (slice u f, List.map (slice u) args))
          in
          equal
            (option (pair string (list string)))
            (Some ("add3", [ "1"; "2"; "3" ]))
            got);
      test "any arity matches: single-argument and partial applications"
        (fun () ->
          let u = Lazy.force unit_ in
          let args p e =
            run Pat.(apply p __) e (fun args -> List.map (slice u) args)
          in
          equal
            (option (list string))
            (Some [ "xs" ])
            (args Pat.(ident "Stdlib.List.length") (find "List.length xs"));
          equal
            (option (list string))
            (Some [ "4"; "5" ])
            (args Pat.drop (find "add3 4 5")));
      test "one labeled argument refuses the whole node" (fun () ->
          let e = find "lab ~x:1" in
          equal (option bool) None (run Pat.(apply drop __) e (fun _ -> true)));
    ]

let typ_tests =
  group "typ"
    [
      test "matches the canonical head of a cmi-declared type" (fun () ->
          let u = Lazy.force unit_ in
          let ty = (find "Ok 9").exp_type in
          equal (option bool) (Some true)
            (Pat.run (Pat.typ "Stdlib.result") u ty true);
          equal (option bool) None (Pat.run (Pat.typ "Stdlib.option") u ty true));
      test "matches a predefined head through its Stdlib spelling" (fun () ->
          let u = Lazy.force unit_ in
          equal (option bool) (Some true)
            (Pat.run (Pat.typ "Stdlib.option") u (find "Some 9").exp_type true);
          equal (option bool) (Some true)
            (Pat.run (Pat.typ "Stdlib.int") u (find "7").exp_type true);
          equal (option bool) None
            (Pat.run (Pat.typ "Stdlib.list") u (find "Some 9").exp_type true));
      test "a type declared in the linted unit matches no canonical name"
        (fun () ->
          let u = Lazy.force unit_ in
          let ty = (find "Box 1").exp_type in
          equal (option bool) None (Pat.run (Pat.typ "Fix_pat.box") u ty true);
          equal (option bool) None (Pat.run (Pat.typ "Stdlib.option") u ty true));
      test "an unresolved name matches nothing; a malformed name raises"
        (fun () ->
          let u = Lazy.force unit_ in
          equal (option bool) None
            (Pat.run
               (Pat.typ "Nowhere_at_all.t")
               u (find "Some 9").exp_type true);
          raises_match (Exn.invalid_arg ~substring:"Pat.typ") (fun () ->
              Pat.typ "not-a-name"));
    ]

let bound_var_tests =
  group "bound_var"
    [
      test "a variable pattern yields its name, location, and uid" (fun () ->
          let p = find_pat "seven" in
          match Pat.bound_var p with
          | None -> fail "no bound variable"
          | Some (name, uid) ->
              equal string "seven" name.Location.txt;
              is_false ~msg:"a written declaration has a real location"
                name.Location.loc.Location.loc_ghost;
              let use_uid =
                match (find "seven").exp_desc with
                | Typedtree.Texp_ident (_, _, vd) -> vd.Types.val_uid
                | _ -> fail "the use of seven is not an identifier"
              in
              is_true ~msg:"the uid is the one the use site carries"
                (Shape.Uid.equal uid use_uid));
      test "an alias pattern yields the alias name" (fun () ->
          match Pat.bound_var (find_pat "(l, _) as whole") with
          | None -> fail "no bound variable"
          | Some (name, _) -> equal string "whole" name.Location.txt);
      test "wildcards and deeper patterns bind nothing at this node" (fun () ->
          (* the wildcard is fetched by capture: several patterns slice
             to a bare [_] since the view shapes joined the fixture *)
          (match run Pat.(pcons drop __) (find_pat "x :: _") Fun.id with
          | Some wild -> is_true ~msg:"wildcard" (Pat.bound_var wild = None)
          | None -> failf "no wildcard tail");
          is_true ~msg:"tuple" (Pat.bound_var (find_pat "(l, _)") = None));
    ]

let constant_tests =
  group "constants and captures"
    [
      test "eint with cst matches the literal, not other literals" (fun () ->
          equal int 1 (count Pat.(eint (cst 0)));
          equal int 1 (count Pat.(eint (cst 7)));
          equal int 0 (count Pat.(eint (cst 42))));
      test "estring compares post-lexing content" (fun () ->
          equal int 1 (count Pat.(estring (cst "hello")));
          equal int 0 (count Pat.(estring (cst "other"))));
      test "__ captures the node itself; drop captures nothing" (fun () ->
          let u = Lazy.force unit_ in
          let e = find "\"hello\"" in
          equal (option string) (Some "\"hello\"")
            (run Pat.__ e (fun x -> slice u x));
          equal (option int) (Some 7) (run Pat.drop e 7));
      test "a successful single-arm run applies the continuation once"
        (fun () ->
          let e = find "List.length xs" in
          let calls = ref 0 in
          let _ =
            run
              Pat.(apply (ident "Stdlib.List.length") (__ ^:: nil))
              e
              (fun _ -> incr calls)
          in
          equal int 1 !calls);
      test "a failed match never applies the continuation" (fun () ->
          (* The mli's contract: captures are staged, and [k] runs exactly
             once, at commit — an arm that refuses after [as__] captured
             has not run [k] at all. *)
          let e = find "List.length xs" in
          let calls = ref 0 in
          let got =
            run
              Pat.(
                apply (as__ (ident "Stdlib.List.length")) (eint (cst 99) ^:: nil))
              e
              (fun _ -> incr calls)
          in
          is_true ~msg:"match failed" (got = None);
          equal int 0 !calls);
      test "alternation applies the continuation for the winning arm only"
        (fun () ->
          let e = find "List.length xs" in
          let calls = ref 0 in
          let got =
            run
              Pat.(
                apply (as__ (ident "Stdlib.List.length")) (eint (cst 99) ^:: nil)
                ||| apply (as__ (ident "Stdlib.List.length")) (drop ^:: nil))
              e
              (fun _ -> incr calls)
          in
          is_true ~msg:"right arm matched" (got <> None);
          (* The abandoned left arm's captures are discarded, not applied:
             [k] runs once, for the arm that committed. *)
          equal int 1 !calls);
    ]

let alternation_tests =
  group "alternation"
    [
      test "falls through to the right arm on failure" (fun () ->
          let e = find "\"hello\"" in
          equal (option bool) (Some true)
            (run Pat.(eint (cst 9) ||| estring (cst "hello")) e true);
          equal (option bool) None
            (run Pat.(eint (cst 9) ||| estring (cst "nope")) e true));
      test "left bias: a matching left arm answers" (fun () ->
          let e = find "0" in
          equal (option bool) (Some true)
            (run Pat.(eint (cst 0) ||| eint (cst 0)) e true));
    ]

let payload_tests =
  let str s =
    Parsetree.PStr
      [
        Ast_helper.Str.eval
          (Ast_helper.Exp.constant (Ast_helper.Const.string s));
      ]
  in
  group "payload_string"
    [
      test "a single string payload is extracted" (fun () ->
          equal (option string) (Some "-a")
            (Option.map fst (Pat.payload_string (str "-a"))));
      test "every other shape is None" (fun () ->
          let int_payload =
            Parsetree.PStr
              [
                Ast_helper.Str.eval
                  (Ast_helper.Exp.constant (Ast_helper.Const.int 3));
              ]
          in
          is_true ~msg:"empty PStr"
            (Pat.payload_string (Parsetree.PStr []) = None);
          is_true ~msg:"integer constant" (Pat.payload_string int_payload = None);
          is_true ~msg:"PSig" (Pat.payload_string (Parsetree.PSig []) = None);
          is_true ~msg:"PTyp"
            (Pat.payload_string (Parsetree.PTyp (Ast_helper.Typ.any ())) = None));
    ]

(* {1 Adopted catalog views}

   Direct pins for the view contracts the rule suites only exercise
   incidentally: the effect-case
   asymmetry of [match_]/[try_], [last] on short lists, [param]'s label
   refusal, predefined-identity refusals, and the [occurs] rebinding
   non-match. *)

let id_of_path = function
  | Path.Pident id -> id
  | p -> failf "expected a Pident, got %s" (Path.name p)

let views_generic =
  group "views: generic"
    [
      test "^:: and nil impose exact shapes" (fun () ->
          let one = find "match yy with _ -> yy + 1" in
          let two = find "match y with n when n > y -> 1 | _ -> 37" in
          let exactly_one = Pat.(match_ drop (case drop drop drop ^:: nil)) in
          let exactly_two =
            Pat.(
              match_ drop (case drop drop drop ^:: case drop drop drop ^:: nil))
          in
          equal (option bool) (Some true) (run exactly_one one true);
          equal (option bool) None (run exactly_one two true);
          equal (option bool) (Some true) (run exactly_two two true));
      test "last reaches the final element, one-element lists included"
        (fun () ->
          let name e =
            run Pat.(fun_body (last (param pvar)) drop) e Ident.name
          in
          equal (option string) (Some "v") (name (find "(fun v -> v + 31)"));
          equal (option string) (Some "v")
            (name (find "(fun acc v -> acc + v)")));
      test "some and none eliminate the optional else branch" (fun () ->
          let one = find "if c then print_string \"x\"" in
          let two = find "if c then 1 else 2" in
          equal (option bool) (Some true)
            (run Pat.(if_ drop drop none) one true);
          equal (option bool) None (run Pat.(if_ drop drop none) two true);
          equal (option bool) (Some true)
            (run Pat.(if_ drop drop (some drop)) two true));
    ]

let views_expr =
  group "views: expressions"
    [
      test "a three-argument list shape matches exactly that arity" (fun () ->
          let u = Lazy.force unit_ in
          equal
            (option (quad string string string string))
            (Some ("add3", "1", "2", "3"))
            (run
               Pat.(apply __ (__ ^:: __ ^:: __ ^:: nil))
               (find "add3 1 2 3")
               (fun f a b c -> (slice u f, slice u a, slice u b, slice u c)));
          equal (option bool) None
            (run
               Pat.(apply drop (drop ^:: drop ^:: drop ^:: nil))
               (find "add3 4 5") true));
      test "var captures the resolved path of any identifier" (fun () ->
          equal (option string) (Some "seven")
            (run Pat.var (find "seven") Path.name));
      test "from_unit is compilation-unit identity, not spelling" (fun () ->
          (* the two List.length uses plus [lam]/[lam2]s map and fold_left *)
          equal int 4 (count (Pat.from_unit "Stdlib__List"));
          equal int 0 (count (Pat.from_unit "Str"));
          raises_match (Exn.invalid_arg ~substring:"from_unit") (fun () ->
              Pat.from_unit "not a module"));
      test "ebool is the predefined literal - fake booleans refuse" (fun () ->
          (* [yes = true] matches; [fakes : fake = true] must not. *)
          equal int 1 (count Pat.(ebool (cst true))));
      test "enil and econs are predefined-list constructor views" (fun () ->
          let u = Lazy.force unit_ in
          equal (option bool) (Some true) (run Pat.enil (find "[]") true);
          equal (option bool) None (run Pat.enil (find "[ 1; 2; 3 ]") true);
          equal (option string) (Some "1")
            (run Pat.(econs __ drop) (find "[ 1; 2; 3 ]") (fun h -> slice u h)));
      test "esome and eok are constructor-identity views" (fun () ->
          let u = Lazy.force unit_ in
          equal (option string) (Some "9")
            (run Pat.(esome __) (find "Some 9") (fun v -> slice u v));
          equal (option string) (Some "9")
            (run Pat.(eok __) (find "Ok 9") (fun v -> slice u v));
          equal (option bool) None (run Pat.(eok drop) (find "Some 9") true);
          equal (option bool) None (run Pat.(esome drop) (find "Ok 9") true));
      test "match_ refuses effect-handler cases" (fun () ->
          let m =
            find
              "match f () with 30 -> 1 | _ -> 2 | effect Ping, k -> \
               Effect.Deep.continue k ()"
          in
          equal (option bool) None (run Pat.(match_ drop drop) m true));
      test "try_ tolerates effect-handler cases" (fun () ->
          let t =
            find
              "try f () with Not_found -> 32 | effect Ping, k -> \
               Effect.Deep.continue k ()"
          in
          equal (option int) (Some 1) (run Pat.(try_ drop __) t List.length));
      test "fun_body and fun_cases split the two function forms" (fun () ->
          let body = find "(fun v -> v + 31)" in
          let cases = find "function Some v -> v | None -> 38" in
          equal (option bool) (Some true)
            (run Pat.(fun_body drop drop) body true);
          equal (option bool) None (run Pat.(fun_cases drop drop) body true);
          equal (option int) (Some 2)
            (run Pat.(fun_cases nil __) cases List.length);
          equal (option bool) None (run Pat.(fun_body drop drop) cases true));
    ]

let views_params_cases =
  group "views: params and cases"
    [
      test "param admits only unlabeled value parameters" (fun () ->
          let lab = find "(fun ~tag -> tag + 1)" in
          equal (option bool) None
            (run Pat.(fun_body (param drop ^:: nil) drop) lab true);
          equal (option bool) (Some true)
            (run Pat.(fun_body (drop ^:: nil) drop) lab true));
      test "case exposes pattern, guard, and right-hand side" (fun () ->
          let two = find "match y with n when n > y -> 1 | _ -> 37" in
          match
            run Pat.(match_ drop (__ ^:: __ ^:: nil)) two (fun a b -> (a, b))
          with
          | None -> failf "the two-case match did not match"
          | Some (c1, c2) ->
              equal ~msg:"guarded case" (option bool) (Some true)
                (run Pat.(case drop (some drop) drop) c1 true);
              equal ~msg:"guard refusal" (option bool) None
                (run Pat.(case drop (some drop) drop) c2 true);
              equal ~msg:"guard-less case" (option bool) (Some true)
                (run Pat.(case drop none drop) c2 true));
    ]

let views_patterns =
  group "views: typed patterns"
    [
      test "pnil, pcons, pvar, pany" (fun () ->
          let cons = find_pat "x :: _" in
          equal (option string) (Some "x")
            (run Pat.(pcons pvar pany) cons Ident.name);
          equal (option bool) (Some true) (run Pat.pnil (find_pat "[]") true);
          equal (option bool) None (run Pat.pnil cons true));
      test "pbool is predefined-bool identity" (fun () ->
          equal (option bool) (Some true)
            (run Pat.(pbool true) (find_pat "true") true);
          (* fake_neg's [false] pattern is of type [fake], not bool. *)
          equal (option bool) None
            (run Pat.(pbool false) (find_pat "false") true));
      test "psome and pnone; pany is Tpat_any exactly" (fun () ->
          equal (option string) (Some "v")
            (run Pat.(psome pvar) (find_pat "Some v") Ident.name);
          equal (option bool) (Some true) (run Pat.pnone (find_pat "None") true);
          (* the payload is a variable, not a wildcard *)
          equal (option bool) None
            (run Pat.(psome pany) (find_pat "Some v") true));
      test "pvalue and pexception split computation cases" (fun () ->
          let m = find "match f () with x -> x | exception Not_found -> 31" in
          match
            run Pat.(match_ drop (__ ^:: __ ^:: nil)) m (fun a b -> (a, b))
          with
          | None -> failf "the exception match did not match"
          | Some (v, e) ->
              equal (option string) (Some "x")
                (run Pat.(pvalue pvar) v.Typedtree.c_lhs Ident.name);
              equal (option bool) None
                (run Pat.(pvalue drop) e.Typedtree.c_lhs true);
              equal (option bool) (Some true)
                (run Pat.(pexception drop) e.Typedtree.c_lhs true));
    ]

let views_queries =
  group "views: queries"
    [
      test "occurs is Ident.same - a same-spelled rebinding does not count"
        (fun () ->
          let scrut_case e =
            run Pat.(match_ var (__ ^:: nil)) e (fun p c -> (id_of_path p, c))
          in
          (match scrut_case (find "match yy with _ -> yy + 1") with
          | None -> failf "occ_pos did not match"
          | Some (yy, c) ->
              is_true ~msg:"the rhs uses the parameter"
                (Pat.occurs yy c.Typedtree.c_rhs));
          match
            scrut_case (find "match zz with _ -> (let zz = 35 in zz + 36)")
          with
          | None -> failf "occ_neg did not match"
          | Some (zz, c) ->
              is_true ~msg:"the rebound zz is a different ident"
                (not (Pat.occurs zz c.Typedtree.c_rhs)));
      test "case_occurs covers guards" (fun () ->
          match
            run
              Pat.(match_ var (__ ^:: __ ^:: nil))
              (find "match y with n when n > y -> 1 | _ -> 37")
              (fun p a b -> (id_of_path p, a, b))
          with
          | None -> failf "guard_use did not match"
          | Some (y, c1, c2) ->
              is_true ~msg:"the guard uses y" (Pat.case_occurs y c1);
              is_true ~msg:"the wildcard case does not"
                (not (Pat.case_occurs y c2)));
    ]

(* Engine-kinds batch views: tuple and record views, and the
   declaration-wide [type_refs] query. The 5.3 leg of the tuple/label
   seams is CI-lane verified (lib/pat/dune); on this leg the labeled
   refusal path is the [tuple_54] leg's code, unreachable from a
   window-portable fixture (labeled-tuple syntax would not compile on
   5.3), so it is not pinned here — recorded in
   doc/engine-kinds-notes.md. *)
let type_decl_of name =
  let u = Lazy.force unit_ in
  let acc = ref [] in
  let default = Tast_iterator.default_iterator in
  let iterator =
    {
      default with
      Tast_iterator.type_declaration =
        (fun sub (d : Typedtree.type_declaration) ->
          acc := d :: !acc;
          default.type_declaration sub d);
    }
  in
  iterator.structure iterator (Litany.Unit.implementation u);
  match
    List.filter
      (fun (d : Typedtree.type_declaration) -> String.equal d.typ_name.txt name)
      (List.rev !acc)
  with
  | [ d ] -> d
  | ds -> failf "%d type declarations named %S" (List.length ds) name

let views_kinds =
  group "tuple and record views"
    [
      test "ptuple matches tuple patterns and captures components" (fun () ->
          let p = find_pat "(a2, b2)" in
          let got =
            run
              Pat.(ptuple (pvar ^:: pvar ^:: nil))
              p
              (fun a b -> (Ident.name a, Ident.name b))
          in
          equal (option (pair string string)) (Some ("a2", "b2")) got;
          is_true (run Pat.(ptuple drop) (find_pat "pr") (fun _ -> ()) = None));
      test "erecord captures fields in declaration order, no base" (fun () ->
          let u = Lazy.force unit_ in
          let e = find "{ px = 40; py = 41 }" in
          match run Pat.(erecord none) e (fun fs -> fs) with
          | None -> failf "construction did not match"
          | Some fs ->
              equal (list string) [ "px"; "py" ]
                (List.map (fun f -> Pat.Lbl.name (Pat.Field.label f)) fs);
              equal
                (list (option string))
                [ Some "40"; Some "41" ]
                (List.map
                   (fun f -> Option.map (slice u) (Pat.Field.definition f))
                   fs);
              List.iter
                (fun f ->
                  is_false (Pat.Lbl.is_mutable (Pat.Field.label f));
                  match Pat.Lbl.res_head (Pat.Field.label f) with
                  | Some p -> equal string "point" (Path.name p)
                  | None -> failf "label has no head")
                fs);
      test "erecord matches the with base; Kept fields have no definition"
        (fun () ->
          let u = Lazy.force unit_ in
          let e = find "{ origin with py = 52 }" in
          match run Pat.(erecord (some __)) e (fun fs base -> (fs, base)) with
          | None -> failf "functional update did not match"
          | Some (fs, base) ->
              equal string "origin" (slice u base);
              equal
                (list (pair string (option string)))
                [ ("px", None); ("py", Some "52") ]
                (List.map
                   (fun f ->
                     ( Pat.Lbl.name (Pat.Field.label f),
                       Option.map (slice u) (Pat.Field.definition f) ))
                   fs));
      test "efield captures the label and matches the subject" (fun () ->
          let u = Lazy.force unit_ in
          let got =
            run
              Pat.(efield __)
              (find "pt.px")
              (fun l s -> (Pat.Lbl.name l, Pat.Lbl.is_mutable l, slice u s))
          in
          equal
            (option (triple string bool string))
            (Some ("px", false, "pt"))
            got;
          let got =
            run
              Pat.(efield drop)
              (find "c.contents")
              (fun l -> Pat.Lbl.is_mutable l)
          in
          equal (option bool) (Some true) got;
          is_true (run Pat.(efield drop) (find "seven + 1") (fun _ -> ()) = None));
      test "labels of one type join by name and Path.same head" (fun () ->
          let head e =
            match run Pat.(efield drop) e (fun l -> Pat.Lbl.res_head l) with
            | Some (Some p) -> p
            | _ -> failf "no label head"
          in
          let construction_head =
            match
              run
                Pat.(erecord none)
                (find "{ px = 40; py = 41 }")
                (fun fs -> Pat.Lbl.res_head (Pat.Field.label (List.hd fs)))
            with
            | Some (Some p) -> p
            | _ -> failf "no construction head"
          in
          is_true ~msg:"same record type, same head"
            (Path.same (head (find "pt.px")) construction_head));
    ]

let query_type_refs =
  group "type_refs"
    [
      test "kind references, in traversal order, head-first" (fun () ->
          (* R of point * cell option: the argument [cell option]'s head
             (option) precedes its parameter (cell). *)
          equal (list string)
            [ "point"; "option"; "cell" ]
            (List.map Path.name (Pat.type_refs (type_decl_of "refs"))));
      test "manifest references count" (fun () ->
          equal (list string) [ "point" ]
            (List.map Path.name (Pat.type_refs (type_decl_of "alias_pt"))));
      test "constraint references count; type variables never do" (fun () ->
          equal (list string) [ "list"; "int" ]
            (List.map Path.name (Pat.type_refs (type_decl_of "wrap"))));
      test "a declaration without references yields nothing" (fun () ->
          equal (list string) []
            (List.map Path.name (Pat.type_refs (type_decl_of "fake"))));
    ]

let reference_tests =
  group "of_ref and reference"
    [
      test "of_ref is total over parsed references" (fun () ->
          let of_ref s =
            match Litany.Naming.Ref.of_string s with
            | Ok r -> Pat.of_ref r
            | Error e ->
                failf "%S did not parse: %a" s Litany.Naming.Ref.pp_error e
          in
          equal ~msg:"a value reference is ident's relation" int 2
            (count (of_ref "Stdlib.List.length"));
          equal ~msg:"a unit reference is the from_unit boundary" int 4
            (count (of_ref "Stdlib__List"));
          equal ~msg:"a dotted module path hops the alias to its unit" int 4
            (count (of_ref "Stdlib.List")));
      test "reference is sugar over the same pair" (fun () ->
          (match Pat.reference "Stdlib.List.length" with
          | Ok p -> equal int 2 (count p)
          | Error m -> failf "refused: %s" m);
          (match Pat.reference "Stdlib.List" with
          | Ok p -> equal int 4 (count p)
          | Error m -> failf "refused: %s" m);
          match Pat.reference "Rd..Internal" with
          | Ok _ -> fail "parsed"
          | Error m -> contains ~sub:"malformed module path" m);
    ]

let registry_tests =
  group "registry"
    [
      test "literal combinators record their names, per namespace" (fun () ->
          ignore (Pat.ident "Stdlib.List.length");
          ignore (Pat.ident "Stdlib.List.length");
          ignore (Pat.idents [ "Stdlib.min"; "Stdlib.(@)" ]);
          ignore (Pat.typ "Stdlib.result");
          let values =
            List.map Litany.Naming.Name.to_string (Pat.Registry.names ())
          in
          let types =
            List.map Litany.Naming.Name.to_string (Pat.Registry.type_names ())
          in
          is_true ~msg:"ident records" (List.mem "Stdlib.List.length" values);
          is_true ~msg:"idents records every arm"
            (List.mem "Stdlib.min" values && List.mem "Stdlib.(@)" values);
          equal ~msg:"deduplicated by rendering" int 1
            (List.length
               (List.filter (String.equal "Stdlib.List.length") values));
          is_true ~msg:"typ records into the type namespace"
            (List.mem "Stdlib.result" types);
          is_false ~msg:"namespaces stay apart"
            (List.mem "Stdlib.result" values));
      test "reference-built patterns are configuration, not literals" (fun () ->
          (match Pat.reference "Cfg_only.leaf_value" with
          | Ok _ -> ()
          | Error m -> failf "refused: %s" m);
          is_false
            (List.mem "Cfg_only.leaf_value"
               (List.map Litany.Naming.Name.to_string (Pat.Registry.names ()))));
    ]

let () =
  Windtrap.run "litany_pat"
    [
      ident_tests;
      apply_tests;
      apply_list_tests;
      typ_tests;
      bound_var_tests;
      constant_tests;
      alternation_tests;
      payload_tests;
      views_generic;
      views_expr;
      views_params_cases;
      views_patterns;
      views_queries;
      views_kinds;
      query_type_refs;
      reference_tests;
      registry_tests;
    ]
