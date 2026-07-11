(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* The unit-file codec, [Litany.Adapter.Unit_file].

   The golden [.units] fixtures are hand-crafted bytes (length prefixes
   computed independently of the encoder), so both directions are pinned:
   decode is checked against the roster the fixture spells, and encode of
   that same roster must reproduce the fixture byte for byte. Error cases
   pin offset and reason exactly; properties check the round trip over
   arbitrary path bytes, non-UTF-8 included. *)

open Windtrap
module Unit_file = Litany.Adapter.Unit_file
module Roster = Litany.Roster
module Entry = Litany.Roster.Entry

let read file = In_channel.with_open_bin file In_channel.input_all
let header = "(12:litany-units1:1)\n"

let decode_ok ?msg bytes =
  require_ok ?msg ~pp_error:Unit_file.pp_error (Unit_file.decode bytes)

let decode_err ?msg bytes = require_error ?msg (Unit_file.decode bytes)

(* Structural roster equality through the public accessors — [Roster.t] is
   abstract and deliberately exposes no [equal]. *)
let entry_repr e =
  ( Entry.source e,
    Entry.cmt e,
    Entry.cmti e,
    Entry.preprocessed_source e,
    Entry.interface_source e,
    Entry.library e,
    Entry.visibility e,
    Entry.kind e )

let roster_repr r =
  (Roster.complete r, Roster.cmi_dirs r, List.map entry_repr (Roster.entries r))

let equal_roster ?msg a b = is_true ?msg (roster_repr a = roster_repr b)

(* {1 Golden rosters}

   The in-memory twins of the fixtures, used by both decode and encode
   golden tests. *)

let minimal_roster =
  Roster.v ~complete:true
    [
      Entry.v ~source:"lib/foo.ml"
        ~cmt:"_build/default/lib/.foo.objs/byte/foo.cmt" ();
    ]

let full_roster =
  Roster.v ~complete:true
    ~cmi_dirs:[ "_build/default/lib/.a.objs/byte"; "/opt/my libs/stdlib" ]
    [
      Entry.v ~source:"lib/a.ml" ~cmt:"_build/default/lib/.a.objs/byte/a.cmt"
        ~cmti:"_build/default/lib/.a.objs/byte/a.cmti"
        ~preprocessed_source:"_build/default/lib/a.pp.ml"
        ~interface_source:"lib/a.mli" ~library:"a" ~visibility:Roster.Public
        ~kind:Roster.Library ();
      Entry.v ~source:"bin/m.ml" ~cmt:"_build/default/bin/.m.eobjs/byte/m.cmt"
        ~library:"m" ~visibility:Roster.Private ~kind:Roster.Executable ();
      Entry.v ~source:"test/t.ml" ~cmt:"_build/default/test/.t.objs/byte/t.cmt"
        ~library:"t" ~kind:Roster.Test ();
    ]

let partial_roster =
  Roster.v ~complete:false
    [
      Entry.v ~source:"lib/iface.mli"
        ~cmti:"_build/default/lib/.i.objs/byte/iface.cmti" ();
    ]

let bytes_roster =
  Roster.v ~complete:true ~cmi_dirs:[ "dirs/\xff\xfe" ]
    [
      Entry.v ~source:"lib/caf\xe9.ml" ~cmt:"lib/caf\xe9.cmt" ();
      Entry.v ~source:"we(ird\n5:).ml" ~cmt:"w.cmt" ();
    ]

let goldens =
  [
    ("golden_minimal.units", minimal_roster);
    ("golden_full.units", full_roster);
    ("golden_partial.units", partial_roster);
    ("golden_bytes.units", bytes_roster);
  ]

