(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* Witness logic against real compiled fixtures under fixtures/: fix_wit
   (wit_direct.ml without mli — the cmt leads with a cmi block; wit_mli.ml(i)
   — the cmt starts at the cmt magic), fix_pp (an action preprocessor whose
   output differs from the editable source, so the cmt digests the built
   [.pp.ml]) and fix_ppflag (compiled with [-pp cat], so the flag is in
   [cmt_args] while the digest matches the editable source). Crafted
   artifacts (wrong magic, truncation) are written to temp files. *)

open Windtrap
module Unit = Litany.Unit
module Entry = Litany.Roster.Entry

(* The witness predicate is driver-internal (a non-facade module of the
   litany library, litany_digest0.ml); reach it by its unmangled global name
   rather than widening the gated [Litany.Unit] surface. *)
module Digest0 = Litany.Digest0

let skip_t =
  Testable.make ~pp:Unit.Skip.pp ~equal:(fun (a : Unit.Skip.t) b -> a = b)

let plain_objs = "fixtures/unit/plain/.fix_wit.objs/byte"
let direct_source = "fixtures/unit/plain/wit_direct.ml"
let direct_cmt = plain_objs ^ "/fix_wit__Wit_direct.cmt"
let mli_source = "fixtures/unit/plain/wit_mli.ml"
let mli_cmt = plain_objs ^ "/fix_wit__Wit_mli.cmt"
let mli_cmti = plain_objs ^ "/fix_wit__Wit_mli.cmti"
let incl_source = "fixtures/unit/plain/wit_incl.ml"
let incl_cmt = plain_objs ^ "/fix_wit__Wit_incl.cmt"
let paren_source = "fixtures/unit/plain/wit_paren.ml"
let paren_cmt = plain_objs ^ "/fix_wit__Wit_paren.cmt"
let asc_source = "fixtures/unit/plain/wit_asc.ml"
let asc_cmt = plain_objs ^ "/fix_wit__Wit_asc.cmt"
let pp_source = "fixtures/unit/pp/wit_pp.ml"
let pp_cmt = "fixtures/unit/pp/.fix_pp.objs/byte/fix_pp__Wit_pp.cmt"
let pp_built = "fixtures/unit/pp/wit_pp.pp.ml"
let ppflag_source = "fixtures/unit/pp/wit_ppflag.ml"

let ppflag_cmt =
  "fixtures/unit/pp/.fix_ppflag.objs/byte/fix_ppflag__Wit_ppflag.cmt"

let read_file path = In_channel.with_open_bin path In_channel.input_all
let resolver () = Litany.Naming.Resolver.create ~cmi_dirs:[ plain_objs ]

let load ?(build_current = false) ?resolver:r entry =
  let resolver = match r with Some r -> r | None -> resolver () in
  Unit.load ~resolver ~build_current entry

let require_load ?build_current ?resolver entry =
  require_ok ~pp_error:Unit.Skip.pp (load ?build_current ?resolver entry)

let require_skip ?build_current entry =
  require_error (load ?build_current entry)

(* A file with chosen bytes, deleted on all outcomes. *)
let with_bytes name setup fn =
  bracket ~setup ~teardown:(fun (path, _) -> Sys.remove path) name fn

let crafted bytes () =
  let path = Filename.temp_file "litany-test" ".cmt" in
  Out_channel.with_open_bin path (fun oc -> Out_channel.output_string oc bytes);
  (path, bytes)

let digest_tests =
  group "Digest0"
    [
      test "accepts an MD5 recorded digest" (fun () ->
          is_true
            (Digest0.matches ~recorded:(Digest.MD5.string "bytes") "bytes"));
      test "accepts a BLAKE128 recorded digest" (fun () ->
          is_true
            (Digest0.matches ~recorded:(Digest.BLAKE128.string "bytes") "bytes"));
      test "rejects a digest of other bytes" (fun () ->
          is_false
            (Digest0.matches ~recorded:(Digest.MD5.string "other") "bytes");
          is_false (Digest0.matches ~recorded:(String.make 16 '\000') "bytes"));
      test "md5 is the raw MD5" (fun () ->
          equal string (Digest.MD5.string "bytes") (Digest0.md5 "bytes"));
    ]

let direct_tests =
  group "Direct witness"
    [
      test "admits a unit whose cmt leads with a cmi block" (fun () ->
          let u =
            require_load (Entry.v ~source:direct_source ~cmt:direct_cmt ())
          in
          equal string
            (String.sub (read_file direct_cmt) 0 12)
            Config.cmi_magic_number;
          equal string direct_source (Unit.path u);
          equal string "Fix_wit__Wit_direct" (Unit.name u);
          is_false (Unit.preprocessed u);
          let w = Unit.witness u in
          is_true (Unit.Witness.kind w = Unit.Witness.Direct);
          equal string direct_source (Unit.Witness.anchor w);
          equal string
            (Digest.MD5.string (read_file direct_source))
            (Unit.Witness.source_digest w);
          equal string (read_file direct_source)
            (Litany.Source.contents (Unit.source u)));
      test "admits a unit whose cmt starts at the cmt magic" (fun () ->
          let u = require_load (Entry.v ~source:mli_source ~cmt:mli_cmt ()) in
          equal string
            (String.sub (read_file mli_cmt) 0 12)
            Config.cmt_magic_number;
          equal string "Fix_wit__Wit_mli" (Unit.name u));
      test "re-exposes the roster entry's project metadata" (fun () ->
          let u =
            require_load
              (Entry.v ~source:direct_source ~cmt:direct_cmt ~library:"fix_wit"
                 ~visibility:Litany.Roster.Public ~kind:Litany.Roster.Library ())
          in
          equal (option string) (Some "fix_wit") (Unit.library u);
          is_true (Unit.visibility u = Unit.Public);
          is_true (Unit.kind u = Some Unit.Library));
      test "defaults metadata to absent and Unknown" (fun () ->
          let u =
            require_load (Entry.v ~source:direct_source ~cmt:direct_cmt ())
          in
          equal (option string) None (Unit.library u);
          is_true (Unit.visibility u = Unit.Unknown);
          equal bool true (Unit.kind u = None));
    ]

