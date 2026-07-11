(* External use sites: references into fix_probe (no mli, unwrapped) and
   fix_probe2 (wrapped, with generated alias module), harvested by
   test_ident. *)

let ext_probe_direct xs = Fix_probe.direct xs
let ext_probe_inner = Fix_probe.Outer.Inner.v
let ext_withmli x = Fix_probe2.Withmli.f x
let ext_nomli_g x = Fix_probe2.Nomli.g x
let ext_nomli_f x = Fix_probe2.Nomli.f x
let ext_asc xs = Fix_probe2.Cases2.Asc.length xs
let ext_tint = Fix_probe.tint
let ext_res = Fix_probe.res_head
let ext_tone = Fix_probe.Tones.warm
