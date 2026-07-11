(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

module Config = Litany.Config_file

type t = { cfg : Config.t; display : string }

let catalog = Cli_common.catalog

(* The selection vocabulary [check_names] validates against — exactly
   [Litany.Rule.select]'s token grammar (groups from [Group.all], so a
   new group lands here by construction). *)
let selection_vocabulary =
  [ "all"; "default"; "nursery" ]
  @ List.map Litany.Rule.Group.to_string Litany.Rule.Group.all
  @ List.concat_map
      (fun r -> Litany.Rule.name r :: Litany.Rule.renamed_from r)
      catalog

let rule_vocabulary =
  List.concat_map
    (fun r -> Litany.Rule.name r :: Litany.Rule.renamed_from r)
    catalog

let refuse_at ~display (a : Config.atom) fmt =
  Printf.ksprintf
    (fun msg ->
      Cli_common.refuse "%s:%d:%d: %s" display a.Config.line a.Config.col msg)
    fmt

(* The audit names print as rule names in output, so a user will paste them
   into the file's ignore; "unknown" would be the one wrong word (the same
   courtesy the flags extend). Checked before [check_names], which knows no
   audit vocabulary. *)
let audit_token cfg =
  let atoms =
    Config.select cfg @ Config.extend cfg @ Config.ignored cfg
    @ List.concat_map Config.Per_path.ignored (Config.per_paths cfg)
  in
  List.find_opt
    (fun (a : Config.atom) -> List.mem a.Config.value Litany.Engine.audit_rules)
    atoms

let load ~root =
  let file = Filename.concat root "litany" in
  let display = if root = "." then "litany" else file in
  if (not (Sys.file_exists file)) || Sys.is_directory file then
    Ok { cfg = Config.empty; display }
  else
    match In_channel.with_open_bin file In_channel.input_all with
    | exception Sys_error msg -> Error (Cli_common.refuse "%s" msg)
    | contents -> (
        match Config.parse contents with
        | Error e ->
            Error
              (Cli_common.refuse "%s" (Config.Error.to_string ~file:display e))
        | Ok cfg -> (
            match audit_token cfg with
            | Some a ->
                Error
                  (refuse_at ~display a
                     "%S is engine-owned hygiene, not a selectable rule"
                     a.Config.value)
            | None -> (
                match
                  Config.check_names cfg ~selection:selection_vocabulary
                    ~rules:rule_vocabulary
                with
                | Error e ->
                    Error
                      (Cli_common.refuse "%s"
                         (Config.Error.to_string ~file:display e))
                | Ok () -> Ok { cfg; display })))

(* [check_names] guaranteed every [(rule <name>)] head is a rule name or
   alias, so resolution here cannot fail — only collide (one rule configured
   under two spellings, the alias-vs-name duplicate parse cannot see). *)
let resolve_rule_name name =
  match Cli_common.find_rule name with
  | Some (`Exact r) | Some (`Renamed r) -> Some r
  | None -> None

let configured_catalog { cfg; display } =
  let exception Refused of int in
  let configured = Hashtbl.create 8 in
  (* (resolved rule name -> spelled head) of forms already applied *)
  match
    List.fold_left
      (fun catalog ro ->
        let head = Config.Rule_options.name ro in
        let spelled = head.Config.value in
        match resolve_rule_name spelled with
        | None -> catalog (* unreachable after check_names *)
        | Some r -> (
            let rule_name = Litany.Rule.name r in
            (match Hashtbl.find_opt configured rule_name with
            | Some first_spelling ->
                raise_notrace
                  (Refused
                     (refuse_at ~display head
                        "rule %S is configured twice (%S names the same rule)"
                        rule_name first_spelling))
            | None -> Hashtbl.replace configured rule_name spelled);
            match Litany.Rule.configure r (Config.Rule_options.options ro) with
            | Error e ->
                raise_notrace
                  (Refused
                     (Cli_common.refuse "%s"
                        (Litany.Rule.Options.to_string ~file:display e)))
            | Ok r' ->
                List.map
                  (fun c ->
                    if String.equal (Litany.Rule.name c) rule_name then r'
                    else c)
                  catalog))
      catalog (Config.rules cfg)
  with
  | catalog -> Ok catalog
  | exception Refused code -> Error code

(* The resolved names of the file's [(rule <name> ...)] forms, in file
   order — the check driver warns on any that ends the run unselected
   (configured-but-silent is otherwise invisible; the check is general,
   not restriction-specific). *)
let configured_rule_names { cfg; _ } =
  List.filter_map
    (fun ro ->
      Option.map Litany.Rule.name
        (resolve_rule_name (Config.Rule_options.name ro).Config.value))
    (Config.rules cfg)

let values atoms = List.map (fun (a : Config.atom) -> a.Config.value) atoms

let tokens { cfg; _ } ~cli_select ~cli_ignore =
  let file_select =
    match (values (Config.select cfg), values (Config.extend cfg)) with
    | [], [] -> []
    | [], extend -> "default" :: extend
    | select, extend -> select @ extend
  in
  let select = if cli_select <> [] then cli_select else file_select in
  let ignore =
    if cli_ignore <> [] then cli_ignore else values (Config.ignored cfg)
  in
  (select, ignore)

(* Per-path token semantics {e are} the selection semantics: each token
   compiles through the one resolution — [Litany.Rule.select] with the
   token as the whole select list (post-[check_names] it cannot fail;
   rename warnings are selection's voice and are dropped here) — so a new
   token, tier, or group lands in per-path filtering the moment it lands
   in selection (one derivation — a hand-rolled twin drifted before). The one
   documented widening stays in the driver: [all] drops every report on
   matching paths, audits included — "ignore this path" must not leave
   the auditors talking. *)
let pred_of_token ~catalog tok : string -> bool =
  match tok with
  | "all" -> fun _ -> true
  | tok -> (
      match Litany.Rule.select ~catalog ~select:[ tok ] ~ignore:[] with
      | Error _ -> fun _ -> false (* unreachable after check_names *)
      | Ok (rules, _rename_warnings) ->
          let names = List.map Litany.Rule.name rules in
          fun rule -> List.mem rule names)

(* [Glob.matches] raises on non-canonical candidates by contract; a path an
   adapter hands us that is not a canonical workspace-relative path simply
   never matches — filtering is report selection, not a correctness gate. *)
let canonical_rel path =
  path <> "" && Filename.is_relative path
  && (not (String.contains path '\000'))
  && List.for_all
       (fun seg -> seg <> "" && seg <> "." && seg <> "..")
       (String.split_on_char '/' path)

let keep { cfg; _ } ~catalog =
  match Config.per_paths cfg with
  | [] -> None
  | pps ->
      let compiled =
        List.map
          (fun pp ->
            let preds =
              List.map
                (fun (a : Config.atom) -> pred_of_token ~catalog a.Config.value)
                (Config.Per_path.ignored pp)
            in
            (pp, fun rule -> List.exists (fun p -> p rule) preds))
          pps
      in
      Some
        (fun ~path ~rule ->
          (not (canonical_rel path))
          || not
               (List.exists
                  (fun (pp, mentions) ->
                    Config.Per_path.matches pp path && mentions rule)
                  compiled))

let closed_world { cfg; _ } = Config.closed_world cfg