let decode_golden_tests =
  group "decode golden"
    [
      test "minimal: source and cmt only, complete by default" (fun () ->
          let r = decode_ok (read "golden_minimal.units") in
          is_true ~msg:"complete" (Roster.complete r);
          equal (list string) [] (Roster.cmi_dirs r);
          match Roster.entries r with
          | [ e ] ->
              equal string "lib/foo.ml" (Entry.source e);
              equal (option string)
                (Some "_build/default/lib/.foo.objs/byte/foo.cmt") (Entry.cmt e);
              equal (option string) None (Entry.cmti e);
              equal (option string) None (Entry.preprocessed_source e);
              equal (option string) None (Entry.library e);
              is_true ~msg:"visibility" (Entry.visibility e = Roster.Unknown);
              is_true ~msg:"kind" (Entry.kind e = None)
          | es -> failf "expected one entry, got %d" (List.length es));
      test "full: cmi-dirs and every unit field" (fun () ->
          let r = decode_ok (read "golden_full.units") in
          is_true ~msg:"complete" (Roster.complete r);
          equal (list string)
            [ "_build/default/lib/.a.objs/byte"; "/opt/my libs/stdlib" ]
            (Roster.cmi_dirs r);
          is_true ~msg:"project capable" (Roster.project_capable r);
          match Roster.entries r with
          | [ a; m; t ] ->
              equal string "lib/a.ml" (Entry.source a);
              equal (option string)
                (Some "_build/default/lib/.a.objs/byte/a.cmti") (Entry.cmti a);
              equal (option string) (Some "_build/default/lib/a.pp.ml")
                (Entry.preprocessed_source a);
              equal (option string) (Some "lib/a.mli")
                (Entry.interface_source a);
              equal (option string) (Some "a") (Entry.library a);
              is_true ~msg:"a public" (Entry.visibility a = Roster.Public);
              is_true ~msg:"a kind" (Entry.kind a = Some Roster.Library);
              is_true ~msg:"m private" (Entry.visibility m = Roster.Private);
              is_true ~msg:"m kind" (Entry.kind m = Some Roster.Executable);
              is_true ~msg:"t unknown" (Entry.visibility t = Roster.Unknown);
              is_true ~msg:"t kind" (Entry.kind t = Some Roster.Test)
          | es -> failf "expected three entries, got %d" (List.length es));
      test "partial: (complete false) and a cmti-only unit" (fun () ->
          let r = decode_ok (read "golden_partial.units") in
          is_false ~msg:"complete" (Roster.complete r);
          match Roster.entries r with
          | [ e ] ->
              equal string "lib/iface.mli" (Entry.source e);
              is_true ~msg:"no cmt" (Entry.cmt e = None);
              equal (option string)
                (Some "_build/default/lib/.i.objs/byte/iface.cmti")
                (Entry.cmti e)
          | es -> failf "expected one entry, got %d" (List.length es));
      test "bytes: non-UTF-8 and csexp-hostile path bytes survive" (fun () ->
          let r = decode_ok (read "golden_bytes.units") in
          equal (list string) [ "dirs/\xff\xfe" ] (Roster.cmi_dirs r);
          equal (list string)
            [ "lib/caf\xe9.ml"; "we(ird\n5:).ml" ]
            (List.map Entry.source (Roster.entries r)));
      test "a header alone is an empty complete roster" (fun () ->
          let r = decode_ok header in
          is_true (Roster.complete r);
          equal (list string) [] (Roster.cmi_dirs r);
          equal int 0 (List.length (Roster.entries r)));
      test "(complete true) states the default explicitly" (fun () ->
          let r = decode_ok (header ^ "(8:complete4:true)\n") in
          is_true (Roster.complete r));
      test "whitespace between top-level forms is tolerated" (fun () ->
          let r =
            decode_ok
              ("  \r\n" ^ header ^ "\n\n(4:unit(6:source4:a.ml)(3:cmt3:a.c))")
          in
          equal int 1 (List.length (Roster.entries r)));
    ]

let encode_golden_tests =
  group "encode golden"
    [
      test "encode reproduces every fixture byte for byte" (fun () ->
          List.iter
            (fun (file, roster) ->
              equal string ~msg:file (read file) (Unit_file.encode roster))
            goldens);
      test "encode is a fixpoint on canonical files" (fun () ->
          List.iter
            (fun (file, _) ->
              let bytes = read file in
              equal string ~msg:file bytes
                (Unit_file.encode (decode_ok ~msg:file bytes)))
            goldens);
      test "encode is byte-identical across runs" (fun () ->
          List.iter
            (fun (file, roster) ->
              equal string ~msg:file (Unit_file.encode roster)
                (Unit_file.encode roster))
            goldens);
      test "encode refuses a duplicate source" (fun () ->
          let r =
            Roster.v
              [
                Entry.v ~source:"a.ml" ~cmt:"a.cmt" ();
                Entry.v ~source:"a.ml" ~cmt:"b.cmt" ();
              ]
          in
          raises_match (Exn.invalid_arg ~substring:"duplicate source")
            (fun () -> Unit_file.encode r));
    ]

(* {1 Errors}

   Every refusal pinned: offsets computed by construction from the input
   bytes, reasons byte-exact. *)

let unit_a = "(4:unit(6:source4:a.ml)(3:cmt5:a.cmt))"

let check_err ?msg bytes ~offset ~reason =
  let e = decode_err ?msg bytes in
  equal int ~msg:"offset" offset e.Unit_file.offset;
  equal string ~msg:"reason" reason e.Unit_file.reason

