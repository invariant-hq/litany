(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Litany

let meta =
  Rule.meta ~name:"redundant-return-bind" ~group:Rule.Style ~since:"1.0"
    ~fix:Rule.Never
    ~summary:"bind of a fresh return wraps a value only to unwrap it"
    ~doc:
      {|Binding a freshly returned value is the left identity law: the wrap is
undone by the bind, so applying the callback to the value directly says
the same thing without the round trip.

    (* bad *)  Option.bind (Option.some x) f
    (* good *) f x

Fires when a known-lawful pair resolves by declaration and the scrutinee
is that pair's return applied to a value — the return function
(`Option.some`, `Result.ok`, `Lwt.return`) or its constructor form
(`Some x`, `Ok x`, by predefined/global constructor identity):
definitional for `Option` and `Result`, documented for `Lwt`. Arbitrary
scrutinees, `Error` (not a return), partial applications, and a
project's own `bind`/`return` deliberately do not fire — each listed
pair is an audited lawfulness claim. No fix: naming the callback's
argument is editorial.|}
    ()

(* The scrutinee is the pair's return applied to a value: the return
   function, or its constructor form — [Some]/[Ok] by predefined/global
   constructor identity. *)
let pair bind ret = Pat.(apply (ident bind) (ret ^:: drop ^:: nil))

let return_bind =
  Pat.(
    pair "Stdlib.Option.bind"
      (apply (ident "Stdlib.Option.some") (drop ^:: nil) ||| esome drop)
    ||| pair "Stdlib.Result.bind"
          (apply (ident "Stdlib.Result.ok") (drop ^:: nil) ||| eok drop)
    ||| pair "Lwt.bind" (apply (ident "Lwt.return") (drop ^:: nil))
    ||| pair "Lwt.Infix.(>>=)" (apply (ident "Lwt.return") (drop ^:: nil)))

let rule =
  Rule.expr meta @@ fun u e ->
  match Pat.run return_bind u e () with
  | None -> []
  | Some () ->
      [
        Finding.v ~loc:e.exp_loc
          "binding a fresh return wraps a value only to unwrap it; apply the \
           callback directly";
      ]
