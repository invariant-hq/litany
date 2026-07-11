(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* The resolver half of this suite pins each resolution mechanism
   against real compiled fixtures under fixtures/:
   fix_probe (no mli, unwrapped), fix_probe2 (wrapped: withmli.ml(i),
   nomli.ml with include, cases2.ml with a module ascription), fix_probe3
   (external use sites into both). Use-site uids are harvested from the
   fixtures' cmts and compared against what the resolver returns for the
   corresponding canonical name. *)

open Windtrap
module Name = Litany.Naming.Name
module Resolver = Litany.Naming.Resolver
module Scope = Litany.Naming.Scope

let name_t = Testable.make ~pp:Name.pp ~equal:Name.equal
let uid_t = Testable.make ~pp:Shape.Uid.print ~equal:Shape.Uid.equal
let name s = require_ok ~pp_error:Name.pp_error (Name.of_string s)

(* {1 Name grammar} *)

let well_formed =
  [
    "Stdlib.abs";
    "Stdlib.List.length";
    "Stdlib.(=)";
    "Base.(|.)";
    "Fix_probe2.Withmli.f";
    "A.b'c_2";
    "A.B.C.d";
    "X.(@@)";
    "X.(~-)";
  ]

(* (input, offset of the failure, fragment of the reason) *)
let malformed =
  [
    ("", 0, "component");
    ("foo", 0, "two components");
    ("Foo", 0, "two components");
    ("Stdlib", 0, "two components");
    ("Stdlib.", 7, "component");
    ("Stdlib.=", 7, "parenthesized");
    ("Stdlib.()", 8, "operator symbol");
    ("Stdlib.(= )", 9, "')'");
    ("Stdlib.(=)x", 10, "end of input");
    ("stdlib.foo", 0, "capitalized");
    ("Stdlib.Foo", 7, "value leaf");
    ("Stdlib.foo.bar", 7, "capitalized");
    ("Stdlib.foo bar", 10, "end of input");
    ("Stdlib._", 7, "not a value name");
    ("Stdlib.9x", 7, "identifier");
  ]

