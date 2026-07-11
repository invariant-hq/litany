(* Fixture for restricted-dependency. The suite configures the rule with
     (forbid Str …)                — a whole compilation unit
     (forbid Rd_dep.Internal …)    — an in-signature submodule
     (forbid Stdlib.invalid_arg …) — one value
     (forbid Stdlib.Obj …)         — a module reached through an alias
   plus forbids that must resolve to nothing (Base.Fn.id, Notaunit.Sub,
   and Stdlib.Str — the Str library is its own unit, not a Stdlib
   member) and therefore match nothing. Unconfigured, every line here is
   clean: the registry rule forbids nothing. *)

(* Unit forbid: every value reference into the Str compilation unit. *)
let re = Str.regexp "a+" (* FIRE *)
let matched s = Str.string_match re s 0 (* FIRE *)

(* An alias does not launder the identity. *)
module R = Str

let quoted s = R.quote s (* FIRE *)

(* Neither does a re-export alias declared in another unit. *)
let requoted s = Rd_dep.Legacy_str.quote s (* FIRE *)

(* Submodule forbid: values reached through Rd_dep.Internal,
   transitively, aliases included. *)
let secret = Rd_dep.Internal.secret (* FIRE *)
let deepest = Rd_dep.Internal.Deeper.deepest (* FIRE *)

module I = Rd_dep.Internal

let via_alias = I.secret (* FIRE *)

(* The sibling value outside the forbidden submodule stays clean. *)
let fine = Rd_dep.ok

(* Value forbid: both spellings resolve to the one declaration. *)
let boom () = invalid_arg "boom" (* FIRE *)
let boom_qualified () = Stdlib.invalid_arg "boom" (* FIRE *)

(* The binding's right-hand side is the reference that fires; a later
   use of [bound] references [bound]'s own declaration. *)
let bound : string -> unit = Stdlib.invalid_arg (* FIRE *)
let reuse () = bound "quiet"

(* Module forbid through an alias hop: Stdlib.Obj denotes Stdlib__Obj. *)
let cast (x : int) : int = Obj.magic x (* FIRE *)

(* Constructors are not value references: references, not types, are the
   finding unit, so forbidden-module data stays clean today — the
   outdated-str-module boundary. *)
let delim = Str.Delim ","

(* A wrapper spelled Str, declared in Rd_dep's unit — the Re.Str
   precedent: its declarations are its own identities. *)
let compat s = Rd_dep.Compat.Str.regexp s

(* A functor parameter named Str mints parameter-local identities,
   whatever it is applied to. *)
module F (Str : sig
  val regexp : string -> string
end) =
struct
  let local = Str.regexp "b*"
end

(* A value merely named str. *)
let str = "not the module"
let still_clean = str

(* Shadowing definitions resolve to their own declarations: clean from
   here down — the documented carve-outs. *)
let invalid_arg (s : string) = s
let quiet = invalid_arg "fine"

module Str = struct
  let regexp (s : string) = s
end

let quiet_module = Str.regexp "c?"
