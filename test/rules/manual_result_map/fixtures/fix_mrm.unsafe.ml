(* Fixture for manual-result-map: positives carry the FIRE marker; every
   other binding is a negative lookalike from the spec plus adversarial
   extras. *)

let parse s = int_of_string s
let wrap e = "w:" ^ e

(* The map form. *)
let p1 r = Result.map (fun x -> (parse x)) r (* FIRE *)

(* Reversed case order. *)
let p2 r = Result.map (fun x -> (x * 2)) r (* FIRE *)

(* The map_error form, function form: report only. *)
let p3 = function Ok x -> Ok x | Error e -> Error (`Msg e) (* FIRE *)

(* Double identity: the match is the scrutinee itself. *)
let p4 r = r (* FIRE *)

(* The map_error form, match form. *)
let p5 r = Result.map_error (fun e -> (wrap e)) r (* FIRE *)

(* negative: the error payload is not the bound rebuild *)
let default_err = "bad"
let n1 f r = match r with Ok x -> Ok (f x) | Error _ -> Error default_err

(* negative: the Ok arm is not an Ok construction — Result.bind territory *)
let n2 f r = match r with Ok x -> f x | Error e -> Error e

(* negative: both arms transform — no single canonical rewrite *)
let n3 f r = match r with Ok x -> Ok (f x) | Error e -> Error (wrap e)

(* negative: a guard *)
let n4 r = match r with Ok x when x > 0 -> Ok x | r' -> r'

(* negative (adversarial): a user variant spelling Ok/Error *)
module UserRes = struct
  type t = Ok of int | Error of string

  let keep v = match v with Ok x -> Ok x | Error e -> Error e
end

(* negative: a deep payload pattern *)
let n5 r = match r with Ok (Some x) -> Ok x | Error e -> Error e
[@@warning "-8"]

(* negative (adversarial extra): an aliased payload is a different shape *)
let n6 r = match r with Ok _ as v -> v | Error e -> Error e

(* A parenthesized single-line arm body: the parser's location for the
   body includes the author's parentheses, and the splice must not add a
   second pair: the raw body keeps the author's bytes, [(fun e -> (wrap e))],
   never [((wrap e))]. *)
let paren_body r = Result.map_error (fun e -> (wrap e)) r (* FIRE *)

(* Argument position: the parenthesized match's location includes the
   parentheses, and the application replacement is not self-delimiting —
   the fix restores the pair or the call re-associates as
   [(Result.is_ok Result.map) ...]. *)
let p_arg r =
  ignore (Result.map (fun x -> (parse x)) r)
