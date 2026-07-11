(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

type atom = { value : string; line : int; col : int }

(* The positioned-sexp vocabulary and its error shape live in the neutral
   [Sexp] leaf: this parser and the rule SDK ([Rule.Options])
   are both its clients, so neither depends on the other to name a payload
   or a position. *)
module Sexp = Sexp
module Error = Sexp.Error

exception Fail of Error.t

let fail line col fmt =
  Printf.ksprintf (fun message -> raise (Fail { Error.line; col; message })) fmt

(* {1 Did-you-mean} *)

(* The did-you-mean metric is [Suggest.suggest] — its one home,
   never a local copy. The domain stays otherwise dependency-free:
   litany_suggest itself depends on nothing, so the leaf costs no
   compiler-libs or registry edge. *)
let hint ~candidates s =
  match Suggest.suggest ~candidates s with
  | Some c -> Printf.sprintf " (did you mean %S?)" c
  | None -> ""

(* {1 Globs} *)

module Glob = struct
  type piece = Lit of string | Star | Question
  type component = Doublestar | Pieces of piece list
  type t = { spelling : string; components : component list }

  let to_string g = g.spelling
  let pp ppf g = Format.pp_print_string ppf g.spelling

  let pieces_of_component s =
    let n = String.length s in
    let rec go acc i =
      if i >= n then List.rev acc
      else
        match s.[i] with
        | '*' -> go (Star :: acc) (i + 1)
        | '?' -> go (Question :: acc) (i + 1)
        | _ ->
            let j = ref i in
            while !j < n && s.[!j] <> '*' && s.[!j] <> '?' do
              incr j
            done;
            go (Lit (String.sub s i (!j - i)) :: acc) !j
    in
    go [] 0

  let has_doublestar s =
    let n = String.length s in
    let rec go i =
      i + 1 < n && ((s.[i] = '*' && s.[i + 1] = '*') || go (i + 1))
    in
    go 0

  let of_string spelling =
    if spelling = "" then Error "empty glob"
    else if String.contains spelling '\000' then Error "NUL byte"
    else if String.contains spelling '\\' then Error "backslash"
    else
      let parts = String.split_on_char '/' spelling in
      let last = List.length parts - 1 in
      let rec build i prev_doublestar acc = function
        | [] -> Ok { spelling; components = List.rev acc }
        | "" :: _ when i = 0 -> Error "absolute glob"
        | "" :: _ when i = last -> Error "trailing '/'"
        | "" :: _ -> Error "empty component"
        | "." :: _ -> Error "'.' component"
        | ".." :: _ -> Error "'..' component"
        | "**" :: rest ->
            if prev_doublestar then Error "adjacent '**' components"
            else build (i + 1) true (Doublestar :: acc) rest
        | c :: rest ->
            if has_doublestar c then Error "'**' must be a whole component"
            else
              build (i + 1) false (Pieces (pieces_of_component c) :: acc) rest
      in
      build 0 false [] parts

  let rec match_pieces pieces s i =
    let n = String.length s in
    match pieces with
    | [] -> i = n
    | Lit l :: rest ->
        let ln = String.length l in
        i + ln <= n && String.sub s i ln = l && match_pieces rest s (i + ln)
    | Question :: rest -> i < n && match_pieces rest s (i + 1)
    | Star :: rest ->
        let rec from j = j <= n && (match_pieces rest s j || from (j + 1)) in
        from i

  let rec match_components comps parts =
    match (comps, parts) with
    | [], [] -> true
    | [], _ :: _ | Pieces _ :: _, [] -> false
    | [ Doublestar ], parts -> parts <> [] (* a final ** matches one or more *)
    | Doublestar :: rest, parts -> (
        (* non-final: zero or more complete components *)
        match_components rest parts
        || match parts with [] -> false | _ :: tl -> match_components comps tl)
    | Pieces ps :: rest, part :: tl ->
        match_pieces ps part 0 && match_components rest tl

  let canonical_parts path =
    if path = "" || String.contains path '\000' then None
    else
      let parts = String.split_on_char '/' path in
      if List.exists (fun p -> p = "" || p = "." || p = "..") parts then None
      else Some parts

  let matches g path =
    match canonical_parts path with
    | Some parts -> match_components g.components parts
    | None ->
        invalid_arg
          (Printf.sprintf "Config_file.Glob.matches: non-canonical path %S" path)
end

(* {1 Lexing and reading} *)

type cursor = {
  src : string;
  mutable pos : int;
  mutable line : int;
  mutable bol : int;
}

let cursor src = { src; pos = 0; line = 1; bol = 0 }
let col c = c.pos - c.bol + 1
let at_eof c = c.pos >= String.length c.src
let peek c = c.src.[c.pos]

let advance c =
  let nl = c.src.[c.pos] = '\n' in
  c.pos <- c.pos + 1;
  if nl then begin
    c.line <- c.line + 1;
    c.bol <- c.pos
  end

let rec skip_blank c =
  if not (at_eof c) then
    match peek c with
    | ' ' | '\t' | '\r' | '\n' ->
        advance c;
        skip_blank c
    | ';' ->
        while (not (at_eof c)) && peek c <> '\n' do
          advance c
        done;
        skip_blank c
    | _ -> ()

let is_delimiter = function
  | ' ' | '\t' | '\r' | '\n' | '(' | ')' | ';' | '"' -> true
  | _ -> false

let read_bare c =
  let start = c.pos in
  while (not (at_eof c)) && not (is_delimiter (peek c)) do
    advance c
  done;
  String.sub c.src start (c.pos - start)

let read_quoted c ~qline ~qcol =
  advance c (* opening quote *);
  let buf = Buffer.create 16 in
  let rec go () =
    if at_eof c then fail qline qcol "unterminated string"
    else
      match peek c with
      | '"' ->
          advance c;
          Buffer.contents buf
      | '\\' ->
          let eline = c.line and ecol = col c in
          advance c;
          if at_eof c then fail qline qcol "unterminated string"
          else begin
            (match peek c with
            | '\\' -> Buffer.add_char buf '\\'
            | '"' -> Buffer.add_char buf '"'
            | 'n' -> Buffer.add_char buf '\n'
            | 't' -> Buffer.add_char buf '\t'
            | 'r' -> Buffer.add_char buf '\r'
            | ch -> fail eline ecol "unknown escape \"\\%c\" in string" ch);
            advance c;
            go ()
          end
      | ch ->
          Buffer.add_char buf ch;
          advance c;
          go ()
  in
  go ()

let rec read c =
  let line = c.line and cl = col c in
  match peek c with
  | '(' ->
      advance c;
      let items = read_items c ~oline:line ~ocol:cl in
      { Sexp.desc = List items; line; col = cl }
  | ')' -> fail line cl "unmatched \")\""
  | '"' ->
      { Sexp.desc = Atom (read_quoted c ~qline:line ~qcol:cl); line; col = cl }
  | _ -> { Sexp.desc = Atom (read_bare c); line; col = cl }

and read_items c ~oline ~ocol =
  skip_blank c;
  if at_eof c then fail oline ocol "unclosed \"(\""
  else if peek c = ')' then begin
    advance c;
    []
  end
  else
    let x = read c in
    x :: read_items c ~oline ~ocol

let read_all c =
  let rec go acc =
    skip_blank c;
    if at_eof c then List.rev acc else go (read c :: acc)
  in
  go []

(* {1 Configurations} *)

module Rule_options = struct
  type t = { name : atom; options : Sexp.t list }

  let name r = r.name
  let options r = r.options
end

module Per_path = struct
  type t = {
    globs : (atom * Glob.t) list;
    ignored : atom list;
    reason : string option;
  }

  let globs p = p.globs
  let ignored p = p.ignored
  let reason p = p.reason
  let matches p path = List.exists (fun (_, g) -> Glob.matches g path) p.globs
end

type t = {
  version : int;
  select : atom list;
  extend : atom list;
  ignored : atom list;
  closed_world : bool;
  rules : Rule_options.t list;
  per_paths : Per_path.t list;
}

let empty =
  {
    version = 1;
    select = [];
    extend = [];
    ignored = [];
    closed_world = false;
    rules = [];
    per_paths = [];
  }

let version c = c.version
let select c = c.select
let extend c = c.extend
let ignored c = c.ignored
let closed_world c = c.closed_world
let rules c = c.rules
let per_paths c = c.per_paths

(* {1 The closed schema} *)

let atom_of ~what (s : Sexp.t) : atom =
  match s.desc with
  | Sexp.Atom value -> { value; line = s.line; col = s.col }
  | Sexp.List _ -> fail s.line s.col "expected %s" what

(* [each_key ~context ~keys items handle] iterates the [(key ...)] forms of a
   keyed form's body, refusing bare items and unknown keys. Duplicate keys are
   the caller's check — it owns the slots. *)
let each_key ~context ~keys items handle =
  List.iter
    (fun (item : Sexp.t) ->
      match item.desc with
      | Sexp.List ({ Sexp.desc = Sexp.Atom key; line; col } :: args) ->
          if List.mem key keys then handle ~key ~line ~col args
          else
            fail line col "unknown key %S in (%s ...)%s" key context
              (hint ~candidates:keys key)
      | _ ->
          fail item.line item.col "expected a (key ...) form in (%s ...)"
            context)
    items

let set_once ~context slot ~key ~line ~col v =
  match !slot with
  | Some _ -> fail line col "duplicate key %S in (%s ...)" key context
  | None -> slot := Some v

let parse_lint items =
  let context = "lint" in
  let select = ref None
  and extend = ref None
  and ignored = ref None
  and closed_world = ref None in
  let tokens = List.map (atom_of ~what:"a rule or group name") in
  each_key ~context ~keys:[ "select"; "extend"; "ignore"; "closed-world" ] items
    (fun ~key ~line ~col args ->
      match key with
      | "select" -> set_once ~context select ~key ~line ~col (tokens args)
      | "extend" -> set_once ~context extend ~key ~line ~col (tokens args)
      | "ignore" -> set_once ~context ignored ~key ~line ~col (tokens args)
      | _ -> (
          match args with
          | [ { Sexp.desc = Sexp.Atom "true"; _ } ] ->
              set_once ~context closed_world ~key ~line ~col true
          | [ { Sexp.desc = Sexp.Atom "false"; _ } ] ->
              set_once ~context closed_world ~key ~line ~col false
          | _ -> fail line col "(closed-world ...) expects true or false"));
  ( Option.value !select ~default:[],
    Option.value !extend ~default:[],
    Option.value !ignored ~default:[],
    Option.value !closed_world ~default:false )

let parse_per_path ~line ~col items =
  let context = "per-path" in
  let paths = ref None and ignored = ref None and reason = ref None in
  each_key ~context ~keys:[ "paths"; "ignore"; "reason" ] items
    (fun ~key ~line:kline ~col:kcol args ->
      match key with
      | "paths" ->
          if args = [] then
            fail kline kcol "(paths ...) expects at least one glob";
          let globs =
            List.map
              (fun s ->
                let a = atom_of ~what:"a glob" s in
                match Glob.of_string a.value with
                | Ok g -> (a, g)
                | Error why ->
                    fail a.line a.col "invalid glob %S: %s" a.value why)
              args
          in
          set_once ~context paths ~key ~line:kline ~col:kcol globs
      | "ignore" ->
          if args = [] then
            fail kline kcol
              "(ignore ...) expects at least one rule or group name";
          set_once ~context ignored ~key ~line:kline ~col:kcol
            (List.map (atom_of ~what:"a rule or group name") args)
      | _ -> (
          match args with
          | [ { Sexp.desc = Sexp.Atom v; _ } ] ->
              set_once ~context reason ~key ~line:kline ~col:kcol v
          | _ -> fail kline kcol "(reason ...) expects one string"));
  match (!paths, !ignored) with
  | None, _ -> fail line col "(per-path ...) requires (paths ...)"
  | _, None -> fail line col "(per-path ...) requires (ignore ...)"
  | Some globs, Some ignored -> { Per_path.globs; ignored; reason = !reason }

let top_candidates = [ "lint"; "litany-config"; "per-path"; "rule" ]
let is_digits s = s <> "" && String.for_all (fun ch -> ch >= '0' && ch <= '9') s

let interpret forms =
  let version = ref 1 in
  let lint = ref None in
  let rules = ref [] in
  let per_paths = ref [] in
  List.iteri
    (fun idx (form : Sexp.t) ->
      match form.desc with
      | Sexp.List ({ Sexp.desc = Sexp.Atom name; line; col } :: rest) -> (
          match name with
          | "litany-config" -> (
              if idx <> 0 then
                fail line col "(litany-config ...) must be the first form"
              else
                match rest with
                | [ { Sexp.desc = Sexp.Atom v; line = vl; col = vc } ]
                  when is_digits v -> (
                    match int_of_string_opt v with
                    | Some n when n = 1 -> version := n
                    | Some n ->
                        fail vl vc
                          "unsupported config version %d (this litany reads \
                           version 1)"
                          n
                    | None ->
                        fail line col
                          "(litany-config ...) expects one integer version")
                | _ ->
                    fail line col
                      "(litany-config ...) expects one integer version")
          | "lint" ->
              if Option.is_some !lint then
                fail line col "duplicate (lint ...) form"
              else lint := Some (parse_lint rest)
          | "rule" -> (
              match rest with
              | { Sexp.desc = Sexp.Atom value; line = nl; col = nc } :: options
                ->
                  if
                    List.exists
                      (fun r -> (Rule_options.name r).value = value)
                      !rules
                  then fail nl nc "duplicate (rule %S) form" value
                  else
                    rules :=
                      {
                        Rule_options.name = { value; line = nl; col = nc };
                        options;
                      }
                      :: !rules
              | s :: _ ->
                  fail s.Sexp.line s.Sexp.col "(rule ...) expects a rule name"
              | [] -> fail line col "(rule ...) expects a rule name")
          | "per-path" ->
              per_paths := parse_per_path ~line ~col rest :: !per_paths
          | _ ->
              fail line col "unknown form %S%s" name
                (hint ~candidates:top_candidates name))
      | Sexp.List _ -> fail form.line form.col "expected a form name"
      | Sexp.Atom _ -> fail form.line form.col "expected a (...) form")
    forms;
  let select, extend, ignored, closed_world =
    Option.value !lint ~default:([], [], [], false)
  in
  {
    version = !version;
    select;
    extend;
    ignored;
    closed_world;
    rules = List.rev !rules;
    per_paths = List.rev !per_paths;
  }

let parse src =
  match interpret (read_all (cursor src)) with
  | t -> Ok t
  | exception Fail e -> Error e

let check_names c ~selection ~rules =
  let check what candidates (a : atom) =
    if not (List.mem a.value candidates) then
      fail a.line a.col "unknown %s %S%s" what a.value
        (hint ~candidates a.value)
  in
  match
    List.iter (check "rule or group" selection) c.select;
    List.iter (check "rule or group" selection) c.extend;
    List.iter (check "rule or group" selection) c.ignored;
    List.iter
      (fun p ->
        List.iter (check "rule or group" selection) (Per_path.ignored p))
      c.per_paths;
    List.iter (fun r -> check "rule" rules (Rule_options.name r)) c.rules
  with
  | () -> Ok ()
  | exception Fail e -> Error e
