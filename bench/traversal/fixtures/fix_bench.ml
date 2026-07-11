(* Bench fixture: a mid-sized module with representative shapes — variants,
   records, matches, list pipelines, applications, attributes, and a few
   launch-rule positives so the emit path is exercised too. *)

type level = Quiet | Normal | Loud of int

type entry = {
  name : string;
  level : level;
  tags : string list;
  weight : float;
}

let make ?(level = Normal) ?(tags = []) ~weight name =
  { name; level; tags; weight }

let volume e = match e.level with Quiet -> 0 | Normal -> 1 | Loud n -> max 1 n
let heavier a b = compare a.weight b.weight > 0

let heaviest entries =
  List.fold_left
    (fun best e ->
      match best with
      | None -> Some e
      | Some b -> if heavier e b then Some e else best)
    None entries

let tagged tag entries =
  List.filter (fun e -> List.exists (String.equal tag) e.tags) entries

let names entries = List.map (fun e -> e.name) entries

let summarize entries =
  entries |> names |> List.sort compare |> String.concat ", "

let count_loud entries =
  List.length (List.filter (fun e -> volume e > 1) entries)

(* Launch-rule positives, in the middle of ordinary code. *)
let any entries = List.length entries > 0
let none entries = 0 = List.length entries
let same_name a b = a.name == b.name

let normalize entries =
  List.map
    (fun e ->
      let weight = if e.weight < 0.0 then 0.0 else e.weight in
      let level =
        match e.level with Loud n when n <= 0 -> Normal | other -> other
      in
      { e with weight; level })
    entries

let merge a b =
  let rec go acc = function
    | [], rest | rest, [] -> List.rev_append acc rest
    | x :: xs, y :: ys ->
        if heavier x y then go (x :: acc) (xs, y :: ys)
        else go (y :: acc) (x :: xs, ys)
  in
  go [] (a, b)

let histogram entries =
  let tbl = Hashtbl.create 16 in
  List.iter
    (fun e ->
      let key = volume e in
      Hashtbl.replace tbl key
        (1 + Option.value ~default:0 (Hashtbl.find_opt tbl key)))
    entries;
  List.sort compare (Hashtbl.fold (fun k v acc -> (k, v) :: acc) tbl [])

let render entries =
  let buf = Buffer.create 256 in
  List.iter
    (fun e ->
      Buffer.add_string buf e.name;
      Buffer.add_char buf ' ';
      Buffer.add_string buf (string_of_int (volume e));
      Buffer.add_char buf '\n')
    entries;
  Buffer.contents buf

let parse_level = function
  | "quiet" -> Some Quiet
  | "normal" -> Some Normal
  | s -> (
      match int_of_string_opt s with
      | Some n when n > 1 -> Some (Loud n)
      | Some _ | None -> None)

let[@inline] scale factor e = { e with weight = e.weight *. factor }

let rebalance factor entries =
  match entries with
  | [] -> []
  | first :: rest ->
      let scaled = List.map (scale factor) rest in
      first :: normalize scaled

let demo =
  [
    make ~weight:1.0 "alpha";
    make ~level:Quiet ~weight:0.5 ~tags:[ "small" ] "beta";
    make ~level:(Loud 3) ~weight:2.5 ~tags:[ "big"; "loud" ] "gamma";
  ]

let report () =
  let entries = normalize demo in
  let loudest = Option.map (fun e -> e.name) (heaviest entries) in
  Printf.sprintf "%s | loud=%d | top=%s | any=%b none=%b" (summarize entries)
    (count_loud entries)
    (Option.value ~default:"-" loudest)
    (any entries) (none entries)
