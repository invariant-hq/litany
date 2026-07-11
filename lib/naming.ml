(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

module Name = struct
  (* The leaf keeps the operator symbol bare (["="], not ["(=)"]): signature
     items name operators by their symbol, so [Resolver] looks the bare form
     up directly. *)
  type leaf = Lident of string | Operator of string

  (* [repr] is the canonical rendering, fixed at construction so that
     [to_string] — the memo key on the match path — allocates nothing. *)
  type t = { modules : string list; leaf : leaf; repr : string }
  type error = Malformed of { input : string; at : int; reason : string }

  let is_uident_start c = 'A' <= c && c <= 'Z'
  let is_lident_start c = ('a' <= c && c <= 'z') || c = '_'

  let is_ident_char c =
    ('a' <= c && c <= 'z')
    || ('A' <= c && c <= 'Z')
    || ('0' <= c && c <= '9')
    || c = '_' || c = '\''

  let is_symbol_char c = String.contains "!$%&*+-./:<=>?@^|~#" c
  let leaf_body = function Lident l -> l | Operator s -> s

  let of_string input =
    let len = String.length input in
    let err at reason = Error (Malformed { input; at; reason }) in
    let scan_ident i =
      let j = ref i in
      while !j < len && is_ident_char input.[!j] do
        incr j
      done;
      !j
    in
    let scan_symbol i =
      let j = ref i in
      while !j < len && is_symbol_char input.[!j] do
        incr j
      done;
      !j
    in
    let finish acc i leaf =
      match acc with
      | [] -> err i "expected at least two components, e.g. Stdlib.length"
      | _ -> Ok { modules = List.rev acc; leaf; repr = input }
    in
    let rec go acc i =
      if i >= len then err i "expected a name component"
      else
        match input.[i] with
        | c when is_uident_start c ->
            let j = scan_ident (i + 1) in
            if j < len && input.[j] = '.' then
              go (String.sub input i (j - i) :: acc) (j + 1)
            else if j < len then err j "expected '.' after a module name"
            else if acc = [] then
              err i "expected at least two components, e.g. Stdlib.length"
            else
              err i
                "expected a value leaf: a module name cannot end a canonical \
                 name"
        | c when is_lident_start c ->
            let j = scan_ident (i + 1) in
            if j < len && input.[j] = '.' then
              err i "expected a capitalized module name before '.'"
            else if j < len then err j "expected end of input after the leaf"
            else if j - i = 1 && input.[i] = '_' then
              err i "'_' is not a value name"
            else finish acc i (Lident (String.sub input i (j - i)))
        | '(' ->
            let j = scan_symbol (i + 1) in
            if j = i + 1 then err j "expected an operator symbol inside '()'"
            else if j >= len || input.[j] <> ')' then
              err j "expected an operator character or ')'"
            else if j + 1 < len then
              err (j + 1) "expected end of input after the operator leaf"
            else finish acc i (Operator (String.sub input (i + 1) (j - i - 1)))
        | c when is_symbol_char c ->
            err i "bare operator: use the parenthesized form, e.g. (=)"
        | _ -> err i "expected an identifier"
    in
    go [] 0

  let to_string n = n.repr
  let components n = n.modules @ [ leaf_body n.leaf ]
  let equal n n' = String.equal n.repr n'.repr
  let compare n n' = List.compare String.compare (components n) (components n')
  let pp ppf n = Format.pp_print_string ppf n.repr

  let pp_error ppf (Malformed { input; at; reason }) =
    Format.fprintf ppf "malformed canonical name %S at offset %d: %s" input at
      reason
end

module Module_path = struct
  (* [repr] is the parse input, fixed at construction — the memo key on
     the match path, exactly as [Name.repr]. *)
  type t = { components : string list; repr : string }

  let of_string input =
    let len = String.length input in
    let err at reason = Error (Name.Malformed { input; at; reason }) in
    let rec go acc i =
      if i >= len then err i "expected a module name"
      else if Name.is_uident_start input.[i] then begin
        let j = ref (i + 1) in
        while !j < len && Name.is_ident_char input.[!j] do
          incr j
        done;
        let comp = String.sub input i (!j - i) in
        if !j < len && input.[!j] = '.' then go (comp :: acc) (!j + 1)
        else if !j < len then
          err !j "expected '.' or end of input after a module name"
        else Ok { components = List.rev (comp :: acc); repr = input }
      end
      else err i "expected a capitalized module name"
    in
    go [] 0

  let to_string p = p.repr
  let components p = p.components
  let pp ppf p = Format.pp_print_string ppf p.repr
