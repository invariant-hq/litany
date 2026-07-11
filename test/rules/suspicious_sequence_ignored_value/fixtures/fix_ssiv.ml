(* Fixture for suspicious-sequence-ignored-value: positives carry the
   FIRE marker; every other line is a negative lookalike from the spec
   plus one adversarial extra. Every enumerated projection appears in
   one positive, so a typo'd canonical name is a failing test. *)

(* The probe-pinned silent cases: Tvar heads warning 10 cannot speak
   on. *)
let f1 xs = List.hd xs; List.length xs (* FIRE *)
let f2 o = Option.get o; ignore o (* FIRE *)
let f3 r = Result.get_ok r; () (* FIRE *)
let f4 r = Result.get_error r; () (* FIRE *)
let f5 q = fst q; ignore q (* FIRE *)
let f5' q = snd q; ignore q (* FIRE *)
let f6 xs i = List.nth xs i; i (* FIRE *)
let f7 k l = List.assoc k l; k (* FIRE *)
let f8 k l = List.assq k l; k (* FIRE *)
let f9 p xs = List.find p xs; xs (* FIRE *)
let f10 t k = Hashtbl.find t k; k (* FIRE *)

(* negative: a concrete head — warning 10 already fires; the Tvar guard
   keeps litany silent (the no-duplicate boundary, pinned) *)
let n1 () =
  let o = Some 1 in
  Option.get o;
  ()
[@@warning "-10"]

(* negative: the sanctioned discard *)
let n2 xs = ignore (List.hd xs); List.length xs

(* negative: effectful pops are deliberate drops — the UIDs are absent
   from the set *)
let n3 q = Queue.pop q; Queue.length q
let n4 s = Stack.pop s; Stack.length s

(* negative: adversarial rebinding — a local UID never matches *)
let my_head = function x :: _ -> x | [] -> raise Not_found

let n5 xs =
  let hd = my_head in
  hd xs;
  List.length xs

(* negative: a Tvar head outside the set — warning 21's business *)
let n6 k = raise Not_found; k [@@warning "-21"]

(* negative: a Tconstr option head — warning 10's, and the callee is
   outside the set *)
let n7 p xs = List.find_opt p xs; xs [@@warning "-10"]

(* negative (adversarial extra): a shadowing List module — the
   positive's spelling, another resolution *)
module List = struct
  let hd = function x :: _ -> x | [] -> raise Not_found
end

let n8 xs = List.hd xs; 0
