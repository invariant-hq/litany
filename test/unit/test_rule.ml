(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule

let invalid = function Invalid_argument _ -> true | _ -> false

let meta ?(name = "test-rule") ?renamed_from ?(group = Rule.Suspicious)
    ?stability ?(summary = "a test rule") () =
  Rule.meta ~name ?renamed_from ~group ?stability ~since:"1.0" ~fix:Rule.Never
    ~summary ~doc:"doc" ()

let meta_tests =
  group "meta"
    [
      test "kebab-case names are accepted" (fun () ->
          List.iter
            (fun name -> ignore (meta ~name ()))
            [ "a"; "needless-list-length"; "utf8-in-2024"; "x0" ]);
      test "non-kebab-case names are refused" (fun () ->
          List.iter
            (fun name -> raises_match invalid (fun () -> meta ~name ()))
            [
              "";
              "Bad-Name";
              "double--dash";
              "-leading";
              "trailing-";
              "under_score";
              "9starts-with-digit";
              "org/rule";
              "dotted.name";
            ]);
      test "aliases obey the same grammar" (fun () ->
          ignore (meta ~renamed_from:[ "old-name" ] ());
          raises_match invalid (fun () -> meta ~renamed_from:[ "Bad" ] ()));
      test "an empty summary is refused" (fun () ->
          raises_match invalid (fun () -> meta ~summary:"" ()));
    ]

let query_tests =
  group "queries"
    [
      test "the declaration round-trips through the accessors" (fun () ->
          let m =
            Rule.meta ~name:"round-trip" ~renamed_from:[ "old-round-trip" ]
              ~group:Rule.Perf ~stability:Rule.Stability.Nursery ~since:"1.2"
              ~fix:Rule.Sometimes ~summary:"summary" ~doc:"doc" ()
          in
          let r = Rule.source m (fun _ -> []) in
          equal string "round-trip" (Rule.name r);
          equal (list string) [ "old-round-trip" ] (Rule.renamed_from r);
          is_true (Rule.group r = Rule.Perf);
          is_true (Rule.stability r = Rule.Stability.Nursery);
          equal string "1.2" (Rule.since r);
          is_true (Rule.fix r = Rule.Sometimes);
          equal string "summary" (Rule.summary r);
          equal string "doc" (Rule.doc r);
          is_false (Rule.is_project r));
      test "defaults: no aliases, stable" (fun () ->
          let r = Rule.source (meta ()) (fun _ -> []) in
          equal (list string) [] (Rule.renamed_from r);
          is_true (Rule.stability r = Rule.Stability.Stable));
      test "each constructor subscribes its own kind" (fun () ->
          let m = meta () in
          let kind r =
            match Rule.callback r with
            | Rule.Expr _ -> "expr"
            | Rule.Pattern _ -> "pattern"
            | Rule.Binding _ -> "binding"
            | Rule.Type_decl _ -> "type_decl"
            | Rule.Let_group _ -> "let_group"
            | Rule.Module_binding _ -> "module_binding"
            | Rule.Export _ -> "export"
            | Rule.Attribute _ -> "attribute"
            | Rule.Source _ -> "source"
            | Rule.Project _ -> "project"
          in
          equal string "expr" (kind (Rule.expr m (fun _ _ -> [])));
          equal string "pattern" (kind (Rule.pattern m (fun _ _ -> [])));
          equal string "binding" (kind (Rule.binding m (fun _ _ -> [])));
          equal string "type_decl" (kind (Rule.type_decl m (fun _ _ -> [])));
          equal string "let_group"
            (kind (Rule.let_group m (fun _ ~loc:_ _ _ -> [])));
          equal string "module_binding"
            (kind (Rule.module_binding m (fun _ _ -> [])));
          equal string "export" (kind (Rule.export m (fun _ _ -> [])));
          equal string "attribute" (kind (Rule.attribute m (fun _ _ -> [])));
          equal string "source" (kind (Rule.source m (fun _ -> [])));
          equal string "project"
            (kind (Rule.project m ~collect:(fun _ -> []) ~report:(fun _ -> []))));
      test "the module-binding view round-trips through its accessors"
        (fun () ->
          let module MB = Rule.Module_binding in
          let loc_of start stop =
            let pos cnum =
              {
                Lexing.pos_fname = "f.ml";
                pos_lnum = 1;
                pos_bol = 0;
                pos_cnum = cnum;
              }
            in
            {
              Location.loc_start = pos start;
              loc_end = pos stop;
              loc_ghost = false;
            }
          in
          let id = Ident.create_local "M" in
          let mb =
            MB.v ~id:(Some id) ~name_loc:(loc_of 7 8) ~loc:(loc_of 0 20)
              ~position:MB.Toplevel
          in
          is_true
            (match MB.id mb with Some i -> Ident.same i id | None -> false);
          equal int 7 (MB.name_loc mb).Location.loc_start.pos_cnum;
          equal int 0 (MB.loc mb).Location.loc_start.pos_cnum;
          equal int 20 (MB.loc mb).Location.loc_end.pos_cnum;
          is_true (MB.position mb = MB.Toplevel);
          let anon =
            MB.v ~id:None ~name_loc:(loc_of 4 5) ~loc:(loc_of 4 9)
              ~position:MB.Local
          in
          is_true (MB.id anon = None);
          is_true (MB.position anon = MB.Local));
      test "project rules are live (M9)" (fun () ->
          (* The ['fact] existential seals per rule as Marshal frames at
             construction; the collect-to-report round-trip is discharged
             engine-end-to-end in the unused-export/dead-code suites
             (check_project_marshal). *)
          let r =
            Rule.project (meta ())
              ~collect:(fun _ -> [ (1, "a") ])
              ~report:(fun _ -> [])
          in
          is_true (Rule.is_project r);
          match Rule.callback r with
          | Rule.Project { collect = _; report } ->
              equal int 0 (List.length (report []))
          | _ -> is_true false);
    ]

let policy_tests =
  group "policy"
    [
      test "group names are the selection vocabulary" (fun () ->
          equal (list string)
            [
              "correctness";
              "suspicious";
              "perf";
              "style";
              "pedantic";
              "restriction";
            ]
            (List.map Rule.Group.to_string Rule.Group.all));
      test "severity derives from the group" (fun () ->
          is_true (Rule.Severity.of_group Rule.Correctness = Rule.Severity.Error);
          List.iter
            (fun g ->
              is_true (Rule.Severity.of_group g = Rule.Severity.Warning))
            [
              Rule.Suspicious;
              Rule.Perf;
              Rule.Style;
              Rule.Pedantic;
              Rule.Restriction;
            ]);
      test "severity prints lowercase" (fun () ->
          equal string "error"
            (Format.asprintf "%a" Rule.Severity.pp Rule.Severity.Error);
          equal string "warning"
            (Format.asprintf "%a" Rule.Severity.pp Rule.Severity.Warning));
      test "stability names are the selection vocabulary" (fun () ->
          equal string "stable" (Rule.Stability.to_string Rule.Stability.Stable);
          equal string "nursery"
            (Rule.Stability.to_string Rule.Stability.Nursery));
    ]

(* A miniature catalog for selection: one rule per (group, stability)
   corner the precedence rules distinguish. *)
let mini name group ?stability ?renamed_from () =
  Rule.source (meta ~name ?renamed_from ~group ?stability ()) (fun _ -> [])

let catalog =
  [
    mini "broken-thing" Rule.Correctness ();
    mini "odd-thing" Rule.Suspicious ();
    mini "slow-thing" Rule.Perf ();
    mini "ugly-thing" Rule.Style ();
    mini "fussy-thing" Rule.Pedantic ();
    mini "banned-thing" Rule.Restriction ();
    mini "young-thing" Rule.Style ~stability:Rule.Stability.Nursery ();
    mini "renamed-thing" Rule.Perf ~renamed_from:[ "old-thing" ] ();
  ]

let names rules = List.map Rule.name rules

let selected ?(select = []) ?(ignore = []) () =
  match Rule.select ~catalog ~select ~ignore with
  | Ok (rules, warnings) -> (names rules, warnings)
  | Error e -> failf "unexpected refusal: %s" e

let refusal ?(select = []) ?(ignore = []) () =
  match Rule.select ~catalog ~select ~ignore with
  | Ok _ -> fail "expected a refusal"
  | Error e -> e

let selection_tests =
  group "selection"
    [
      test "no tokens means the default set" (fun () ->
          equal
            (pair (list string) (list string))
            ([ "broken-thing"; "odd-thing"; "slow-thing"; "renamed-thing" ], [])
            (selected ()));
      test "all is every stable rule; nursery and restriction stay out"
        (fun () ->
          equal
            (pair (list string) (list string))
            ( [
                "broken-thing";
                "odd-thing";
                "slow-thing";
                "ugly-thing";
                "fussy-thing";
                "renamed-thing";
              ],
              [] )
            (selected ~select:[ "all" ] ()));
      test "a group name selects its stable rules alone" (fun () ->
          equal (list string)
            [ "ugly-thing"; "young-thing" ]
            (fst (selected ~select:[ "style"; "nursery" ] ()));
          equal (list string) [ "ugly-thing" ]
            (fst (selected ~select:[ "style" ] ())));
      test "an exact name outranks its group in ignore" (fun () ->
          equal (list string)
            [ "broken-thing"; "odd-thing"; "renamed-thing" ]
            (fst (selected ~ignore:[ "slow-thing" ] ()));
          equal (list string) [ "slow-thing" ]
            (fst (selected ~select:[ "slow-thing" ] ~ignore:[ "perf" ] ())));
      test "a group outranks all in ignore" (fun () ->
          equal (list string)
            [ "broken-thing"; "odd-thing"; "ugly-thing"; "fussy-thing" ]
            (fst (selected ~select:[ "all" ] ~ignore:[ "perf" ] ())));
      test "at equal specificity ignore wins" (fun () ->
          equal (list string) []
            (fst
               (selected ~select:[ "slow-thing" ] ~ignore:[ "slow-thing" ] ()));
          equal (list string) []
            (fst (selected ~select:[ "perf" ] ~ignore:[ "perf" ] ())));
      test "a nursery rule joins by tier or exact name, never by group"
        (fun () ->
          equal (list string) [ "young-thing" ]
            (fst (selected ~select:[ "nursery" ] ()));
          equal (list string) [ "young-thing" ]
            (fst (selected ~select:[ "young-thing" ] ()));
          is_true
            (not
               (List.mem "young-thing" (fst (selected ~select:[ "style" ] ())))));
      test "a restriction rule joins by group token or exact name, never by all"
        (fun () ->
          is_true
            (not
               (List.mem "banned-thing" (fst (selected ~select:[ "all" ] ()))));
          equal (list string) [ "banned-thing" ]
            (fst (selected ~select:[ "banned-thing" ] ()));
          equal (list string) [ "banned-thing" ]
            (fst (selected ~select:[ "restriction" ] ())));
      test "a bare restriction group token warns once; exact name never"
        (fun () ->
          (* The counts are the mini-catalog's: banned-thing is its one
             restriction rule, and it is Stable, so the token enables
             1 of 1 — the wording stays honest when rules graduate. *)
          let warning =
            "restriction rules are independent house policies, and some \
             contradict each other — adopt each by exact name; the group token \
             enables 1 of 1 restriction rules (group tokens cover stable rules \
             only; nursery members need \"nursery\" or their exact name)"
          in
          equal (list string) [ warning ]
            (snd (selected ~select:[ "restriction" ] ()));
          equal (list string) [ warning ]
            (snd (selected ~select:[ "all"; "restriction"; "nursery" ] ()));
          equal (list string) [] (snd (selected ~select:[ "banned-thing" ] ()));
          equal (list string) [] (snd (selected ~ignore:[ "restriction" ] ())));
      test "the full-catalog audit spelling selects the whole catalog"
        (fun () ->
          equal (list string) (names catalog)
            (fst (selected ~select:[ "all"; "restriction"; "nursery" ] ())));
      test "a tombstone alias resolves with a rename warning" (fun () ->
          equal
            (pair (list string) (list string))
            ( [ "renamed-thing" ],
              [ "rule \"old-thing\" was renamed to \"renamed-thing\"" ] )
            (selected ~select:[ "old-thing" ] ()));
      test "an unknown token refuses with a did-you-mean" (fun () ->
          equal string
            "unknown rule or group \"styel\" (did you mean \"style\"?)"
            (refusal ~select:[ "styel" ] ());
          equal string
            "unknown rule or group \"slow-thign\" (did you mean \
             \"slow-thing\"?)"
            (refusal ~ignore:[ "slow-thign" ] ()));
      test "an unknown token far from everything gets no hint" (fun () ->
          equal string "unknown rule or group \"zzzzzz\""
            (refusal ~select:[ "zzzzzz" ] ()));
      test "suggest picks the nearest candidate, ties lexicographic" (fun () ->
          equal (option string) (Some "style")
            (Rule.suggest ~candidates:[ "style"; "stale" ] "styel");
          equal (option string) (Some "ab")
            (Rule.suggest ~candidates:[ "ac"; "ab" ] "aa");
          equal (option string) None
            (Rule.suggest ~candidates:[ "style" ] "unrelated"));
    ]

let () =
  run "litany_rule" [ meta_tests; query_tests; policy_tests; selection_tests ]
