(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Restricted_dependency.rule
let source = "fixtures/rd_use.ml"
let cmt = "fixtures/.fix_rd.objs/byte/rd_use.cmt"

(* Payload constructors: positioned s-expressions as the config parser
   hands them to the schema. Positions are synthetic (1:1) — the cram
   suite pins real positions from a real config file. *)
let atom s = { Litany.Sexp.desc = Litany.Sexp.Atom s; line = 1; col = 1 }
let list xs = { Litany.Sexp.desc = Litany.Sexp.List xs; line = 1; col = 1 }

let forbid path use =
  list [ atom "forbid"; atom path; list [ atom "use"; atom use ] ]

let str_remedy = "Re — Str answers matches through global state"
let internal_remedy = "the public Rd_dep surface"

let ia_remedy = "Import.invalid_arg' — house messages carry module and function"

let obj_remedy = "a typed interface"

(* The suite's configuration: the four live forbids plus three that must
   resolve to nothing — a library the workspace does not link, a unit
   that does not exist, and the design sketch's [Stdlib.Str] spelling
   (the Str library is its own compilation unit, not a Stdlib member) —
   and therefore match nothing, never error. *)
let payload =
  [
    forbid "Str" str_remedy;
    forbid "Rd_dep.Internal" internal_remedy;
    forbid "Stdlib.invalid_arg" ia_remedy;
    forbid "Stdlib.Obj" obj_remedy;
    forbid "Base.Fn.id" "nothing — Base is not linked here";
    forbid "Notaunit.Sub" "nothing — no such unit";
    forbid "Stdlib.Str" "nothing — Str is not a Stdlib member";
  ]

let configured payload =
  match Rule.configure rule payload with
  | Ok r -> r
  | Error e -> failf "schema refused: %s" (Rule.Options.to_string e)

let refused payload =
  match Rule.configure rule payload with
  | Ok _ -> fail "schema accepted; expected a refusal"
  | Error e -> e.Rule.Options.message

(* The message's noun branches on the forbid's shape: module
   forbids read "restricted module", value forbids "restricted value". *)
let message path noun remedy =
  Printf.sprintf "%s is a restricted %s; use %s" path noun remedy

let count msg findings =
  List.length
    (List.filter
       (fun (_, f) -> String.equal (Litany.Finding.message f) msg)
       findings)

let () =
  Windtrap.run "restricted-dependency"
    [
      test "declares its one metadata record" (fun () ->
          equal string "restricted-dependency" (Rule.name rule);
          is_true ~msg:"group is Restriction"
            (Rule.group rule = Rule.Restriction);
          is_true ~msg:"stable" (Rule.stability rule = Rule.Stability.Stable);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.0" (Rule.since rule));
      test "unconfigured, the rule is inert" (fun () ->
          let rep = Support.report rule ~source ~cmt in
          equal ~msg:"rule failures" int 0
            (List.length (Litany.Engine.Report.failures rep));
          equal ~msg:"no forbids, no findings" int 0
            (List.length (Litany.Engine.Report.findings rep)));
      test "configured, fires exactly on the marked references" (fun () ->
          Support.check_markers (configured payload) ~source ~cmt);
      test "messages carry each forbid's use remedy verbatim" (fun () ->
          let findings =
            Litany.Engine.Report.findings
              (Support.report (configured payload) ~source ~cmt)
          in
          equal ~msg:"total findings" int 11 (List.length findings);
          equal ~msg:"Str unit forbid" int 4
            (count (message "Str" "module" str_remedy) findings);
          equal ~msg:"Rd_dep.Internal submodule forbid" int 3
            (count
               (message "Rd_dep.Internal" "module" internal_remedy)
               findings);
          equal ~msg:"Stdlib.invalid_arg value forbid" int 3
            (count (message "Stdlib.invalid_arg" "value" ia_remedy) findings);
          equal ~msg:"Stdlib.Obj alias-hop forbid" int 1
            (count (message "Stdlib.Obj" "module" obj_remedy) findings));
      test "an empty payload configures the inert rule" (fun () ->
          let rep = Support.report (configured []) ~source ~cmt in
          equal int 0 (List.length (Litany.Engine.Report.findings rep)));
      test "the reconfigured rule re-attaches the schema" (fun () ->
          let once = configured [ forbid "Str" str_remedy ] in
          match
            Rule.configure once [ forbid "Stdlib.invalid_arg" ia_remedy ]
          with
          | Ok _ -> ()
          | Error e ->
              failf "second configure refused: %s" (Rule.Options.to_string e));
      test "schema refusals are actionable config errors" (fun () ->
          equal ~msg:"forbid without use — the mandatory-remedy contract" string
            {|forbid Str wants a (use "<replacement>") remedy — every ban names its replacement|}
            (refused [ list [ atom "forbid"; atom "Str" ] ]);
          equal ~msg:"malformed module path" string
            {|malformed module path "Rd_dep..Internal" at offset 7: expected a capitalized module name|}
            (refused [ forbid "Rd_dep..Internal" "x" ]);
          equal ~msg:"malformed value name" string
            {|malformed canonical name "lowercase" at offset 0: expected at least two components, e.g. Stdlib.length|}
            (refused [ forbid "lowercase" "x" ]);
          equal ~msg:"duplicate forbid" string "Str is forbidden twice"
            (refused [ forbid "Str" "Re"; forbid "Str" "Re again" ]);
          equal ~msg:"unknown option" string
            {|unknown option "forbud" (did you mean "forbid"?)|}
            (refused [ list [ atom "forbud"; atom "Str" ] ]);
          equal ~msg:"empty remedy" string
            "forbid Str wants a non-empty replacement in (use …)"
            (refused [ forbid "Str" "" ]);
          equal ~msg:"unknown key inside forbid" string
            {|unknown key "usee" inside forbid Str (did you mean "use"?)|}
            (refused
               [
                 list
                   [
                     atom "forbid"; atom "Str"; list [ atom "usee"; atom "Re" ];
                   ];
               ]));
    ]
