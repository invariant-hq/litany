(* Fixture for suspicious-str-formatter: each FIRE marker sits on a
   reference resolving to Format.str_formatter or
   Format.flush_str_formatter; every other formatter use is a negative
   from the spec plus the shadowing adversarial. *)

(* The print-then-flush pair: one reference per line. *)
let render x =
  Format.fprintf Format.str_formatter "%d" x; (* FIRE *)
  String.trim (Format.flush_str_formatter ()) (* FIRE *)

(* Alias transparency: the alias resolves to the same declaration. *)
module F = Format

let via_alias () = F.flush_str_formatter () (* FIRE *)

(* The ifprintf sink: benign intent, still the shared value — the
   recorded FP risk Nursery corpus runs adjudicate. *)
let sink () = Format.ifprintf Format.str_formatter "%d" 3 (* FIRE *)

(* The total replacement. *)
let clean x = Format.asprintf "%d" x

(* Private state. *)
let buffered () =
  let b = Buffer.create 16 in
  Format.formatter_of_buffer b

(* A different value. *)
let std () = Format.std_formatter

(* Adversarial: a shadowing local Format is a different declaration. *)
module Local = struct
  module Format = struct
    let str_formatter = 0
  end

  let shadowed () = Format.str_formatter
end
