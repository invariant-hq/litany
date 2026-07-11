(* Fixture for unsafe-partial-stdlib: every reference to a listed partial
   eliminator carries the FIRE marker, whatever the saturation; the rest
   are the total spellings and lookalikes. *)

let line = "a,b,c"
let xs = [ 1; 2; 3 ]
let rows = [ [ 1 ]; [ 2 ] ]
let o = Some 1
let r : (int, string) result = Ok 1
let r' : (int, string) result = Error "boom"

(* Saturated calls, one reference each. *)
let p1 = List.hd (String.split_on_char ',' line) (* FIRE *)
let p2 = List.tl xs (* FIRE *)
let p3 = List.nth xs 0 (* FIRE *)
let p4 = Option.get o (* FIRE *)
let p5 = Result.get_ok r (* FIRE *)
let p6 = Result.get_error r' (* FIRE *)

(* First-class references fire at the mention. *)
let p7 = List.map List.hd rows (* FIRE *)

(* Resolution through open and alias (identity, not spelling). *)
let p8 =
  let open List in
  hd xs (* FIRE *)

module L = List

let p9 = L.tl xs (* FIRE *)

(* Total siblings and the match remedy. *)
let n1 = List.nth_opt xs 0
let n2 = Option.value o ~default:0
let n3 = match xs with x :: _ -> x | [] -> 0

(* A value merely named hd. *)
let n4 =
  let hd (x, _) = x in
  hd (1, 2)

(* The Not_found retrieval protocol is deliberately unlisted. *)
let n5 = List.find (fun x -> x > 1) xs

(* A shadowed module carries local UIDs (adversarial shadowing). *)
module List = struct
  let hd = function x :: _ -> x | [] -> 0
end

let n6 = List.hd xs
