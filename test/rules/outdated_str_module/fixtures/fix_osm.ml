(* Fixture for outdated-str-module: references into the Str compilation
   unit collapse to one finding per referenced declaration per unit,
   anchored at the first reference — one reference per line so the
   markers stay exact. *)

let re = Str.regexp "a+" (* FIRE *)
let matched s = Str.string_match re s 0 (* FIRE *)
let group () = Str.matched_group 1 "input" (* FIRE *)

(* An alias does not launder the identity — and the direct spelling
   further down joins this reference's cluster: the declaration UID,
   not the spelling, is the cluster key, so the alias reference anchors
   and the message still names Str.quote. *)
module R = Str

let quoted s = R.quote s (* FIRE *)

(* A cluster: three references to one declaration are one finding at
   the first, its message counting all three. *)
let r1 = Str.global_replace re "x" "abc" (* FIRE *)
let r2 = Str.global_replace re "y" "abca"
let r3 s = Str.global_replace re "z" s

(* Two declarations interleaved are two clusters, one finding each —
   the cluster is the declaration, not the dense region. *)
let s1 = Str.split re "a,b" (* FIRE *)
let b1 = Str.bounded_split re "a,b" 1 (* FIRE *)
let s2 = Str.split re "c,d"
let b2 = Str.bounded_split re "c,d" 2

(* The direct spelling that joins the alias-anchored quote cluster. *)
let quoted_again s = Str.quote s

(* Constructors are not value references: references, not types, are the
   finding unit, so Str.split_result data stays clean today. *)
let delim = Str.Delim ","

(* Adversarial: a functor parameter named Str mints parameter-local
   identities, whatever it is applied to. *)
module F (Str : sig
  val regexp : string -> string
end) =
struct
  let local = Str.regexp "b*"
end

(* A value merely named str. *)
let str = "not the module"
let still_clean = str

(* A project-local module named Str shadows the unit from here down:
   local identities, clean — the documented carve-out. *)
module Str = struct
  let regexp (s : string) = s
end

let n1 = Str.regexp "c?"
