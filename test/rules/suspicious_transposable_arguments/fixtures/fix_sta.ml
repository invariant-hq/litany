(* Fixture for suspicious-transposable-arguments, derived-export case
   (no mli: every structure-level binding is exported under its
   definition UID). Each FIRE marker sits on a binding whose spine has
   three or more adjacent same-typed unlabeled parameters. *)

(* module, function, message: three transposable strings. *)
let invalid_arg3 (m : string) (fn : string) (msg : string) : 'a = (* FIRE *)
  failwith (m ^ fn ^ msg)

(* Four adjacent. *)
let require4 a b c d = a ^ b ^ c ^ d (* FIRE *)

(* Adversarial: the same type variable three times is transposable. *)
let pick3 x y z = if true then x else if true then y else z (* FIRE *)

(* Two adjacent, symmetric by design: below threshold. *)
let levenshtein (a : string) (b : string) = String.length a + String.length b

(* The label breaks adjacency: the remedy itself. *)
let admit ~recorded s t = recorded ^ s ^ t

(* Two adjacent after the labeled one. *)
let wrap ~count x y = count + x + y

(* Mixed types. *)
let mixed a b c = a ^ b ^ string_of_int c

(* A local helper is outside the exported-value claim. *)
let outer () =
  let inner (a : string) (b : string) (c : string) = a ^ b ^ c in
  inner "a" "b" "c"

(* Recorded false negative: syntactic type equality does not expand
   abbreviations, so [s] and [string] stay distinct. *)
type s = string

let abbr (a : s) (b : string) (c : s) = a ^ b ^ c

(* Keep everything used. *)
let all () =
  invalid_arg3 "a" "b"
    (require4 "c" "d" "e" (pick3 "f" "g" (levenshtein "h" "i" |> string_of_int))
    ^ admit ~recorded:"j" "k" "l"
    ^ string_of_int (wrap ~count:1 2 3)
    ^ mixed "m" "n" 4 ^ outer () ^ abbr "o" "p" "q")
