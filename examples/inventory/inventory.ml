type t = { stock : (string * int) list }

let restock t = t
let check t = if List.length t.stock = 0 then restock t else t
let find t name = List.find (fun (n, _) -> n == name) t.stock
