(* Fixture for manual-format-quoting: positives carry the FIRE marker;
   every other binding is a negative lookalike from the spec plus
   adversarial extras. *)

(* Hand-quoted %s in a printf. *)
let p1 x = Printf.sprintf "a\"%s\"b" x (* FIRE *)

(* Any format6 consumer: the literal is keyed, not the function. *)
let p2 n = Format.asprintf "name=\"%s\"" n (* FIRE *)

(* A user-defined consumer still elaborates the literal at the call. *)
let my_log fmt = Printf.sprintf fmt
let p3 id = my_log "id \"%s\"" id (* FIRE *)

(* Box directives produce nested ghost formats; exactly one finding. *)
let p4 x = Format.asprintf "@[a \"%s\"@]" x (* FIRE *)

(* negative: already %S *)
let n1 x = Printf.sprintf "a%Sb" x

(* negative: a plain string is never elaborated to a format *)
let n2 = "write \"%s\" here"

(* negative: unquoted %s *)
let n3 x = Printf.sprintf "%s" x

(* negative: a dynamic format has no literal *)
let n4 s = Scanf.format_from_string s "%s"

(* negative: a sub-format literal whose outer format is clean *)
let n5 x = Format.asprintf "@[%S@]" x

(* negative (adversarial): a same-named module cannot fake the identity *)
module Fake = struct
  module CamlinternalFormatBasics = struct
    type fmt = F
    type format6 = Format of fmt * string
  end

  let v = CamlinternalFormatBasics.Format (CamlinternalFormatBasics.F, "\"%s\"")
end

(* negative (adversarial extra): the quotes must be adjacent to %s *)
let n6 x = Printf.sprintf "\" %s \"" x
