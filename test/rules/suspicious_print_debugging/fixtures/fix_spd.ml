(* Fixture for suspicious-print-debugging: each marked line references a
   console printing entrypoint; every other line is a negative from the
   spec plus adversarial extras. The kind gate is roster metadata, so
   the suite runs this one artifact under Library (fires), Executable,
   Test, and no kind (all silent). *)

let dump x = string_of_int x

(* Direct references to the listed printers. *)
let show st = print_endline ("state: " ^ dump st) (* FIRE *)
let banner () = print_string "litany" (* FIRE *)
let debug n = Printf.printf "DEBUG %d\n" n (* FIRE *)
let complain n = Printf.eprintf "DEBUG %d\n" n (* FIRE *)
let warn s = prerr_endline s (* FIRE *)

(* An alias to a printer is a printer: the reference itself fires; the
   alias's own uses resolve locally and do not. *)
let log = Printf.printf (* FIRE *)
let use_log () = log "%d" 1

(* Module aliasing is transparent to resolved identity. *)
module P = Printf

let via_alias n = P.printf "%d" n (* FIRE *)

(* String builders are not output. *)
let build n = Printf.sprintf "%d" n
let buffered buf s = Printf.bprintf buf "%s" s

(* Format.printf is deliberately unlisted in this version. *)
let formatted n = Format.printf "%d" n

(* Shadowing: a local print_endline resolves to a local declaration. *)
let shadowed buf x =
  let print_endline s = Buffer.add_string buf s in
  print_endline x

(* Adversarial extra: a same-spelled local Printf is a different
   module. *)
module Printf = struct
  let printf _ = ()
end

let lookalike () = Printf.printf "not the stdlib one"
