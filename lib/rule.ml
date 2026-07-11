(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

module Group = struct
  type t = Correctness | Suspicious | Perf | Style | Pedantic | Restriction

  (* Every group, in declaration order — the one spelling of the list
     (selection's parse and did-you-mean candidates both read it). *)
  let all = [ Correctness; Suspicious; Perf; Style; Pedantic; Restriction ]

  let to_string = function
    | Correctness -> "correctness"
    | Suspicious -> "suspicious"
    | Perf -> "perf"
    | Style -> "style"
    | Pedantic -> "pedantic"
    | Restriction -> "restriction"

  let pp ppf g = Format.pp_print_string ppf (to_string g)
end

module Severity = struct
  type t = Error | Warning

  let of_group = function
    | Group.Correctness -> Error
    | Group.Suspicious | Group.Perf | Group.Style | Group.Pedantic
    | Group.Restriction ->
        Warning

  let pp ppf s =
    Format.pp_print_string ppf
      (match s with Error -> "error" | Warning -> "warning")
end

module Stability = struct
  type t = Stable | Nursery

  let to_string = function Stable -> "stable" | Nursery -> "nursery"
  let pp ppf s = Format.pp_print_string ppf (to_string s)
end

type group = Group.t =
  | Correctness
  | Suspicious
  | Perf
  | Style
  | Pedantic
  | Restriction

type availability = Fix.availability = Never | Sometimes | Always

type meta = {
  name : string;
  renamed_from : string list;
  group : Group.t;
  stability : Stability.t;
  since : string;
  fix : availability;
  summary : string;
  doc : string;
  requires_options : bool;
  kind_gated : bool;
}

(* Kebab-case ASCII: leading lowercase letter, [a-z0-9] segments joined by
   single dashes. Org prefixes ([org/rule-name]) are rendering, not name
   grammar. *)
let is_kebab name =
  name <> ""
  && (match name.[0] with 'a' .. 'z' -> true | _ -> false)
  && List.for_all
       (fun seg ->
         seg <> ""
         && String.for_all
              (function 'a' .. 'z' | '0' .. '9' -> true | _ -> false)
              seg)
       (String.split_on_char '-' name)

let meta ~name ?(renamed_from = []) ~group ?(stability = Stability.Stable)
    ~since ~fix ~summary ~doc ?(requires_options = false) ?(kind_gated = false)
    () =
  let check_name n =
    if not (is_kebab n) then
      invalid_arg
        (Printf.sprintf "Rule.meta: %S is not a kebab-case rule name" n)
  in
  check_name name;
  List.iter check_name renamed_from;
  if summary = "" then
    invalid_arg (Printf.sprintf "Rule.meta: rule %s has an empty summary" name);
  {
    name;
    renamed_from;
    group;
    stability;
    since;
    fix;
    summary;
    doc;
    requires_options;
    kind_gated;
  }

(* The module-binding payload view: the [module_binding] record gained
   fields mid-window ([mb_uid]), so rules receive this view, never the
   record. [v] is the engine's constructor — dispatch plumbing, not
   rule-author surface. *)
module Module_binding = struct
  type position = Toplevel | Nested | Local

  type t = {
    id : Ident.t option;
    name_loc : Location.t;
    loc : Location.t;
    position : position;
  }

  let id mb = mb.id
  let name_loc mb = mb.name_loc
  let loc mb = mb.loc
  let position mb = mb.position
  let v ~id ~name_loc ~loc ~position = { id; name_loc; loc; position }
end

type callback =
  | Expr of (Unit.t -> Typedtree.expression -> Finding.t list)
  | Pattern of (Unit.t -> Typedtree.pattern -> Finding.t list)
  | Binding of (Unit.t -> Typedtree.value_binding -> Finding.t list)
  | Type_decl of (Unit.t -> Typedtree.type_declaration list -> Finding.t list)
  | Let_group of
      (Unit.t ->
      loc:Location.t ->
      Asttypes.rec_flag ->
      Typedtree.value_binding list ->
      Finding.t list)
  | Module_binding of (Unit.t -> Module_binding.t -> Finding.t list)
  | Export of (Unit.t -> Unit.Export.t -> Finding.t list)
  | Attribute of
      string list option * (Unit.t -> Parsetree.attribute -> Finding.t list)
  | Source of (Source.t -> Finding.t list)
  | Project of {
      collect : Unit.t -> string list;
      report : string list -> Finding.t list;
    }

module Sexp = Sexp

module Options = struct
  type error = Sexp.Error.t = { line : int; col : int; message : string }

  let v ~at message = { line = at.Sexp.line; col = at.Sexp.col; message }
  let to_string = Sexp.Error.to_string
  let pp = Sexp.Error.pp
end

type t = {
  meta : meta;
  callback : callback;
  (* The option schema, when the rule declares one ([with_options]);
     consumed by [configure] at driver wiring time. *)
  options : (Sexp.t list -> (t, Options.error) result) option;
}

let expr m f = { meta = m; callback = Expr f; options = None }
let pattern m f = { meta = m; callback = Pattern f; options = None }
let binding m f = { meta = m; callback = Binding f; options = None }
let type_decl m f = { meta = m; callback = Type_decl f; options = None }
let let_group m f = { meta = m; callback = Let_group f; options = None }

let module_binding m f =
  { meta = m; callback = Module_binding f; options = None }

let export m f = { meta = m; callback = Export f; options = None }

let attribute ?names m f =
  { meta = m; callback = Attribute (names, f); options = None }

let source m f = { meta = m; callback = Source f; options = None }

(* Facts are opaque to everything but the collecting rule's own [report]:
   [project] seals each ['fact] as one [Marshal] frame right here, at
   construction — no flags, so a closure or custom block raises at [collect]
   time, deterministically on every run (the engine isolates that as the
   rule's failure on the unit). Only this rule's own [report] decodes the
   frames — sound because the engine keys facts by rule name and its payload
   channels never cross binary images (cache: binary-digest key; workers:
   forked same image). *)
let project m ~collect ~report =
  let collect u = List.map (fun f -> Marshal.to_string f []) (collect u) in
  let report frames =
    report (List.map (fun b -> Marshal.from_string b 0) frames)
  in
  { meta = m; callback = Project { collect; report }; options = None }

let callback r = r.callback
let name r = r.meta.name
let with_options schema r = { r with options = Some schema }

let configure r payload =
  match (payload, r.options) with
  | [], _ -> Ok r
  | first :: _, None ->
      Error
        (Options.v ~at:first
           (Printf.sprintf "rule %S takes no options" r.meta.name))
  | _, Some schema -> (
      match schema payload with
      | Error _ as e -> e
      | Ok r' ->
          if not (String.equal r'.meta.name r.meta.name) then
            invalid_arg
              (Printf.sprintf
                 "Rule.configure: rule %S's option schema returned rule %S — \
                  options reconfigure a rule, never substitute one"
                 r.meta.name r'.meta.name);
          Ok r')

let renamed_from r = r.meta.renamed_from
let group r = r.meta.group
let is_project r = match r.callback with Project _ -> true | _ -> false
let stability r = r.meta.stability
let since r = r.meta.since
let fix r = r.meta.fix
let summary r = r.meta.summary
let doc r = r.meta.doc
let requires_options r = r.meta.requires_options
let kind_gated r = r.meta.kind_gated

(* {1 Selection} *)

(* The did-you-mean metric has one home, [Suggest]; this
   re-export keeps the SDK surface whole. *)
let suggest = Suggest.suggest

(* Selection tokens, with their specificity tier: an exact name (2) outranks
   a group or the nursery tier (1), which outranks all/default (0). *)
type token = All | Default | Nursery | In_group of Group.t | Name of string

let group_of_string s = List.find_opt (fun g -> Group.to_string g = s) Group.all

let specificity = function
  | All | Default -> 0
  | Nursery | In_group _ -> 1
  | Name _ -> 2

let on_by_default r =
  r.meta.stability = Stability.Stable
  &&
  match r.meta.group with
  | Correctness | Suspicious | Perf -> true
  | Style | Pedantic | Restriction -> false

let mentions tok r =
  match tok with
  | All ->
      (* [all] is every stable rule outside [Restriction]: a house policy
         enabled by a workspace that has not adopted it produces
         contract-true noise, so policy rules join an audit only by group
         token or exact name. *)
      r.meta.stability = Stability.Stable && r.meta.group <> Group.Restriction
  | Default -> on_by_default r
  | Nursery -> r.meta.stability = Stability.Nursery
  | In_group g -> r.meta.group = g && r.meta.stability = Stability.Stable
  | Name n -> r.meta.name = n

let select ~catalog ~select ~ignore =
  let exception Unknown of string in
  let resolve warnings s =
    match s with
    | "all" -> (All, warnings)
    | "default" -> (Default, warnings)
    | "nursery" -> (Nursery, warnings)
    | _ -> (
        match group_of_string s with
        | Some g -> (In_group g, warnings)
        | None -> (
            if List.exists (fun r -> r.meta.name = s) catalog then
              (Name s, warnings)
            else
              match
                List.find_opt (fun r -> List.mem s r.meta.renamed_from) catalog
              with
              | Some r ->
                  ( Name r.meta.name,
                    Printf.sprintf "rule %S was renamed to %S" s r.meta.name
                    :: warnings )
              | None -> raise_notrace (Unknown s)))
  in
  let resolve_all tokens =
    List.fold_left
      (fun (toks, warnings) s ->
        let tok, warnings = resolve warnings s in
        (tok :: toks, warnings))
      ([], []) tokens
  in
  match
    let select = if select = [] then [ "default" ] else select in
    let sel, sel_warnings = resolve_all select in
    let ign, ign_warnings = resolve_all ignore in
    (* A bare whole-group [restriction] on the enabling side warns
       once: the tier is a shelf of independent house policies meant to
       be adopted one by one. The warning states what the token did — a
       group token covers stable rules only, so an all-Nursery tier
       enables nothing, and saying so names the trap; when restriction
       rules graduate the counts keep the sentence honest. Exact-name
       selection of a restriction rule warns nothing, and [restriction]
       under ignore disables — nothing to warn about. *)
    let sel_warnings =
      if List.mem (In_group Group.Restriction) sel then
        let restriction =
          List.filter (fun r -> r.meta.group = Group.Restriction) catalog
        in
        let stable =
          List.filter (fun r -> r.meta.stability = Stability.Stable) restriction
        in
        Printf.sprintf
          "restriction rules are independent house policies, and some \
           contradict each other — adopt each by exact name; the group token \
           enables %d of %d restriction rules (group tokens cover stable rules \
           only; nursery members need \"nursery\" or their exact name)"
          (List.length stable) (List.length restriction)
        :: sel_warnings
      else sel_warnings
    in
    let tier tokens r =
      List.fold_left
        (fun best tok ->
          if mentions tok r then max best (specificity tok) else best)
        (-1) tokens
    in
    let chosen = List.filter (fun r -> tier sel r > tier ign r) catalog in
    (* Warnings in flag order, select before ignore; [resolve_all]
       accumulated each list reversed. *)
    (chosen, List.rev sel_warnings @ List.rev ign_warnings)
  with
  | result -> Ok result
  | exception Unknown s ->
      let candidates =
        ("all" :: "default" :: "nursery" :: List.map Group.to_string Group.all)
        @ List.concat_map (fun r -> r.meta.name :: r.meta.renamed_from) catalog
      in
      let hint =
        match suggest ~candidates s with
        | Some c -> Printf.sprintf " (did you mean %S?)" c
        | None -> ""
      in
      Error (Printf.sprintf "unknown rule or group %S%s" s hint)
