(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* The engine against real compiled fixtures under fixtures/: fix_engine
   (plain Direct units with known byte offsets) and fix_nope (an editable
   source that does not parse, compiled through a sed preprocessor — the
   Derived, degraded lane). Test rules are constructed inline; the emit
   contract is exercised by fabricating locations. *)

open Windtrap
module Engine = Litany.Engine
module Report = Litany.Engine.Report
module Rule = Litany.Rule
module Finding = Litany.Finding
module Entry = Litany.Roster.Entry
module Source = Litany.Source
module Span = Litany.Span

let plain_objs = "fixtures/engine/plain/.fix_engine.objs/byte"
let a_source = "fixtures/engine/plain/emit_a.ml"
let a_cmt = plain_objs ^ "/fix_engine__Emit_a.cmt"
let b_source = "fixtures/engine/plain/emit_b.ml"
let b_cmt = plain_objs ^ "/fix_engine__Emit_b.cmt"
let attr_source = "fixtures/engine/plain/attr.ml"
let attr_cmt = plain_objs ^ "/fix_engine__Attr.cmt"
let nope_source = "fixtures/engine/nope/wit_nope.ml"
let nope_cmt = "fixtures/engine/nope/.fix_nope.objs/byte/fix_nope__Wit_nope.cmt"
let nope_pp = "fixtures/engine/nope/wit_nope.pp.ml"
let entry_a () = Entry.v ~source:a_source ~cmt:a_cmt ()
let entry_b () = Entry.v ~source:b_source ~cmt:b_cmt ()
let entry_attr () = Entry.v ~source:attr_source ~cmt:attr_cmt ()

let entry_nope () =
  Entry.v ~source:nope_source ~cmt:nope_cmt ~preprocessed_source:nope_pp ()

(* An entry whose artifact does not exist: a [Missing_artifact] skip. *)
let entry_missing () =
  Entry.v ~source:"fixtures/engine/plain/missing.ml"
    ~cmt:"fixtures/engine/plain/missing.cmt" ()

let allow_objs = "fixtures/engine/allow/.fix_allow.objs/byte"
let alw_source = "fixtures/engine/allow/alw.ml"
let own_source = "fixtures/engine/allow/own.ml"
let flo_source = "fixtures/engine/allow/flo.ml"
let nst_source = "fixtures/engine/allow/nst.ml"
let ali_source = "fixtures/engine/allow/ali.ml"
let srx_source = "fixtures/engine/allow/srx.ml"

let allow_entry name =
  let base = Filename.remove_extension (Filename.basename name) in
  Entry.v ~source:name
    ~cmt:(allow_objs ^ "/fix_allow__" ^ String.capitalize_ascii base ^ ".cmt")
    ()

let resolver = lazy (Litany.Naming.Resolver.create ~cmi_dirs:[ plain_objs ])

let load entry =
  Litany.Unit.load ~resolver:(Lazy.force resolver) ~build_current:true entry

let run ?catalog ?keep ?(rules = []) entries =
  Engine.run ?keep ~rules
    ~catalog:(Option.value catalog ~default:rules)
    ~roster:(Litany.Roster.v entries) ~load ()

(* [where path sub] is the (start, stop) byte offsets of the first occurrence
   of [sub] in the fixture at [path] — assertions never hand-count bytes. *)
let where path sub =
  let s = In_channel.with_open_bin path In_channel.input_all in
  let n = String.length s and m = String.length sub in
  let rec at i =
    if i + m > n then failf "%S does not occur in %s" sub path
    else if String.sub s i m = sub then i
    else at (i + 1)
  in
  let start = at 0 in
  (start, start + m)

