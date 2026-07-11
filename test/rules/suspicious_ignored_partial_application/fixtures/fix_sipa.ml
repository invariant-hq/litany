(* Fixture for suspicious-ignored-partial-application: positives carry
   the FIRE marker; the rest are the spec's negatives plus adversarial
   rebindings. The spec's spelled-out positives — ignore (List.iter
   print_string), save 1 |> ignore — are warning 5 errors under the dev
   profile: the compiler owns that half of the defect and this fixture
   cannot even write it — the recorded
   coverage split. *)

let f = succ
let save (_ : int) (s : string) = print_string s

(* Function values reaching ignore: closures whose remaining arguments —
   and effects — never happen, and warning 5 cannot see. *)
let iterate = List.iter print_string
let () = ignore iterate (* FIRE *)
let printer = Format.printf "%d"
let () = ignore printer (* FIRE *)
let flush = save 1
let () = flush |> ignore (* FIRE *)

(* Alias transparency: Stdlib reached through a local module alias. *)
let () =
  let module I = Stdlib in
  I.ignore f (* FIRE *)

(* A literal closure is an arrow too — the pinned decision: fires. *)
let () = ignore (fun () -> print_newline ()) (* FIRE *)

(* Saturated call: the result is unit, not an arrow. *)
let names = [ "a"; "b" ]
let () = ignore (List.iter print_string names)

(* A shadowed ignore resolves locally (adversarial shadowing). *)
let n1 =
  let ignore h = h () in
  ignore print_newline

(* A non-arrow argument. *)
let () = ignore 3

(* An abbreviation head is not expanded (documented false negative). *)
type cb = unit -> unit

let cb : cb = fun () -> ()
let () = ignore cb

(* An explicit constraint is the documented discard intent — warning 5's
   escape hatch and this rule's. *)
let () = ignore (f : _ -> _)

(* A different callee, bound to a variable (let _ = would be warning 5's
   own report). *)
let kept = Sys.opaque_identity f

(* A local module spelled Stdlib mints its own identity (adversarial). *)
module Stdlib = struct
  let ignore _ = ()
end

let () = Stdlib.ignore f
