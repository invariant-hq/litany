(* A quadruple negation fires at every node spelling not (not e) — the
   outer pair, the shifted middle pair, and the inner pair. The fixes'
   spans nest, so the applier's conflict deferral owns application and
   this fixture is exercised for markers only. Layout is load-bearing
   (each finding needs its own marked line): the file is listed in
   .ocamlformat-ignore. *)

let deep b =
  not (* FIRE *)
    (not (* FIRE *)
       (not (* FIRE *)
          (not b)))