end

module Ref = struct
  type t = Value of Name.t | Module of Module_path.t

  (* Classification is by the last component's shape alone — a capitalized
     last component is a module path, anything else (an operator leaf
     included: '(' never occurs in a module path) is a canonical value
     name — and each class is then validated by its own grammar. The
     operator guard comes first because [rindex] would find the dot inside
     an operator like [(|.)]. *)
  let module_shaped s =
    (not (String.contains s '('))
    &&
    match String.rindex_opt s '.' with
    | Some i -> i + 1 < String.length s && Name.is_uident_start s.[i + 1]
    | None -> s <> "" && Name.is_uident_start s.[0]

  let of_string input =
    if module_shaped input then
      Result.map (fun p -> Module p) (Module_path.of_string input)
    else Result.map (fun n -> Value n) (Name.of_string input)

  let to_string = function
    | Value n -> Name.to_string n
    | Module p -> Module_path.to_string p

  let pp ppf r = Format.pp_print_string ppf (to_string r)

  (* The classified rendering: the error's input re-classifies exactly as
     [of_string] classified it, so the message names the grammar the parse
     ran under. Configuration surfaces print through here. *)
  let pp_error ppf (Name.Malformed { input; at; reason } as e) =
    if module_shaped input then
      Format.fprintf ppf "malformed module path %S at offset %d: %s" input at
        reason
    else Name.pp_error ppf e
end

(* Predefined types are declared in no cmi; their canonical spelling is
   [Stdlib.<name>] and their use sites carry the predefined [Pident].
   [builtin_idents] also lists predefined exceptions, but those are
   uidents and cannot collide with a type leaf. Two consumers:
   [Scope.matches_type]'s accepted set and [Resolver.probe_type]'s
   audit. *)
let predef_type_ident (n : Name.t) =
  match n.Name.modules with
  | [ "Stdlib" ] ->
      List.assoc_opt (Name.leaf_body n.Name.leaf) Predef.builtin_idents
  | _ -> None

