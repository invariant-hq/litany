(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"manual-temp-dir" ~group:Rule.Suspicious ~since:"1.0"
    ~fix:Rule.Sometimes
    ~summary:"temp file removed and re-created as a directory"
    ~doc:
      {|`Filename.temp_file` creates the file exclusively — that exclusivity
is its entire security contract. Removing the file and re-creating its
name as a directory forfeits it: between the remove and the mkdir any
other process can claim the now-predictable path in a shared temp
directory (CWE-377), making the mkdir fail — or succeed inside an
attacker-provided symlinked parent where the temp directory is shared.
`Filename.temp_dir` (stdlib since 5.1, always inside the support
window) is the atomic, dedicated form.

    (* bad *)  let d = Filename.temp_file p "" in
               Sys.remove d; Sys.mkdir d 0o700; ...
    (* good *) let d = Filename.temp_dir p "" in ...

Fires on the three-step sequence: a binding of a `Filename.temp_file`
application (the omitted `?temp_dir` is tolerated) whose body removes
the bound path (`Sys.remove` or `Unix.unlink`) and then — directly, or
after one intervening statement in this version's window — re-creates
it with `Unix.mkdir` or `Sys.mkdir`. Path identity is the bound
declaration's, never spelling: removing or making some other path
never counts. Anchored at the `temp_file` application. The fix
rewrites the direct shape to `Filename.temp_dir`, dropping the remove
and mkdir statements, when the unit is not preprocessed, the callee is
spelled exactly `Filename.temp_file`, the argument gaps are pure
whitespace (a written `~temp_dir:` refuses), the permission argument
is an integer literal (carried as `~perms:` unless it is `0o700`,
`temp_dir`'s default), the mkdir is followed by further statements
(so the binding still binds a path the rest uses), and no comment sits
in the deleted region. Any refused gate refuses the fix, never the
finding. The sequence split across helper functions is a documented
false negative.|}
    ()

let message =
  "removing a temp file to re-create its name as a directory races; use \
   Filename.temp_dir"

let temp_file_call =
  Pat.(
    apply_opt
      (as__ (ident "Stdlib.Filename.temp_file"))
      (as__ drop ^:: as__ drop ^:: nil))

let removes = [ "Stdlib.Sys.remove"; "Unix.unlink" ]
let mkdirs = [ "Unix.mkdir"; "Stdlib.Sys.mkdir" ]

(* body = [remove; rest]: the remove statement, the removed path, and
   the rest of the statement spine. *)
let remove_then =
  Pat.(seq_ (as__ (apply (idents removes) (var ^:: nil))) (as__ drop))

(* rest = [mkdir; tail]: the fixable direct shape, capturing the made
   path, the permission expression, and the tail the binding survives
   into. *)
let mkdir_then =
  Pat.(seq_ (apply (idents mkdirs) (var ^:: as__ drop ^:: nil)) (as__ drop))

(* rest = [mkdir] alone: the sequence ends at the mkdir. *)
let mkdir_last = Pat.(apply (idents mkdirs) (var ^:: as__ drop ^:: nil))
let is_bound id = function Path.Pident i -> Ident.same i id | _ -> false

(* How the mkdir follows the remove: directly with a tail (the fixable
   shape), or as the final statement / after one intervening statement
   (finding only). *)
type shape =
  | Direct of Typedtree.expression * Typedtree.expression
      (** permission expression, tail *)
  | Unfixable

let mkdir_shape u id rest =
  let direct rest' =
    match
      Pat.run mkdir_then u rest' (fun path perms tail -> (path, perms, tail))
    with
    | Some (path, perms, tail) when is_bound id path -> Some (perms, tail)
    | Some _ | None -> None
  in
  let last rest' =
    match Pat.run mkdir_last u rest' (fun path _perms -> path) with
    | Some path when is_bound id path -> true
    | Some _ | None -> false
  in
  match direct rest with
  | Some (perms, tail) -> Some (Direct (perms, tail))
  | None ->
      if last rest then Some Unfixable
      else
        (* One intervening statement in this version's window. *)
        Option.bind
          (Pat.run Pat.(seq_ drop (as__ drop)) u rest Fun.id)
          (fun rest' ->
            if Option.is_some (direct rest') || last rest' then Some Unfixable
            else None)

let cn (p : Lexing.position) = p.Lexing.pos_cnum

let span_of start stop =
  if start < 0 || stop < start then None else Some (Span.v ~start ~stop)

let slice_of u start stop =
  Option.bind (span_of start stop) (Source.slice (Unit.source u))

let is_ws s =
  String.for_all (function ' ' | '\t' | '\n' | '\r' -> true | _ -> false) s

let no_comment s =
  let n = String.length s in
  let rec go i =
    i + 1 >= n || ((s.[i] <> '(' || s.[i + 1] <> '*') && go (i + 1))
  in
  go 0

(* The fix, for the direct shape only: replace the callee with
   [Filename.temp_dir], carry a non-default literal permission as
   [~perms:], and delete the remove and mkdir statements. *)
let temp_dir_fix u (callee : Typedtree.expression) (pre : Typedtree.expression)
    (suf : Typedtree.expression) (perms : Typedtree.expression)
    (remove : Typedtree.expression) (tail : Typedtree.expression) =
  if Unit.preprocessed u then None
  else
    let c0 = cn callee.exp_loc.Location.loc_start
    and c1 = cn callee.exp_loc.Location.loc_end
    and pre0 = cn pre.exp_loc.Location.loc_start
    and pre1 = cn pre.exp_loc.Location.loc_end
    and suf0 = cn suf.exp_loc.Location.loc_start
    and suf1 = cn suf.exp_loc.Location.loc_end
    and rm0 = cn remove.exp_loc.Location.loc_start
    and tl0 = cn tail.exp_loc.Location.loc_start in
    let perms_edits =
      match perms.exp_desc with
      | Typedtree.Texp_constant (Asttypes.Const_int 0o700) -> Some []
      | Typedtree.Texp_constant (Asttypes.Const_int _) ->
          Option.bind (span_of suf1 suf1) (fun at ->
              Option.map
                (fun p -> [ { Fix.span = at; text = " ~perms:" ^ p } ])
                (Unit.splice u perms))
      | _ -> None
    in
    match
      ( slice_of u c0 c1,
        slice_of u c1 pre0,
        slice_of u pre1 suf0,
        slice_of u rm0 tl0,
        perms_edits )
    with
    | Some "Filename.temp_file", Some g1, Some g2, Some deleted, Some perms
      when is_ws g1 && is_ws g2 && no_comment deleted -> (
        match (span_of c0 c1, span_of rm0 tl0) with
        | Some callee_span, Some deleted_span ->
            Some
              (Fix.v ~applicability:Fix.Safe ~title:"use Filename.temp_dir"
                 ({ Fix.span = callee_span; text = "Filename.temp_dir" }
                 :: { Fix.span = deleted_span; text = "" }
                 :: perms))
        | _, _ -> None)
    | _, _, _, _, _ -> None

let rule =
  Rule.expr meta @@ fun u e ->
  match e.exp_desc with
  | Typedtree.Texp_let (Asttypes.Nonrecursive, [ vb ], body) -> (
      match Pat.run Pat.pvar u vb.Typedtree.vb_pat Fun.id with
      | None -> []
      | Some id -> (
          match
            Pat.run temp_file_call u vb.Typedtree.vb_expr (fun callee pre suf ->
                (callee, pre, suf))
          with
          | None -> []
          | Some (callee, pre, suf) -> (
              match
                Pat.run remove_then u body (fun rm path rest ->
                    (rm, path, rest))
              with
              | Some (rm, path, rest) when is_bound id path -> (
                  match mkdir_shape u id rest with
                  | Some (Direct (perms, tail)) ->
                      let fix = temp_dir_fix u callee pre suf perms rm tail in
                      [
                        Finding.v ?fix ~loc:vb.Typedtree.vb_expr.exp_loc message;
                      ]
                  | Some Unfixable ->
                      [ Finding.v ~loc:vb.Typedtree.vb_expr.exp_loc message ]
                  | None -> [])
              | Some _ | None -> [])))
  | _ -> []