let skip_tests =
  group "Skips"
    [
      test "an edited source is stale" (fun () ->
          (* Same basename as the recorded source: only the bytes changed.
             A differing basename is the derived-without-anchor case below. *)
          let dir = temp_dir () in
          let path = Filename.concat dir "wit_direct.ml" in
          Out_channel.with_open_bin path (fun oc ->
              Out_channel.output_string oc
                (read_file direct_source ^ "\n(* edited *)\n"));
          equal skip_t Unit.Skip.Stale
            (require_skip (Entry.v ~source:path ~cmt:direct_cmt ())));
      test "a missing source file is missing-source" (fun () ->
          equal skip_t Unit.Skip.Missing_source
            (require_skip
               (Entry.v ~source:"fixtures/unit/plain/absent.ml" ~cmt:direct_cmt
                  ())));
      test "an entry without a cmt is missing-artifact" (fun () ->
          equal skip_t Unit.Skip.Missing_artifact
            (require_skip (Entry.v ~source:mli_source ~cmti:mli_cmti ())));
      test "a nonexistent cmt path is missing-artifact" (fun () ->
          equal skip_t Unit.Skip.Missing_artifact
            (require_skip
               (Entry.v ~source:direct_source ~cmt:(plain_objs ^ "/nope.cmt") ())));
      with_bytes "a foreign magic is wrong-magic, found before any decode"
        (crafted ("Caml1999T099" ^ String.make 64 '\000'))
        (fun (path, _) ->
          match require_skip (Entry.v ~source:direct_source ~cmt:path ()) with
          | Unit.Skip.Wrong_magic { found; expected } ->
              equal string "Caml1999T099" found;
              equal string Config.cmt_magic_number expected
          | sk -> failf "expected wrong-magic, got %a" Unit.Skip.pp sk);
      with_bytes "a truncated artifact with a good magic is unreadable"
        (fun () ->
          let bytes = read_file mli_cmt in
          crafted (String.sub bytes 0 40) ())
        (fun (path, _) ->
          match require_skip (Entry.v ~source:mli_source ~cmt:path ()) with
          | Unit.Skip.Unreadable _ -> ()
          | sk -> failf "expected unreadable, got %a" Unit.Skip.pp sk);
      with_bytes "a file shorter than the magic is unreadable" (crafted "Caml")
        (fun (path, _) ->
          match require_skip (Entry.v ~source:direct_source ~cmt:path ()) with
          | Unit.Skip.Unreadable _ -> ()
          | sk -> failf "expected unreadable, got %a" Unit.Skip.pp sk);
      test "a cmti offered as the cmt is partial-or-packed" (fun () ->
          (* The fixture cmti decodes as Interface annots: a mispaired
             entry, no whole implementation to lint. *)
          equal skip_t Unit.Skip.Partial_or_packed
            (require_skip (Entry.v ~source:mli_source ~cmt:mli_cmti ())));
      test "a bare cmi offered as the cmt is missing-artifact" (fun () ->
          (* A cmi decodes with no typedtree block: no admissible artifact
             was ever there. *)
          equal skip_t Unit.Skip.Missing_artifact
            (require_skip
               (Entry.v ~source:direct_source
                  ~cmt:(plain_objs ^ "/fix_wit.cmi")
                  ())));
    ]

let message_tests =
  group "Skip messages"
    [
      test "known magics render as compiler versions" (fun () ->
          let m =
            Unit.Skip.message
              (Unit.Skip.Wrong_magic
                 { found = "Caml1999T035"; expected = "Caml1999T037" })
          in
          equal string "built by OCaml 5.3; this litany reads 5.5" m);
      test "unknown magics render verbatim" (fun () ->
          contains ~sub:"\"Caml1999T099\""
            (Unit.Skip.message
               (Unit.Skip.Wrong_magic
                  { found = "Caml1999T099"; expected = "Caml1999T036" })));
      test "messages state facts, never dune vocabulary" (fun () ->
          List.iter
            (fun sk ->
              let m = Unit.Skip.message sk in
              is_true ~msg:"non-empty" (String.length m > 0);
              not_contains ~sub:"dune" (String.lowercase_ascii m))
            [
              Unit.Skip.Stale;
              Unit.Skip.Missing_source;
              Unit.Skip.Missing_artifact;
              Unit.Skip.Derived_needs_build;
              Unit.Skip.Unreadable "detail";
              Unit.Skip.Partial_or_packed;
              Unit.Skip.Modified_during_run;
            ]);
    ]

let derived_entry ?pp () =
  Entry.v ~source:pp_source ~cmt:pp_cmt
    ?preprocessed_source:(Some (Option.value pp ~default:pp_built))
    ()

