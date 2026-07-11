(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

module Directive = struct
  type kind = Allow | Expect

  type t = {
    kind : kind;
    rule : string;
    reason : string;
    scope : Span.t;
    span : Span.t;
  }

  let kind d = d.kind
  let rule d = d.rule
  let reason d = d.reason
  let scope d = d.scope
  let span d = d.span
  let horizontal = function ' ' | '\t' -> true | _ -> false

  let deletion ~source d =
    let len = String.length source in
    let start = min (Span.start d.span) len
    and stop = min (Span.stop d.span) len in
    let rec back i =
      if i > 0 && horizontal source.[i - 1] then back (i - 1) else i
    in
    let left = back start in
    let line_start = left = 0 || Char.equal source.[left - 1] '\n' in
    (* The rest of the line after the attribute: blanks up to a line ending
       (or end of file) mean the attribute owns the line. *)
    let rec fore i =
      if i >= len then Some i
      else if horizontal source.[i] then fore (i + 1)
      else if Char.equal source.[i] '\n' then Some (i + 1)
      else if
        Char.equal source.[i] '\r'
        && i + 1 < len
        && Char.equal source.[i + 1] '\n'
      then Some (i + 2)
      else None
    in
    match if line_start then fore stop else None with
    | Some right -> Span.v ~start:left ~stop:right
    | None -> Span.v ~start:left ~stop

  let pp ppf d =
    Format.fprintf ppf "%s %S: %S at %a over %a"
      (match d.kind with Allow -> "allow" | Expect -> "expect")
      d.rule d.reason Span.pp d.span Span.pp d.scope
end

let reserved =
  [ ("litany.allow", Directive.Allow); ("litany.expect", Directive.Expect) ]

module Malformed = struct
  type problem =
    | Unknown_name of string
    | Not_a_string
    | Missing_colon
    | Missing_rule
    | Missing_reason
    | Invalid_reason

  type t = { kind : Directive.kind option; problem : problem; span : Span.t }

  let kind m = m.kind
  let problem m = m.problem
  let span m = m.span

  let message m =
    let kind_word =
      match m.kind with
      | Some Directive.Allow | None -> "allow"
      | Some Directive.Expect -> "expect"
    in
    match m.problem with
    | Unknown_name name ->
        (* The whole did-you-mean — the near-miss policy, not just the
           edit-distance metric — is [Suggest]; never re-spell it
           with a local filter. *)
        let suggestion =
          match Suggest.suggest ~candidates:(List.map fst reserved) name with
          | None -> ""
          | Some r -> Printf.sprintf " (did you mean %S?)" r
        in
        Printf.sprintf "unknown attribute %S%s" name suggestion
    | Not_a_string ->
        Printf.sprintf
          "malformed %s payload \xe2\x80\x94 expected one string literal \
           \"rule-name: reason\""
          kind_word
    | Missing_colon ->
        Printf.sprintf
          "malformed %s payload \xe2\x80\x94 missing \":\" (expected \
           \"rule-name: reason\")"
          kind_word
    | Missing_rule ->
        Printf.sprintf
          "malformed %s payload \xe2\x80\x94 missing rule name before \":\""
          kind_word
    | Missing_reason ->
        Printf.sprintf
          "malformed %s payload \xe2\x80\x94 a reason is mandatory after \":\""
          kind_word
    | Invalid_reason ->
        Printf.sprintf
          "malformed %s payload \xe2\x80\x94 the reason must be one non-empty \
           line"
          kind_word

  let pp ppf m = Format.fprintf ppf "%s at %a" (message m) Span.pp m.span
end

type t = { directives : Directive.t list; malformed : Malformed.t list }

let directives p = p.directives
let malformed p = p.malformed

(* {1 Payload grammar}

   ["rule-name: reason"] — first colon splits, horizontal whitespace trimmed
   around both parts, reason mandatory and one printable line. *)

let is_horizontal_space = function ' ' | '\t' -> true | _ -> false

let trim_horizontal s =
  let n = String.length s in
  let first = ref 0 and last = ref n in
  while !first < n && is_horizontal_space s.[!first] do
    incr first
  done;
  while !last > !first && is_horizontal_space s.[!last - 1] do
    decr last
  done;
  String.sub s !first (!last - !first)

let parse_payload s =
  match String.index_opt s ':' with
  | None -> Error Malformed.Missing_colon
  | Some colon -> (
      let rule = trim_horizontal (String.sub s 0 colon) in
      let reason =
        trim_horizontal (String.sub s (colon + 1) (String.length s - colon - 1))
      in
      if rule = "" then Error Malformed.Missing_rule
      else if reason = "" then Error Malformed.Missing_reason
      else
        match String.for_all (fun c -> c >= ' ' && c <> '\x7f') reason with
        | true -> Ok (rule, reason)
        | false -> Error Malformed.Invalid_reason)

(* The single string literal of an attribute payload, if that is what the
   payload is. Attributes on the inner [Pstr_eval] are tolerated. *)
let payload_string (p : Parsetree.payload) =
  match p with
  | Parsetree.PStr
      [
        {
          pstr_desc =
            Parsetree.Pstr_eval
              ( {
                  pexp_desc =
                    Parsetree.Pexp_constant
                      { pconst_desc = Parsetree.Pconst_string (s, _, _); _ };
                  _;
                },
                _ );
          _;
        };
      ] ->
      Some s
  | _ -> None

(* {1 Collection}

   One walk of the structure. Host hooks claim the attributes of the node
   kinds that carry them, scoping each directive to the node's span; the
   catch-all [attribute] hook picks up [litany.] attributes on carriers no
   host hook recognizes (classes, object fields), scoping them to their own
   span so the audit surfaces them instead of silence. *)

type collector = {
  mutable dirs : Directive.t list;  (** Reversed collection order. *)
  mutable bad : Malformed.t list;  (** Reversed collection order. *)
  claimed : (int * int, unit) Hashtbl.t;  (** Attribute spans already scoped. *)
  source_length : int;
}

let span_of_loc (l : Location.t) =
  let start = l.loc_start.pos_cnum and stop = l.loc_end.pos_cnum in
  if start < 0 || stop < start then None else Some (Span.v ~start ~stop)

let record c (attr : Parsetree.attribute) ~scope =
  match span_of_loc attr.attr_loc with
  | None -> ()
  | Some span -> (
      let name = attr.attr_name.txt in
      match List.assoc_opt name reserved with
      | None ->
          c.bad <-
            { Malformed.kind = None; problem = Unknown_name name; span }
            :: c.bad
      | Some kind -> (
          let fail problem =
            c.bad <- { Malformed.kind = Some kind; problem; span } :: c.bad
          in
          match payload_string attr.attr_payload with
          | None -> fail Malformed.Not_a_string
          | Some s -> (
              match parse_payload s with
              | Error problem -> fail problem
              | Ok (rule, reason) ->
                  c.dirs <-
                    { Directive.kind; rule; reason; scope; span } :: c.dirs)))

let is_litany (attr : Parsetree.attribute) =
  let name = attr.attr_name.txt in
  String.length name > 7 && String.sub name 0 7 = "litany."

(* [mark c sp] records [sp] as scoped by a host hook, so the catch-all
   [attribute] hook's re-visit skips it. *)
let mark c sp = Hashtbl.replace c.claimed (Span.start sp, Span.stop sp) ()

let claim c (loc : Location.t) (attrs : Parsetree.attributes) =
  (* Attributes first: the overwhelmingly common node carries none, and
     must not pay [span_of_loc]'s allocation to learn it. *)
  if List.exists is_litany attrs then
    match span_of_loc loc with
    | None -> ()
    | Some scope ->
        List.iter
          (fun (attr : Parsetree.attribute) ->
            if is_litany attr then begin
              (match span_of_loc attr.attr_loc with
              | Some sp -> mark c sp
              | None -> ());
              record c attr ~scope
            end)
          attrs

let of_structure ~source_length tree =
  let c = { dirs = []; bad = []; claimed = Hashtbl.create 8; source_length } in
  let d = Ast_iterator.default_iterator in
  let it =
    {
      d with
      Ast_iterator.expr =
        (fun sub (e : Parsetree.expression) ->
          claim c e.pexp_loc e.pexp_attributes;
          d.expr sub e);
      pat =
        (fun sub (p : Parsetree.pattern) ->
          claim c p.ppat_loc p.ppat_attributes;
          d.pat sub p);
      typ =
        (fun sub (ty : Parsetree.core_type) ->
          claim c ty.ptyp_loc ty.ptyp_attributes;
          d.typ sub ty);
      value_binding =
        (fun sub (vb : Parsetree.value_binding) ->
          claim c vb.pvb_loc vb.pvb_attributes;
          d.value_binding sub vb);
      value_description =
        (fun sub (vd : Parsetree.value_description) ->
          claim c vd.pval_loc vd.pval_attributes;
          d.value_description sub vd);
      type_declaration =
        (fun sub (td : Parsetree.type_declaration) ->
          claim c td.ptype_loc td.ptype_attributes;
          d.type_declaration sub td);
      type_extension =
        (fun sub (te : Parsetree.type_extension) ->
          claim c te.ptyext_loc te.ptyext_attributes;
          d.type_extension sub te);
      type_exception =
        (fun sub (te : Parsetree.type_exception) ->
          claim c te.ptyexn_loc te.ptyexn_attributes;
          d.type_exception sub te);
      extension_constructor =
        (fun sub (ec : Parsetree.extension_constructor) ->
          claim c ec.pext_loc ec.pext_attributes;
          d.extension_constructor sub ec);
      constructor_declaration =
        (fun sub (cd : Parsetree.constructor_declaration) ->
          claim c cd.pcd_loc cd.pcd_attributes;
          d.constructor_declaration sub cd);
      label_declaration =
        (fun sub (ld : Parsetree.label_declaration) ->
          claim c ld.pld_loc ld.pld_attributes;
          d.label_declaration sub ld);
      module_binding =
        (fun sub (mb : Parsetree.module_binding) ->
          claim c mb.pmb_loc mb.pmb_attributes;
          d.module_binding sub mb);
      module_declaration =
        (fun sub (md : Parsetree.module_declaration) ->
          claim c md.pmd_loc md.pmd_attributes;
          d.module_declaration sub md);
      module_type_declaration =
        (fun sub (mtd : Parsetree.module_type_declaration) ->
          claim c mtd.pmtd_loc mtd.pmtd_attributes;
          d.module_type_declaration sub mtd);
      module_expr =
        (fun sub (me : Parsetree.module_expr) ->
          claim c me.pmod_loc me.pmod_attributes;
          d.module_expr sub me);
      module_type =
        (fun sub (mt : Parsetree.module_type) ->
          claim c mt.pmty_loc mt.pmty_attributes;
          d.module_type sub mt);
      open_declaration =
        (fun sub (od : Parsetree.open_declaration) ->
          claim c od.popen_loc od.popen_attributes;
          d.open_declaration sub od);
      include_declaration =
        (fun sub (id : Parsetree.include_declaration) ->
          claim c id.pincl_loc id.pincl_attributes;
          d.include_declaration sub id);
      structure_item =
        (fun sub (si : Parsetree.structure_item) ->
          (match si.pstr_desc with
          | Parsetree.Pstr_eval (_, attrs) | Parsetree.Pstr_extension (_, attrs)
            ->
              claim c si.pstr_loc attrs
          | Parsetree.Pstr_attribute attr ->
              if is_litany attr then
                begin match span_of_loc attr.attr_loc with
                | None -> ()
                | Some sp ->
                    mark c sp;
                    let scope =
                      Span.v ~start:(Span.start sp)
                        ~stop:(max c.source_length (Span.start sp))
                    in
                    record c attr ~scope
                end
          | _ -> ());
          d.structure_item sub si);
      attribute =
        (fun sub (attr : Parsetree.attribute) ->
          (if is_litany attr then
             match span_of_loc attr.attr_loc with
             | None -> ()
             | Some sp ->
                 if not (Hashtbl.mem c.claimed (Span.start sp, Span.stop sp))
                 then record c attr ~scope:sp);
          d.attribute sub attr);
    }
  in
  it.structure it tree;
  let by_span a b = Span.compare a b in
  {
    directives =
      List.sort (fun a b -> by_span a.Directive.span b.Directive.span) c.dirs;
    malformed =
      List.sort (fun a b -> by_span a.Malformed.span b.Malformed.span) c.bad;
  }

(* {1 Matching} *)

let covering p ~rule span =
  let better (d : Directive.t) (best : Directive.t) =
    let ld = Span.length d.scope and lb = Span.length best.scope in
    ld < lb || (ld = lb && Span.start d.span > Span.start best.span)
  in
  List.fold_left
    (fun best (d : Directive.t) ->
      if rule d.rule && Span.includes d.scope span then
        match best with Some b when not (better d b) -> best | _ -> Some d
      else best)
    None p.directives

(* {1 The demand scan} *)

(* [contains_sub s sub ~anchor] is [true] iff [sub] occurs in [s]. Candidate
   positions come from [String.index_from_opt] on [sub.[anchor]] (memchr, so
   the whole-file scan runs at C speed between hits) — pick the needle's
   rarest byte. This scan runs on every admitted unit, so it must stay
   cheap. *)
let contains_sub s sub ~anchor =
  let n = String.length s and m = String.length sub in
  let c = sub.[anchor] in
  let rec eq i j = j = m || (s.[i + j] = sub.[j] && eq i (j + 1)) in
  let rec at i =
    (* [i] is the next candidate position of the anchor byte. *)
    if i >= n then false
    else
      match String.index_from_opt s i c with
      | None -> false
      | Some j ->
          let start = j - anchor in
          (start >= 0 && start + m <= n && eq start 0) || at (j + 1)
  in
  at anchor

(* The needle is the token ["litany"], not ["litany."]: an attribute id is
   a token sequence, so blanks and comments are legal around the dot
   ([[@litany . allow "r: x"]] spells no ["litany."]) — the LIDENT itself
   cannot be split. The engine's demand gate computes an equivalent
   conjunction over its shared ["[@"] scan; keep them in step. *)
let spelled contents =
  contains_sub contents "[@" ~anchor:1
  && contains_sub contents "litany" ~anchor:5
