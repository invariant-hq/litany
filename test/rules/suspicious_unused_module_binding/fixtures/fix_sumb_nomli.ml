(* Spec negative 2, its own unit: without an .mli everything is
   exported through the inferred signature, so the unused toplevel
   binding is silent — the exact case where an enabled warning 60 is
   also silent. *)

module Hidden = struct
  let zero = 0
end

let touch = 1
