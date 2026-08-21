(* Fixture for manual-eta-lambda: each FIRE marker sits on an anonymous
   function that only forwards its parameters, in order, to an identifier
   callee; every other lambda is a negative from the spec, one per gate
   clause. The .fixed golden is this file after --fix and must compile:
   every positive sits in argument or operand position, so the golden
   proves the replacement's delimiting. *)

let parse s = int_of_string_opt s |> Option.to_result ~none:"not an int"
let step x = x + 1
let add a b = a + b
let labeled_step ~x = x + 1
let g_opt ?(d = 0) x = x + d
let make_step () x = x + 1
let add_pair (a, b) = a + b
let xs = [ 1; 2; 3 ]
let r = Ok "42"

(* Argument position under Result.map: the lambda's location includes
   the author's parentheses, and the identifier replacement needs none. *)
let p1 = Result.map (fun x -> parse x) r (* FIRE *)

(* Under List.map. *)
let p2 = List.map (fun x -> step x) xs (* FIRE *)

(* In a pipeline. *)
let p3 = xs |> List.map (fun x -> step x) (* FIRE *)

(* Two parameters, in order. *)
let p4 = List.fold_left (fun acc x -> add acc x) 0 xs (* FIRE *)

(* A module-path callee. *)
let p5 = List.map (fun s -> String.length s) [ "a"; "bb" ] (* FIRE *)

(* Trailing-open, unparenthesized: the replacement is atomic and the
   slice had no delimiters, so none are added. *)
let p6 = xs |> fun l -> List.length l (* FIRE *)

(* The callee's own arity is irrelevant: [add x] is [add] at the same
   type. *)
let p7 = List.map (fun x -> add x) xs (* FIRE *)

(* Folded from needless-identity-function, whose argument-position view
   excluded these: a list element, the callee of an immediate
   application, an argument of a labeled application, and two forwards
   in one application (two findings, one marker per line — ocamlformat
   would join the fixed lines, hence the opt-out). Each reduction is
   exact. *)
let tagged ~tag x = (tag, x)
let pair f g n = (f 1, g 2, n)
let p8 = [ (fun x -> step x) ] (* FIRE *)
let p9 = (fun x -> step x) 5 (* FIRE *)
let p10 = tagged ~tag:0 (fun x -> step x) (* FIRE *)

let p11 =
  pair
    (fun first_value -> step first_value) (* FIRE *)
    (fun second_value -> step second_value) (* FIRE *)
    0
[@@ocamlformat "disable"]

(* A recursively bound callee below an intervening function is a
   delayed use; the reduction is legal. *)
type tree = Leaf | Node of tree list | Pair of tree * tree

let sum = List.fold_left ( + ) 1

let rec size t =
  match t with
  | Leaf -> 1
  | Node ts -> sum (List.map (fun t -> size t) ts) (* FIRE *)
  | Pair (a, b) -> size a + size b

(* negative: a partial forward — not every parameter is applied *)
let n1 = List.map (fun x _y -> add x) xs

(* negative: an extra argument *)
let n2 = List.map (fun x -> add x 0) xs

(* negative: a labeled argument *)
let n3 = List.map (fun x -> labeled_step ~x) xs

(* negative: a destructuring parameter *)
let n4 = List.map (fun (a, b) -> add_pair (a, b)) [ (1, 2) ]

(* negative: the callee is a parameter *)
let n5 = List.map (fun f -> f 1) [ step ]

(* negative: an effectful callee — forced once per call, not once *)
let n6 = List.map (fun x -> (make_step ()) x) xs

(* negative: swapped parameter order *)
let n7 = List.fold_left (fun acc x -> add x acc) 0 xs

(* negative: a repeated parameter *)
let n8 = List.map (fun x -> add x x) xs

(* negative: a let-bound definition, in either spelling, is
   eta-reducible-forwarding's *)
let n9 = fun x -> step x
let n10 x = step x

(* negative: the erasure gate — the callee carries an optional argument
   the application commits *)
let n11 = List.map (fun x -> g_opt x) xs

(* negative: operator callees, binary and the respelled unary minus *)
let n12 = List.fold_left (fun a b -> a + b) 0 xs
let n12' = List.map (fun x -> -x) xs

(* negative: tail position of a let rec right-hand side forwarding to the
   recursively bound name — the reduction is rejected by the compiler *)
let rec n13 =
  let _k = 1 in
  fun x -> n13 x

(* negative: an annotated parameter *)
let n14 = List.map (fun (x : int) -> step x) xs

(* negative: an attribute on the lambda *)
let n15 = List.map ((fun x -> step x) [@warning "-26"]) xs

(* negative: an annotated body *)
let n16 = List.map (fun x -> (step x : int)) xs

(* negative: a newtype the reduction would drop *)
let n17 = List.map (fun (type a) x -> step x) xs [@@warning "-34"]

(* negative: a coerced argument forwards a different value — the
   predecessor rule's corpus-recorded false positive *)
type base = < name : string >
type derived = < name : string ; id : int >

let describe (o : base) = o#name
let n18 = List.map (fun (d : derived) -> describe (d :> base)) []
let n18' = List.map (fun d -> describe (d :> base)) ([] : derived list)

(* negative: an annotated argument *)
let n19 = List.map (fun x -> step (x : int)) xs

(* negative: a curried multi-stage wrapper — the body is a function *)
let n20 = List.map (fun x -> fun y -> add x y) xs

(* negative: a `function` body *)
let n21 = List.map (fun x -> function 0 -> x | m -> m) xs

(* negative: a staged callee is not an identifier *)
let n22 = List.map (fun x -> (add 1) x) xs

(* negative (adversarial): shadowed parameters — the applied [x] is the
   second parameter's identity, so position one fails *)
let n23 = List.map ((fun x x -> add x x) [@warning "-27"]) xs

let all () =
  ignore (p1, p2, p3, p4, p5, p6, p7, size (Node [ Leaf ]));
  ignore (p8, p9, p10, p11);
  ignore
    ( List.map (fun f -> f 0) n1,
      n2,
      n3,
      n4,
      n5,
      n6,
      n7,
      n8,
      n9 1,
      n10 1,
      n11,
      n12,
      n12' );
  ignore (n13, n14, n15, n16, n17, n18, n18', n19);
  ignore (List.map (fun f -> f 0) n20, List.map (fun f -> f 0) n21, n22);
  ignore (List.map (fun f -> f 0) n23)