let error_tests =
  group "errors"
    [
      test "empty input" (fun () ->
          check_err "" ~offset:0
            ~reason:"empty file: expected a (litany-units 1) header");
      test "whitespace-only input" (fun () ->
          check_err " \n " ~offset:0
            ~reason:"empty file: expected a (litany-units 1) header");
      test "wrong header form" (fun () ->
          check_err "(3:foo)" ~offset:0
            ~reason:"expected a (litany-units 1) header");
      test "header is an atom" (fun () ->
          check_err "5:hello" ~offset:0
            ~reason:"expected a (litany-units 1) header");
      test "unsupported version" (fun () ->
          check_err "(12:litany-units1:2)" ~offset:16
            ~reason:"unsupported version 2: this Litany reads version 1");
      test "duplicate header" (fun () ->
          check_err (header ^ header) ~offset:(String.length header)
            ~reason:"duplicate (litany-units ...) header");
      test "unclosed list" (fun () ->
          check_err (header ^ "(4:unit") ~offset:(String.length header)
            ~reason:"unclosed list");
      test "lying length prefix" (fun () ->
          check_err (header ^ "(99:x)")
            ~offset:(String.length header + 4)
            ~reason:"atom extends past end of input");
      test "no length prefix" (fun () ->
          check_err (header ^ "x") ~offset:(String.length header)
            ~reason:"expected a length prefix");
      test "unmatched close paren" (fun () ->
          check_err (header ^ ")") ~offset:(String.length header)
            ~reason:"unmatched ')'");
      test "top-level atom" (fun () ->
          check_err (header ^ "3:foo") ~offset:(String.length header)
            ~reason:"expected a form (a list), not an atom");
      test "empty form" (fun () ->
          check_err (header ^ "()") ~offset:(String.length header)
            ~reason:"form must begin with a keyword atom");
      test "unknown form" (fun () ->
          check_err (header ^ "(5:bogus)") ~offset:(String.length header)
            ~reason:
              "unknown form \"bogus\": expected (unit ...), (complete ...), or \
               (cmi-dirs ...)");
      test "unknown field" (fun () ->
          let prefix = "(4:unit(6:source4:a.ml)(3:cmt5:a.cmt)" in
          check_err
            (header ^ prefix ^ "(5:extra1:x))")
            ~offset:(String.length header + String.length prefix)
            ~reason:"unknown field \"extra\" in unit form");
      test "duplicate field" (fun () ->
          let prefix = "(4:unit(6:source4:a.ml)(3:cmt5:a.cmt)" in
          check_err
            (header ^ prefix ^ "(3:cmt5:b.cmt))")
            ~offset:(String.length header + String.length prefix)
            ~reason:"duplicate \"cmt\" field in unit form");
      test "missing source" (fun () ->
          check_err
            (header ^ "(4:unit(3:cmt5:a.cmt))")
            ~offset:(String.length header)
            ~reason:"unit form missing its source field");
      test "neither cmt nor cmti" (fun () ->
          check_err
            (header ^ "(4:unit(6:source4:a.ml))")
            ~offset:(String.length header)
            ~reason:"unit form for \"a.ml\" names neither cmt nor cmti");
      test "duplicate source" (fun () ->
          check_err
            (header ^ unit_a ^ "\n" ^ unit_a)
            ~offset:(String.length header + String.length unit_a + 1)
            ~reason:"duplicate unit for source \"a.ml\"");
      test "malformed public value" (fun () ->
          let prefix = "(4:unit(6:source4:a.ml)(3:cmt5:a.cmt)(6:public" in
          check_err
            (header ^ prefix ^ "3:yes))")
            ~offset:(String.length header + String.length prefix)
            ~reason:"expected true or false for public");
      test "malformed kind value" (fun () ->
          let prefix = "(4:unit(6:source4:a.ml)(3:cmt5:a.cmt)(4:kind" in
          check_err
            (header ^ prefix ^ "6:module))")
            ~offset:(String.length header + String.length prefix)
            ~reason:"expected lib, exe, or test for kind");
      test "field without a value" (fun () ->
          check_err
            (header ^ "(4:unit(6:source))")
            ~offset:(String.length header + 7)
            ~reason:"expected a two-atom (field value) pair in unit form");
      test "complete after a unit form" (fun () ->
          check_err
            (header ^ unit_a ^ "\n(8:complete5:false)")
            ~offset:(String.length header + String.length unit_a + 1)
            ~reason:"(complete ...) must precede unit forms");
      test "cmi-dirs after a unit form" (fun () ->
          check_err
            (header ^ unit_a ^ "\n(8:cmi-dirs3:dir)")
            ~offset:(String.length header + String.length unit_a + 1)
            ~reason:"(cmi-dirs ...) must precede unit forms");
      test "duplicate complete form" (fun () ->
          check_err
            (header ^ "(8:complete5:false)\n(8:complete4:true)")
            ~offset:(String.length header + 20)
            ~reason:"duplicate (complete ...) form");
      test "duplicate cmi-dirs form" (fun () ->
          check_err
            (header ^ "(8:cmi-dirs)\n(8:cmi-dirs)")
            ~offset:(String.length header + 13)
            ~reason:"duplicate (cmi-dirs ...) form");
      test "malformed complete payload" (fun () ->
          check_err (header ^ "(8:complete)") ~offset:(String.length header)
            ~reason:"expected (complete true) or (complete false)");
      test "non-atom cmi-dirs entry" (fun () ->
          check_err
            (header ^ "(8:cmi-dirs(3:foo))")
            ~offset:(String.length header + 11)
            ~reason:"cmi-dirs entries must be atoms");
      test "pp_error names the byte offset" (fun () ->
          let e = decode_err "" in
          equal string
            "unit file: byte 0: empty file: expected a (litany-units 1) header"
            (Format.asprintf "%a" Unit_file.pp_error e));
    ]

