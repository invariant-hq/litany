let live_helper () = Dcx_used.entry () + 1
let dead_helper x = x * 2 (* FIRE — the executable's own dead export *)
let () = ignore (live_helper ())
