(* Fixture for suspicious-failwith-in-library: each marked line is a
   reference resolving to Stdlib.failwith outside any enclosing try; the
   other lines are the spec's negatives plus adversarial extras. The
   kind gate is roster metadata, so the suite runs this one artifact
   under Library (fires), Executable, Test, and no kind (all silent). *)

(* Boundary escapes. *)
let connect m = failwith ("TLS configuration error: " ^ m) (* FIRE *)
let short_write () : int = Stdlib.failwith "short write" (* FIRE *)

(* Aliasing a failwith is a failwith: the reference itself fires; the
   alias's own uses resolve locally and do not. *)
let fail = failwith (* FIRE *)
let use_fail () : unit = fail "invariant violated"

(* negative: the same-function trampoline — raise here, catch here. *)
let trampoline g =
  try if g () then Ok 1 else failwith "no" with Failure e -> Error e

(* negative (recorded FN, pinned): any enclosing try exempts — the spec
   narrows the exemption to handlers matching Stdlib.Failure, which
   needs a pattern-side exception-constructor view. *)
let too_wide g = try failwith (g ()) with Not_found -> 0

(* negative: a locally shadowed failwith resolves locally. *)
let shadowed () =
  let failwith code = Error code in
  failwith 3

(* negative (adversarial): a same-spelled function from a local module. *)
module Report = struct
  let failwith msg = Error msg
end

let local_failwith () = Report.failwith "m"