(* The engine's degradation note, asserted verbatim. *)
let degraded_note =
  "editable source does not parse \xe2\x80\x94 attribute rules, attribute \
   suppression, and corroboration unavailable"

let meta ?(group = Rule.Suspicious) ?(fix = Rule.Never) ?renamed_from name =
  Rule.meta ~name ?renamed_from ~group ~since:"1.0" ~fix ~summary:"test rule"
    ~doc:"test rule" ()

(* [flag_int] fires at every integer constant of the typedtree — offsets are
   known per fixture. *)
let flag_int ?group ?(name = "flag-int") () =
  Rule.expr (meta ?group name) (fun _ e ->
      match e.Typedtree.exp_desc with
      | Typedtree.Texp_constant (Asttypes.Const_int _) ->
          [ Finding.v ~loc:e.exp_loc "int constant" ]
      | _ -> [])

let flag_string ?(name = "flag-string") () =
  Rule.expr (meta name) (fun _ e ->
      match e.Typedtree.exp_desc with
      | Typedtree.Texp_constant (Asttypes.Const_string _) ->
          [ Finding.v ~loc:e.exp_loc "string constant" ]
      | _ -> [])

(* [on_41 name mk] fires [mk] exactly once per fixture unit — at the integer
   constant [41] — so fabricated-location tests emit a single finding. *)
let on_41 name mk =
  Rule.expr (meta name) (fun u e ->
      match e.Typedtree.exp_desc with
      | Typedtree.Texp_constant (Asttypes.Const_int 41) -> mk u e
      | _ -> [])

let pos fname lnum bol cnum =
  { Lexing.pos_fname = fname; pos_lnum = lnum; pos_bol = bol; pos_cnum = cnum }

(* (rule, path, start, stop) per finding, in report order — the shape most
   assertions compare. *)
let shape rep =
  List.map
    (fun (rule, f) ->
      let l = Finding.loc f in
      ( rule,
        l.Location.loc_start.pos_fname,
        l.Location.loc_start.pos_cnum,
        l.Location.loc_end.pos_cnum ))
    (Report.findings rep)

let shape_t = list (quad string string int int)

let messages rep =
  List.map (fun (_, f) -> Finding.message f) (Report.findings rep)

let outcome_pp ppf (o : Report.outcome) =
  match o with
  | Report.Linted -> Format.pp_print_string ppf "linted"
  | Report.Facts_only -> Format.pp_print_string ppf "facts-only"
  | Report.Skipped sk ->
      Format.fprintf ppf "skipped (%a)" Litany.Unit.Skip.pp sk

let outcome_t =
  Testable.make ~pp:outcome_pp ~equal:(fun (a : Report.outcome) b -> a = b)

let units_t = list (pair string outcome_t)

let dispatch_tests =
  group "dispatch"
    [
      test "expr rules see every typed expression of interest" (fun () ->
          let rep = run ~rules:[ flag_int () ] [ entry_a () ] in
          equal shape_t
            [ ("flag-int", a_source, 13, 15); ("flag-int", a_source, 18, 19) ]
            (shape rep));
      test "pattern rules see value patterns" (fun () ->
          let count = ref 0 in
          let r =
            Rule.pattern (meta "pat-count") (fun _ p ->
                (match p.Typedtree.pat_desc with
                | Typedtree.Tpat_var _ -> incr count
                | _ -> ());
                [])
          in
          let _ = run ~rules:[ r ] [ entry_a () ] in
          (* answer, double, x *)
          equal int 3 !count);
      test "binding rules see value bindings" (fun () ->
          let rep =
            run
              ~rules:
                [
                  Rule.binding (meta "bind") (fun _ vb ->
                      [ Finding.v ~loc:vb.Typedtree.vb_pat.pat_loc "binding" ]);
                ]
              [ entry_a () ]
          in
          equal shape_t
            [ ("bind", a_source, 4, 10); ("bind", a_source, 24, 30) ]
            (shape rep));
      test "attribute rules see node and floating attributes" (fun () ->
          let rep =
            run
              ~rules:
                [
                  Rule.attribute (meta "attrs") (fun _ a ->
                      [
                        Finding.v ~loc:a.Parsetree.attr_loc
                          a.Parsetree.attr_name.txt;
                      ]);
                ]
              [ entry_attr () ]
          in
          equal (list string)
            [ "inline"; "fixture.node"; "fixture.mark" ]
            (messages rep));
      test "source rules run once per unit and skip corroboration" (fun () ->
          let calls = ref [] in
          let r =
            Rule.source (meta "text") (fun src ->
                calls := Source.path src :: !calls;
                match Source.location src (Span.v ~start:0 ~stop:3) with
                | Some loc -> [ Finding.v ~loc "leading let" ]
                | None -> [])
          in
          let rep = run ~rules:[ r ] [ entry_a (); entry_b () ] in
          equal (list string) [ a_source; b_source ] (List.rev !calls);
          (* [0;3) is no parse-node span; text findings are kept anyway. *)
          equal shape_t
            [ ("text", a_source, 0, 3); ("text", b_source, 0, 3) ]
            (shape rep);
          equal int 0 (Report.dropped rep));
      test "source rules run over the paired interface source too" (fun () ->
          (* The interface text lane's pinned case: a 14-byte mli with a
             trailing tab and no final LF. Findings
             anchor in the interface file, unrewritten, and drop nothing. *)
          let ipath = Filename.temp_file "litany-engine-test" ".mli" in
          Out_channel.with_open_bin ipath (fun oc ->
              Out_channel.output_string oc "val eof : int\t");
          Fun.protect
            ~finally:(fun () -> Sys.remove ipath)
            (fun () ->
              let calls = ref [] in
              let r =
                Rule.source (meta "text") (fun src ->
                    calls := Source.path src :: !calls;
                    let len = Source.length src in
                    let bytes = Source.contents src in
                    if len > 0 && bytes.[len - 1] <> '\n' then
                      match
                        Source.location src (Span.v ~start:len ~stop:len)
                      with
                      | Some loc -> [ Finding.v ~loc "no final newline" ]
                      | None -> []
                    else [])
              in
              let entry =
                Entry.v ~source:a_source ~cmt:a_cmt ~interface_source:ipath ()
              in
              let rep = run ~rules:[ r ] [ entry ] in
              equal (list string) [ a_source; ipath ] (List.rev !calls);
              equal shape_t [ ("text", ipath, 14, 14) ] (shape rep);
              equal int 0 (Report.dropped rep)));
    ]

(* The engine-kinds package: [type_decl], [let_group], [module_binding]
   against a fixture with groups at every dispatch position. Expected
   shapes are in report order (byte offsets), not dispatch order. *)
let kinds_source = "fixtures/engine/plain/kinds.ml"
let kinds_cmt = plain_objs ^ "/fix_engine__Kinds.cmt"
let entry_kinds () = Entry.v ~source:kinds_source ~cmt:kinds_cmt ()
let start_of path sub = fst (where path sub)

let flag_name = function
  | Asttypes.Recursive -> "rec"
  | Asttypes.Nonrecursive -> "nonrec"

let kinds_tests =
  group "engine kinds"
    [
      test "type_decl sees every group's declarations in source order"
        (fun () ->
          let r =
            Rule.type_decl (meta "td") (fun _ ds ->
                let names =
                  List.map
                    (fun (d : Typedtree.type_declaration) -> d.typ_name.txt)
                    ds
                in
                [
                  Finding.v ~loc:(List.hd ds).Typedtree.typ_name.loc
                    (String.concat "," names);
                ])
          in
          let rep = run ~rules:[ r ] [ entry_kinds () ] in
          (* Anchors ascend in source order, so report order is group
             order: root groups first, then the nested structure's. *)
          equal (list string)
            [ "single"; "alias"; "t1,t2"; "nested" ]
            (messages rep));
      test "let_group sees structure- and expression-level groups" (fun () ->
          let r =
            Rule.let_group (meta "lg") (fun _ ~loc rf vbs ->
                [
                  Finding.v ~loc
                    (Printf.sprintf "%s:%d" (flag_name rf) (List.length vbs));
                ])
          in
          let rep = run ~rules:[ r ] [ entry_kinds () ] in
          let at sub = start_of kinds_source sub in
          equal
            (list (pair int string))
            [
              (at "let uses_single", "nonrec:1");
              (at "let of_alias", "nonrec:1");
              (at "let build", "nonrec:1");
              (at "let rec fib", "rec:1");
              (at "let pair_a", "nonrec:2");
              (at "let inner", "nonrec:1");
              (at "let local_groups", "nonrec:1");
              (at "let x = 5", "nonrec:1");
              (at "let rec loop", "rec:1");
            ]
            (List.map
               (fun (_, f) ->
                 ((Finding.loc f).Location.loc_start.pos_cnum, Finding.message f))
               (Report.findings rep)));
      test "module_binding sees toplevel, nested, anonymous, and local"
        (fun () ->
          let r =
            Rule.module_binding (meta "mb") (fun _ mb ->
                let module MB = Rule.Module_binding in
                [
                  Finding.v ~loc:(MB.name_loc mb)
                    (Printf.sprintf "%s:%s"
                       (match MB.id mb with
                       | Some i -> Ident.name i
                       | None -> "_")
                       (match MB.position mb with
                       | MB.Toplevel -> "top"
                       | MB.Nested -> "nested"
                       | MB.Local -> "local"));
                ])
          in
          let rep = run ~rules:[ r ] [ entry_kinds () ] in
          equal (list string)
            [ "M:top"; "Deep:nested"; "_:top"; "L:local" ]
            (messages rep));
      test "module_binding whole-binding loc spans the item" (fun () ->
          let r =
            Rule.module_binding (meta "mb-loc") (fun _ mb ->
                let module MB = Rule.Module_binding in
                match MB.id mb with
                | Some i when Ident.name i = "M" ->
                    [ Finding.v ~loc:(MB.loc mb) "whole" ]
                | _ -> [])
          in
          let rep = run ~rules:[ r ] [ entry_kinds () ] in
          equal
            (list (pair int string))
            [ (start_of kinds_source "module M", "whole") ]
            (List.map
               (fun (_, f) ->
                 ((Finding.loc f).Location.loc_start.pos_cnum, Finding.message f))
               (Report.findings rep)));
      test "kind gates: a unit without matching nodes dispatches nothing"
        (fun () ->
          let calls = ref 0 in
          let r =
            Rule.type_decl (meta "td-none") (fun _ _ ->
                incr calls;
                [])
          in
          let rep = run ~rules:[ r ] [ entry_a () ] in
          equal int 0 !calls;
          equal shape_t [] (shape rep));
      test "export dispatches every row of the export index" (fun () ->
          (* The probe anchors every finding at the first structure item
             (a real span, so the emit contract keeps it) and encodes the
             dispatched row as its message; same rule and location, so the
             report's total order sorts by message. *)
          let r =
            Rule.export (meta "exp") (fun u x ->
                let anchor =
                  (List.hd (Litany.Unit.implementation u).Typedtree.str_items)
                    .Typedtree.str_loc
                in
                let k =
                  match Litany.Unit.Export.kind x with
                  | Litany.Unit.Export.Value -> "value"
                  | Litany.Unit.Export.Type -> "type"
                  | Litany.Unit.Export.Module -> "module"
                  | Litany.Unit.Export.Exception -> "exception"
                in
                [ Finding.v ~loc:anchor (k ^ ":" ^ Litany.Unit.Export.name x) ])
          in
          let rep = run ~rules:[ r ] [ entry_kinds () ] in
          equal (list string)
            [
              "exception:Kaboom";
              "exception:M.Inner_boom";
              "module:M";
              "module:M.Deep";
              "type:M.nested";
              "type:alias";
              "type:single";
              "type:t1";
              "type:t2";
              "value:M.inner";
              "value:build";
              "value:fib";
              "value:local_groups";
              "value:of_alias";
              "value:pair_a";
              "value:pair_b";
              "value:uses_single";
            ]
            (messages rep));
    ]

let emit_contract_tests =
  group "emit contract"
    [
      test "ghost locations are dropped and counted" (fun () ->
          let r =
            on_41 "ghostly" (fun _ e ->
                [
                  Finding.v
                    ~loc:{ e.Typedtree.exp_loc with loc_ghost = true }
                    "ghost";
                ])
          in
          let rep = run ~rules:[ r ] [ entry_a () ] in
          equal shape_t [] (shape rep);
          equal int 1 (Report.dropped rep));
      test "locations outside the unit's file are dropped" (fun () ->
          let r =
            on_41 "elsewhere" (fun _ _ ->
                let loc =
                  {
                    Location.loc_start = pos "elsewhere.ml" 1 0 0;
                    loc_end = pos "elsewhere.ml" 1 0 3;
                    loc_ghost = false;
                  }
                in
                [ Finding.v ~loc "not ours" ])
          in
          let rep = run ~rules:[ r ] [ entry_a () ] in
          equal shape_t [] (shape rep);
          equal int 1 (Report.dropped rep));
      test "typed findings must match a pre-PPX node span" (fun () ->
          (* [0;2) is consistent and owned but no node of the parse. *)
          let r =
            on_41 "fabricated" (fun u _ ->
                let src = Litany.Unit.source u in
                match Source.location src (Span.v ~start:0 ~stop:2) with
                | Some loc -> [ Finding.v ~loc "fabricated" ]
                | None -> [])
          in
          let rep = run ~rules:[ r; flag_int () ] [ entry_a () ] in
          equal shape_t
            [ ("flag-int", a_source, 13, 15); ("flag-int", a_source, 18, 19) ]
            (shape rep);
          equal int 1 (Report.dropped rep));
      test "corroboration is span membership, not node identity" (fun () ->
          (* A typed finding anchored at a different real node's span — here
             the enclosing [41 + 1] — passes (d): the guarantee is that a
             finding can only anchor at a span that existed in the editable
             source, not that generated nodes cannot produce diagnostics
             (a PPX copying a whole user span onto generated code still
             surfaces, at that user span). *)
          let r =
            on_41 "elsewhere-span" (fun u _ ->
                let src = Litany.Unit.source u in
                match Source.location src (Span.v ~start:13 ~stop:19) with
                | Some loc -> [ Finding.v ~loc "anchored at the sum" ]
                | None -> [])
          in
          let rep = run ~rules:[ r ] [ entry_a () ] in
          equal shape_t [ ("elsewhere-span", a_source, 13, 19) ] (shape rep);
          equal int 0 (Report.dropped rep));
      test "ownership is by basename: same-basename foreign dirs are owned"
        (fun () ->
          (* Documented limit of (b): recorded names may not be filesystem
             paths, so they are compared by basename — a same-basename file
             in another directory is indistinguishable, owned, and
             rewritten to the unit's path. *)
          let r =
            on_41 "foreign-dir" (fun _ e ->
                let redir (p : Lexing.position) =
                  { p with pos_fname = "elsewhere/emit_a.ml" }
                in
                let loc =
                  {
                    e.Typedtree.exp_loc with
                    loc_start = redir e.exp_loc.loc_start;
                    loc_end = redir e.exp_loc.loc_end;
                  }
                in
                [ Finding.v ~loc "foreign directory, same basename" ])
          in
          let rep = run ~rules:[ r ] [ entry_a () ] in
          equal shape_t [ ("foreign-dir", a_source, 13, 15) ] (shape rep);
          equal int 0 (Report.dropped rep));
      test "offset-inconsistent findings are kept, not dropped" (fun () ->
          let r =
            on_41 "bad-offsets" (fun u _ ->
                let path = Litany.Unit.path u in
                let loc =
                  {
                    Location.loc_start = pos path 1 0 100;
                    loc_end = pos path 1 0 100;
                    loc_ghost = false;
                  }
                in
                [ Finding.v ~loc "line-anchored" ])
          in
          let rep = run ~rules:[ r ] [ entry_a () ] in
          equal shape_t [ ("bad-offsets", a_source, 100, 100) ] (shape rep);
          equal int 0 (Report.dropped rep));
      test "duplicate (rule, loc, message) findings collapse" (fun () ->
          let r =
            on_41 "dup" (fun _ e ->
                let f = Finding.v ~loc:e.Typedtree.exp_loc "twice" in
                [ f; f ])
          in
          let rep = run ~rules:[ r ] [ entry_a () ] in
          equal shape_t [ ("dup", a_source, 13, 15) ] (shape rep);
          (* deduplication is not a drop *)
          equal int 0 (Report.dropped rep));
      test "kept locations are rewritten to the adapter path" (fun () ->
          let recorded = ref "" in
          let r =
            on_41 "recorder" (fun _ e ->
                recorded := e.Typedtree.exp_loc.Location.loc_start.pos_fname;
                [ Finding.v ~loc:e.exp_loc "int" ])
          in
          let rep = run ~rules:[ r ] [ entry_a () ] in
          (* The compiler recorded its own invocation path... *)
          is_false (String.equal !recorded a_source);
          (* ...and the report carries only the adapter-supplied one. *)
          equal shape_t [ ("recorder", a_source, 13, 15) ] (shape rep));
    ]

let degraded_tests =
  group "degraded units"
    [
      test "typed findings on a non-parsing source are kept, noted" (fun () ->
          let rep = run ~rules:[ flag_int () ] [ entry_nope () ] in
          equal shape_t
            [
              ("flag-int", nope_source, 12, 14);
              ("flag-int", nope_source, 17, 18);
            ]
            (shape rep);
          equal int 0 (Report.dropped rep);
          equal
            (list (pair string string))
            [ (nope_source, degraded_note) ]
            (Report.degraded rep));
      test "no findings, no demand: the unit is not marked degraded" (fun () ->
          let rep = run ~rules:[ flag_string () ] [ entry_nope () ] in
          equal shape_t [] (shape rep);
          equal (list (pair string string)) [] (Report.degraded rep));
      test "a names-less attribute rule demands the parse, notes its absence"
        (fun () ->
          let calls = ref 0 in
          let r =
            Rule.attribute (meta "attr") (fun _ _ ->
                incr calls;
                [])
          in
          let rep = run ~rules:[ r ] [ entry_nope () ] in
          equal int 0 !calls;
          equal
            (list (pair string string))
            [ (nope_source, degraded_note) ]
            (Report.degraded rep));
      test "declared attribute names gate the parse demand" (fun () ->
          (* wit_nope.ml spells no [@ at all: a names-declared attribute
             rule demands no parse there — no dispatch and no degradation
             note, although the source does not parse. *)
          let calls = ref 0 in
          let r =
            Rule.attribute ~names:[ "warning" ] (meta "gated") (fun _ _ ->
                incr calls;
                [])
          in
          let rep = run ~rules:[ r ] [ entry_nope () ] in
          equal int 0 !calls;
          equal (list (pair string string)) [] (Report.degraded rep));
      test "a spelled declared name demands the parse and dispatches" (fun () ->
          let seen = ref [] in
          let r =
            Rule.attribute ~names:[ "fixture.mark" ] (meta "marked")
              (fun _ (a : Parsetree.attribute) ->
                if String.equal a.attr_name.txt "fixture.mark" then
                  seen := a.attr_name.txt :: !seen;
                [])
          in
          let _ = run ~rules:[ r ] [ entry_attr () ] in
          equal (list string) [ "fixture.mark" ] !seen);
      test "an attribute rule declaring no names keeps the full demand"
        (fun () ->
          let r = Rule.attribute (meta "all-attrs") (fun _ _ -> []) in
          let rep = run ~rules:[ r ] [ entry_nope () ] in
          equal
            (list (pair string string))
            [ (nope_source, degraded_note) ]
            (Report.degraded rep));
    ]

let ordering_tests =
  group "total order"
    [
      test "findings sort by (path, start, rule, end, message)" (fun () ->
          let rep =
            run
              ~rules:
                [ flag_int (); flag_int ~name:"also-int" (); flag_string () ]
              [ entry_b (); entry_a () ]
          in
          equal shape_t
            [
              ("also-int", a_source, 13, 15);
              ("flag-int", a_source, 13, 15);
              ("also-int", a_source, 18, 19);
              ("flag-int", a_source, 18, 19);
              ("flag-string", b_source, 15, 22);
            ]
            (shape rep));
    ]

let failure_tests =
  group "rule failure isolation"
    [
      test "a raising rule fails on that unit only, exit 3" (fun () ->
          let bomb =
            Rule.expr (meta "bomb") (fun _ e ->
                match e.Typedtree.exp_desc with
                | Typedtree.Texp_constant (Asttypes.Const_int 41) ->
                    [ Finding.v ~loc:e.exp_loc "before boom" ]
                | Typedtree.Texp_constant (Asttypes.Const_int 1) ->
                    failwith "boom"
                | _ -> [])
          in
          let rep =
            run ~rules:[ bomb; flag_int () ] [ entry_a (); entry_b () ]
          in
          (* The failed rule's findings on that unit are discarded; the
             other rule and the other unit complete. *)
          equal shape_t
            [ ("flag-int", a_source, 13, 15); ("flag-int", a_source, 18, 19) ]
            (shape rep);
          (match Report.failures rep with
          | [ { Report.rule; unit_path; message } ] ->
              equal string "bomb" rule;
              equal string a_source unit_path;
              contains ~sub:"boom" message
          | fs -> failf "expected one failure, got %d" (List.length fs));
          equal int 3 (Report.exit_code rep));
      test "duplicate rule names are refused before any load" (fun () ->
          let loads = ref 0 in
          let load entry =
            incr loads;
            load entry
          in
          raises_match
            (function Invalid_argument _ -> true | _ -> false)
            (fun () ->
              Engine.run
                ~rules:[ flag_int (); flag_int () ]
                ~catalog:[]
                ~roster:(Litany.Roster.v [ entry_a () ])
                ~load ());
          equal int 0 !loads);
    ]

(* (rule, start, stop, reason) per suppressed finding, in report order. *)
let suppressed_shape rep =
  List.map
    (fun (rule, f, reason) ->
      let l = Finding.loc f in
      (rule, l.Location.loc_start.pos_cnum, l.Location.loc_end.pos_cnum, reason))
    (Report.suppressed rep)

let suppressed_t = list (quad string int int string)

let suppression_tests =
  group "suppression"
    [
      test "allow and a fulfilled expect hide; stale directives audit"
        (fun () ->
          let rep = run ~rules:[ flag_int () ] [ allow_entry alw_source ] in
          let unused =
            where alw_source {|[@litany.allow "flag-int: nothing to see"]|}
          in
          let unfulfilled =
            where alw_source {|[@litany.expect "flag-int: silent"]|}
          in
          equal shape_t
            [
              ( "flag-int",
                alw_source,
                fst (where alw_source "42"),
                snd (where alw_source "42") );
              ("unused-allow", alw_source, fst unused, snd unused);
              ( "unfulfilled-expect",
                alw_source,
                fst unfulfilled,
                snd unfulfilled );
            ]
            (shape rep);
          equal (list string)
            [
              "int constant";
              "allow \"flag-int\" matched no finding";
              "expect \"flag-int\" matched no finding";
            ]
            (messages rep);
          (* The typedtree's span for a parenthesized expression includes
             the parens and the attribute — the finding anchors there. *)
          let a41 =
            {|(41 [@litany.allow "flag-int: identity is the point"])|}
          in
          let d43 = {|(43 [@litany.expect "flag-int: fires"])|} in
          equal suppressed_t
            [
              ( "flag-int",
                fst (where alw_source a41),
                snd (where alw_source a41),
                "identity is the point" );
              ( "flag-int",
                fst (where alw_source d43),
                snd (where alw_source d43),
                "fires" );
            ]
            (suppressed_shape rep);
          equal int 1 (Report.exit_code rep));
      test "audit findings render as warnings" (fun () ->
          let rep = run ~rules:[ flag_int () ] [ allow_entry alw_source ] in
          Report.iter_findings rep (fun ~rule:_ ~severity _ ->
              is_true (severity = Rule.Severity.Warning)));
      test "audits are gated off when the rule is known but unselected"
        (fun () ->
          let rep =
            run ~catalog:[ flag_int () ] ~rules:[] [ allow_entry alw_source ]
          in
          equal shape_t [] (shape rep);
          equal suppressed_t [] (suppressed_shape rep);
          equal int 0 (Report.exit_code rep));
      test "an unselected catalog text rule's directive still audits" (fun () ->
          (* A text-rule directive can never match under any selection —
             config-suppressed only — so it is a syntactic fact, audited
             from the catalog even when the rule is unselected. *)
          let text = Rule.source (meta "flag-text") (fun _ -> []) in
          let rep =
            run ~catalog:[ text ] ~rules:[] [ allow_entry srx_source ]
          in
          equal (list string)
            [ "text rule \"flag-text\" is not attribute-suppressible" ]
            (messages rep);
          equal int 1 (Report.exit_code rep));
      test "an unselected rule's alias directive still notes the rename"
        (fun () ->
          (* Known-but-unselected withholds the audit, not the rename note:
             the attribute needs updating regardless of selection. *)
          let aliased =
            Rule.expr (meta ~renamed_from:[ "old-flag-int" ] "flag-int")
              (fun _ _ -> [])
          in
          let rep =
            run ~catalog:[ aliased ] ~rules:[] [ allow_entry ali_source ]
          in
          equal shape_t [] (shape rep);
          equal
            (list (pair string string))
            [
              ( ali_source,
                "suppression attribute names \"old-flag-int\"; the rule is now \
                 \"flag-int\" \xe2\x80\x94 update the attribute" );
            ]
            (Report.notes rep);
          equal int 0 (Report.exit_code rep));
      test "under the default catalog an unselected rule reads as unknown"
        (fun () ->
          let rep = run ~rules:[] [ allow_entry alw_source ] in
          equal (list string)
            [
              "unknown rule \"flag-int\"";
              "unknown rule \"flag-int\"";
              "unknown rule \"flag-int\"";
              "unknown rule \"flag-int\"";
            ]
            (messages rep));
      test
        "engine-owned, malformed, and unknown directives audit unconditionally"
        (fun () ->
          let rep = run ~rules:[ flag_int () ] [ allow_entry own_source ] in
          (* The four findings survive — no valid directive covers them —
             and each broken directive audits at its attribute, including
             the allow naming the auditor itself: nothing suppresses the
             audit rules. *)
          equal (list string)
            [
              "int constant";
              "\"unused-allow\" is engine-owned and cannot be suppressed";
              "int constant";
              "malformed allow payload \xe2\x80\x94 missing \":\" (expected \
               \"rule-name: reason\")";
              "int constant";
              "unknown attribute \"litany.alow\" (did you mean \
               \"litany.allow\"?)";
              "int constant";
              "unknown rule \"flag-itn\" (did you mean \"flag-int\"?)";
            ]
            (messages rep));
      test "no rule may take an engine-owned audit name" (fun () ->
          raises_match
            (function Invalid_argument _ -> true | _ -> false)
            (fun () ->
              run ~rules:[ flag_int ~name:"unused-allow" () ] [] |> ignore);
          raises_match
            (function Invalid_argument _ -> true | _ -> false)
            (fun () ->
              run
                ~catalog:[ flag_int ~name:"unfulfilled-expect" () ]
                ~rules:[] []
              |> ignore));
      test "a floating directive covers the rest of the file" (fun () ->
          let rep = run ~rules:[ flag_int () ] [ allow_entry flo_source ] in
          equal shape_t
            [
              ( "flag-int",
                flo_source,
                fst (where flo_source "41"),
                snd (where flo_source "41") );
            ]
            (shape rep);
          equal suppressed_t
            [
              ( "flag-int",
                fst (where flo_source "42"),
                snd (where flo_source "42"),
                "below this line" );
              ( "flag-int",
                fst (where flo_source "43"),
                snd (where flo_source "43"),
                "below this line" );
            ]
            (suppressed_shape rep));
      test "the innermost directive wins and the loser audits" (fun () ->
          let rep = run ~rules:[ flag_int () ] [ allow_entry nst_source ] in
          let outer = where nst_source {|[@@litany.allow "flag-int: outer"]|} in
          equal shape_t
            [ ("unused-allow", nst_source, fst outer, snd outer) ]
            (shape rep);
          let inner = {|(41 [@litany.allow "flag-int: inner"])|} in
          equal suppressed_t
            [
              ( "flag-int",
                fst (where nst_source inner),
                snd (where nst_source inner),
                "inner" );
              ( "flag-int",
                fst (where nst_source "42"),
                snd (where nst_source "42"),
                "item" );
            ]
            (suppressed_shape rep));
      test "a tombstone alias matches with a rename note" (fun () ->
          let aliased =
            Rule.expr (meta ~renamed_from:[ "old-flag-int" ] "flag-int")
              (fun _ e ->
                match e.Typedtree.exp_desc with
                | Typedtree.Texp_constant (Asttypes.Const_int _) ->
                    [ Finding.v ~loc:e.exp_loc "int constant" ]
                | _ -> [])
          in
          let rep = run ~rules:[ aliased ] [ allow_entry ali_source ] in
          equal shape_t [] (shape rep);
          let a41 = {|(41 [@litany.allow "old-flag-int: renamed alias"])|} in
          equal suppressed_t
            [
              ( "flag-int",
                fst (where ali_source a41),
                snd (where ali_source a41),
                "renamed alias" );
            ]
            (suppressed_shape rep);
          equal
            (list (pair string string))
            [
              ( ali_source,
                "suppression attribute names \"old-flag-int\"; the rule is now \
                 \"flag-int\" \xe2\x80\x94 update the attribute" );
            ]
            (Report.notes rep);
          equal int 0 (Report.exit_code rep));
      test "text-rule findings are never attribute-suppressed" (fun () ->
          let text =
            Rule.source (meta "flag-text") (fun src ->
                match Source.location src (Span.v ~start:0 ~stop:3) with
                | Some loc -> [ Finding.v ~loc "text finding" ]
                | None -> [])
          in
          let rep = run ~rules:[ text ] [ allow_entry srx_source ] in
          equal (list string)
            [
              "text finding";
              "text rule \"flag-text\" is not attribute-suppressible";
            ]
            (messages rep);
          equal suppressed_t [] (suppressed_shape rep));
      test "an offset-inconsistent finding is not suppressed by its offsets"
        (fun () ->
          (* The finding's cnums sit inside the a41 allow's scope, but its
             mangled line makes it offset-inconsistent: the emit contract
             keeps it line-anchored, so suppression must not trust the same
             offsets it distrusts — the finding survives and every directive
             audits instead of one silently claiming it. *)
          let r =
            on_41 "flag-int" (fun _ e ->
                let l = e.Typedtree.exp_loc in
                let loc =
                  {
                    l with
                    Location.loc_start =
                      { l.Location.loc_start with pos_lnum = 999 };
                  }
                in
                [ Finding.v ~loc "mangled" ])
          in
          let rep = run ~rules:[ r ] [ allow_entry alw_source ] in
          equal suppressed_t [] (suppressed_shape rep);
          equal (list string)
            [
              "mangled";
              "allow \"flag-int\" matched no finding";
              "allow \"flag-int\" matched no finding";
              "expect \"flag-int\" matched no finding";
              "expect \"flag-int\" matched no finding";
            ]
            (messages rep);
          equal int 1 (Report.exit_code rep));
      test "a failed rule's directives audit nothing on that unit" (fun () ->
          let bomb = Rule.expr (meta "flag-int") (fun _ _ -> failwith "boom") in
          let rep = run ~rules:[ bomb ] [ allow_entry alw_source ] in
          equal shape_t [] (shape rep);
          equal suppressed_t [] (suppressed_shape rep);
          (match Report.failures rep with
          | [ { Report.rule; _ } ] -> equal string "flag-int" rule
          | fs -> failf "expected one failure, got %d" (List.length fs));
          equal int 3 (Report.exit_code rep));
      test "a skipped unit's directives audit nothing" (fun () ->
          let rep =
            run
              ~rules:[ flag_int () ]
              [
                Entry.v ~source:alw_source
                  ~cmt:"fixtures/engine/allow/missing.cmt" ();
              ]
          in
          equal shape_t [] (shape rep);
          equal int 0 (Report.exit_code rep));
      test "suppressed findings keep the total order across units" (fun () ->
          let rep =
            run
              ~rules:[ flag_int () ]
              [ allow_entry flo_source; allow_entry alw_source ]
          in
          equal (list string)
            [ alw_source; alw_source; flo_source; flo_source ]
            (List.map
               (fun (_, f, _) -> (Finding.loc f).Location.loc_start.pos_fname)
               (Report.suppressed rep)));
    ]

(* {1 Fix channel: audit fixes and the expected subset} *)

let fix_channel_tests =
  group "fix channel"
    [
      test "a stale allow's audit carries the safe deletion fix" (fun () ->
          let rep = run ~rules:[ flag_int () ] [ allow_entry alw_source ] in
          let audit =
            List.find (fun (r, _) -> r = "unused-allow") (Report.findings rep)
          in
          match Finding.fix (snd audit) with
          | None -> failf "unused-allow shipped no fix"
          | Some fx ->
              is_true ~msg:"safe" (Litany.Fix.applicability fx = Litany.Fix.Safe);
              equal string "delete the unused allow" (Litany.Fix.title fx);
              (* One deletion edit: the attribute span widened over the
                 blank before it — editable-source coordinates. *)
              let start, stop =
                where alw_source {| [@litany.allow "flag-int: nothing to see"]|}
              in
              equal
                (list (triple int int string))
                [ (start, stop, "") ]
                (List.map
                   (fun (e : Litany.Fix.edit) ->
                     (Litany.Span.start e.span, Litany.Span.stop e.span, e.text))
                   (Litany.Fix.edits fx)));
      test "an unfulfilled expect ships no fix" (fun () ->
          let rep = run ~rules:[ flag_int () ] [ allow_entry alw_source ] in
          let audit =
            List.find
              (fun (r, _) -> r = "unfulfilled-expect")
              (Report.findings rep)
          in
          is_none (Finding.fix (snd audit)));
      test "expected is the expect-claimed subset of suppressed" (fun () ->
          let rep = run ~rules:[ flag_int () ] [ allow_entry alw_source ] in
          let shape l =
            List.map
              (fun (rule, f, reason) ->
                ((Finding.loc f).Location.loc_start.pos_cnum, rule, reason))
              l
          in
          let d43 = {|(43 [@litany.expect "flag-int: fires"])|} in
          equal
            (list (triple int string string))
            [ (fst (where alw_source d43), "flag-int", "fires") ]
            (shape (Report.expected rep));
          equal int 2 (List.length (Report.suppressed rep)));
    ]

let report_tests =
  group "report"
    [
      test "exit codes: 0 clean, 1 findings" (fun () ->
          equal int 0 (Report.exit_code (run [ entry_a () ]));
          equal int 1
            (Report.exit_code (run ~rules:[ flag_int () ] [ entry_a () ])));
      test "every roster entry has exactly one outcome, in order" (fun () ->
          let rep = run [ entry_a (); entry_missing (); entry_b () ] in
          equal units_t
            [
              (a_source, Report.Linted);
              ( "fixtures/engine/plain/missing.ml",
                Report.Skipped Litany.Unit.Skip.Missing_artifact );
              (b_source, Report.Linted);
            ]
            (Report.units rep));
      test "load is called exactly once per entry" (fun () ->
          let loads = ref 0 in
          let load entry =
            incr loads;
            load entry
          in
          let _ =
            let rules = [ flag_int () ] in
            Engine.run ~rules ~catalog:rules
              ~roster:(Litany.Roster.v [ entry_a (); entry_b () ])
              ~load ()
          in
          equal int 2 !loads);
      test "severity derives from the emitting rule's group" (fun () ->
          let severities rep =
            let acc = ref [] in
            Report.iter_findings rep (fun ~rule:_ ~severity _ ->
                acc := severity :: !acc);
            List.rev !acc
          in
          let sev_t =
            Testable.make ~pp:Rule.Severity.pp
              ~equal:(fun (a : Rule.Severity.t) b -> a = b)
          in
          let correctness =
            run ~rules:[ flag_int ~group:Rule.Correctness () ] [ entry_a () ]
          in
          equal (list sev_t)
            [ Rule.Severity.Error; Rule.Severity.Error ]
            (severities correctness);
          let suspicious = run ~rules:[ flag_int () ] [ entry_a () ] in
          equal (list sev_t)
            [ Rule.Severity.Warning; Rule.Severity.Warning ]
            (severities suspicious));
      test "project rules: none selected reads an empty disposition list"
        (fun () ->
          let rep = run [ entry_a () ] in
          is_true (Report.project_rules rep = []));
    ]

(* An unreadable cmi on the resolver's search path must degrade the
   run visibly; a missing cmi stays ordinary match-nothing. The rule below
   consults the scope for a canonical name of unit [Trunc] at every
   identifier — [Pat.ident]'s consultation, inlined so the suite needs no
   pattern dependency. *)
let resolver_degradation_tests =
  let trunc_name =
    match Litany.Naming.Name.of_string "Trunc.value" with
    | Ok n -> n
    | Error _ -> assert false
  in
  let mention_trunc =
    Rule.expr (meta "mention-trunc") (fun u e ->
        match e.Typedtree.exp_desc with
        | Typedtree.Texp_ident (_, _, vd) ->
            if
              Litany.Naming.Scope.matches (Litany.Unit.scope u) trunc_name
                vd.Types.val_uid
            then [ Finding.v ~loc:e.exp_loc "mentioned" ]
            else []
        | _ -> [])
  in
  let run_with ~cmi_dirs entries =
    let resolver = Litany.Naming.Resolver.create ~cmi_dirs in
    Engine.run ~rules:[ mention_trunc ] ~catalog:[ mention_trunc ]
      ~roster:(Litany.Roster.v entries)
      ~load:(Litany.Unit.load ~resolver ~build_current:true)
      ()
  in
  group "resolver degradation"
    [
      test "an unreadable cmi degrades the unit that first demanded it"
        (fun () ->
          let dir = temp_dir () in
          let trunc_cmi = Filename.concat dir "trunc.cmi" in
          (* The toolchain magic and nothing after it: exists, unreadable. *)
          Out_channel.with_open_bin trunc_cmi (fun oc ->
              Out_channel.output_string oc Config.cmi_magic_number);
          let rep = run_with ~cmi_dirs:[ dir ] [ entry_a (); entry_b () ] in
          equal shape_t [] (shape rep);
          equal ~msg:"degradation is not a failure exit" int 0
            (Report.exit_code rep);
          match Report.degraded rep with
          | [ (path, note) ] ->
              equal ~msg:"attributed to the first demanding unit" string
                a_source path;
              contains ~sub:"canonical-name resolution degraded" note;
              contains ~sub:trunc_cmi note;
              contains ~sub:"corrupted or truncated" note
          | ds -> failf "expected one degradation note, got %d" (List.length ds));
      test "a missing cmi is match-nothing, never a degradation" (fun () ->
          let rep = run_with ~cmi_dirs:[ plain_objs ] [ entry_a () ] in
          equal shape_t [] (shape rep);
          equal (list (pair string string)) [] (Report.degraded rep);
          equal int 0 (Report.exit_code rep));
    ]

(* Duplicate roster entries dedup in the total order, and
   generated units take the facts-only outcome. *)
let roster_shape_tests =
  group "roster shapes"
    [
      test "duplicate roster entries for one source report each finding once"
        (fun () ->
          (* Two artifact copies of one unit (merlin-lib's vendored
             frontend built into two sublibraries): both entries load and
             both outcomes list, but identical (rule, location, message)
             findings collapse in the total order. *)
          let rep = run ~rules:[ flag_int () ] [ entry_a (); entry_a () ] in
          let single = run ~rules:[ flag_int () ] [ entry_a () ] in
          equal shape_t (shape single) (shape rep);
          equal units_t
            [ (a_source, Report.Linted); (a_source, Report.Linted) ]
            (Report.units rep));
      test "a generated unit takes the facts-only outcome" (fun () ->
          (* A [.ml-gen] source (dune alias modules): byte-identical to its
             build product, so it admits Direct — and no finding may anchor
             in a file the user cannot edit. *)
          let dir = temp_dir () in
          let gen = Filename.concat dir "emit_a.ml-gen" in
          Out_channel.with_open_bin gen (fun oc ->
              Out_channel.output_string oc
                (In_channel.with_open_bin a_source In_channel.input_all));
          let entry = Entry.v ~source:gen ~cmt:a_cmt () in
          let rep = run ~rules:[ flag_int () ] [ entry ] in
          equal shape_t [] (shape rep);
          equal units_t [ (gen, Report.Facts_only) ] (Report.units rep);
          equal int 0 (Report.exit_code rep));
    ]

(* M6: per-path report selection ([run]'s [keep]) and end-of-run demotion
   ([Report.demote]) — selection of reports, never of analysis. *)
let m6_tests =
  group "m6: keep and demote"
    [
      test "keep drops reports without touching outcomes" (fun () ->
          let keep ~path ~rule:_ = not (String.equal path a_source) in
          let rep =
            run ~keep
              ~rules:[ flag_int (); flag_string () ]
              [ entry_a (); entry_b () ]
          in
          is_true ~msg:"a's findings deselected"
            (List.for_all (fun (_, p, _, _) -> p <> a_source) (shape rep));
          is_true ~msg:"b's findings kept"
            (List.exists (fun (_, p, _, _) -> p = b_source) (shape rep));
          equal ~msg:"both units analyzed" units_t
            [ (a_source, Report.Linted); (b_source, Report.Linted) ]
            (Report.units rep);
          equal ~msg:"selection is not the drop channel" int 0
            (Report.dropped rep));
      test "keep sees the emitting rule's name" (fun () ->
          let keep ~path:_ ~rule = not (String.equal rule "flag-int") in
          let rep =
            run ~keep
              ~rules:[ flag_int (); flag_string () ]
              [ entry_a (); entry_b () ]
          in
          is_true ~msg:"flag-int deselected everywhere"
            (List.for_all (fun (r, _, _, _) -> r <> "flag-int") (shape rep)));
      test "demote removes a unit's findings and skips it" (fun () ->
          let rep =
            run
              ~rules:[ flag_int (); flag_string () ]
              [ entry_a (); entry_b () ]
          in
          let rep' =
            Report.demote ~path:a_source Litany.Unit.Skip.Modified_during_run
              rep
          in
          is_true ~msg:"a's findings gone"
            (List.for_all (fun (_, p, _, _) -> p <> a_source) (shape rep'));
          equal ~msg:"a demoted to the skip" units_t
            [
              (a_source, Report.Skipped Litany.Unit.Skip.Modified_during_run);
              (b_source, Report.Linted);
            ]
            (Report.units rep');
          equal ~msg:"b's findings still count" int 1 (Report.exit_code rep');
          let rep'' =
            Report.demote ~path:b_source Litany.Unit.Skip.Modified_during_run
              rep'
          in
          equal ~msg:"nothing left: exit 0" int 0 (Report.exit_code rep''));
      test "demote of an unknown path is a no-op" (fun () ->
          let rep = run ~rules:[ flag_int () ] [ entry_a () ] in
          let rep' =
            Report.demote ~path:"nowhere.ml"
              Litany.Unit.Skip.Modified_during_run rep
          in
          equal shape_t (shape rep) (shape rep');
          equal units_t (Report.units rep) (Report.units rep'));
    ]

(* M8: the per-unit payload seam ([?unit_cache]/[?capture]) — replay must
   equal recompute through the one assembly path, undecodable bytes are a
   miss, failures are never stored, and capture fires once per admitted
   unit on both paths. *)
let unit_cache_tests =
  let store_all () =
    let tbl = Hashtbl.create 8 in
    ( tbl,
      {
        Engine.Unit_cache.load =
          (fun e -> Hashtbl.find_opt tbl (Entry.source e));
        store = (fun e bytes -> Hashtbl.replace tbl (Entry.source e) bytes);
      } )
  in
  let same_report a b =
    equal shape_t (shape a) (shape b);
    equal (list string) (messages a) (messages b);
    equal units_t (Report.units a) (Report.units b);
    equal (list (pair string string)) (Report.notes a) (Report.notes b);
    equal (list (pair string string)) (Report.degraded a) (Report.degraded b);
    equal int
      (List.length (Report.suppressed a))
      (List.length (Report.suppressed b));
    equal int (Report.dropped a) (Report.dropped b);
    equal int (Report.exit_code a) (Report.exit_code b)
  in
  group "unit cache"
    [
      test "a replayed run is the recomputed run, and never loads" (fun () ->
          let tbl, uc = store_all () in
          let entries = [ entry_a (); entry_b (); entry_missing () ] in
          let rules = [ flag_int (); flag_string () ] in
          let cold =
            Engine.run ~unit_cache:uc ~rules ~catalog:rules
              ~roster:(Litany.Roster.v entries) ~load ()
          in
          equal ~msg:"both admitted units stored" int 2 (Hashtbl.length tbl);
          let warm =
            Engine.run ~unit_cache:uc ~rules ~catalog:rules
              ~roster:(Litany.Roster.v entries)
              ~load:(fun e ->
                if Hashtbl.mem tbl (Entry.source e) then
                  failf "replay called load for %s" (Entry.source e)
                else load e)
              ()
          in
          same_report cold warm);
      test "capture fires once per admitted unit, cold and warm" (fun () ->
          let tbl, uc = store_all () in
          let entries = [ entry_a (); entry_missing () ] in
          let captured () =
            let acc = ref [] in
            ((fun e (_ : string) -> acc := Entry.source e :: !acc), acc)
          in
          let cap_cold, cold_acc = captured () in
          let _ =
            let rules = [ flag_int () ] in
            Engine.run ~unit_cache:uc ~capture:cap_cold ~rules ~catalog:rules
              ~roster:(Litany.Roster.v entries) ~load ()
          in
          equal ~msg:"cold: the admitted unit, not the skip" (list string)
            [ a_source ] (List.rev !cold_acc);
          let cap_warm, warm_acc = captured () in
          let _ =
            let rules = [ flag_int () ] in
            Engine.run ~unit_cache:uc ~capture:cap_warm ~rules ~catalog:rules
              ~roster:(Litany.Roster.v entries) ~load ()
          in
          equal ~msg:"warm: same capture from the replay path" (list string)
            [ a_source ] (List.rev !warm_acc));
      test "undecodable payload bytes are a miss, never an error" (fun () ->
          let uc =
            {
              Engine.Unit_cache.load = (fun _ -> Some "garbage");
              store = (fun _ _ -> ());
            }
          in
          let plain = run ~rules:[ flag_int () ] [ entry_a () ] in
          let rep =
            let rules = [ flag_int () ] in
            Engine.run ~unit_cache:uc ~rules ~catalog:rules
              ~roster:(Litany.Roster.v [ entry_a () ])
              ~load ()
          in
          same_report plain rep);
      test "a unit with a rule failure is reported but never stored" (fun () ->
          let tbl, uc = store_all () in
          let boom = Rule.expr (meta "boom") (fun _ _ -> failwith "boom") in
          let rep =
            Engine.run ~unit_cache:uc ~rules:[ boom ] ~catalog:[ boom ]
              ~roster:(Litany.Roster.v [ entry_a () ])
              ~load ()
          in
          equal ~msg:"failure dominates: exit 3" int 3 (Report.exit_code rep);
          equal ~msg:"nothing stored" int 0 (Hashtbl.length tbl));
    ]

let () =
  Windtrap.run "litany_engine"
    [
      dispatch_tests;
      kinds_tests;
      emit_contract_tests;
      degraded_tests;
      resolver_degradation_tests;
      roster_shape_tests;
      ordering_tests;
      failure_tests;
      suppression_tests;
      fix_channel_tests;
      report_tests;
      m6_tests;
      unit_cache_tests;
    ]