let derived_tests =
  group "Derived witness"
    [
      test "fixture shape: the cmt digests the built pp file" (fun () ->
          is_true
            (Digest0.matches
               ~recorded:(Digest.MD5.string (read_file pp_built))
               (read_file pp_built));
          is_false (String.equal (read_file pp_built) (read_file pp_source)));
      test "joins Derived when the pp digest matches and the build is current"
        (fun () ->
          let u = require_load ~build_current:true (derived_entry ()) in
          let w = Unit.witness u in
          is_true (Unit.Witness.kind w = Unit.Witness.Derived);
          equal string pp_built (Unit.Witness.anchor w);
          equal string
            (Digest.MD5.string (read_file pp_source))
            (Unit.Witness.source_digest w);
          is_true (Unit.preprocessed u));
      test "skips derived-needs-build without build currency" (fun () ->
          equal skip_t Unit.Skip.Derived_needs_build
            (require_skip ~build_current:false (derived_entry ())));
      test "a pp unit without a named pp source has no Derived anchor"
        (fun () ->
          (* fix_pp carries no -pp in cmt_args (dune compiled the built file
             directly), so the Direct digest check fails — but the recorded
             source name ([wit_pp.pp.ml]) is not the supplied source's
             basename: the compiler never read [wit_pp.ml], so this is a
             derived unit with no anchor, not a staleness claim. *)
          equal skip_t Unit.Skip.Missing_artifact
            (require_skip (Entry.v ~source:pp_source ~cmt:pp_cmt ())));
      test "a pp file with the wrong digest is stale" (fun () ->
          equal skip_t Unit.Skip.Stale
            (require_skip ~build_current:true
               (derived_entry ~pp:direct_source ())));
      test "a missing pp file is missing-artifact" (fun () ->
          equal skip_t Unit.Skip.Missing_artifact
            (require_skip ~build_current:true
               (derived_entry ~pp:"fixtures/unit/pp/absent.pp.ml" ())));
      test "-pp in cmt_args without a pp path is missing-artifact" (fun () ->
          equal skip_t Unit.Skip.Missing_artifact
            (require_skip ~build_current:true
               (Entry.v ~source:ppflag_source ~cmt:ppflag_cmt ())));
      test "-pp in cmt_args joins Derived through a named pp file" (fun () ->
          (* ocamlc -pp digests the editable source itself, so the editable
             file doubles as the pp anchor here. *)
          let u =
            require_load ~build_current:true
              (Entry.v ~source:ppflag_source ~cmt:ppflag_cmt
                 ~preprocessed_source:ppflag_source ())
          in
          is_true (Unit.Witness.kind (Unit.witness u) = Unit.Witness.Derived);
          is_true (Unit.preprocessed u));
    ]

let substrate_tests =
  group "Substrates"
    [
      test "implementation is the typedtree of the fixture" (fun () ->
          let u =
            require_load (Entry.v ~source:direct_source ~cmt:direct_cmt ())
          in
          is_true ((Unit.implementation u).Typedtree.str_items <> []));
      test "interface decodes on demand from the cmti" (fun () ->
          let u =
            require_load
              (Entry.v ~source:mli_source ~cmt:mli_cmt ~cmti:mli_cmti ())
          in
          is_some (Unit.interface u));
      test "interface is None without a cmti" (fun () ->
          let u = require_load (Entry.v ~source:mli_source ~cmt:mli_cmt ()) in
          is_true (Unit.interface u = None));
      with_bytes "an unreadable cmti degrades to None, not a skip"
        (crafted ("Caml1999T099" ^ String.make 64 '\000'))
        (fun (path, _) ->
          let u =
            require_load (Entry.v ~source:mli_source ~cmt:mli_cmt ~cmti:path ())
          in
          is_true (Unit.interface u = None));
      with_bytes "a stale cmti fails its witness check and degrades to None"
        (crafted "val edited_since_the_build : int\n")
        (fun (mli_path, mli_bytes) ->
          (* The real cmti beside interface bytes it was not built from: the
             recorded source digest cannot match, so the decode degrades
             exactly like an unreadable cmti — and the export rows fall to
             the derived case (the hidden helper appears), never to rows a
             stale artifact fabricates. *)
          let u =
            require_load
              (Entry.v ~source:mli_source ~cmt:mli_cmt ~cmti:mli_cmti
                 ~interface_source:mli_path ())
          in
          is_true ~msg:"the stale cmti must not decode" (Unit.interface u = None);
          equal ~msg:"exports fall to the derived rows" (list string)
            [ "exported"; "internal_helper"; "shout" ]
            (List.map Unit.Export.name (Unit.exports u));
          (* Guard: the paired-mli text lane is untouched — it lints the
             exact bytes read at load and never consults the cmti. *)
          match Unit.interface_source u with
          | None -> fail "expected the interface source"
          | Some isrc -> equal string mli_bytes (Litany.Source.contents isrc));
      test "a cmti matching the interface source passes the witness check"
        (fun () ->
          let u =
            require_load
              (Entry.v ~source:mli_source ~cmt:mli_cmt ~cmti:mli_cmti
                 ~interface_source:"fixtures/unit/plain/wit_mli.mli" ())
          in
          is_some (Unit.interface u);
          equal ~msg:"interface rows follow the mli" (list string)
            [ "exported"; "shout" ]
            (List.map Unit.Export.name (Unit.exports u)));
      test "interface_source is read at load when the entry names one"
        (fun () ->
          let u =
            require_load
              (Entry.v ~source:mli_source ~cmt:mli_cmt ~cmti:mli_cmti
                 ~interface_source:"fixtures/unit/plain/wit_mli.mli" ())
          in
          match Unit.interface_source u with
          | None -> fail "expected the interface source"
          | Some isrc ->
              equal string "fixtures/unit/plain/wit_mli.mli"
                (Litany.Source.path isrc);
              equal string
                (read_file "fixtures/unit/plain/wit_mli.mli")
                (Litany.Source.contents isrc));
      test "interface_source is None when unnamed, absent when unreadable"
        (fun () ->
          let u = require_load (Entry.v ~source:mli_source ~cmt:mli_cmt ()) in
          is_true (Unit.interface_source u = None);
          let u =
            require_load
              (Entry.v ~source:mli_source ~cmt:mli_cmt
                 ~interface_source:"fixtures/unit/plain/no-such.mli" ())
          in
          is_true (Unit.interface_source u = None));
      test "parsetree is the engine's own parse, cached" (fun () ->
          let u =
            require_load (Entry.v ~source:direct_source ~cmt:direct_cmt ())
          in
          is_some (Unit.parsetree u);
          is_true ~msg:"same value on the second call"
            (Unit.parsetree u == Unit.parsetree u));
    ]

