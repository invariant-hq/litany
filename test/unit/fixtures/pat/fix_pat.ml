(* Fixture for the combinator suite: one binding per shape the tests fish
   out by source slice. *)

let xs = [ 1; 2; 3 ]
let ys : int list = []
let len = List.length xs
let empty = List.length ys = 0
let seven = 7
let greet = "hello"
let biggest = max 1 2
let partial = max 1
let lab ~x = x + 1
let labelled = lab ~x:1
let add3 a b c = a + b + c
let three = add3 1 2 3
let stage = add3 4 5
let opt = Some 9
let res : (int, string) result = Ok 9

type 'a box = Box of 'a

let boxed = Box 1
let paired p = match p with (l, _) as whole -> (l, whole)
let uses_seven = seven + 1

(* Shapes for the adopted catalog views (M5). This file is
   .ocamlformat-ignore'd: the tests fish nodes out by exact source
   slice, so the spellings below are byte-stable by hand. *)
let lam = List.map (fun v -> v + 31) [ 33 ]
let lam2 = List.fold_left (fun acc v -> acc + v) 34 [ 33 ]
let expects_lab (g : tag:int -> int) = g ~tag:1
let labfun_use = expects_lab (fun ~tag -> tag + 1)
let one_armed c = if c then print_string "x"
let both_arms c = if c then 1 else 2
let yes = true
let is_yes b = match b with true -> 1 | _ -> 30

type fake = true | false

let fakes : fake = true
let fake_neg (x : fake) = match x with false -> 1 | _ -> 30
let classify = function [] -> 30 | x :: _ -> x
let opt_default = function Some v -> v | None -> 38
let safe f = match f () with x -> x | exception Not_found -> 31

type _ Effect.t += Ping : unit Effect.t

let with_effects f =
  match f () with 30 -> 1 | _ -> 2 | effect Ping, k -> Effect.Deep.continue k ()

let tried f =
  try f () with Not_found -> 32 | effect Ping, k -> Effect.Deep.continue k ()

let occ_pos yy = match yy with _ -> yy + 1
let occ_neg zz = match zz with _ -> (let zz = 35 in zz + 36)
let guard_use y = match y with n when n > y -> 1 | _ -> 37

(* Shapes for the engine-kinds batch views (tuples, records, type_refs). *)
type point = { px : int; py : int }
type cell = { mutable contents : int }
type alias_pt = point
type 'a wrap = W of 'a constraint 'a = int list
type refs = R of point * cell option

let origin = { px = 40; py = 41 }
let shifted = { origin with py = 52 }
let cell0 = { contents = 43 }
let read_px pt = pt.px
let read_contents c = c.contents
let pair2 = (44, 45)
let swap pr = match pr with (a2, b2) -> (b2, a2)
let wrapped : int list wrap = W [ 49 ]
let referenced = R (origin, Some cell0)
