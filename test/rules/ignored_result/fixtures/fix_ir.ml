(* Fixture for ignored-result: each marked line is a wildcard binding
   discarding a value whose head type is canonically Stdlib.result or
   Stdlib.option; every other line is a negative — the old suite's
   expressible cases plus fresh same-spelling and abbreviation
   adversaries. *)

let make_result () : (int, string) result = Ok 1
let make_option () = Some 3

(* Wildcard discards of canonical result and option, at the top level. *)
let _ = make_result () (* FIRE *)
let _ = make_option () (* FIRE *)

(* A local wildcard binding fires too. *)
let local () =
  let _ (* FIRE *) = make_result () in
  ()

(* Foreign declarations whose types head at Stdlib.result / the
   predefined option. *)
let _ = Result.ok 4 (* FIRE *)
let _ = List.nth_opt [ 1 ] 0 (* FIRE *)

(* Named bindings are not wildcard discards — underscore-prefixed ones
   included. *)
let named = make_result ()
let _named = make_option ()
let () = ignore named

(* Unit and every other head type stay clean. *)
let _ = print_newline ()
let _ = 1 + 2
let _ = [ make_option () ]
let _ = (make_option (), 1)
let _ = fun () -> make_result ()
let _ = Bool.equal true false

(* ignore consumes the value: an application, not a binding. *)
let _ = ignore (make_result ())

(* An abbreviation head is not expanded. *)
type alias = int option

let make_alias () : alias = Some 5
let _ = make_alias ()

(* Same-spelling local declarations are distinct identities. *)
type ('a, 'b) result = Okay of 'a | Nope of 'b
type 'a option = Present of 'a | Absent

let _ = Okay 1
let _ = Nope "e"
let _ = Present 2
let _ = (Absent : int option)

(* Documentation-by-fixture, adopted from the prior implementation's
   suite: the warning-10 positions — a sequence's left-hand side and a
   for-loop body — discard values too, but this rule anchors on the
   wildcard *binding* pattern, so neither can fire here structurally. The
   compiler's own warning 10 (non-unit statement) owns them; disabled
   locally so the fixture compiles. *)
let[@warning "-10"] sequence_lhs () =
  make_result ();
  ()

let[@warning "-10"] loop_body () =
  for _i = 1 to 2 do
    make_option ()
  done
