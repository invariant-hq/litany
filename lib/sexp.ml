(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

type t = { desc : desc; line : int; col : int }
and desc = Atom of string | List of t list

let is_plain_atom s =
  s <> ""
  && String.for_all
       (function
         | ' ' | '\t' | '\r' | '\n' | '(' | ')' | ';' | '"' -> false | _ -> true)
       s

let rec pp ppf t =
  match t.desc with
  | Atom a ->
      if is_plain_atom a then Format.pp_print_string ppf a
      else Format.fprintf ppf "%S" a
  | List items ->
      Format.fprintf ppf "(@[<hv>%a@])"
        (Format.pp_print_list ~pp_sep:Format.pp_print_space pp)
        items

module Error = struct
  type t = { line : int; col : int; message : string }

  let line e = e.line
  let column e = e.col
  let message e = e.message

  let to_string ?(file = "litany") e =
    Printf.sprintf "%s:%d:%d: %s" file e.line e.col e.message

  let pp ppf e = Format.pp_print_string ppf (to_string e)
end
