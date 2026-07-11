(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

type module_ = {
  name : string;
  impl : string option;
  intf : string option;
  cmt : string option;
  cmti : string option;
}

type library = {
  name : string;
  local : bool;
  source_dir : string option;
  modules : module_ list;
  include_dirs : string list;
}

type executables = {
  names : string list;
  modules : module_ list;
  include_dirs : string list;
}

type stanza = Library of library | Executables of executables

type t = {
  root : string option;
  build_context : string option;
  stanzas : stanza list;
}

(* {1 Csexp}

   Canonical s-expressions: [atom ::= <len> ":" <bytes>], [list ::= "(" sexp*
   ")"]. Hand-rolled because csexp is not in the lock; ~30 lines against a
   frozen grammar. *)

type sexp = Atom of string | List of sexp list

exception Malformed of int * string

let parse_sexp bytes =
  let len = String.length bytes in
  let err at reason = raise_notrace (Malformed (at, reason)) in
  let rec value i =
    if i >= len then err i "unexpected end of input"
    else if bytes.[i] = '(' then items (i + 1) []
    else atom i
  and items i acc =
    if i >= len then err i "unclosed list"
    else if bytes.[i] = ')' then (List (List.rev acc), i + 1)
    else
      let v, i = value i in
      items i (v :: acc)
  and atom i =
    let j = ref i in
    while !j < len && '0' <= bytes.[!j] && bytes.[!j] <= '9' do
      incr j
    done;
    if !j = i then err i "expected a length prefix"
    else if !j >= len || bytes.[!j] <> ':' then err !j "expected ':'"
    else
      let n = int_of_string (String.sub bytes i (!j - i)) in
      let start = !j + 1 in
      if start + n > len then err start "atom extends past end of input"
      else (Atom (String.sub bytes start n), start + n)
  in
  match value 0 with
  | v, stop ->
      (* Trailing whitespace is tolerated (dune ends the reply with a
         newline); trailing data is not. *)
      let rest = String.sub bytes stop (len - stop) in
      if String.trim rest = "" then Ok v
      else Error (stop, "trailing data after the document")
  | exception Malformed (at, reason) -> Error (at, reason)

(* {1 Interpretation} *)

exception Undecodable of string

let fail fmt = Format.kasprintf (fun s -> raise_notrace (Undecodable s)) fmt

let field name fields =
  List.find_map
    (function
      | List [ Atom k; v ] when String.equal k name -> Some v | _ -> None)
    fields

let atom what = function
  | Atom a -> a
  | List _ -> fail "%s: expected an atom" what

let atoms what = function
  | List vs -> List.map (atom what) vs
  | Atom _ -> fail "%s: expected a list" what

(* [(impl (path))] carries zero or one path. *)
let path_opt what = function
  | List [] -> None
  | List [ Atom p ] -> Some p
  | _ -> fail "%s: expected zero or one path" what

let decode_module = function
  | List fields ->
      let get name = field name fields in
      let name =
        match get "name" with
        | Some v -> atom "module name" v
        | None -> fail "module without a name field"
      in
      let popt f = Option.bind (get f) (path_opt f) in
      {
        name;
        impl = popt "impl";
        intf = popt "intf";
        cmt = popt "cmt";
        cmti = popt "cmti";
      }
  | Atom _ -> fail "module: expected a list"

let decode_modules = function
  | List ms -> List.map decode_module ms
  | Atom _ -> fail "modules: expected a list"

let decode_library payload =
  let fields = match payload with List fs -> fs | Atom _ -> [] in
  let name =
    match field "name" fields with
    | Some v -> atom "library name" v
    | None -> fail "library without a name field"
  in
  let local =
    match field "local" fields with
    | Some v -> String.equal (atom "local" v) "true"
    | None -> false
  in
  let source_dir = Option.map (atom "source_dir") (field "source_dir" fields) in
  let modules =
    match field "modules" fields with Some v -> decode_modules v | None -> []
  in
  let include_dirs =
    match field "include_dirs" fields with
    | Some v -> atoms "include_dirs" v
    | None -> []
  in
  Library { name; local; source_dir; modules; include_dirs }

let decode_executables payload =
  let fields = match payload with List fs -> fs | Atom _ -> [] in
  let names =
    match field "names" fields with
    | Some v -> atoms "names" v
    | None -> fail "executables without a names field"
  in
  let modules =
    match field "modules" fields with Some v -> decode_modules v | None -> []
  in
  let include_dirs =
    match field "include_dirs" fields with
    | Some v -> atoms "include_dirs" v
    | None -> []
  in
  Executables { names; modules; include_dirs }

let decode_items items =
  let root = ref None and build_context = ref None and stanzas = ref [] in
  List.iter
    (fun item ->
      match item with
      | List [ Atom "root"; Atom v ] -> root := Some v
      | List [ Atom "build_context"; Atom v ] -> build_context := Some v
      | List [ Atom "library"; payload ] ->
          stanzas := decode_library payload :: !stanzas
      | List [ Atom "executables"; payload ] ->
          stanzas := decode_executables payload :: !stanzas
      | _ -> (* unknown item kinds are future dune; ignore *) ())
    items;
  { root = !root; build_context = !build_context; stanzas = List.rev !stanzas }

let decode bytes =
  match parse_sexp bytes with
  | Error (at, reason) -> Error (Printf.sprintf "byte %d: %s" at reason)
  | Ok (Atom _) -> Error "byte 0: expected a list of workspace items"
  | Ok (List items) -> (
      match decode_items items with
      | t -> Ok t
      | exception Undecodable reason -> Error reason)
