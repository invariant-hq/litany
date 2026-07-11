(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

module Witness = struct
  type kind = Direct | Derived
  type t = { kind : kind; anchor : string; source_digest : string }

  let kind w = w.kind
  let anchor w = w.anchor
  let source_digest w = w.source_digest

  let pp ppf w =
    Format.fprintf ppf "@[<h>%s witness on %s (source digest %s)@]"
      (match w.kind with Direct -> "direct" | Derived -> "derived")
      w.anchor
      (Digest.to_hex w.source_digest)
end

module Skip = struct
  type t =
    | Stale
    | Wrong_magic of { found : string; expected : string }
    | Missing_source
    | Missing_artifact
    | Derived_needs_build
    | Unreadable of string
    | Partial_or_packed
    | Modified_during_run

  (* One exhaustive match is the whole slug table: a new skip arm fails to
     compile here instead of silently vanishing from the machine
     vocabulary. The rank is the declaration-order sort key summary
     listings group by. *)
  let rank_slug = function
    | Stale -> (0, "stale")
    | Wrong_magic _ -> (1, "wrong-magic")
    | Missing_source -> (2, "missing-source")
    | Missing_artifact -> (3, "missing-artifact")
    | Derived_needs_build -> (4, "derived-needs-build")
    | Unreadable _ -> (5, "unreadable")
    | Partial_or_packed -> (6, "partial-or-packed")
    | Modified_during_run -> (7, "modified-during-run")

  let slug sk = snd (rank_slug sk)
  let rank sk = fst (rank_slug sk)

  (* Known cmt/cmi magic numbers, rendered as compiler versions in
     [message]. cmi and cmt numbers move in lockstep; 036 and 037 are
     verified against the 5.4.1 and 5.5.0 sources in the lock, 035 is the
     5.3 release value. Anything else renders verbatim. *)
  let generation m =
    if
      String.length m = 12
      && String.starts_with ~prefix:"Caml1999" m
      && (m.[8] = 'I' || m.[8] = 'T')
    then Some (String.sub m 9 3)
    else None

  let version_of_magic m =
    match generation m with
    | None -> None
    | Some "035" -> Some "5.3"
    | Some "036" -> Some "5.4"
    | Some "037" -> Some "5.5"
    | Some _ -> None

  let same_generation m m' =
    match (generation m, generation m') with
    | Some g, Some g' -> String.equal g g'
    | None, None -> String.equal m m'
    | Some _, None | None, Some _ -> false

  let message = function
    | Stale -> "stale — the source changed since the compiler read it"
    | Wrong_magic { found; expected } -> (
        match (version_of_magic found, version_of_magic expected) with
        | Some f, Some e ->
            Printf.sprintf "built by OCaml %s; this litany reads %s" f e
        | None, Some e ->
            Printf.sprintf "built with magic %S; this litany reads OCaml %s"
              found e
        | Some f, None ->
            Printf.sprintf "built by OCaml %s; this litany reads magic %S" f
              expected
        | None, None ->
            Printf.sprintf "built with magic %S; this litany reads %S" found
              expected)
    | Missing_source -> "missing source — the source file cannot be read"
    | Missing_artifact -> "missing artifact — no cmt to admit for this unit"
    | Derived_needs_build ->
        "derived unit — no build-currency evidence for its preprocessed source"
    | Unreadable detail -> "unreadable artifact — " ^ detail
    | Partial_or_packed ->
        "partial or packed artifact — no whole implementation to lint"
    | Modified_during_run ->
        "modified during run — the source changed after it was admitted"

  let pp ppf sk = Format.pp_print_string ppf (message sk)
end

(* {1 The loader edge}

   Everything below and including [load] is the one place artifact bytes are
   read and Marshal-decoded. Exceptions from compiler-libs decoding are
   mapped to skips here and never escape. *)

let read_file path =
  match In_channel.with_open_bin path In_channel.input_all with
  | contents -> Some contents
  | exception Sys_error _ -> None

(* The cheap precheck: 12 bytes, no decode — wrong-generation artifacts
   were measured at 67% of a real shared store and must cost ~0.2 ms, not a
   decode attempt. A cmt whose module has no mli leads with a cmi block, so both of
   this compiler's magics admit; any other leading magic is a foreign
   generation. *)
let precheck_magic cmt_path =
  let len = String.length Config.cmt_magic_number in
  match
    In_channel.with_open_bin cmt_path (fun ic -> really_input_string ic len)
  with
  | exception Sys_error _ -> Error Skip.Missing_artifact
  | exception End_of_file -> Error (Skip.Unreadable "truncated artifact")
  | magic ->
      if
        String.equal magic Config.cmt_magic_number
        || String.equal magic Config.cmi_magic_number
      then Ok ()
      else
        Error
          (Skip.Wrong_magic
             { found = magic; expected = Config.cmt_magic_number })

let decode_cmt cmt_path =
  match Cmt_format.read cmt_path with
  | _, Some cmt -> Ok cmt
  | _, None ->
      (* The file decodes as a bare cmi: no typedtree was ever there. *)
      Error Skip.Missing_artifact
  | exception Cmi_format.Error _ ->
      Error (Skip.Unreadable "artifact failed to decode")
  | exception Cmt_format.Error (Not_a_typedtree detail) ->
      Error (Skip.Unreadable ("not a typedtree: " ^ detail))
  | exception End_of_file -> Error (Skip.Unreadable "truncated artifact")
  | exception Failure detail -> Error (Skip.Unreadable detail)
  | exception Sys_error detail -> Error (Skip.Unreadable detail)

(* The intra-unit bridge: inside the defining unit, use sites carry
   implementation uids, so each canonical (interface) uid this unit
   implements is extended with its [cmt_declaration_dependencies] reverse
   image. The filter is load-bearing: only [Definition_to_declaration] pairs
   whose definition side is an [Impl] [Item] of the linted unit and whose
   declaration side is an [Intf] [Item] — of any unit, because an [.mli] that
   [include]s a foreign signature declares its values under the foreign
   unit's interface uids. Ascriptions record pairs whose definition side is a
   foreign [Intf] item; admitting them would silently rewrite foreign
   identities, and the def side alone refuses them. *)
let intra_of_cmt (cmt : Cmt_format.cmt_infos) =
  let unit_name = cmt.cmt_modname in
  let tbl = Shape.Uid.Tbl.create 8 in
  List.iter
    (fun (dep_kind, def, decl) ->
      if Dep_kind.is_definition_to_declaration dep_kind then
        match ((def : Shape.Uid.t), (decl : Shape.Uid.t)) with
        | ( Item { comp_unit = def_unit; from = Unit_info.Impl; _ },
            Item { from = Unit_info.Intf; _ } )
          when String.equal def_unit unit_name ->
            Shape.Uid.Tbl.add tbl decl def
        | _ -> ())
    cmt.cmt_declaration_dependencies;
  if Shape.Uid.Tbl.length tbl = 0 then fun _ -> []
  else fun uid -> Shape.Uid.Tbl.find_all tbl uid

let args_have flag args = Array.exists (String.equal flag) args

(* The witness join, the flat three-way decision the mli states. Direct when
   the compiler read the editable source itself: no pp anchor named and no
   [-pp] in [cmt_args] — [-ppx] alone transforms the AST of the editable
   source, so such units join Direct. [-pp] with no named pp file has no
   Derived anchor at all. On a Direct digest miss, the recorded source name
   ([recorded_source], consulted as a string only — never resolved as a
   path) discriminates genuine staleness from a unit whose compiler input
   was a derived file the entry does not name ([*.pp.ml], [*.ml-gen],
   menhir outputs): such a unit has no Derived anchor either, and "the
   source changed" would be false — the compiler never read it. *)
let join_witness ~build_current ~recorded ~recorded_source ~path ~contents
    ~pp_arg entry =
  match (Roster.Entry.preprocessed_source entry, pp_arg) with
  | None, false -> (
      match Digest0.admit ~recorded contents with
      | Some source_digest ->
          Ok { Witness.kind = Witness.Direct; anchor = path; source_digest }
      | None ->
          let derived_unnamed =
            match recorded_source with
            | None -> false
            | Some recorded_source ->
                not
                  (String.equal
                     (Filename.basename recorded_source)
                     (Filename.basename path))
          in
          if derived_unnamed then Error Skip.Missing_artifact
          else Error Skip.Stale)
  | None, true -> Error Skip.Missing_artifact
  | Some pp_path, _ -> (
      match read_file pp_path with
      | None -> Error Skip.Missing_artifact
      | Some pp_contents ->
          if not (Digest0.matches ~recorded pp_contents) then Error Skip.Stale
          else if not build_current then Error Skip.Derived_needs_build
          else
            Ok
              {
                Witness.kind = Witness.Derived;
                anchor = pp_path;
                source_digest = Digest0.md5 contents;
              })

(* {1 Exported declarations} *)

module Export = struct
  type kind = Value | Type | Module | Exception
  type t = { uid : Shape.Uid.t; name : string; kind : kind; loc : Location.t }

  let uid x = x.uid
  let name x = x.name
  let kind x = x.kind
  let loc x = x.loc

  let pp ppf x =
    Format.fprintf ppf "@[<h>%s %s (%a)@]"
      (match x.kind with
      | Value -> "value"
      | Type -> "type"
      | Module -> "module"
      | Exception -> "exception")
      x.name Shape.Uid.print x.uid
end

(* {1 Outgoing references} *)

module Dep = struct
  type t = { unit_name : string; uid : Shape.Uid.t }

  let unit_name d = d.unit_name
  let uid d = d.uid

  let compare a b =
    match String.compare a.unit_name b.unit_name with
    | 0 -> Shape.Uid.compare a.uid b.uid
    | c -> c

  let pp ppf d =
    Format.fprintf ppf "@[<h>%s (%a)@]" d.unit_name Shape.Uid.print d.uid
end

(* {1 Units} *)

type visibility = Roster.visibility = Public | Private | Unknown
type kind = Roster.kind = Library | Executable | Test

(* Demand-gated substrate cache: [Not_loaded] until first access, then the
   answer, including a remembered [None]. *)
type 'a demand = Not_loaded | Loaded of 'a

(* The two cmt tables [deps] reads, kept exactly as decoded until the first
   [deps] call computes the rows and releases them. [Dep_kind.kind] is the
   version seam for the pair type's first component (the type moved modules
   at 5.5); the values are never inspected — both kinds' foreign sides are
   references. *)
type raw_tables = {
  decl_deps : (Dep_kind.kind * Shape.Uid.t * Shape.Uid.t) list;
  occurrences : (Longident.t Location.loc * Shape_reduce.result) list;
}

(* Item rows and unit-level reference names, computed together from the raw
   tables (ALT-PROJ-05: [deps] carries declaration-pinned rows only; the
   unit-level residue is [unit_refs]). *)
type deps_state =
  | Deps_raw of raw_tables
  | Deps_done of Dep.t list * string list

(* The generated-unit classification. Generated units (ocamllex, menhir,
   [(rule)] outputs) are not admission failures — they admit normally and
   take the facts-only outcome, because findings must not anchor in files
   the user cannot edit. Until build systems declare their generated
   outputs to the adapter, the closest sound rule reads the admitted bytes
   themselves: a source
   whose path ends in [.ml-gen] (dune-generated alias modules), or whose
   digest-verified bytes carry an OCaml line directive [# N "file"] naming
   an [.mll]/[.mly] file, identifies itself as ocamllex/menhir output.
   cppo and ppx outputs also carry line directives, but those name [.ml]
   files — hand-written, editable sources that must keep linting.

   The scan is lexical — raw bytes, no string/comment awareness — so a
   hand-written file *quoting* a directive line in a string literal
   classifies too (realistic exactly where litany operates: lexer-generator
   test suites, codegen goldens). The classification is
   therefore never anonymous: [generated]'s marker names what classified the
   unit, the engine notes it per unit in the report, and [--list-units]
   prints it — a user whose hand-written file went facts-only can see why
   without diffing counts. A top-of-file restriction would not fix the FP
   (real ocamllex output can place its first directive hundreds of lines
   in — recall requires the whole-file scan); string/comment-aware
   lexing is the sound refinement if the named residue ever bites. *)
let lex_yacc_directive contents =
  let len = String.length contents in
  let rec next_line i =
    match String.index_from_opt contents i '\n' with
    | None -> None
    | Some j -> at_line_start (j + 1)
  and at_line_start i =
    if i >= len then None
    else if contents.[i] = '#' then directive (i + 1)
    else next_line i
  and directive i =
    let digits = ref (skip_blanks i) in
    let start = !digits in
    while
      !digits < len && '0' <= contents.[!digits] && contents.[!digits] <= '9'
    do
      incr digits
    done;
    if !digits = start then next_line i
    else
      let k = skip_blanks !digits in
      if k < len && contents.[k] = '"' then
        match String.index_from_opt contents (k + 1) '"' with
        | None -> None
        | Some q ->
            let file = String.sub contents (k + 1) (q - k - 1) in
            if
              Filename.check_suffix file ".mll"
              || Filename.check_suffix file ".mly"
            then Some file
            else next_line q
      else next_line i
  and skip_blanks i =
    if i < len && (contents.[i] = ' ' || contents.[i] = '\t') then
      skip_blanks (i + 1)
    else i
  in
  at_line_start 0

let generated_marker_of ~path ~contents =
  if Filename.check_suffix path ".ml-gen" then Some "path ends in .ml-gen"
  else
    match lex_yacc_directive contents with
    | Some file ->
        (* Basename only: directives can carry whole build-tree paths, and
           the marker's job is naming the generator's input, not echoing a
           layout. *)
        Some (Printf.sprintf "line directive names %s" (Filename.basename file))
    | None -> None

type t = {
  path : string;
  name : string;
  source : Source.t;
  interface_source : Source.t option;
  witness : Witness.t;
  generated_marker : string option;
  preprocessed : bool;
  library : string option;
  visibility : visibility;
  kind : kind option;
  implementation : Typedtree.structure;
  cmti : string option;
  scope : Naming.Scope.t;
  intra : Shape.Uid.t -> Shape.Uid.t list;
  mutable interface : Typedtree.signature option demand;
  mutable parsetree : Parsetree.structure option demand;
  mutable uses : Location.t list Shape.Uid.Tbl.t demand;
  mutable module_uses : Location.t list Ident.Tbl.t demand;
  mutable exports : Export.t list demand;
  mutable deps : deps_state;
}
(* Decode-and-drop: of the decoded [cmt_infos] a unit retains only
   [cmt_modname], the [Implementation] typedtree (the substrate itself), the
   filtered intra-unit uid table (a few entries), the [-pp]/[-ppx] bit from
   [cmt_args], and — until the first [deps] call computes and replaces them —
   the declaration-dependency and occurrence tables. The heavy rest —
   [cmt_initial_env], [cmt_uid_to_decl], the load path — is unreachable once
   [load] returns, so RSS stays bounded when the driver streams units. *)

let load ~resolver ~build_current entry =
  match Roster.Entry.cmt entry with
  | None -> Error Skip.Missing_artifact
  | Some cmt_path -> (
      match precheck_magic cmt_path with
      | Error _ as e -> e
      | Ok () -> (
          match decode_cmt cmt_path with
          | Error _ as e -> e
          | Ok cmt -> (
              match cmt.cmt_annots with
              | Packed _ | Interface _ | Partial_implementation _
              | Partial_interface _ ->
                  Error Skip.Partial_or_packed
              | Implementation implementation -> (
                  let path = Roster.Entry.source entry in
                  match read_file path with
                  | None -> Error Skip.Missing_source
                  | Some contents -> (
                      match cmt.cmt_source_digest with
                      | None ->
                          Error (Skip.Unreadable "no source digest recorded")
                      | Some recorded -> (
                          let pp_arg = args_have "-pp" cmt.cmt_args in
                          match
                            join_witness ~build_current ~recorded
                              ~recorded_source:cmt.cmt_sourcefile ~path
                              ~contents ~pp_arg entry
                          with
                          | Error _ as e -> e
                          | Ok witness ->
                              let intra = intra_of_cmt cmt in
                              Ok
                                {
                                  path;
                                  name = cmt.cmt_modname;
                                  source = Source.v ~path contents;
                                  interface_source =
                                    (* Read once, here — the loader is the
                                       IO place. The text lane needs no
                                       witness: its findings anchor in the
                                       exact bytes read, so staleness cannot
                                       misattribute; an unreadable named
                                       interface is absent, and the text
                                       lane sees nothing there. These bytes
                                       are also the [interface] substrate's
                                       witness: the demand-gated cmti decode
                                       checks its recorded source digest
                                       against them. *)
                                    (match
                                       Roster.Entry.interface_source entry
                                     with
                                    | None -> None
                                    | Some ipath ->
                                        Option.map
                                          (fun bytes ->
                                            Source.v ~path:ipath bytes)
                                          (read_file ipath));
                                  witness;
                                  generated_marker =
                                    generated_marker_of ~path ~contents;
                                  preprocessed =
                                    witness.Witness.kind = Derived
                                    || pp_arg
                                    || args_have "-ppx" cmt.cmt_args;
                                  library = Roster.Entry.library entry;
                                  visibility = Roster.Entry.visibility entry;
                                  kind = Roster.Entry.kind entry;
                                  implementation;
                                  cmti = Roster.Entry.cmti entry;
                                  scope =
                                    Naming.Scope.v ~resolver ~intra
                                      ~local:implementation.Typedtree.str_type;
                                  intra;
                                  interface = Not_loaded;
                                  parsetree = Not_loaded;
                                  uses = Not_loaded;
                                  module_uses = Not_loaded;
                                  exports = Not_loaded;
                                  deps =
                                    Deps_raw
                                      {
                                        decl_deps =
                                          cmt.cmt_declaration_dependencies;
                                        occurrences = cmt.cmt_ident_occurrences;
                                      };
                                }))))))

(* {1 Queries} *)

let path u = u.path
let name u = u.name
let source u = u.source
let interface_source u = u.interface_source
let witness u = u.witness
let generated u = u.generated_marker
let preprocessed u = u.preprocessed
let library u = u.library
let visibility u = u.visibility
let kind u = u.kind
let implementation u = u.implementation
let scope u = u.scope

(* {1 Demand-gated substrates} *)

let interface u =
  match u.interface with
  | Loaded v -> v
  | Not_loaded ->
      let v =
        match u.cmti with
        | None -> None
        | Some cmti_path -> (
            (* An unreadable or wrong-magic cmti degrades to [None]. A
               decodable one is witness-checked against the paired interface
               source read at load: a cmti whose recorded source digest no
               longer matches the [.mli] bytes describes an interface the
               user has since edited, and its rows would be fabricated
               inputs — stale degrades to [None] exactly like unreadable.
               When either half of the witness is missing (no interface
               source named, or no digest recorded) the decode is accepted
               unchecked — the caveat the interface doc states. The text
               lane is untouched either way: it linted [interface_source]'s
               exact bytes and never reads the cmti. *)
            match Cmt_format.read cmti_path with
            | _, Some ({ cmt_annots = Interface sg; _ } as info) ->
                let fresh =
                  match (info.cmt_source_digest, u.interface_source) with
                  | Some recorded, Some src ->
                      Digest0.matches ~recorded (Source.contents src)
                  | None, _ | _, None -> true
                in
                if fresh then Some sg else None
            | _ -> None
            | exception
                ( Cmi_format.Error _ | Cmt_format.Error _ | End_of_file
                | Failure _ | Sys_error _ ) ->
                None)
      in
      u.interface <- Loaded v;
      v

let parsetree u =
  match u.parsetree with
  | Loaded v -> v
  | Not_loaded ->
      let v =
        let lexbuf = Lexing.from_string (Source.contents u.source) in
        Lexing.set_filename lexbuf u.path;
        match Parse.implementation lexbuf with
        | tree -> Some tree
        | exception (Syntaxerr.Error _ | Lexer.Error _) -> None
      in
      u.parsetree <- Loaded v;
      v

(* {1 Use index} *)

(* One traversal on first demand; buckets accumulate reversed and are
   flipped in place once, so queries return the cached in-order lists
   without allocating. *)
let use_index u =
  match u.uses with
  | Loaded tbl -> tbl
  | Not_loaded ->
      let tbl = Shape.Uid.Tbl.create 64 in
      let default = Tast_iterator.default_iterator in
      let iterator =
        {
          default with
          Tast_iterator.expr =
            (fun sub e ->
              (match e.exp_desc with
              | Typedtree.Texp_ident (_, _, vd) ->
                  let uid = vd.Types.val_uid in
                  let seen =
                    Option.value ~default:[] (Shape.Uid.Tbl.find_opt tbl uid)
                  in
                  Shape.Uid.Tbl.replace tbl uid (e.exp_loc :: seen)
              | _ -> ());
              default.expr sub e);
        }
      in
      iterator.structure iterator u.implementation;
      Shape.Uid.Tbl.filter_map_inplace (fun _ locs -> Some (List.rev locs)) tbl;
      u.uses <- Loaded tbl;
      tbl

let uses u uid =
  Option.value ~default:[] (Shape.Uid.Tbl.find_opt (use_index u) uid)

let implementations u uid = u.intra uid

(* {1 Module-use index}

   Every stored [Path.t] of the implementation, bucketed under each ident it
   carries — root and prefix positions alike ([Pdot] members are strings,
   so idents occur only at [Pident] leaves, including both sides of
   [Papply]). Recording is uniform: a bare value or type ident occupies a
   bucket no module query ever hits ([Ident.same] is stamp identity), which
   costs a little memory and buys a carrier set with no per-node special
   cases — completeness is this index's correctness budget. [Ident.Tbl]'s
   equality is [Ident.same] (stamp-aware), so lookups need no re-filtering.

   Carriers — the contract is every stored [Path.t] the default iterator
   reaches: expression identifiers, [Tmod_ident]
   (open/include/aliases/functor arguments/packs), [Tmty_ident]/
   [Tmty_alias], [Ttyp_constr], class references ([Tcl_ident],
   [Tcty_constr], [Texp_new], [Ttyp_class]), the result-type head paths of
   constructor and label descriptions at both expression- and pattern-side
   use sites, plus the extension constructor's own tag path at those same
   sites (an exception's result-type head is the predef [exn]; only the
   [Cstr_extension] tag carries the module it is spelled through —
   [Head] is the version seam over the descriptions' module
   home), the type- and pattern-level opens ([Ttyp_open], [Tpat_open]) and
   [Tpat_type], package types ([Ttyp_package]'s path, through [Head]'s
   field seam), extension-constructor references
   ([Texp_extension_constructor]) and rebinds ([Text_rebind]), and the
   instance-variable paths ([Texp_instvar]/[Texp_setinstvar]/
   [Texp_override] — never module components today, recorded uniformly so
   the contract stays "every stored path"). Ghost locations count — a
   synthesized use is still a use. *)
let module_use_index u =
  match u.module_uses with
  | Loaded tbl -> tbl
  | Not_loaded ->
      let tbl = Ident.Tbl.create 32 in
      let record (loc : Location.t) (p : Path.t) =
        let rec go = function
          | Path.Pident id ->
              let seen = Option.value ~default:[] (Ident.Tbl.find_opt tbl id) in
              Ident.Tbl.replace tbl id (loc :: seen)
          | Path.Pdot (p', _) -> go p'
          | Path.Papply (f, x) ->
              go f;
              go x
          | Path.Pextra_ty (p', _) -> go p'
        in
        go p
      in
      let at (lid : _ Location.loc) p = record lid.Location.loc p in
      let head_use lid = function Some p -> at lid p | None -> () in
      let default = Tast_iterator.default_iterator in
      let iterator =
        {
          default with
          Tast_iterator.expr =
            (fun sub e ->
              (match e.exp_desc with
              | Typedtree.Texp_ident (p, lid, _) -> at lid p
              | Typedtree.Texp_construct (lid, cd, _) ->
                  head_use lid (Head.cstr cd);
                  head_use lid (Head.cstr_ext cd)
              | Typedtree.Texp_field (_, lid, ld) -> head_use lid (Head.lbl ld)
              | Typedtree.Texp_setfield (_, lid, ld, _) ->
                  head_use lid (Head.lbl ld)
              | Typedtree.Texp_record { fields; _ } ->
                  Array.iter
                    (fun (ld, def) ->
                      match def with
                      | Typedtree.Overridden (lid, _) ->
                          head_use lid (Head.lbl ld)
                      | Typedtree.Kept _ -> ())
                    fields
              | Typedtree.Texp_new (p, lid, _) -> at lid p
              | Typedtree.Texp_extension_constructor (lid, p) -> at lid p
              | Typedtree.Texp_instvar (p1, p2, sloc) ->
                  record sloc.Location.loc p1;
                  record sloc.Location.loc p2
              | Typedtree.Texp_setinstvar (p1, p2, sloc, _) ->
                  record sloc.Location.loc p1;
                  record sloc.Location.loc p2
              | Typedtree.Texp_override (p, _) -> record e.exp_loc p
              | _ -> ());
              default.expr sub e);
          pat =
            (fun (type k) sub (gp : k Typedtree.general_pattern) ->
              List.iter
                (fun (extra, _, _) ->
                  match extra with
                  | Typedtree.Tpat_open (p, lid, _) -> at lid p
                  | Typedtree.Tpat_type (p, lid) -> at lid p
                  | _ -> ())
                gp.pat_extra;
              (match gp.pat_desc with
              | Typedtree.Tpat_construct (lid, cd, _, _) ->
                  head_use lid (Head.cstr cd);
                  head_use lid (Head.cstr_ext cd)
              | Typedtree.Tpat_record (fields, _) ->
                  List.iter
                    (fun (lid, ld, _) -> head_use lid (Head.lbl ld))
                    fields
              | _ -> ());
              default.pat sub gp);
          module_expr =
            (fun sub me ->
              (match me.Typedtree.mod_desc with
              | Typedtree.Tmod_ident (p, lid) -> at lid p
              | _ -> ());
              default.module_expr sub me);
          module_type =
            (fun sub mt ->
              (match mt.Typedtree.mty_desc with
              | Typedtree.Tmty_ident (p, lid) | Typedtree.Tmty_alias (p, lid) ->
                  at lid p
              | _ -> ());
              default.module_type sub mt);
          typ =
            (fun sub ct ->
              (match ct.Typedtree.ctyp_desc with
              | Typedtree.Ttyp_constr (p, lid, _)
              | Typedtree.Ttyp_class (p, lid, _)
              | Typedtree.Ttyp_open (p, lid, _) ->
                  at lid p
              | _ -> ());
              default.typ sub ct);
          package_type =
            (fun sub pkg ->
              let p, lid = Head.package pkg in
              at lid p;
              default.package_type sub pkg);
          extension_constructor =
            (fun sub ec ->
              (match ec.Typedtree.ext_kind with
              | Typedtree.Text_rebind (p, lid) -> at lid p
              | _ -> ());
              default.extension_constructor sub ec);
          class_expr =
            (fun sub ce ->
              (match ce.Typedtree.cl_desc with
              | Typedtree.Tcl_ident (p, lid, _) -> at lid p
              | _ -> ());
              default.class_expr sub ce);
          class_type =
            (fun sub cty ->
              (match cty.Typedtree.cltyp_desc with
              | Typedtree.Tcty_constr (p, lid, _) -> at lid p
              | _ -> ());
              default.class_type sub cty);
        }
      in
      iterator.structure iterator u.implementation;
      Ident.Tbl.filter_map_inplace (fun _ locs -> Some (List.rev locs)) tbl;
      u.module_uses <- Loaded tbl;
      tbl

let module_uses u m =
  Option.value ~default:[] (Ident.Tbl.find_opt (module_use_index u) m)

(* {1 Export index} *)

(* Rows out of a [Types.signature], in signature order (the fold prepends,
   the caller reverses once). Exported-visibility value/type/module/exception
   items only ([Sig_typext] rows count exactly when their status is
   [Text_exception] — a [type t += …] constructor is not an exception);
   module rows recurse into literal sub-signatures ([Mty_signature]),
   never through aliases, named module types, or functor results — the
   wildcard also absorbs [Hidden] items and the item kinds 1.0 does not
   index. *)
let rec exports_of_signature prefix acc (sg : Types.signature) =
  List.fold_left
    (fun acc (item : Types.signature_item) ->
      match item with
      | Sig_value (id, vd, Exported) ->
          {
            Export.uid = vd.val_uid;
            name = prefix ^ Ident.name id;
            kind = Export.Value;
            loc = vd.val_loc;
          }
          :: acc
      | Sig_type (id, td, _, Exported) ->
          {
            Export.uid = td.type_uid;
            name = prefix ^ Ident.name id;
            kind = Export.Type;
            loc = td.type_loc;
          }
          :: acc
      | Sig_typext (id, ec, Text_exception, Exported) ->
          {
            Export.uid = ec.ext_uid;
            name = prefix ^ Ident.name id;
            kind = Export.Exception;
            loc = ec.ext_loc;
          }
          :: acc
      | Sig_module (id, _, md, _, Exported) -> (
          let name = prefix ^ Ident.name id in
          let acc =
            {
              Export.uid = md.md_uid;
              name;
              kind = Export.Module;
              loc = md.md_loc;
            }
            :: acc
          in
          match md.md_type with
          | Mty_signature sub -> exports_of_signature (name ^ ".") acc sub
          | _ -> acc)
      | _ -> acc)
    acc sg

let exports u =
  match u.exports with
  | Loaded v -> v
  | Not_loaded ->
      let sg =
        match interface u with
        | Some sg -> sg.Typedtree.sig_type
        | None -> u.implementation.Typedtree.str_type
      in
      let v = List.rev (exports_of_signature "" [] sg) in
      u.exports <- Loaded v;
      v

(* {1 Outgoing references} *)

(* [foreign_item ~name uid] classifies [uid] against the unit's own name:
   [`Item unit_name] for a declaration of another unit, [`Unit unit_name]
   for another unit's own [Compilation_unit] identity (a unit-level
   reference, no declaration pinned — an [unit_refs] contribution, never a
   [deps] row), [`Skip] otherwise. The wildcard drops [Internal], [Predef],
   and 5.5's [Local_opaque_item] (a usage identity minted in the using unit
   — never a cross-unit reference), keeping the match compilable across the
   support window. *)
let foreign_item ~name (uid : Shape.Uid.t) =
  match uid with
  | Item { comp_unit; _ } when not (String.equal comp_unit name) ->
      `Item comp_unit
  | Compilation_unit cu when not (String.equal cu name) -> `Unit cu
  | _ -> `Skip

(* Compilation units named by an unreduced shape: every [Comp_unit] head
   reachable through the structural constructors. The wildcard covers the
   leaves ([Var], [Leaf], [Error]) and 5.5's [Pack]. *)
let rec shape_units acc (s : Shape.t) =
  match s.desc with
  | Comp_unit cu -> cu :: acc
  | Abs (_, t) | Alias t | Proj (t, _) -> shape_units acc t
  | App (f, x) -> shape_units (shape_units acc f) x
  | Struct items ->
      Shape.Item.Map.fold (fun _ t acc -> shape_units acc t) items acc
  | _ -> acc

(* One occurrence reduction: resolved UIDs on the left accumulator (an alias
   chain contributes every step), units named by unresolved shapes on the
   right. The wildcard covers [Approximated None] and
   [Internal_error_missing_uid], and on 5.5 also [Resolved_local_use] (a
   locally-minted usage identity) and [Missing_uid]. *)
let rec harvest_reduction ((uids, units) as acc) (r : Shape_reduce.result) =
  match r with
  | Resolved uid -> (uid :: uids, units)
  | Resolved_alias (uid, r) -> harvest_reduction (uid :: uids, units) r
  | Approximated (Some uid) -> (uid :: uids, units)
  | Unresolved s -> (uids, shape_units units s)
  | _ -> acc

let compute_deps u { decl_deps; occurrences } =
  let name = u.name in
  let add (items, units) uid =
    match foreign_item ~name uid with
    | `Item unit_name -> ({ Dep.unit_name; uid } :: items, units)
    | `Unit cu -> (items, cu :: units)
    | `Skip -> (items, units)
  in
  let acc =
    List.fold_left
      (fun acc (_, def, decl) -> add (add acc def) decl)
      ([], []) decl_deps
  in
  let acc =
    Shape.Uid.Tbl.fold (fun uid _ acc -> add acc uid) (use_index u) acc
  in
  let items, unit_names =
    List.fold_left
      (fun acc (_, r) ->
        let uids, units = harvest_reduction ([], []) r in
        let acc = List.fold_left add acc uids in
        List.fold_left
          (fun (items, names) cu ->
            if String.equal cu name then (items, names) else (items, cu :: names))
          acc units)
      acc occurrences
  in
  (List.sort_uniq Dep.compare items, List.sort_uniq String.compare unit_names)

let deps_and_refs u =
  match u.deps with
  | Deps_done (items, refs) -> (items, refs)
  | Deps_raw raw ->
      let ((items, refs) as v) = compute_deps u raw in
      u.deps <- Deps_done (items, refs);
      v

let deps u = fst (deps_and_refs u)
let unit_refs u = snd (deps_and_refs u)

(* {1 Source slicing} *)

(* One outer bracket pair delimiting the whole slice; refuse when a string
   literal could hide a bracket. [atomic]'s bracketed case — where a wrong
   [false] only costs a harmless wrap. *)
let outer_pair text =
  let len = String.length text in
  len >= 2
  && (match (text.[0], text.[len - 1]) with
    | '(', ')' | '[', ']' | '{', '}' -> not (String.contains text '"')
    | _ -> false)
  &&
  let depth = ref 0 and ok = ref true in
  String.iteri
    (fun i c ->
      (match c with
      | '(' | '[' | '{' -> incr depth
      | ')' | ']' | '}' -> decr depth
      | _ -> ());
      if !depth = 0 && i < len - 1 then ok := false)
    text;
  !ok && !depth = 0

(* Conservative atomicity: splicing a wrapped atom is always safe, failing
   to wrap is not, so anything unrecognized gets parentheses. *)
let atomic text =
  let len = String.length text in
  let is_token_char = function
    | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '\'' | '.' -> true
    | _ -> false
  in
  let all_token () = String.for_all is_token_char text in
  let bracketed () = outer_pair text in
  let string_literal () =
    len >= 2
    && text.[0] = '"'
    && text.[len - 1] = '"'
    &&
    let quotes = ref 0 in
    String.iter (fun c -> if c = '"' then incr quotes) text;
    !quotes = 2
  in
  len > 0 && (all_token () || bracketed () || string_literal ())

(* The guarded raw slice both source-text views share: [None] for
   preprocessed units, ghost or inconsistent endpoints, reversed pairs,
   and unsliceable spans. *)
let sliced u (loc : Location.t) =
  if u.preprocessed then None
  else if loc.Location.loc_ghost then None
  else if
    not
      (Source.consistent u.source loc.Location.loc_start
      && Source.consistent u.source loc.Location.loc_end)
  then None
  else if
    (* Reversed locations: [consistent] checks each endpoint
       independently, so only the pair ordering is left to guard. After
       it, [Span.of_location] cannot raise — [consistent] already
       excludes negative offsets. *)
    loc.Location.loc_end.pos_cnum < loc.Location.loc_start.pos_cnum
  then None
  else
    match Source.slice u.source (Span.of_location loc) with
    | None | Some "" -> None
    | Some text -> Some text

let text u (e : Typedtree.expression) = sliced u e.exp_loc

let splice u (e : Typedtree.expression) =
  match sliced u e.exp_loc with
  | None -> None
  | Some text -> if atomic text then Some text else Some ("(" ^ text ^ ")")

(* The parser's delimiter pairs: [( e )] and [begin e end] are relocated
   alike to the span including the delimiters ([reloc_exp]). The test is
   deliberately liberal — the slice starts with an opening delimiter and
   ends with a closing one, no pairing scan: a string, comment, or
   character literal could hide a delimiter from a scan, and where the
   scan would be wrong the liberal answer is merely cosmetic (restoring
   parentheses the author did not write, as in [(a) = (b)]) while the
   scan's wrong [false] breaks the program. *)
let delimiter_framed text =
  let len = String.length text in
  let is_token_char = function
    | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '\'' -> true
    | _ -> false
  in
  let keyword_at i w =
    let m = String.length w in
    i >= 0
    && i + m <= len
    && String.equal (String.sub text i m) w
    && (i = 0 || not (is_token_char text.[i - 1]))
    && (i + m = len || not (is_token_char text.[i + m]))
  in
  len >= 2
  && (text.[0] = '(' || keyword_at 0 "begin")
  && (text.[len - 1] = ')' || keyword_at (len - 3) "end")

let parenthesized u (e : Typedtree.expression) =
  match sliced u e.exp_loc with
  | None -> false
  | Some text -> delimiter_framed text

let delimited u (e : Typedtree.expression) text =
  if parenthesized u e && not (atomic text) then "(" ^ text ^ ")" else text
