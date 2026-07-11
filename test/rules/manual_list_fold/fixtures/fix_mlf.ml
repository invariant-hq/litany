(* Fixture for manual-list-fold: positives carry the FIRE marker; every
   other binding is a negative lookalike from the spec plus one
   adversarial extra. *)

(* fold_left, the match form, function-parameter step. *)
let rec fold_left (* FIRE *) f acc l =
  match l with [] -> acc | x :: xs -> fold_left f (f acc x) xs

(* fold_left, the function form. *)
let rec fold_left' (* FIRE *) f acc = function
  | [] -> acc
  | x :: xs -> fold_left' f (f acc x) xs

(* fold_right: the result rebuilt around the recursive call. *)
let rec fold_right (* FIRE *) f acc l =
  match l with [] -> acc | x :: xs -> f x (fold_right f acc xs)

(* An operator step — in scope here. *)
let rec sum acc = function [] -> acc | x :: xs -> sum (acc + x) xs (* FIRE *)

(* fold_right with swapped parameter order — positions, not names. *)
let rec fold_right' (* FIRE *) f l acc =
  match l with [] -> acc | x :: xs -> f x (fold_right' f xs acc)

(* negative: the accumulator is changed AND the call sits under a
   context — neither fold shape *)
let rec fr acc = function [] -> acc | x :: xs -> x + fr (acc + 1) xs

(* negative: the nil case is a literal, not a parameter — a fold
   morally, but the rewrite would change the signature (deliberate
   false negative) *)
let rec len = function [] -> 0 | _ :: xs -> 1 + len xs

(* negative: two self-calls are not a fold *)
let rec twice acc = function
  | [] -> acc
  | _ :: xs -> twice acc xs + twice acc xs

(* negative: no [rec] under an outer fold — identity refuses the
   self-call (adversarial shadowing) *)
let fold_left f acc l =
  match l with [] -> acc | x :: xs -> fold_left f (f acc x) xs

(* negative: a guard on the cons case (the deliberately partial
   lookalike needs its warning silenced; the shape is the point) *)
let rec foldg p acc = function
  | [] -> acc
  | x :: xs when p x -> foldg p (acc + x) xs
[@@warning "-8"]

(* negative: extra cases and alias patterns *)
let rec fold3 acc = function
  | [] -> acc
  | [ x ] -> acc + x
  | x :: xs -> fold3 (acc + x) xs

let rec folda acc = function
  | [] -> acc
  | x :: xs as l -> folda (acc + x + List.length l) xs

(* negative: a user-defined (::)/[] — predefined identity refuses *)
module UserList = struct
  type t = ( :: ) of int * t | []

  let rec usum acc = function ([] : t) -> acc | x :: xs -> usum (acc + x) xs
  let sample = 1 :: []
end

(* negative (adversarial extra): the nil case returns a parameter that
   is not the accumulator the step transforms — wrong designation,
   neither shape *)
let rec wf f acc l = match l with [] -> f | x :: xs -> wf f (f acc x) xs

(* negative: the step reads the scrutinized list parameter, rebound at
   every recursive call — no fold callback sees it (the
   fold_left form would compute a different value). *)
let rec spooky_sum acc l =
  match l with [] -> acc | _ :: tl -> spooky_sum (acc + List.length l) tl

(* negative: the fold_right step reading the scrutinized parameter is
   the same hole from the other side. *)
let rec spooky_right acc l =
  match l with
  | [] -> acc
  | _ :: tl -> min (List.length l) (spooky_right acc tl)