let name_tests =
  group "Name"
    [
      cases
        ~name:(fun s -> s)
        "well-formed round trip" well_formed
        (fun s ->
          let n = require_ok ~pp_error:Name.pp_error (Name.of_string s) in
          equal string s (Name.to_string n);
          equal
            (result name_t Testable.(make ~pp:Name.pp_error ~equal:( = )))
            (Ok n)
            (Name.of_string (Name.to_string n)));
      cases
        ~name:(fun (s, _, _) -> if s = "" then "<empty>" else s)
        "malformed inputs" malformed
        (fun (s, at, fragment) ->
          match Name.of_string s with
          | Ok n -> failf "parsed as %a" Name.pp n
          | Error (Name.Malformed { input; at = got; reason }) ->
              equal string s input;
              equal int ~msg:"offset" at got;
              contains ~sub:fragment reason);
      test "equal identifies equal spellings only" (fun () ->
          equal name_t (name "Stdlib.(=)") (name "Stdlib.(=)");
          is_false (Name.equal (name "Stdlib.abs") (name "Stdlib.min"));
          is_false (Name.equal (name "A.B.c") (name "A.c")));
      test "compare is componentwise, not a string compare" (fun () ->
          (* Componentwise: "~-" > "B" at component 2. A string compare of
             the renderings would see '(' < 'B' and invert the order. *)
          is_true (Name.compare (name "A.(~-)") (name "A.B.c") > 0);
          is_true (Name.compare (name "A.B.c") (name "A.x") < 0);
          equal int 0 (Name.compare (name "A.b") (name "A.b")));
      test "compare is compatible with equal" (fun () ->
          let all = List.map name well_formed in
          List.iter
            (fun n ->
              List.iter
                (fun n' -> equal bool (Name.equal n n') (Name.compare n n' = 0))
                all)
            all);
      test "pp_error quotes the input and points at the offset" (fun () ->
          let e = require_error (Name.of_string "Stdlib.=") in
          let rendered = Format.asprintf "%a" Name.pp_error e in
          contains ~sub:"\"Stdlib.=\"" rendered;
          contains ~sub:"7" rendered);
    ]

(* {1 References: the union grammar} *)

let ref_tests =
  group "Ref"
    [
      test "classification is by the last component's shape" (fun () ->
          (match Litany.Naming.Ref.of_string "Stdlib.Obj" with
          | Ok (Litany.Naming.Ref.Module p) ->
              equal string "Stdlib.Obj" (Litany.Naming.Module_path.to_string p)
          | Ok (Litany.Naming.Ref.Value _) -> fail "classified as a value"
          | Error _ -> fail "did not parse");
          (match Litany.Naming.Ref.of_string "Str" with
          | Ok (Litany.Naming.Ref.Module _) -> ()
          | Ok (Litany.Naming.Ref.Value _) -> fail "classified as a value"
          | Error _ -> fail "did not parse");
          (match Litany.Naming.Ref.of_string "Stdlib.List.length" with
          | Ok (Litany.Naming.Ref.Value n) ->
              equal name_t (name "Stdlib.List.length") n
          | Ok (Litany.Naming.Ref.Module _) -> fail "classified as a module"
          | Error _ -> fail "did not parse");
          match Litany.Naming.Ref.of_string "Base.(|.)" with
          | Ok (Litany.Naming.Ref.Value _) -> ()
          | Ok (Litany.Naming.Ref.Module _) ->
              fail "an operator leaf is never module-shaped"
          | Error _ -> fail "did not parse");
      test "well-formed references round-trip" (fun () ->
          List.iter
            (fun input ->
              match Litany.Naming.Ref.of_string input with
              | Ok r -> equal string input (Litany.Naming.Ref.to_string r)
              | Error e ->
                  failf "%S did not parse: %a" input Litany.Naming.Ref.pp_error
                    e)
            [ "Stdlib.Obj"; "Str"; "Stdlib.List.length"; "Stdlib.(=)" ]);
      test "errors keep each grammar's positioned shape" (fun () ->
          (match Litany.Naming.Ref.of_string "Rd..Internal" with
          | Ok _ -> fail "parsed"
          | Error (Name.Malformed { at; reason; _ }) ->
              equal int ~msg:"offset" 3 at;
              contains ~sub:"capitalized" reason);
          match Litany.Naming.Ref.of_string "lowercase" with
          | Ok _ -> fail "parsed"
          | Error (Name.Malformed { at; reason; _ }) ->
              equal int ~msg:"offset" 0 at;
              contains ~sub:"two components" reason);
      test "pp_error names the classified grammar" (fun () ->
          let render input =
            match Litany.Naming.Ref.of_string input with
            | Ok _ -> failf "%S parsed" input
            | Error e -> Format.asprintf "%a" Litany.Naming.Ref.pp_error e
          in
          contains ~sub:"malformed module path \"Rd..Internal\""
            (render "Rd..Internal");
          contains ~sub:"malformed canonical name \"lowercase\""
            (render "lowercase"));
    ]

(* {1 Fixtures} *)

let stdlib_dir () =
  match Sys.getenv_opt "LITANY_TEST_STDLIB" with
  | Some dir -> dir
  | None -> fail "LITANY_TEST_STDLIB not set: run through dune"

let fixture_cmi_dirs =
  [
    "fixtures/ident/probe/.fix_probe.objs/byte";
    "fixtures/ident/probe2/.fix_probe2.objs/byte";
    "fixtures/ident/probe3/.fix_probe3.objs/byte";
  ]

let resolver () =
  Resolver.create ~cmi_dirs:(fixture_cmi_dirs @ [ stdlib_dir () ])

let read_cmt path =
  match Cmt_format.read path with
  | _, Some infos -> infos
  | _, None -> failf "%s carries no cmt info" path
  | exception e -> failf "cannot read %s: %s" path (Printexc.to_string e)

(* Use sites of one cmt as [(Path.name, val_uid)] pairs. *)
let harvest cmt_path =
  let infos = read_cmt cmt_path in
  let structure =
    match infos.Cmt_format.cmt_annots with
    | Implementation str -> str
    | _ -> failf "%s is not an implementation cmt" cmt_path
  in
  let occurrences = ref [] in
  let iter =
    let open Tast_iterator in
    {
      default_iterator with
      expr =
        (fun sub expr ->
          (match expr.exp_desc with
          | Texp_ident (path, _, vd) ->
              occurrences := (Path.name path, vd.Types.val_uid) :: !occurrences
          | _ -> ());
          default_iterator.expr sub expr);
    }
  in
  iter.structure iter structure;
  !occurrences

let use_site occurrences key =
  match List.assoc_opt key occurrences with
  | Some uid -> uid
  | None -> failf "no use site %S in the harvested cmt" key

let probe_cmt = "fixtures/ident/probe/.fix_probe.objs/byte/fix_probe.cmt"
let probe3_cmt = "fixtures/ident/probe3/.fix_probe3.objs/byte/fix_probe3.cmt"

let withmli_cmt =
  "fixtures/ident/probe2/.fix_probe2.objs/byte/fix_probe2__Withmli.cmt"

let cases2_cmt =
  "fixtures/ident/probe2/.fix_probe2.objs/byte/fix_probe2__Cases2.cmt"

(* {1 The 12-case resolution table} *)

(* canonical name, harvested cmt, use-site key (Path.name at the use site) *)
let table =
  [
    ("Stdlib.List.length", probe_cmt, "Stdlib.List.length");
    ("Stdlib.List.length", probe_cmt, "L.length");
    ("Stdlib.(=)", probe_cmt, "Stdlib.=");
    ("Stdlib.Map.Make.find_opt", probe_cmt, "Int_map.find_opt");
    ("Fix_probe.Int_map.find_opt", probe_cmt, "Int_map.find_opt");
    ("Fix_probe.Shadow.length", probe_cmt, "Shadow.length");
    ("Fix_probe.AliasB.bv", probe_cmt, "AliasB.bv");
    ("Fix_probe.Concrete.sv", probe_cmt, "Concrete.sv");
    ("Fix_probe.direct", probe3_cmt, "Fix_probe.direct");
    ("Fix_probe.Outer.Inner.v", probe3_cmt, "Fix_probe.Outer.Inner.v");
    ("Fix_probe2.Withmli.f", probe3_cmt, "Fix_probe2.Withmli.f");
    ("Fix_probe2.Nomli.g", probe3_cmt, "Fix_probe2.Nomli.g");
    ("Fix_probe2.Nomli.f", probe3_cmt, "Fix_probe2.Nomli.f");
    ("Fix_probe2.Cases2.Asc.length", probe3_cmt, "Fix_probe2.Cases2.Asc.length");
  ]

let resolver_tests =
  group "Resolver"
    [
      cases
        ~name:(fun (canonical, _, key) -> canonical ^ " = " ^ key)
        "resolves to the uid the use site carries" table
        (fun (canonical, cmt, key) ->
          let r = resolver () in
          equal (list uid_t)
            [ use_site (harvest cmt) key ]
            (Resolver.resolve r (name canonical)));
      test "a shadowing module is a distinct identity" (fun () ->
          let r = resolver () in
          not_equal (list uid_t)
            (Resolver.resolve r (name "Stdlib.List.length"))
            (Resolver.resolve r (name "Fix_probe.Shadow.length")));
      test "an ascribed module is a distinct identity" (fun () ->
          let r = resolver () in
          not_equal (list uid_t)
            (Resolver.resolve r (name "Stdlib.List.length"))
            (Resolver.resolve r (name "Fix_probe2.Cases2.Asc.length")));
      test "an include re-export preserves the uid" (fun () ->
          (* Two canonical names, one identity. *)
          let r = resolver () in
          equal (list uid_t)
            (Resolver.resolve r (name "Fix_probe2.Withmli.f"))
            (Resolver.resolve r (name "Fix_probe2.Nomli.f")));
      test "all functor instances share the body's interface uid" (fun () ->
          let r = resolver () in
          equal (list uid_t)
            (Resolver.resolve r (name "Stdlib.Map.Make.find_opt"))
            (Resolver.resolve r (name "Fix_probe.Int_map.find_opt")));
      test "a local alias is never resolved to a same-named foreign unit"
        (fun () ->
          (* fixtures/foreign plants a compilation unit [Base] with a value
             [bv] — the bait. [Fix_probe.AliasB] aliases the *local* [Base];
             its non-persistent head must resolve within fix_probe's own
             signature, never to the foreign cmi, even with the bait first
             on the search path. *)
          let foreign_dir = "fixtures/ident/foreign/.fix_foreign.objs/byte" in
          let r =
            Resolver.create
              ~cmi_dirs:((foreign_dir :: fixture_cmi_dirs) @ [ stdlib_dir () ])
          in
          let local = Resolver.resolve r (name "Fix_probe.AliasB.bv") in
          equal (list uid_t) [ use_site (harvest probe_cmt) "AliasB.bv" ] local;
          let foreign = Resolver.resolve r (name "Base.bv") in
          is_true ~msg:"the bait is findable" (foreign <> []);
          not_equal (list uid_t) foreign local);
      test "a missing cmi resolves to nothing, and is not a read failure"
        (fun () ->
          (* The quiet direction: absence is ordinary match-nothing — a
             workspace without Base must not error or degrade on a rule
             mentioning Base.*. *)
          let r = resolver () in
          equal (list uid_t) []
            (Resolver.resolve r (name "Nonexistent_unit.foo"));
          equal (list (pair string string)) [] (Resolver.read_failures r));
      test "a name absent from the signature resolves to nothing" (fun () ->
          let r = resolver () in
          equal (list uid_t) [] (Resolver.resolve r (name "Stdlib.List.nope"));
          equal (list uid_t) []
            (Resolver.resolve r (name "Stdlib.Nomodule.foo")));
      test "a value used as a module resolves to nothing" (fun () ->
          equal (list uid_t) []
            (Resolver.resolve (resolver ()) (name "Fix_probe.Direct.foo")));
      test "an unreadable cmi resolves to nothing and records the failure"
        (fun () ->
          (* The loud direction: a cmi that exists but cannot be read
             still matches nothing (matching undecodable bytes would be a
             guess) but the read failure is recorded, so the engine can
             surface the degradation instead of reporting a clean run. *)
          let dir = temp_dir () in
          let write file bytes =
            Out_channel.with_open_bin (Filename.concat dir file) (fun oc ->
                Out_channel.output_string oc bytes)
          in
          (* Garbage past the magic length: not a compiled interface. *)
          write "bogus.cmi" "definitely not a compiled interface";
          (* The toolchain magic and nothing after it: truncated. *)
          write "trunc.cmi" Config.cmi_magic_number;
          (* A foreign generation's magic: same prefix, other version. *)
          let magic = Config.cmi_magic_number in
          write "foreign.cmi"
            (String.sub magic 0 (String.length magic - 3) ^ "000");
          let r = Resolver.create ~cmi_dirs:[ dir ] in
          equal (list uid_t) [] (Resolver.resolve r (name "Bogus.foo"));
          equal (list uid_t) [] (Resolver.resolve r (name "Trunc.foo"));
          equal (list uid_t) [] (Resolver.resolve r (name "Foreign.foo"));
          (* A second name into the same unit re-records nothing: the read
             is memoized, one failure per cmi. *)
          equal (list uid_t) [] (Resolver.resolve r (name "Bogus.bar"));
          match Resolver.read_failures r with
          | [ (p1, r1); (p2, r2); (p3, r3) ] ->
              equal ~msg:"discovery order" string
                (Filename.concat dir "bogus.cmi")
                p1;
              contains ~sub:"not a compiled interface" r1;
              equal string (Filename.concat dir "trunc.cmi") p2;
              contains ~sub:"corrupted or truncated" r2;
              equal string (Filename.concat dir "foreign.cmi") p3;
              contains ~sub:"version of OCaml" r3
          | fs -> failf "expected three read failures, got %d" (List.length fs));
      test "resolutions are memoized" (fun () ->
          let r = resolver () in
          let n = name "Stdlib.List.length" in
          let first = Resolver.resolve r n in
          is_true ~msg:"same list on the second call"
            (first == Resolver.resolve r n));
    ]

(* {1 Scopes and the intra-unit bridge} *)

let no_intra _ = []

(* The loader's filter, exactly as [Litany.Naming.Scope]'s contract states it:
   only Definition_to_declaration pairs whose definition side is an Impl Item
   of the linted unit and whose declaration side is an Intf Item — of any
   unit, because an mli-side [include] declares values under the included
   unit's interface uids. The reverse image maps each canonical (interface)
   uid to the same-unit definition uids implementing it. *)
let filtered_intra (cmt : Cmt_format.cmt_infos) =
  let unit_name = cmt.cmt_modname in
  let pairs =
    List.filter_map
      (fun (kind, def, decl) ->
        if not (Dep_kind.is_definition_to_declaration kind) then None
        else
          match ((def : Shape.Uid.t), (decl : Shape.Uid.t)) with
          | ( Item { comp_unit = def_unit; from = Unit_info.Impl; _ },
              Item { from = Unit_info.Intf; _ } )
            when String.equal def_unit unit_name ->
              Some (decl, def)
          | _ -> None)
      cmt.cmt_declaration_dependencies
  in
  fun uid ->
    List.filter_map
      (fun (decl, def) -> if Shape.Uid.equal decl uid then Some def else None)
      pairs

(* The same reverse image without the filter — what the spike proved must
   never ship: ascriptions record cross-unit pairs that rewrite foreign
   identities. Used below to show the fixture really exercises the filter. *)
let unfiltered_intra (cmt : Cmt_format.cmt_infos) =
  let pairs =
    List.filter_map
      (fun (kind, def, decl) ->
        if Dep_kind.is_definition_to_declaration kind then Some (decl, def)
        else None)
      cmt.cmt_declaration_dependencies
  in
  fun uid ->
    List.filter_map
      (fun (decl, def) -> if Shape.Uid.equal decl uid then Some def else None)
      pairs

let scope_tests =
  group "Scope"
    [
      test "matches external use sites through the resolver alone" (fun () ->
          let sc = Scope.v ~resolver:(resolver ()) ~intra:no_intra ~local:[] in
          let occs = harvest probe3_cmt in
          is_true
            (Scope.matches sc
               (name "Fix_probe2.Withmli.f")
               (use_site occs "Fix_probe2.Withmli.f"));
          is_false
            (Scope.matches sc
               (name "Fix_probe2.Withmli.f")
               (use_site occs "Fix_probe2.Nomli.g")));
      test "an unresolved name matches nothing" (fun () ->
          let sc = Scope.v ~resolver:(resolver ()) ~intra:no_intra ~local:[] in
          is_false
            (Scope.matches sc
               (name "Nonexistent_unit.foo")
               (use_site (harvest probe3_cmt) "Fix_probe2.Withmli.f")));
      test "an intra-unit use carries the impl uid, missed without the bridge"
        (fun () ->
          (* Inside withmli.ml, [uses_f]'s call of [f] carries the impl uid,
             not the interface uid the resolver returns. *)
          let intra_use = use_site (harvest withmli_cmt) "f" in
          let sc = Scope.v ~resolver:(resolver ()) ~intra:no_intra ~local:[] in
          is_false (Scope.matches sc (name "Fix_probe2.Withmli.f") intra_use));
      test "the intra-unit bridge extends the canonical uid to impl uses"
        (fun () ->
          let cmt = read_cmt withmli_cmt in
          let sc =
            Scope.v ~resolver:(resolver ()) ~intra:(filtered_intra cmt)
              ~local:[]
          in
          let occs = harvest withmli_cmt in
          is_true
            (Scope.matches sc (name "Fix_probe2.Withmli.f") (use_site occs "f"));
          (* The bridge extends, it never blurs: [priv]'s uid is not [f]'s. *)
          is_false
            (Scope.matches sc
               (name "Fix_probe2.Withmli.f")
               (use_site occs "priv")));
      test "a unit without an mli needs no bridge" (fun () ->
          let cmt = read_cmt probe_cmt in
          let sc =
            Scope.v ~resolver:(resolver ()) ~intra:(filtered_intra cmt)
              ~local:[]
          in
          (* The derived cmi embeds definition uids, so intra-unit uses of
             Shadow.length already carry the canonical uid. *)
          is_true
            (Scope.matches sc
               (name "Fix_probe.Shadow.length")
               (use_site (harvest probe_cmt) "Shadow.length")));
      test "the bridge filter refuses the ascription's cross-unit pair"
        (fun () ->
          (* cases2.ml's ascription records a def->decl pair whose definition
             side is Stdlib__List's interface uid — a foreign identity. The
             unfiltered reverse image would extend the ascribed canonical
             name to every direct List.length use in the unit; the filter
             must refuse it. First prove the trap is really in the cmt. *)
          let cmt = read_cmt cases2_cmt in
          let occs = harvest cases2_cmt in
          let asc_name = name "Fix_probe2.Cases2.Asc.length" in
          let list_use = use_site occs "Stdlib.List.length" in
          let unfiltered =
            Scope.v ~resolver:(resolver ()) ~intra:(unfiltered_intra cmt)
              ~local:[]
          in
          is_true ~msg:"fixture exercises the cross-unit pair"
            (Scope.matches unfiltered asc_name list_use);
          let filtered =
            Scope.v ~resolver:(resolver ()) ~intra:(filtered_intra cmt)
              ~local:[]
          in
          is_false ~msg:"filtered bridge refuses the foreign identity"
            (Scope.matches filtered asc_name list_use);
          (* Both directions stay distinct, and both names still match their
             own use sites. *)
          let asc_use = use_site occs "Asc.length" in
          is_true (Scope.matches filtered asc_name asc_use);
          is_false (Scope.matches filtered (name "Stdlib.List.length") asc_use);
          is_true (Scope.matches filtered (name "Stdlib.List.length") list_use));
    ]

(* {1 The type namespace} *)

(* [type_head cmt key] is the head [Tconstr] path of the inferred type of
   the identifier use spelled [key] — the path a type use site carries,
   which [matches_type] consumes. *)
let type_head cmt_path key =
  let infos = read_cmt cmt_path in
  let structure =
    match infos.Cmt_format.cmt_annots with
    | Implementation str -> str
    | _ -> failf "%s is not an implementation cmt" cmt_path
  in
  let found = ref None in
  let iter =
    let open Tast_iterator in
    {
      default_iterator with
      expr =
        (fun sub expr ->
          (match expr.exp_desc with
          | Texp_ident (path, _, _) when String.equal (Path.name path) key -> (
              match Types.get_desc expr.exp_type with
              | Types.Tconstr (head, _, _) -> found := Some head
              | _ -> ())
          | _ -> ());
          default_iterator.expr sub expr);
    }
  in
  iter.structure iter structure;
  match !found with
  | Some head -> head
  | None -> failf "no constructor-typed use site %S in the harvested cmt" key

let type_scope () = Scope.v ~resolver:(resolver ()) ~intra:no_intra ~local:[]

let type_tests =
  group "type namespace"
    [
      test "resolve_type walks Sig_type where resolve walks Sig_value"
        (fun () ->
          let r = resolver () in
          is_true ~msg:"a unit-level type resolves"
            (Resolver.resolve_type r (name "Fix_probe.shade") <> []);
          is_true ~msg:"a nested-module type resolves"
            (Resolver.resolve_type r (name "Fix_probe.Tones.tone") <> []);
          is_true ~msg:"a Stdlib type resolves"
            (Resolver.resolve_type r (name "Stdlib.result") <> []);
          equal (list uid_t) ~msg:"namespaces never mix: a value is no type" []
            (Resolver.resolve_type r (name "Fix_probe.direct"));
          equal (list uid_t) ~msg:"namespaces never mix: a type is no value" []
            (Resolver.resolve r (name "Fix_probe.shade"));
          equal (list uid_t) ~msg:"an absent type resolves to nothing" []
            (Resolver.resolve_type r (name "Fix_probe.nope")));
      test "matches_type joins a use-site head to its canonical type" (fun () ->
          let sc = type_scope () in
          let shade = type_head probe3_cmt "Fix_probe.tint" in
          is_true (Scope.matches_type sc (name "Fix_probe.shade") shade);
          is_false (Scope.matches_type sc (name "Fix_probe.Tones.tone") shade);
          let tone = type_head probe3_cmt "Fix_probe.Tones.warm" in
          is_true (Scope.matches_type sc (name "Fix_probe.Tones.tone") tone));
      test "a Stdlib-declared head matches through the cmi walk" (fun () ->
          let sc = type_scope () in
          let res = type_head probe3_cmt "Fix_probe.res_head" in
          is_true (Scope.matches_type sc (name "Stdlib.result") res);
          is_false (Scope.matches_type sc (name "Fix_probe.shade") res);
          is_false ~msg:"predefined option is not the result head"
            (Scope.matches_type sc (name "Stdlib.option") res));
      test "a predefined head matches its Stdlib spelling" (fun () ->
          let sc = type_scope () in
          is_true
            (Scope.matches_type sc (name "Stdlib.option") Predef.path_option);
          is_true (Scope.matches_type sc (name "Stdlib.bool") Predef.path_bool);
          is_false ~msg:"predefined identities stay distinct"
            (Scope.matches_type sc (name "Stdlib.list") Predef.path_option);
          is_false ~msg:"a predefined path is not a declared type"
            (Scope.matches_type sc (name "Stdlib.result") Predef.path_option));
      test "an unresolved name matches no head" (fun () ->
          let sc = type_scope () in
          is_false
            (Scope.matches_type sc
               (name "Nonexistent_unit.t")
               (type_head probe3_cmt "Fix_probe.tint")));
    ]

(* {1 The audit classification} *)

let probe_t =
  Testable.make
    ~pp:(fun ppf c ->
      Format.pp_print_string ppf
        (match c with
        | `Resolved -> "`Resolved"
        | `Absent_unit -> "`Absent_unit"
        | `Unresolved -> "`Unresolved"))
    ~equal:( = )

let probe_tests =
  group "probe"
    [
      test "probe separates the typo signal from an absent unit" (fun () ->
          let r = resolver () in
          equal probe_t `Resolved (Resolver.probe r (name "Stdlib.List.length"));
          equal probe_t `Resolved (Resolver.probe r (name "Fix_probe.direct"));
          equal probe_t ~msg:"leaf typo: the unit is in hand" `Unresolved
            (Resolver.probe r (name "Stdlib.List.lengt"));
          equal probe_t ~msg:"module typo: the unit is in hand" `Unresolved
            (Resolver.probe r (name "Stdlib.Lst.length"));
          equal probe_t ~msg:"no cmi, nothing to audit against" `Absent_unit
            (Resolver.probe r (name "Nonexistent_unit.foo")));
      test "probe_type counts predefined spellings resolved" (fun () ->
          let r = resolver () in
          equal probe_t `Resolved (Resolver.probe_type r (name "Stdlib.option"));
          equal probe_t `Resolved (Resolver.probe_type r (name "Stdlib.result"));
          equal probe_t `Resolved
            (Resolver.probe_type r (name "Fix_probe.shade"));
          equal probe_t ~msg:"a type typo is the same signal" `Unresolved
            (Resolver.probe_type r (name "Fix_probe.nope"));
          equal probe_t ~msg:"namespaces never mix: a value is no type"
            `Unresolved
            (Resolver.probe_type r (name "Fix_probe.direct"));
          equal probe_t `Absent_unit
            (Resolver.probe_type r (name "Nonexistent_unit.t")));
    ]

let () =
  run "litany_ident"
    [
      name_tests;
      ref_tests;
      resolver_tests;
      scope_tests;
      type_tests;
      probe_tests;
    ]
