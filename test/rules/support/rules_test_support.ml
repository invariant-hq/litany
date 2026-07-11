(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap

(* The creation-time literal audit (the registry's one consumer): every
   [ident]/[idents]/[typ] literal of every rule linked into the suite
   binary was recorded at module initialization; a literal probing
   [`Unresolved] — its defining unit's cmi is in hand and the name
   denotes nothing in it — is a typo, named here. [`Absent_unit]
   literals ([Lwt.*] in a workspace without lwt) are out of audit
   reach and pass, per the match-nothing contract. *)
let assert_all_resolve resolver =
  let unresolved probe tag names =
    List.filter_map
      (fun n ->
        match probe resolver n with
        | `Unresolved -> Some (tag ^ Litany.Naming.Name.to_string n)
        | `Resolved | `Absent_unit -> None)
      names
  in
  equal ~msg:"name literals denoting nothing (typo in a hoisted pattern?)"
    (list string) []
    (unresolved Litany.Naming.Resolver.probe "" (Litany.Pat.Registry.names ())
    @ unresolved Litany.Naming.Resolver.probe_type "type "
        (Litany.Pat.Registry.type_names ()))

let report ?cmti ?kind ?visibility rule ~source ~cmt =
  let entry = Litany.Roster.Entry.v ~source ~cmt ?cmti ?kind ?visibility () in
  (* The unix otherlib's cmis live beside the standard library; searching
     them lets suites exercise canonical [Unix.*] names the way a real
     workspace linking unix does. *)
  let unix_dir = Filename.concat Config.standard_library "unix" in
  let resolver =
    Litany.Naming.Resolver.create
      ~cmi_dirs:
        ([ Filename.dirname cmt; Config.standard_library ]
        @ if Sys.file_exists unix_dir then [ unix_dir ] else [])
  in
  assert_all_resolve resolver;
  Litany.Engine.run ~rules:[ rule ] ~catalog:[ rule ]
    ~roster:(Litany.Roster.v [ entry ])
    ~load:(Litany.Unit.load ~resolver ~build_current:true)
    ()

let marker = "(* FIRE *)"

let has_marker line =
  let n = String.length line and m = String.length marker in
  let rec at i =
    i + m <= n && (String.equal (String.sub line i m) marker || at (i + 1))
  in
  at 0

let fire_lines ~source =
  let ic = open_in_bin source in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () ->
      let rec loop n acc =
        match input_line ic with
        | line -> loop (n + 1) (if has_marker line then n :: acc else acc)
        | exception End_of_file -> List.rev acc
      in
      loop 1 [])

let check_markers ?message ?cmti ?kind ?visibility rule ~source ~cmt =
  let rep = report ?cmti ?kind ?visibility rule ~source ~cmt in
  (* A raising rule must read as a failure, not a marker mismatch. *)
  equal ~msg:"rule failures" (list string) []
    (List.map
       (fun (f : Litany.Engine.Report.failure) -> f.rule ^ ": " ^ f.message)
       (Litany.Engine.Report.failures rep));
  equal ~msg:"dropped findings" int 0 (Litany.Engine.Report.dropped rep);
  let name = Litany.Rule.name rule in
  let findings = Litany.Engine.Report.findings rep in
  List.iter (fun (r, _) -> equal ~msg:"emitting rule" string name r) findings;
  (match message with
  | None -> ()
  | Some m ->
      List.iter
        (fun (_, f) -> equal ~msg:"message" string m (Litany.Finding.message f))
        findings);
  equal ~msg:"finding lines vs (* FIRE *) markers" (list int)
    (fire_lines ~source)
    (List.map
       (fun (_, f) -> (Litany.Finding.loc f).Location.loc_start.Lexing.pos_lnum)
       findings)

let shape rep =
  List.map
    (fun (rule, f) ->
      let l = Litany.Finding.loc f in
      ( rule,
        l.Location.loc_start.pos_fname,
        l.Location.loc_start.pos_cnum,
        l.Location.loc_end.pos_cnum ))
    (Litany.Engine.Report.findings rep)

let read_file path = In_channel.with_open_bin path In_channel.input_all

let check_fixed ?(unsafe = false) rule ~source ~cmt ~golden =
  let rep = report rule ~source ~cmt in
  equal ~msg:"rule failures" (list string) []
    (List.map
       (fun (f : Litany.Engine.Report.failure) -> f.rule ^ ": " ^ f.message)
       (Litany.Engine.Report.failures rep));
  equal ~msg:"dropped findings" int 0 (Litany.Engine.Report.dropped rep);
  (* Kept findings plus expected findings: the suites are the sole place
     expected findings' fixes apply, producing the [.fixed] golden. *)
  let findings =
    Litany.Engine.Report.findings rep
    @ List.map (fun (r, f, _) -> (r, f)) (Litany.Engine.Report.expected rep)
  in
  if Litany.Rule.fix rule = Litany.Rule.Always then
    List.iter
      (fun (_, f) ->
        is_true ~msg:"promise is Always: every finding carries a fix"
          (Litany.Finding.fix f <> None))
      findings;
  let plan =
    Litany.Apply.plan ~unsafe
      (List.filter_map
         (fun (rule, f) ->
           Option.map
             (fun fix -> { Litany.Apply.rule; fix })
             (Litany.Finding.fix f))
         findings)
  in
  equal ~msg:"conflicting fixes (a fixture defect: split the fixture)" int 0
    (List.length (Litany.Apply.conflicting plan));
  let fixed =
    Litany.Apply.patch (read_file source)
      (List.concat_map
         (fun (c : Litany.Apply.candidate) -> Litany.Fix.edits c.fix)
         (Litany.Apply.selected plan))
  in
  equal ~msg:"fixed bytes vs the committed golden" string (read_file golden)
    fixed

(* {1 Project-rule suites} *)

type project_unit = {
  pu_source : string;
  pu_cmt : string;
  pu_cmti : string option;
  pu_interface_source : string option;
  pu_library : string;
  pu_visibility : Litany.Roster.visibility;
  pu_kind : Litany.Roster.kind;
}

let project_unit ?cmti ?interface_source ?(library = "fixlib")
    ?(visibility = Litany.Roster.Private) ?(kind = Litany.Roster.Library)
    ~source ~cmt () =
  {
    pu_source = source;
    pu_cmt = cmt;
    pu_cmti = cmti;
    pu_interface_source = interface_source;
    pu_library = library;
    pu_visibility = visibility;
    pu_kind = kind;
  }

let project_entries units =
  List.map
    (fun u ->
      Litany.Roster.Entry.v ~source:u.pu_source ~cmt:u.pu_cmt ?cmti:u.pu_cmti
        ?interface_source:u.pu_interface_source ~library:u.pu_library
        ~visibility:u.pu_visibility ~kind:u.pu_kind ())
    units

let project_resolver units =
  let unix_dir = Filename.concat Config.standard_library "unix" in
  let dirs =
    List.sort_uniq String.compare
      (List.map (fun u -> Filename.dirname u.pu_cmt) units)
  in
  Litany.Naming.Resolver.create
    ~cmi_dirs:
      (dirs
      @ [ Config.standard_library ]
      @ if Sys.file_exists unix_dir then [ unix_dir ] else [])

let project_report ?(complete = true) rules units =
  let resolver = project_resolver units in
  assert_all_resolve resolver;
  Litany.Engine.run ~rules ~catalog:rules
    ~roster:(Litany.Roster.v ~complete (project_entries units))
    ~load:(Litany.Unit.load ~resolver ~build_current:true)
    ()

let check_project_marshal rule units =
  match Litany.Rule.callback rule with
  | Litany.Rule.Project { collect; report } ->
      let resolver = project_resolver units in
      let facts =
        List.concat_map
          (fun entry ->
            match Litany.Unit.load ~resolver ~build_current:true entry with
            | Ok u -> collect u
            | Error sk ->
                failwith
                  (Format.asprintf "fixture unit skipped: %s (%a)"
                     (Litany.Roster.Entry.source entry)
                     Litany.Unit.Skip.pp sk))
          (project_entries units)
      in
      (* [Litany.Rule.project] seals each fact as one Marshal frame inside
         [collect] (no flags: Marshal refuses closures and custom blocks
         outright), so an unmarshalable fact fails right here, in the rule's
         own suite; [report] decodes the frames it is handed — the round
         trip is the seam itself. Frames concatenated once and reported
         twice pin the decode as deterministic. *)
      let view findings =
        List.map
          (fun f ->
            let l = Litany.Finding.loc f in
            ( Litany.Finding.message f,
              l.Location.loc_start.pos_fname,
              l.Location.loc_start.pos_cnum ))
          findings
      in
      equal ~msg:"report over the sealed frames is deterministic"
        (list (triple string string int))
        (view (report facts))
        (view (report facts))
  | _ -> failwith "check_project_marshal: not a project rule"
