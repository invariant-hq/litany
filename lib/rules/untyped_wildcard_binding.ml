(*---------------------------------------------------------------------------
   Copyright (c) 2026 Hypha Technologies Ltd.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"untyped-wildcard-binding" ~group:Rule.Restriction
    ~since:"1.1" ~fix:Rule.Never
    ~summary:"let _ discards a value without naming its type"
    ~doc:
      {|`let _ = e` throws a value away; naming its type keeps the throw
honest, so the day `e` returns a partial application, a promise or a
`result` the discard no longer compiles. `untyped-ignore` is the same
rule for `ignore`.

    (* bad *)  let _ = write path text in ...
    (* good *) let (_ : (unit, error) result) = write path text in ...

Why restrict this? Discarding is legitimate OCaml; naming the type of
every discard is a discipline a house adopts.

Fires at a wildcard binding, at any depth, whose pattern carries no
type constraint. `let (_ : t) = e`, a named binding (`let _x = e`
included), `let () = e`, and a wildcard nested in a pattern deliberately
do not fire. No fix: only the author knows the type meant.|}
    ()

let constrained (p : Typedtree.pattern) =
  List.exists
    (fun (extra, _, _) ->
      match extra with Typedtree.Tpat_constraint _ -> true | _ -> false)
    p.pat_extra

let rule =
  Rule.binding meta @@ fun _ vb ->
  match vb.Typedtree.vb_pat.pat_desc with
  | Tpat_any when not (constrained vb.vb_pat) ->
      [
        Finding.v ~loc:vb.vb_pat.pat_loc
          "let _ discards a value without naming its type: let (_ : t) = e";
      ]
  | _ -> []
