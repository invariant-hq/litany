(* Use-index fixture: bindings with known use counts, including qualified
   uses through a module path and an unused binding. *)

let base = 2
let twice = base + base
let unused = 7

module M = struct
  let hidden = 9
end

let qualified = M.hidden + M.hidden

let localized () =
  let inner = base in
  inner + 1
