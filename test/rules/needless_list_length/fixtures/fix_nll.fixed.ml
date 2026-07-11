(* Fixture for needless-list-length: positives carry the FIRE marker; every
   other line is a negative lookalike ported from the prior implementation's cases. *)

let xs = [ 1; 2; 3 ]
let big x = x > 1

(* Every relation equivalent to emptiness, in both operand orders. *)
let p1 = xs = [] (* FIRE *)
let p2 = xs <> [] (* FIRE *)
let p3 = List.length xs > 0 (* FIRE *)
let p4 = List.length xs <= 0 (* FIRE *)
let p5 = List.length xs >= 1 (* FIRE *)
let p6 = List.length xs < 1 (* FIRE *)
let p7 = xs = [] (* FIRE *)
let p8 = xs <> [] (* FIRE *)
let p9 = 0 < List.length xs (* FIRE *)
let p10 = 0 >= List.length xs (* FIRE *)
let p11 = 1 <= List.length xs (* FIRE *)
let p12 = 1 > List.length xs (* FIRE *)
let p13 = (List.filter big xs) = [] (* FIRE *)

(* Relations over 0/1 that are not emptiness tests. *)
let n1 = List.length xs = 1
let n2 = List.length xs < 0
let n3 = List.length xs >= 0
let n4 = List.length xs > 1
let n5 = 1 < List.length xs
let n6 = 0 > List.length xs
let n7 = List.length xs = 2

(* Non-literal constants and indirect shapes. *)
let zero = 0
let n8 = List.length xs = zero
let n9 = compare (List.length xs) 0 = 0
let n10 = Stdlib.( = ) (List.length xs)

(* Shadowed identities never match. *)
let n11 =
  let module List = struct
    let length _ = 0
  end in
  List.length xs = 0

let n12 =
  let ( = ) _ _ = false in
  List.length xs = 0

(* Functor parameters. An explicitly written parameter signature mints
   parameter-local identities — [F]'s body never matches, whatever the
   functor is applied to. *)
module F (L : sig
  val length : 'a list -> int
end) =
struct
  let is_empty ys = L.length ys = 0
end

(* [module type of] hands the parameter List's own interface UIDs (the
   compiler's UID semantics), so the body matches for every instantiation —
   the documented false-positive family pinned here as a positive. *)
module G (L : module type of List) = struct
  let is_empty ys = ys = [] (* FIRE *)
end

(* negative: -1 is not an emptiness test (adopted literal coverage) *)
let n xs = List.length xs = -1

(* A fix-site scope that shadows the spliced operator:
   the cross-operator cells' fix is Unsafe, so --fix leaves the line
   alone; only --fix --unsafe may apply it. *)
let cor02 =
  let ( <> ) (_ : int list) (_ : int list) = false in
  if List.length xs > 0 (* FIRE *) then xs <> [] else false

(* An expected finding's fix still lands in the golden: the rule suites
   are the sole place expected findings' fixes apply. *)
let expected_empty ys = ys = []
[@@litany.expect "needless-list-length: golden-leg pin"]

(* Adopted from the prior implementation's suite: the prefix
   spelling is the same typedtree shape as the infix one — the prior
   implementation's Infix-only gate was a synthetic-view artifact... *)
let prefix_spelling = xs = [] (* FIRE *)

(* ...and an operand typed through an abbreviation is a true positive the prior
   implementation's Constr-view silently dropped — the documented widening, pinned. *)
type t = int list

let alias_input (v : t) = v = [] (* FIRE *)

(* The parser's paren-inclusive location: a parenthesized comparison's
   location includes the author's parentheses, so the replacement must
   restore them — assert's argument grammar re-associates around a bare
   rewrite ((assert xs) = []). Pinned by compilation of the golden. *)
let paren_ctx () = assert (xs = []) (* FIRE *)

(* The same, under a prefix application and as a cons head: the restored
   pair keeps [not] applied to the comparison and the comparison inside
   the cell. *)
let paren_not () = not (xs = []) (* FIRE *)
let paren_cons () = (xs = []) (* FIRE *) :: []
