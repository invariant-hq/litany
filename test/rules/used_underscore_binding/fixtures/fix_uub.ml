(* Fixture for used-underscore-binding: each marked line declares exactly
   one underscore-prefixed binding the unit uses somewhere; the finding
   anchors at the declaration, once per binding. Every other line is a
   negative — the prior implementation's cases plus ascription and shadowing
   adversaries. *)

let _answer = 42 (* FIRE *)
let uses_let = _answer + 1
let uses_again = _answer * 2

(* A used parameter fires at the parameter. *)
let param _x = _x + 1 (* FIRE *)

(* A used match-arm binding fires at its declaration in the pattern. *)
let match_use l = match l with _head :: _ -> _head (* FIRE *) | [] -> 0

(* A used alias binding ([as]) fires at the alias name. *)
let alias_pat p = match p with (a, _) as _pair -> a + fst _pair (* FIRE *)

(* An unused alias is the convention working. *)
let alias_unused p = match p with (x, _) as _spare -> x

(* Shadowing: the used inner [_v] is a distinct declaration and fires at
   its own declaration; the shadowed one is unused and stays clean. *)
let shadowing () =
  let _v = 1 in
  match 2 with _v -> _v + 1 (* FIRE *)

(* Double underscores follow a different convention. *)
let __internal = 7
let uses_double = __internal + 1

(* Unused underscore bindings are the convention working as intended. *)
let _unused = 3

(* Ordinary names are ordinary. *)
let ordinary = 5
let uses_ordinary = ordinary + 1

(* Tool-minted shapes stay clean even when used:
   an underscore followed by digits only is a menhir semantic value... *)
let _1 = 42
let uses_menhir = _1 + 1

(* ...and a name ending in a double underscore, digits, and a final
   underscore is a ppx-minted internal. *)
let _of_a__001_ = 3
let uses_ppx = _of_a__001_ + 1

(* Adversarial lookalikes still fire: digits not at the tail... *)
let _1x = 4 (* FIRE *)
let uses_digit_prefix = _1x + 1

(* ...one underscore before the digit run... *)
let _v_1_ = 5 (* FIRE *)
let uses_single_run = _v_1_ + 1

(* ...and no digits between the double underscore and the tail. *)
let _a___ = 6 (* FIRE *)
let uses_no_digits = _a___ + 1

(* A qualified use through a module path is a use of the declaration. *)
module M = struct
  let _hidden = 9 (* FIRE *)
end

let qualified = M._hidden

(* A signature ascription mints a fresh identity: the qualified use
   carries the ascription's uid, not the declaration's. *)
module A : sig
  val _sealed : int
end = struct
  let _sealed = 11
end

let through_seal = A._sealed

(* Tuple-pattern components are distinct bindings (adopted from the
   prior implementation's suite): each used component fires once, at
   its own declaration — once per binding, never once per pattern. *)
let ( _first (* FIRE *),
      _second (* FIRE *) ) =
  (1, 2)

let uses_tuple = _first + _second