(* [bound_expr u name] is the expression bound to the top-level variable
   [name] in [u]'s implementation. *)
let bound_expr u =
  let bindings =
    List.concat_map
      (fun (item : Typedtree.structure_item) ->
        match item.str_desc with
        | Tstr_value (_, vbs) ->
            List.filter_map
              (fun (vb : Typedtree.value_binding) ->
                match vb.vb_pat.pat_desc with
                | Tpat_var (id, _, _) -> Some (Ident.name id, vb.vb_expr)
                | _ -> None)
              vbs
        | _ -> [])
      (Unit.implementation u).str_items
  in
  fun name ->
    match List.assoc_opt name bindings with
    | Some e -> e
    | None -> fail ("no binding " ^ name ^ " in the fixture")

let splice_tests =
  group "splice"
    [
      test "atomic expressions splice bare, compound ones wrap" (fun () ->
          let u =
            require_load (Entry.v ~source:direct_source ~cmt:direct_cmt ())
          in
          let spliced =
            List.filter_map
              (fun (item : Typedtree.structure_item) ->
                match item.str_desc with
                | Tstr_value (_, vbs) ->
                    Some
                      (List.filter_map
                         (fun (vb : Typedtree.value_binding) ->
                           Unit.splice u vb.vb_expr)
                         vbs)
                | _ -> None)
              (Unit.implementation u).str_items
            |> List.concat
          in
          (* wit_direct.ml: [let answer = 42], [let double x = x * 2],
             [let sum = 1 + 2]. *)
          is_true ~msg:"42 stays bare" (List.mem "42" spliced);
          is_true ~msg:"1 + 2 is wrapped" (List.mem "(1 + 2)" spliced));
      test "preprocessed units never slice" (fun () ->
          let u = require_load ~build_current:true (derived_entry ()) in
          List.iter
            (fun (item : Typedtree.structure_item) ->
              match item.str_desc with
              | Tstr_value (_, vbs) ->
                  List.iter
                    (fun (vb : Typedtree.value_binding) ->
                      is_true (Unit.splice u vb.vb_expr = None))
                    vbs
              | _ -> ())
            (Unit.implementation u).str_items);
      test "parenthesized sees the author's delimiters, parens or begin/end"
        (fun () ->
          let u =
            require_load (Entry.v ~source:paren_source ~cmt:paren_cmt ())
          in
          let e = bound_expr u in
          is_true ~msg:"(1 + 2)" (Unit.parenthesized u (e "paren"));
          is_true ~msg:"begin 1 + 2 end" (Unit.parenthesized u (e "block"));
          is_false ~msg:"1 + 2" (Unit.parenthesized u (e "bare"));
          (* Framing only, no pairing scan: a wrong [true] is a harmless
             pair, a wrong [false] a broken program. *)
          is_true ~msg:"(1) + (2) frames"
            (Unit.parenthesized u (e "framed_both"));
          is_false ~msg:"an identifier starting with begin"
            (Unit.parenthesized u (e "begin_prefix"));
          is_false ~msg:"an identifier ending with end"
            (Unit.parenthesized u (e "end_suffix")));
      test "delimited restores the pair around non-atomic text only" (fun () ->
          let u =
            require_load (Entry.v ~source:paren_source ~cmt:paren_cmt ())
          in
          let e = bound_expr u in
          equal string "(f x)" (Unit.delimited u (e "paren") "f x");
          equal string "(f x)" (Unit.delimited u (e "block") "f x");
          equal string "(xs = [])" (Unit.delimited u (e "paren") "xs = []");
          equal ~msg:"atomic text needs no pair" string "x"
            (Unit.delimited u (e "paren") "x");
          equal ~msg:"already bracketed text needs no pair" string "(g y)"
            (Unit.delimited u (e "paren") "(g y)");
          equal ~msg:"an undelimited original passes through" string "f x"
            (Unit.delimited u (e "bare") "f x"));
    ]

let name s =
  require_ok ~pp_error:Litany.Naming.Name.pp_error
    (Litany.Naming.Name.of_string s)

(* Use sites of one cmt as [(Path.name, val_uid)] pairs — the compiler is the
   oracle for the uids use sites carry (test_ident's harvest, repeated here
   so the shipped [Litany.Unit.load] path is what builds the scope). *)
let harvest cmt_path =
  let structure =
    match Cmt_format.read cmt_path with
    | _, Some { Cmt_format.cmt_annots = Implementation str; _ } -> str
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

let scope_tests =
  group "Scope"
    [
      test "the loaded scope resolves canonical names" (fun () ->
          let r = resolver () in
          let u =
            require_load ~resolver:r
              (Entry.v ~source:mli_source ~cmt:mli_cmt ())
          in
          let shout = name "Fix_wit.Wit_mli.shout" in
          match Litany.Naming.Resolver.resolve r shout with
          | [] -> fail "resolver found no uid for Fix_wit.Wit_mli.shout"
          | uid :: _ ->
              is_true (Litany.Naming.Scope.matches (Unit.scope u) shout uid));
      test "the loaded scope carries the intra-unit bridge" (fun () ->
          let r = resolver () in
          let u =
            require_load ~resolver:r
              (Entry.v ~source:mli_source ~cmt:mli_cmt ())
          in
          let shout = name "Fix_wit.Wit_mli.shout" in
          let canonical =
            match Litany.Naming.Resolver.resolve r shout with
            | uid :: _ -> uid
            | [] -> fail "unresolved"
          in
          let deps =
            match Cmt_format.read mli_cmt with
            | _, Some infos -> infos.Cmt_format.cmt_declaration_dependencies
            | _ -> fail "cannot re-read the fixture cmt"
          in
          let impl_uid =
            match
              List.find_map
                (fun (_, def, decl) ->
                  if Shape.Uid.equal decl canonical then Some def else None)
                deps
            with
            | Some uid -> uid
            | None -> fail "no def->decl pair for shout in the fixture"
          in
          is_true ~msg:"impl uid matched through the bridge"
            (Litany.Naming.Scope.matches (Unit.scope u) shout impl_uid);
          (* A different unit's scope knows the canonical uid but not this
             unit's impl uid. *)
          let other =
            require_load ~resolver:r
              (Entry.v ~source:direct_source ~cmt:direct_cmt ())
          in
          is_false
            (Litany.Naming.Scope.matches (Unit.scope other) shout impl_uid));
      test "the bridge spans an mli-side include's foreign declaration"
        (fun () ->
          (* wit_incl.mli is [include Wit_sigs.S]: the canonical uid of [v]
             is Wit_sigs's interface item, this unit's own use of [v] an
             impl uid. The def->decl pair's declaration side is foreign, so
             a both-sides-same-unit filter would refuse it and the unit's
             own uses would never match — the hole the def-side filter
             closes. *)
          let r = resolver () in
          let u =
            require_load ~resolver:r
              (Entry.v ~source:incl_source ~cmt:incl_cmt ())
          in
          let v = name "Fix_wit.Wit_incl.v" in
          let intra_use = use_site (harvest incl_cmt) "v" in
          is_false ~msg:"resolver alone misses the impl use"
            (Litany.Naming.Scope.matches
               (Litany.Naming.Scope.v ~resolver:r
                  ~intra:(fun _ -> [])
                  ~local:[])
               v intra_use);
          is_true ~msg:"the loaded scope bridges it"
            (Litany.Naming.Scope.matches (Unit.scope u) v intra_use));
      test "the shipped filter refuses the ascription's cross-unit pair"
        (fun () ->
          (* wit_asc's ascription records a def->decl pair whose definition
             side is Stdlib__List's interface item. First prove the trap is
             really in this cmt, then that the scope built by the shipped
             loader refuses it: the ascribed name must not match the unit's
             direct List.length uses. *)
          let deps =
            match Cmt_format.read asc_cmt with
            | _, Some infos -> infos.Cmt_format.cmt_declaration_dependencies
            | _ -> fail "cannot re-read the fixture cmt"
          in
          is_true ~msg:"fixture records a foreign-def pair"
            (List.exists
               (fun (_, (def : Shape.Uid.t), _) ->
                 match def with
                 | Item { comp_unit; _ } ->
                     not (String.equal comp_unit "Fix_wit__Wit_asc")
                 | _ -> false)
               deps);
          let u = require_load (Entry.v ~source:asc_source ~cmt:asc_cmt ()) in
          let asc = name "Fix_wit.Wit_asc.Asc.length" in
          let occs = harvest asc_cmt in
          is_true ~msg:"the ascribed name matches its own use"
            (Litany.Naming.Scope.matches (Unit.scope u) asc
               (use_site occs "Asc.length"));
          is_false ~msg:"and never the foreign identity"
            (Litany.Naming.Scope.matches (Unit.scope u) asc
               (use_site occs "Stdlib.List.length")));
    ]

(* {1 The use index} *)

let uses_source = "fixtures/unit/plain/wit_uses.ml"
let uses_cmt = plain_objs ^ "/fix_wit__Wit_uses.cmt"

(* [bound_uid u name] is the declaration uid of the unique variable
   pattern spelled [name] in [u]'s implementation — the join key a
   pattern rule would hand to [Unit.uses]. [Tpat_var]'s shape is stable
   across the support window (verified 5.3.0/5.4.1/5.5.0). *)
let bound_uid u var =
  let found = ref None in
  let default = Tast_iterator.default_iterator in
  let iterator =
    {
      default with
      Tast_iterator.pat =
        (fun (type k) sub (p : k Typedtree.general_pattern) ->
          (match p.pat_desc with
          | Typedtree.Tpat_var (id, _, uid)
            when String.equal (Ident.name id) var ->
              found := Some uid
          | _ -> ());
          default.pat sub p);
    }
  in
  iterator.structure iterator (Unit.implementation u);
  match !found with
  | Some uid -> uid
  | None -> failf "no variable pattern %S in the fixture" var

let uses_tests =
  group "uses"
    [
      test "counts every use of a declaration, in traversal order" (fun () ->
          let u = require_load (Entry.v ~source:uses_source ~cmt:uses_cmt ()) in
          let locs = Unit.uses u (bound_uid u "base") in
          equal ~msg:"two uses in [twice], one in [localized]" int 3
            (List.length locs);
          let offsets =
            List.map (fun (l : Location.t) -> l.loc_start.pos_cnum) locs
          in
          is_true ~msg:"traversal order is source order here"
            (List.sort compare offsets = offsets));
      test "a qualified use through a module path joins by uid" (fun () ->
          let u = require_load (Entry.v ~source:uses_source ~cmt:uses_cmt ()) in
          equal int 2 (List.length (Unit.uses u (bound_uid u "hidden"))));
      test "an unused declaration has no uses" (fun () ->
          let u = require_load (Entry.v ~source:uses_source ~cmt:uses_cmt ()) in
          equal int 0 (List.length (Unit.uses u (bound_uid u "unused"))));
      test "repeated queries return the cached index" (fun () ->
          let u = require_load (Entry.v ~source:uses_source ~cmt:uses_cmt ()) in
          let uid = bound_uid u "inner" in
          let first = Unit.uses u uid in
          equal int 1 (List.length first);
          is_true ~msg:"same list on the second call" (first == Unit.uses u uid));
    ]

(* {1 The module-use index} *)

let muses_source = "fixtures/unit/plain/wit_muses.ml"
let muses_cmt = plain_objs ^ "/fix_wit__Wit_muses.cmt"

let muses_unit () =
  require_load (Entry.v ~source:muses_source ~cmt:muses_cmt ())

(* Named module idents of the fixture, in binding order. *)
let module_idents u =
  let acc = ref [] in
  let default = Tast_iterator.default_iterator in
  let iterator =
    {
      default with
      Tast_iterator.structure_item =
        (fun sub item ->
          (match item.Typedtree.str_desc with
          | Typedtree.Tstr_module mb -> (
              match mb.Typedtree.mb_id with
              | Some id -> acc := id :: !acc
              | None -> ())
          | _ -> ());
          default.structure_item sub item);
    }
  in
  iterator.structure iterator (Unit.implementation u);
  List.rev !acc

let module_ident u nm =
  match
    List.filter (fun i -> String.equal (Ident.name i) nm) (module_idents u)
  with
  | [ id ] -> id
  | [] -> failf "no module binding named %S" nm
  | ids -> failf "%d module bindings named %S" (List.length ids) nm

(* [covered locs sub] is [true] iff some recorded use lies inside the
   first occurrence of [sub] in the fixture — assertions never hand-count
   bytes. *)
let covered locs sub =
  let s = read_file muses_source in
  let n = String.length s and m = String.length sub in
  let rec at i =
    if i + m > n then failf "%S does not occur in %s" sub muses_source
    else if String.sub s i m = sub then i
    else at (i + 1)
  in
  let start = at 0 in
  let stop = start + m in
  List.exists
    (fun (l : Location.t) ->
      l.loc_start.pos_cnum >= start && l.loc_end.pos_cnum <= stop)
    locs

let module_uses_tests =
  group "module_uses"
    [
      test "every carrier form records a use of M" (fun () ->
          let u = muses_unit () in
          let locs = Unit.module_uses u (module_ident u "M") in
          List.iter
            (fun sub -> is_true ~msg:sub (covered locs sub))
            [
              (* expression ident *)
              "M.f 1";
              (* open *)
              "open M";
              (* include *)
              "include M";
              (* alias *)
              "module A = M";
              (* functor argument *)
              "F2 (M)";
              (* first-class pack *)
              "(module M.Inner : M.S)";
              (* Tmty_ident *)
              "module Y : M.S";
              (* Tmty_alias *)
              "module A2 = M";
              (* Ttyp_constr *)
              "leaf : M.t";
              (* pattern-side constructor *)
              "M.Leaf ->";
              (* expression-side constructor *)
              "M.C8 3";
              (* pattern-side constructor argument form *)
              "(M.C8 n)";
              (* construction label *)
              "{ M.lab = 4 }";
              (* field-access label *)
              "r.M.lab";
              (* setfield label *)
              "x.mf <- 5";
              (* pattern-side label *)
              "{ M.lab = l0 }";
              (* Texp_new *)
              "new M.cl";
              (* Tcl_ident *)
              "class sub = M.cl";
              (* Tcty_constr *)
              "class type ct2 = M.cl";
              (* Ttyp_open *)
              "M.(t)";
              (* Tpat_open *)
              "M.(Leaf)";
              (* Tpat_type *)
              "#M.vt";
              (* Ttyp_package *)
              "(module M.S)";
              (* Texp_extension_constructor *)
              "[%extension_constructor M.E]";
              (* Text_rebind *)
              "exception E2 = M.E";
              (* expression-side extension constructor (tag path) *)
              "raise M.E";
              (* pattern-side extension constructor (tag path) *)
              "M.E -> 0";
            ]);
      test "an unmentioned module has no uses" (fun () ->
          let u = muses_unit () in
          equal int 0
            (List.length (Unit.module_uses u (module_ident u "Quiet"))));
      test "a same-spelled rebinding joins by identity, not name" (fun () ->
          let u = muses_unit () in
          match
            List.filter
              (fun i -> String.equal (Ident.name i) "Shadow")
              (module_idents u)
          with
          | [ first; second ] ->
              is_false ~msg:"two distinct idents" (Ident.same first second);
              let uses_first = Unit.module_uses u first in
              let uses_second = Unit.module_uses u second in
              equal ~msg:"one use each" int 1 (List.length uses_first);
              equal int 1 (List.length uses_second);
              is_true ~msg:"first Shadow's use precedes the rebinding"
                (covered uses_first "Shadow.s1");
              is_true ~msg:"second Shadow's use follows it"
                (covered uses_second "Shadow.s2")
          | ids -> failf "%d Shadow bindings" (List.length ids));
      test "repeated queries return the cached index" (fun () ->
          let u = muses_unit () in
          let id = module_ident u "M" in
          is_true ~msg:"same list on the second call"
            (Unit.module_uses u id == Unit.module_uses u id));
    ]

(* {1 The export index} *)

let export_source = "fixtures/unit/plain/wit_export.ml"
let export_cmt = plain_objs ^ "/fix_wit__Wit_export.cmt"
let export_cmti = plain_objs ^ "/fix_wit__Wit_export.cmti"
let incl_cmti = plain_objs ^ "/fix_wit__Wit_incl.cmti"
let user_source = "fixtures/unit/plain/wit_user.ml"
let user_cmt = plain_objs ^ "/fix_wit__Wit_user.cmt"

let export_row u nm =
  match
    List.find_opt
      (fun x -> String.equal (Unit.Export.name x) nm)
      (Unit.exports u)
  with
  | Some x -> x
  | None -> failf "no export row %S" nm

let export_names u = List.map Unit.Export.name (Unit.exports u)

let resolve_one r nm =
  match Litany.Naming.Resolver.resolve r (name nm) with
  | uid :: _ -> uid
  | [] -> failf "resolver found no uid for %s" nm

let comp_unit_of (uid : Shape.Uid.t) =
  match uid with
  | Item { comp_unit; _ } -> comp_unit
  | Compilation_unit cu -> cu
  | _ -> failf "uid %a has no compilation unit" Shape.Uid.print uid

let exports_tests =
  group "exports"
    [
      test "interface-sourced rows follow the mli, not the implementation"
        (fun () ->
          (* wit_export.ml declares [scale]; the mli hides it. Signature
             order, a module row before its members'. *)
          let u =
            require_load
              (Entry.v ~source:export_source ~cmt:export_cmt ~cmti:export_cmti
                 ())
          in
          equal (list string) [ "t"; "make"; "Sub"; "Sub.x" ] (export_names u);
          is_true (Unit.Export.kind (export_row u "t") = Unit.Export.Type);
          is_true (Unit.Export.kind (export_row u "make") = Unit.Export.Value);
          is_true (Unit.Export.kind (export_row u "Sub") = Unit.Export.Module);
          is_true (Unit.Export.kind (export_row u "Sub.x") = Unit.Export.Value);
          equal ~msg:"locs point into the mli" string "wit_export.mli"
            (Filename.basename
               (Unit.Export.loc (export_row u "make")).loc_start.pos_fname));
      test "interface uids are the canonical identities" (fun () ->
          let r = resolver () in
          let u =
            require_load ~resolver:r
              (Entry.v ~source:export_source ~cmt:export_cmt ~cmti:export_cmti
                 ())
          in
          is_true ~msg:"make's row carries the uid the resolver walks to"
            (Shape.Uid.equal
               (Unit.Export.uid (export_row u "make"))
               (resolve_one r "Fix_wit.Wit_export.make")));
      test "a no-mli unit's derived rows are the definition identities"
        (fun () ->
          let u =
            require_load (Entry.v ~source:direct_source ~cmt:direct_cmt ())
          in
          equal (list string) [ "answer"; "double"; "sum" ] (export_names u);
          is_true ~msg:"answer's row is its variable pattern's uid"
            (Shape.Uid.equal
               (Unit.Export.uid (export_row u "answer"))
               (bound_uid u "answer")));
      test "an export row's uid is the uses join key" (fun () ->
          (* wit_uses: [M.hidden] is used twice; the nested derived row's
             uid keys straight into the use index. *)
          let u = require_load (Entry.v ~source:uses_source ~cmt:uses_cmt ()) in
          is_true (Unit.Export.kind (export_row u "M") = Unit.Export.Module);
          equal int 2
            (List.length
               (Unit.uses u (Unit.Export.uid (export_row u "M.hidden")))));
      test "an mli-side include exports the foreign interface identity"
        (fun () ->
          let r = resolver () in
          let u =
            require_load ~resolver:r
              (Entry.v ~source:incl_source ~cmt:incl_cmt ~cmti:incl_cmti ())
          in
          let v = export_row u "v" in
          equal string "Fix_wit__Wit_sigs" (comp_unit_of (Unit.Export.uid v));
          is_true ~msg:"and it is the canonical uid of Fix_wit.Wit_incl.v"
            (Shape.Uid.equal (Unit.Export.uid v)
               (resolve_one r "Fix_wit.Wit_incl.v")));
      test "an ascription's rows keep the minted identities" (fun () ->
          let u = require_load (Entry.v ~source:asc_source ~cmt:asc_cmt ()) in
          is_true (Unit.Export.kind (export_row u "Asc") = Unit.Export.Module);
          let length = export_row u "Asc.length" in
          equal ~msg:"minted in this unit, never the ascribee's" string
            "Fix_wit__Wit_asc"
            (comp_unit_of (Unit.Export.uid length));
          is_false
            (Shape.Uid.equal (Unit.Export.uid length)
               (use_site (harvest asc_cmt) "Stdlib.List.length")));
      test "without the cmti the derived rows over-approximate" (fun () ->
          (* The documented degradation: an mli-backed unit whose entry
             names no cmti falls back to the derived signature, so hidden
             values appear and uids are definition identities. *)
          let hidden =
            require_load
              (Entry.v ~source:mli_source ~cmt:mli_cmt ~cmti:mli_cmti ())
          in
          is_false (List.mem "internal_helper" (export_names hidden));
          let degraded =
            require_load (Entry.v ~source:mli_source ~cmt:mli_cmt ())
          in
          is_true (List.mem "internal_helper" (export_names degraded)));
      test "repeated queries return the cached list, loads are deterministic"
        (fun () ->
          let load_rows () =
            let u =
              require_load
                (Entry.v ~source:export_source ~cmt:export_cmt ~cmti:export_cmti
                   ())
            in
            is_true ~msg:"same list on the second call"
              (Unit.exports u == Unit.exports u);
            List.map
              (fun x ->
                (Unit.Export.name x, Format.asprintf "%a" Unit.Export.pp x))
              (Unit.exports u)
          in
          equal (list (pair string string)) (load_rows ()) (load_rows ()));
    ]

(* {1 Outgoing references} *)

let dep_rows u =
  List.map (fun d -> (Unit.Dep.unit_name d, Unit.Dep.uid d)) (Unit.deps u)

let has_dep u unit_name uid =
  List.exists
    (fun d ->
      String.equal (Unit.Dep.unit_name d) unit_name
      && Shape.Uid.equal (Unit.Dep.uid d) uid)
    (Unit.deps u)

let deps_tests =
  group "deps"
    [
      test "cross-unit value uses join by declaration uid" (fun () ->
          (* wit_user calls Wit_mli.shout: the dep row carries the interface
             uid the resolver walks to — the item-level join key. *)
          let r = resolver () in
          let u =
            require_load ~resolver:r
              (Entry.v ~source:user_source ~cmt:user_cmt ())
          in
          is_true
            (has_dep u "Fix_wit__Wit_mli"
               (resolve_one r "Fix_wit.Wit_mli.shout")));
      test "a dep row joins the target unit's export row" (fun () ->
          (* wit_user reads Wit_direct.answer; wit_direct has no mli, so the
             dep uid is exactly the export row's definition uid. *)
          let user =
            require_load (Entry.v ~source:user_source ~cmt:user_cmt ())
          in
          let target =
            require_load (Entry.v ~source:direct_source ~cmt:direct_cmt ())
          in
          is_true
            (has_dep user "Fix_wit__Wit_direct"
               (Unit.Export.uid (export_row target "answer"))));
      test "unresolved occurrences contribute unit_refs names" (fun () ->
          (* Local reduction leaves cross-unit projections unresolved; their
             head units surface in [unit_refs], never as [deps] rows. *)
          let u = require_load (Entry.v ~source:user_source ~cmt:user_cmt ()) in
          is_true ~msg:"the library wrapper heads the projections"
            (List.mem "Fix_wit" (Unit.unit_refs u));
          is_true (List.mem "Stdlib" (Unit.unit_refs u));
          List.iter
            (fun d ->
              is_true ~msg:"every dep row pins a declaration"
                (match Unit.Dep.uid d with
                | Shape.Uid.Item _ -> true
                | _ -> false))
            (Unit.deps u));
      test "the mli include's foreign interface is a dep" (fun () ->
          let u = require_load (Entry.v ~source:incl_source ~cmt:incl_cmt ()) in
          is_true
            (List.exists
               (fun d ->
                 String.equal (Unit.Dep.unit_name d) "Fix_wit__Wit_sigs")
               (Unit.deps u)));
      test "the ascription's foreign definition is a dep" (fun () ->
          let u = require_load (Entry.v ~source:asc_source ~cmt:asc_cmt ()) in
          is_true
            (has_dep u "Stdlib__List"
               (use_site (harvest asc_cmt) "Stdlib.List.length")));
      test "same-unit identities never appear" (fun () ->
          List.iter
            (fun (source, cmt) ->
              let u = require_load (Entry.v ~source ~cmt ()) in
              List.iter
                (fun d ->
                  is_false ~msg:"no dep names the unit itself"
                    (String.equal (Unit.Dep.unit_name d) (Unit.name u)))
                (Unit.deps u);
              List.iter
                (fun cu ->
                  is_false ~msg:"no unit_ref names the unit itself"
                    (String.equal cu (Unit.name u)))
                (Unit.unit_refs u))
            [ (user_source, user_cmt); (asc_source, asc_cmt) ]);
      test "rows are deduplicated and sorted" (fun () ->
          (* wit_asc records Stdlib__List.length twice — as the ascription's
             declaration-dependency def side and as a use-index key — and
             once must survive. Strict ascending order implies both. *)
          let check u =
            let rec strictly_ascending = function
              | (n1, u1) :: ((n2, u2) :: _ as rest) ->
                  let c =
                    match String.compare n1 n2 with
                    | 0 -> Shape.Uid.compare u1 u2
                    | c -> c
                  in
                  is_true ~msg:"strictly ascending" (c < 0);
                  strictly_ascending rest
              | _ -> ()
            in
            strictly_ascending (dep_rows u)
          in
          check (require_load (Entry.v ~source:asc_source ~cmt:asc_cmt ()));
          check (require_load (Entry.v ~source:user_source ~cmt:user_cmt ())));
      test "repeated queries return the cached rows, loads are deterministic"
        (fun () ->
          let load_rows () =
            let u =
              require_load (Entry.v ~source:user_source ~cmt:user_cmt ())
            in
            is_true ~msg:"same list on the second call"
              (Unit.deps u == Unit.deps u);
            is_true ~msg:"same names on the second call"
              (Unit.unit_refs u == Unit.unit_refs u);
            List.map (fun d -> Format.asprintf "%a" Unit.Dep.pp d) (Unit.deps u)
            @ Unit.unit_refs u
          in
          equal (list string) (load_rows ()) (load_rows ()));
    ]

let pp_tests =
  group "pp"
    [
      test "Witness.pp names the kind and anchor" (fun () ->
          let u =
            require_load (Entry.v ~source:direct_source ~cmt:direct_cmt ())
          in
          let rendered =
            Format.asprintf "%a" Unit.Witness.pp (Unit.witness u)
          in
          contains ~sub:"direct" rendered;
          contains ~sub:direct_source rendered);
      test "Skip.pp formats the message" (fun () ->
          equal string
            (Unit.Skip.message Unit.Skip.Stale)
            (Format.asprintf "%a" Unit.Skip.pp Unit.Skip.Stale));
    ]

(* The generated-unit classification — [.ml-gen] paths and lex/yacc
   line-directive markers classify; hand-written sources (and cppo-style
   directives naming .ml files) never do. The lex fixture is real ocamllex
   output, admitted under the ordinary Direct witness. *)
let generated_tests =
  let lex_source = "fixtures/unit/lex/wit_lex.ml" in
  let lex_cmt = "fixtures/unit/lex/.wit_lex.objs/byte/wit_lex.cmt" in
  group "generated classification"
    [
      test "ocamllex output classifies generated by its line directives"
        (fun () ->
          let u = require_load (Entry.v ~source:lex_source ~cmt:lex_cmt ()) in
          is_true ~msg:"admits Direct like any unit"
            (Unit.Witness.kind (Unit.witness u) = Unit.Witness.Direct);
          equal
            ~msg:"classifies generated, the marker naming the directive's file"
            (option string) (Some "line directive names wit_lex.mll")
            (Unit.generated u));
      test "a hand-written source does not classify generated" (fun () ->
          let u =
            require_load (Entry.v ~source:direct_source ~cmt:direct_cmt ())
          in
          equal (option string) None (Unit.generated u));
      test "a directive naming a .ml file does not classify" (fun () ->
          (* cppo and ppx dumps carry [# N "foo.ml"] directives over
             hand-written, editable sources — those keep linting. The pp
             fixture's editable source is the probe: inject nothing, just
             assert the loaded pp unit stays unclassified. *)
          let entry =
            Entry.v ~source:pp_source ~cmt:pp_cmt ~preprocessed_source:pp_built
              ()
          in
          let u = require_load ~build_current:true entry in
          equal (option string) None (Unit.generated u));
      test "a quoted directive line classifies — named, never anonymous"
        (fun () ->
          (* The trap/control fixture pair: the marker scan is lexical, so a
             hand-written file whose only [.mll] mention is a directive
             line quoted in a string literal classifies too — a documented
             false positive, accepted until a string/comment-aware scan is
             warranted. What this pins is the honesty consequence: the
             classification carries a marker naming its cause, so the
             report and [--list-units] can attribute the reclassification
             instead of leaving an anonymous facts-only count. The control
             (same shape, no directive line) stays unclassified. *)
          let trap =
            require_load
              (Entry.v ~source:"fixtures/unit/plain/wit_trap.ml"
                 ~cmt:(plain_objs ^ "/fix_wit__Wit_trap.cmt")
                 ())
          in
          equal
            ~msg:
              "the trap classifies (lexical scan, known FP), the marker naming \
               the quoted file"
            (option string) (Some "line directive names lexer.mll")
            (Unit.generated trap);
          let ctrl =
            require_load
              (Entry.v ~source:"fixtures/unit/plain/wit_ctrl.ml"
                 ~cmt:(plain_objs ^ "/fix_wit__Wit_ctrl.cmt")
                 ())
          in
          equal ~msg:"the control stays unclassified" (option string) None
            (Unit.generated ctrl));
    ]

let () =
  run "litany_unit"
    [
      digest_tests;
      direct_tests;
      skip_tests;
      message_tests;
      derived_tests;
      substrate_tests;
      splice_tests;
      scope_tests;
      uses_tests;
      module_uses_tests;
      exports_tests;
      deps_tests;
      generated_tests;
      pp_tests;
    ]