(* {1 Round-trip properties}

   Paths are arbitrary bytes — the whole point of csexp over JSON — so the
   generator draws from the full byte range: non-UTF-8 sequences, parens,
   digits, colons, and newlines all land inside atoms. *)

let gen_path = Gen.(string_of ~size:(int_range 0 12) (char_range '\x00' '\xff'))
let gen_vis = Gen.of_list [ Roster.Public; Roster.Private; Roster.Unknown ]
let gen_kind = Gen.of_list [ Roster.Library; Roster.Executable; Roster.Test ]

let gen_entry =
  let open Gen in
  let* which = of_list [ `Cmt; `Cmti; `Both ] in
  let+ source = gen_path
  and+ a = gen_path
  and+ b = gen_path
  and+ preprocessed_source = option gen_path
  and+ interface_source = option gen_path
  and+ library = option gen_path
  and+ visibility = gen_vis
  and+ kind = option gen_kind in
  let cmt, cmti =
    match which with
    | `Cmt -> (Some a, None)
    | `Cmti -> (None, Some a)
    | `Both -> (Some a, Some b)
  in
  Entry.v ~source ?cmt ?cmti ?preprocessed_source ?interface_source ?library
    ~visibility ?kind ()

let with_source source e =
  Entry.v ~source ?cmt:(Entry.cmt e) ?cmti:(Entry.cmti e)
    ?preprocessed_source:(Entry.preprocessed_source e)
    ?interface_source:(Entry.interface_source e) ?library:(Entry.library e)
    ~visibility:(Entry.visibility e) ?kind:(Entry.kind e) ()

(* Sources are made distinct by an index prefix (itself csexp-hostile bytes:
   digits and a colon) — [decode] refuses duplicate sources, so a decodable
   roster cannot carry them. *)
let gen_roster =
  let open Gen in
  let+ complete = bool
  and+ cmi_dirs = list ~size:(int_range 0 4) gen_path
  and+ entries = list ~size:(int_range 0 6) gen_entry in
  let entries =
    List.mapi
      (fun i e -> with_source (string_of_int i ^ ":" ^ Entry.source e) e)
      entries
  in
  Roster.v ~complete ~cmi_dirs entries

let property_tests =
  group "round trip"
    [
      prop "decode inverts encode" gen_roster (fun r ->
          equal_roster ~msg:"decode (encode r) = r" r
            (decode_ok (Unit_file.encode r)));
      prop "encode is deterministic and a codec fixpoint" gen_roster (fun r ->
          let bytes = Unit_file.encode r in
          equal string ~msg:"deterministic" bytes (Unit_file.encode r);
          equal string ~msg:"fixpoint" bytes
            (Unit_file.encode (decode_ok bytes)));
      test "non-UTF-8 path bytes round-trip losslessly" (fun () ->
          let r =
            Roster.v ~complete:false ~cmi_dirs:[ "\xff\xfe\x00" ]
              [
                Entry.v ~source:"a/\xc3\x28\xa0\xa1.ml" ~cmt:"\x80.cmt"
                  ~library:"caf\xe9" ();
              ]
          in
          equal_roster r (decode_ok (Unit_file.encode r)));
    ]

let () =
  run "litany_adapter_unit_file"
    [ decode_golden_tests; encode_golden_tests; error_tests; property_tests ]