module Resolver = struct
  type t = {
    cmi_dirs : string list;
    signatures : (string, Types.signature option) Hashtbl.t;
        (* per compilation unit, [None] cached for unreadable or absent cmis *)
    mutable failed_reads : (string * string) list;
        (* (cmi path, reason) per unreadable cmi, reversed discovery order.
           Missing cmis are never here: absence is enumerated as ordinary
           match-nothing; a cmi that exists but cannot be read is a
           degradation the run must surface. *)
    resolutions : (string, Shape.Uid.t list) Hashtbl.t;
        (* per canonical rendering, value namespace *)
    type_resolutions : (string, Shape.Uid.t list) Hashtbl.t;
        (* per canonical rendering, type namespace *)
    module_resolutions : (string, string list * Shape.Uid.t list) Hashtbl.t;
        (* per module-path rendering: the module's identity boundary —
           compilation-unit names plus collected value declaration UIDs *)
  }

  let create ~cmi_dirs =
    {
      cmi_dirs;
      signatures = Hashtbl.create 16;
      failed_reads = [];
      resolutions = Hashtbl.create 16;
      type_resolutions = Hashtbl.create 16;
      module_resolutions = Hashtbl.create 16;
    }

  let read_failures t = List.rev t.failed_reads

  let find_cmi t unit_name =
    let file = String.uncapitalize_ascii unit_name ^ ".cmi" in
    List.find_map
      (fun dir ->
        let path = Filename.concat dir file in
        if Sys.file_exists path then Some path else None)
      t.cmi_dirs

  (* The one IO edge: one cmi read per compilation unit per run, memoized.
     A missing cmi is a resolution failure and nothing else — a workspace
     without [Base] must not error on a rule mentioning [Base.*]. A cmi
     that exists but cannot be read (foreign magic, truncation, IO error)
     is also a resolution failure, but it is additionally recorded in
     [failed_reads]: silently matching nothing because of an unreadable
     file would let one incompatible cmi mute every canonical-name rule of
     the run with a clean exit ("silence is enumerated"). The reasons are
     fixed one-line strings, so reports stay byte-deterministic. *)
  let signature_of_unit t unit_name =
    match Hashtbl.find_opt t.signatures unit_name with
    | Some cached -> cached
    | None ->
        let result =
          match find_cmi t unit_name with
          | None -> None
          | Some path -> (
              let fail reason =
                t.failed_reads <- (path, reason) :: t.failed_reads;
                None
              in
              match Cmi_format.read_cmi path with
              | cmi -> Some cmi.Cmi_format.cmi_sign
              | exception Cmi_format.Error (Cmi_format.Not_an_interface _) ->
                  fail "not a compiled interface"
              | exception
                  Cmi_format.Error (Cmi_format.Wrong_version_interface (_, v))
                ->
                  fail ("compiled for " ^ v ^ " version of OCaml")
              | exception Cmi_format.Error (Cmi_format.Corrupted_interface _) ->
                  fail "corrupted or truncated"
              | exception (Sys_error _ | End_of_file | Failure _) ->
                  fail "cannot be read")
        in
        Hashtbl.add t.signatures unit_name result;
        result

  let find_module name sg =
    List.find_map
      (function
        | Types.Sig_module (id, _, md, _, _)
          when String.equal (Ident.name id) name ->
            Some md.Types.md_type
        | _ -> None)
      sg

  (* Local ([Pident]) heads resolve by ident stamp, never by name.
     The linted unit's [str_type] can hold several same-named module
     bindings — [include] keeps both the included binding and a later
     explicit one — and a first-hit name lookup reads the shadowed
     binding's identity (a use typed through [module M = Set.Make (Int)]
     matched [Stdlib.Hashtbl.t] when an included [M = Hashtbl] preceded
     it). The use-site path carries the binding's exact ident, so the
     stamp resolves both shadowing directions correctly. *)
  let find_module_by_ident id sg =
    List.find_map
      (function
        | Types.Sig_module (mid, _, md, _, _) when Ident.same mid id ->
            Some md.Types.md_type
        | _ -> None)
      sg

  let find_modtype name sg =
    List.find_map
      (function
        | Types.Sig_modtype (id, mtd, _) when String.equal (Ident.name id) name
          ->
            Some mtd.Types.mtd_type
        | _ -> None)
      sg

  (* A [Local] signature can hold several same-named [Sig_modtype]
     items — [include] keeps both the included binding and a later
     explicit one — and the use site's
     [Mty_ident] carries the exact ident, so the stamp resolves both
     shadowing directions correctly, exactly as [find_module_by_ident]. *)
  let find_modtype_by_ident id sg =
    List.find_map
      (function
        | Types.Sig_modtype (mid, mtd, _) when Ident.same mid id ->
            Some mtd.Types.mtd_type
        | _ -> None)
      sg

  let find_value name sg =
    List.find_map
      (function
        | Types.Sig_value (id, vd, _) when String.equal (Ident.name id) name ->
            Some vd.Types.val_uid
        | _ -> None)
      sg

  let find_type name sg =
    List.find_map
      (function
        | Types.Sig_type (id, td, _, _) when String.equal (Ident.name id) name
          ->
            Some td.Types.type_uid
        | _ -> None)
      sg

  (* [ctx] is the signature the module type appeared in, used to resolve
     local ([Pident]) module and module-type references, tagged with where
     it came from. [Local] — the linted unit's own [str_type], where the
     typechecker's ident stamps are live and [include] can leave several
     same-named bindings, so [Pident] lookups must go by [Ident.same]; a
     stamp miss is an honest opaque step, never a name-lookup
     guess — a name hit there could only be a *different* binding than the
     one the use site names. [Loaded] — a signature read from a cmi, where
     item names are unique by construction (the compiler deduplicates on
     write) and unmarshalled stamps need not relate to anything the use
     site carries, so lookups go by name. Signatures found inside a tagged
     signature inherit its tag; crossing into a persistent unit's cmi is
     always [Loaded]. [descend_functor] descends into functor results only
     when a canonical-name component continues into the body; path
     resolution never does. Opaque steps ([Papply], [Pextra_ty], an
     abstract module type, an undescended functor, a local head whose
     target lives in an outer signature [ctx] does not carry) yield
     [None]: the name matches nothing, per the mli.

     A [Pident] head is a compilation unit only when the ident is
     persistent: a local alias ([module Alias = Base] with [Base] a sibling
     module) records a non-persistent head, and reading a same-named
     foreign unit's cmi for it would resolve to a foreign identity —
     different bytes than the typechecker read. *)
  type ctx = Local of Types.signature | Loaded of Types.signature

  let ctx_sig = function Local sg | Loaded sg -> sg

  let in_ctx ctx sg =
    match ctx with Local _ -> Local sg | Loaded _ -> Loaded sg

  (* Where a name lookup is forced by path shape ([Pdot] carries no
     ident), the search direction must still honor shadowing. Into a [Local] signature — an unascribed local
     module's inferred signature can hold include-duplicates — the
     compiler's shadowing semantics denote the {e last} same-named item, so
     the [Local] legs run last-match; [Loaded] signatures keep first-hit
     (cmi item names are unique by construction, so the two coincide and
     first-hit stops early). *)
  let last_match f sg =
    List.fold_left
      (fun acc item -> match f item with Some _ as hit -> hit | None -> acc)
      None sg

  let find_module_ctx name = function
    | Loaded sg -> find_module name sg
    | Local sg ->
        last_match
          (function
            | Types.Sig_module (id, _, md, _, _)
              when String.equal (Ident.name id) name ->
                Some md.Types.md_type
            | _ -> None)
          sg

  let find_modtype_ctx name = function
    | Loaded sg -> find_modtype name sg
    | Local sg ->
        last_match
          (function
            | Types.Sig_modtype (id, mtd, _)
              when String.equal (Ident.name id) name ->
                Some mtd.Types.mtd_type
            | _ -> None)
          sg

  let rec signature_of_path t ~ctx path =
    match (path : Path.t) with
    | Pident id ->
        if Ident.persistent id then
          Option.map (fun sg -> Loaded sg) (signature_of_unit t (Ident.name id))
        else
          let md =
            match ctx with
            | Local sg -> find_module_by_ident id sg
            | Loaded sg -> find_module (Ident.name id) sg
          in
          Option.bind md (signature_of_mty t ~descend_functor:false ~ctx)
    | Pdot (prefix, name) -> (
        match signature_of_path t ~ctx prefix with
        | None -> None
        | Some tagged ->
            Option.bind
              (find_module_ctx name tagged)
              (signature_of_mty t ~descend_functor:false ~ctx:tagged))
    | Papply _ | Pextra_ty _ -> None

  and signature_of_mty t ~descend_functor ~ctx mty =
    match (mty : Types.module_type) with
    | Mty_signature sg -> Some (in_ctx ctx sg)
    | Mty_alias path -> signature_of_path t ~ctx path
    | Mty_ident path -> (
        let mtd =
          match (path : Path.t) with
          | Pident id -> (
              (* By stamp in the linted unit's own signature — the path
                 carries the exact ident; a name hit there could only be a
                 different binding (module-type namespace). Name lookup
                 stays correct on [Loaded]. *)
              match ctx with
              | Local sg -> find_modtype_by_ident id sg
              | Loaded sg -> find_modtype (Ident.name id) sg)
          | Pdot (prefix, name) ->
              Option.bind (signature_of_path t ~ctx prefix) (fun tagged ->
                  find_modtype_ctx name tagged)
          | Papply _ | Pextra_ty _ -> None
        in
        match mtd with
        | Some (Some mty) -> signature_of_mty t ~descend_functor:false ~ctx mty
        | Some None | None -> None)
    | Mty_functor (_, result) when descend_functor ->
        signature_of_mty t ~descend_functor ~ctx result
    | Mty_functor _ -> None

  (* [find_leaf] is the namespace: [find_value] for the value walk,
     [find_type] for the type walk. The module steps are shared. *)
  let resolve_uncached t (n : Name.t) ~find_leaf =
    match n.Name.modules with
    | [] -> assert false (* non-empty by construction *)
    | unit_name :: inner -> (
        match signature_of_unit t unit_name with
        | None -> []
        | Some root ->
            let leaf = Name.leaf_body n.Name.leaf in
            let rec walk sg = function
              | [] -> (
                  match find_leaf leaf sg with
                  | Some uid -> [ uid ]
                  | None -> [])
              | m :: rest -> (
                  match find_module m sg with
                  | None -> []
                  | Some mty -> (
                      match
                        signature_of_mty t ~descend_functor:true
                          ~ctx:(Loaded sg) mty
                      with
                      | None -> []
                      | Some tagged -> walk (ctx_sig tagged) rest))
            in
            walk root inner)

  let memoized tbl t n ~find_leaf =
    let key = Name.to_string n in
    match Hashtbl.find tbl key with
    | uids -> uids
    | exception Not_found ->
        let uids = resolve_uncached t n ~find_leaf in
        Hashtbl.add tbl key uids;
        uids

  let resolve t n = memoized t.resolutions t n ~find_leaf:find_value
  let resolve_type t n = memoized t.type_resolutions t n ~find_leaf:find_type

  (* The audit classification ([Pat.Registry]'s consumer): a name
     resolving to nothing is a typo signal only when its defining unit's
     signature is in hand — a missing cmi says nothing about the name,
     per the match-nothing contract. Unreadable cmis classify as absent
     here; they are already surfaced through [read_failures]. *)
  let probe_with t (n : Name.t) = function
    | _ :: _ -> `Resolved
    | [] -> (
        match n.Name.modules with
        | [] -> `Unresolved
        | unit_name :: _ -> (
            match signature_of_unit t unit_name with
            | None -> `Absent_unit
            | Some _ -> `Unresolved))

  let probe t n = probe_with t n (resolve t n)

  let probe_type t n =
    if Option.is_some (predef_type_ident n) then `Resolved
    else probe_with t n (resolve_type t n)

  (* A module's identity boundary: every reference reaching through the
     module is either into a compilation unit the module denotes wholly
     (the [from_unit] relation — use-site UIDs carry the unit name) or to
     a value declaration collected from an in-signature submodule walk.
     Aliases hop to their targets — a persistent head is recorded as a
     unit, everything else keeps collecting through [signature_of_path] —
     and functor results are descended (functor-body interface UIDs match
     every instance, the documented {!Scope.matches} relation). The
     [seen] guard is physical identity on visited signatures, so an
     alias cycle across cmis terminates. Constructors and record labels
     are not collected: references, not types, are the boundary — the
     [outdated-str-module] precedent. *)
  let collect_module t ~ctx mty =
    let units = ref [] and uids = ref [] and seen = ref [] in
    let add_unit u = if not (List.mem u !units) then units := u :: !units in
    let rec of_mty ~ctx mty =
      match (mty : Types.module_type) with
      | Mty_alias (Pident id) when Ident.persistent id ->
          add_unit (Ident.name id)
      | Mty_alias p -> (
          match signature_of_path t ~ctx p with
          | None -> ()
          | Some tagged -> of_sig tagged)
      | Mty_functor (_, result) -> of_mty ~ctx result
      | Mty_signature _ | Mty_ident _ -> (
          match signature_of_mty t ~descend_functor:false ~ctx mty with
          | None -> ()
          | Some tagged -> of_sig tagged)
    and of_sig tagged =
      let sg = ctx_sig tagged in
      if not (List.memq sg !seen) then begin
        seen := sg :: !seen;
        List.iter
          (function
            | Types.Sig_value (_, vd, _) -> uids := vd.Types.val_uid :: !uids
            | Types.Sig_module (_, _, md, _, _) ->
                of_mty ~ctx:tagged md.Types.md_type
            | _ -> ())
          sg
      end
    in
    of_mty ~ctx mty;
    (List.rev !units, List.rev !uids)

  (* Module-path resolution: a single component is a compilation unit —
     the [from_unit] boundary, no cmi read, so a vendored unit with no
     cmi on the search path still matches — and a dotted path walks the
     head unit's cmi through [find_module] steps exactly as canonical
     names do, then collects the final module's boundary. Failure at any
     step is [([], [])]: match-nothing, the {!resolve} contract. *)
  let resolve_module_uncached t = function
    | [] -> ([], [])
    | [ unit_name ] -> ([ unit_name ], [])
    | unit_name :: inner -> (
        match signature_of_unit t unit_name with
        | None -> ([], [])
        | Some root ->
            let rec descend sg = function
              | [] -> assert false (* [inner] is non-empty *)
              | [ last ] -> (
                  match find_module last sg with
                  | None -> ([], [])
                  | Some mty -> collect_module t ~ctx:(Loaded sg) mty)
              | m :: rest -> (
                  match find_module m sg with
                  | None -> ([], [])
                  | Some mty -> (
                      match
                        signature_of_mty t ~descend_functor:true
                          ~ctx:(Loaded sg) mty
                      with
                      | None -> ([], [])
                      | Some tagged -> descend (ctx_sig tagged) rest))
            in
            descend root inner)

  let resolve_module t (p : Module_path.t) =
    let key = Module_path.to_string p in
    match Hashtbl.find t.module_resolutions key with
    | boundary -> boundary
    | exception Not_found ->
        let boundary = resolve_module_uncached t (Module_path.components p) in
        Hashtbl.add t.module_resolutions key boundary;
        boundary

  (* Use-site view: a type-constructor path to its declaration uid, by the
     same cmi walk canonical names use. A [Pdot] resolves when its head is
     a persistent unit, or — the local-alias hop — when [local] (the linted
     unit's own signature) binds the head module by a plain alias or a
     functor application, whose signatures keep the aliased/functor-body
     interface uids; the binding is located by ident stamp, so same-named
     shadowed bindings ([include]-provided vs. a later explicit one)
     resolve to the exact binding the use site names. A named
     module-type ascription carries the module type's interface uids and
     resolves through them; an inline-signature ascription carries freshly
     minted uids and resolves to an identity no canonical name owns. A
     bare [Pident] head is predefined or a local type —
     [Scope.matches_type] owns the predefined test, and local type
     declarations have no canonical identity. Unmemoized: the signature
     reads behind it are, and the callers reach here only after a cheap
     head test. *)
  let type_uid_of_path t ~local path =
    match (path : Path.t) with
    | Path.Pdot (prefix, leaf) ->
        Option.bind (signature_of_path t ~ctx:(Local local) prefix)
          (fun tagged -> find_type leaf (ctx_sig tagged))
    | Path.Pident _ | Path.Papply _ | Path.Pextra_ty _ -> None
end

module Scope = struct
  type t = {
    resolver : Resolver.t;
    intra : Shape.Uid.t -> Shape.Uid.t list;
    local : Types.signature;
        (* the linted unit's own signature — [matches_type]'s local-alias
           context, fixed at construction so every node of a unit is
           matched under the same context *)
    accepted : (string, Shape.Uid.t list) Hashtbl.t;
        (* per canonical rendering: resolver uids + intra-unit extensions *)
    accepted_types : (string, Ident.t option * Shape.Uid.t list) Hashtbl.t;
        (* per canonical rendering: the predefined ident when [Stdlib.x]
           names a builtin type, plus the type-namespace uids *)
    accepted_modules : (string, string list * Shape.Uid.t list) Hashtbl.t;
        (* per module-path rendering: resolver boundary, uids extended
           with the intra-unit reverse image as [accepted] is *)
  }

  let v ~resolver ~intra ~local =
    {
      resolver;
      intra;
      local;
      accepted = Hashtbl.create 16;
      accepted_types = Hashtbl.create 16;
      accepted_modules = Hashtbl.create 16;
    }

  let read_failures sc = Resolver.read_failures sc.resolver

  let accepted_uids sc n =
    let key = Name.to_string n in
    match Hashtbl.find sc.accepted key with
    | uids -> uids
    | exception Not_found ->
        let canonical = Resolver.resolve sc.resolver n in
        let uids = canonical @ List.concat_map sc.intra canonical in
        Hashtbl.add sc.accepted key uids;
        uids

  let matches sc n uid = List.exists (Shape.Uid.equal uid) (accepted_uids sc n)

  let accepted_module sc p =
    let key = Module_path.to_string p in
    match Hashtbl.find sc.accepted_modules key with
    | boundary -> boundary
    | exception Not_found ->
        let units, canonical = Resolver.resolve_module sc.resolver p in
        let boundary =
          (units, canonical @ List.concat_map sc.intra canonical)
        in
        Hashtbl.add sc.accepted_modules key boundary;
        boundary

  let matches_module sc p uid =
    let units, uids = accepted_module sc p in
    (match (uid : Shape.Uid.t) with
      | Shape.Uid.Item { comp_unit; _ } ->
          List.exists (String.equal comp_unit) units
      | Shape.Uid.Compilation_unit cu -> List.exists (String.equal cu) units
      | _ -> false)
    || List.exists (Shape.Uid.equal uid) uids

  let accepted_type_ids sc (n : Name.t) =
    let key = Name.to_string n in
    match Hashtbl.find sc.accepted_types key with
    | ids -> ids
    | exception Not_found ->
        let ids = (predef_type_ident n, Resolver.resolve_type sc.resolver n) in
        Hashtbl.add sc.accepted_types key ids;
        ids

  (* The [local] hop rides the scope: the construction-time [local]
     signature resolves head modules the linted unit itself binds, so
     every node of a unit is matched under one local context. *)
  let matches_type sc n path =
    let predef, uids = accepted_type_ids sc n in
    match (path : Path.t) with
    | Path.Pident id -> (
        match predef with Some pid -> Ident.same pid id | None -> false)
    | Path.Pdot _ | Path.Papply _ | Path.Pextra_ty _ -> (
        uids <> []
        &&
        match Resolver.type_uid_of_path sc.resolver ~local:sc.local path with
        | Some uid -> List.exists (Shape.Uid.equal uid) uids
        | None -> false)
end
