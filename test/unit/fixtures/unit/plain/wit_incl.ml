(* mli-side include: the canonical uid of [v] is [Wit_sigs]'s interface
   item, while this unit's own use of [v] carries an impl uid — the bridge
   pair whose declaration side is a foreign Intf item. *)
let v = 3
let uses_v = v + 1
