(* Shadowing fixture for the matches_type local-alias hop: a plain
   same-name rebinding is refused by the compiler ("Names must be unique in
   a given structure"), so the only same-name route into [str_type] is
   [include] — the included [M = Hashtbl] is shadowed by the later explicit
   [M = Set.Make (Int)], and the unit's signature keeps both bindings. A
   use typed through either [M] must resolve to that binding's identity:
   the hop locates the [Sig_module] by ident stamp, never by first-hit
   name lookup. *)

module Inner = struct
  module M = Hashtbl
end

include Inner

let first_probe : (string, int) M.t = M.create 8
let first_use = first_probe

module M = Set.Make (Int)

let second_probe = M.empty
let second_use = second_probe
