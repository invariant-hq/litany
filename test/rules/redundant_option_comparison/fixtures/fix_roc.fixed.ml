(* Fixture for redundant-option-comparison: positives carry the FIRE
   marker; every other case is a spec negative plus one adversarial
   extra. *)

let o = List.nth_opt [ 1; 2; 3 ] 0
let lookup k = List.assoc_opt k [ (1, "a") ]
let default = 0
let run _ = 1

(* Both operators, both operand orders. *)
let p1 = if Option.is_none o then default else run o (* FIRE *)
let p2 = Option.is_some o (* FIRE *)
let p3 = Option.is_none (lookup 1) (* FIRE *)

(* A computed operand parenthesizes in the fix. *)
let p4 = Option.is_some (lookup 1) (* FIRE *)

(* The tag decides without traversing the payload: a Some operand still
   compares (to false) rather than raising — probe-pinned, and why the
   fix is safe. *)
let p5 = Option.is_none (Some (run o)) (* FIRE *)

(* The spec's loop context: the comparison is just an expression. *)
let drain q =
  while Option.is_some (Queue.peek_opt q) (* FIRE *) do
    Queue.clear q
  done

(* A && chain of two or more None comparisons is one finding at the
   chain, its fix rewriting every member — the presence-predicate
   chain shape, reported under containment. *)
let c1 a b c = Option.is_some a && Option.is_some b && Option.is_some c (* FIRE *)

(* Mixed connectives, a parenthesized sub-chain, and a non-comparison
   operand all join the same chain. *)
let c2 a b ok = Option.is_none a || (ok && Option.is_some b) (* FIRE *)

(* A chain carrying exactly one None comparison reports it as the
   standalone form does — anchored at the comparison. *)
let c3 a ok = ok && Option.is_none a (* FIRE *)

(* A comparison below a non-connective operand is not a member: the
   chain sees an opaque operand, the comparison keeps its finding. *)
let c4 f ok = ok && Option.is_none o |> f (* FIRE *)

(* Argument position: the parens belong to the call, not to the
   comparison's location, so a bare application replacement would
   re-associate as [(check Option.is_none) o]. *)
let check b = b
let p_arg = check (Option.is_none o) (* FIRE *)

(* [begin]/[end] delimit exactly as parentheses do, and the parser
   relocates over them alike; the restored pair is a parenthesis pair.
   Kept on one line so the marker sits on the finding's line — the
   delimiter-inclusive location starts at [begin]. *)
let p_begin = check (Option.is_none o) (* FIRE *) [@@ocamlformat "disable"]

(* A multi-line chain anchors at the chain start. *)
let c5 the_first_compared_operand the_second_compared_operand =
  Option.is_some the_first_compared_operand (* FIRE *)
  && Option.is_some the_second_compared_operand

(* negative: payload equality is a meaningful program — the adjudicated
   Some boundary. *)
let n1 = o = Some 3

(* negative: two constants. *)
let n2 = (None : int option) = None

(* negative: already the remedy. *)
let n3 = Option.is_none o

(* negative: physical equality is not these operators, and
   suspicious-physical-equality does not fire either — no gap, no
   double. *)
let n4 = o == None

(* negative (adversarial): a rebound operator resolves elsewhere. *)
let n5 =
  let ( = ) (_ : int option) (_ : int option) = false in
  o = None

(* negative (adversarial extra): orderings and compare are out of
   scope. *)
let n6 = o > None
let n7 = compare o None

(* negative (adversarial): a rebound connective is no chain — its member
   comparisons keep their own findings, one each. *)
let n9 first_compared_operand second_compared_operand =
  let ( && ) x y = x || y in
  Option.is_none first_compared_operand (* FIRE *)
  && Option.is_none second_compared_operand (* FIRE *)

(* negative: user lookalike constructors — predefined-option identity
   refuses. Last in the file so the lookalikes shadow nothing above. *)
type t = None | Some of int

let n8 (x : t) = x = None
