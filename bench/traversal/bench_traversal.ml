(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* The M3 traversal lane, hermetic: the engine with the launch catalog over
   one compiled fixture unit. Three cases bracket the budget (plan rule 7:
   engine overhead < 30% of decode+run):

   - [load]:    decode + witness join alone — the M2 lane per unit.
   - [analyze]: [Litany.Engine.run] over an already-loaded unit — traversal,
     dispatch, and the emit contract, the engine's own cost.
   - [check]:   load + analyze, the full per-unit lane. The committed
     baseline records this case too, deliberately: [analyze] pre-pays the
     demand-gated parse in its setup, so only [check] sees the
     attribute-lane cost that rule 7 budgets.

   After a whole-suite check passes, the rule-7 drift gate below re-measures
   [load] and [check] under the quick protocol and fails the run when the
   hermetic overhead ratio drifts over its ceiling — so a corpus-scale
   30%→40% regression class fails runtest instead of waiting for the next
   hand measurement. The corpus-scale ratio itself is measured by
   bench_corpus.ml (corpus-directory argument, not runtest-wired). *)

let source = "fixtures/fix_bench.ml"
let cmt = "fixtures/.fix_bench.objs/byte/fix_bench.cmt"

let resolver () =
  Litany.Naming.Resolver.create
    ~cmi_dirs:[ Filename.dirname cmt; Config.standard_library ]

let entry () = Litany.Roster.Entry.v ~source ~cmt ()
let load resolver entry = Litany.Unit.load ~resolver ~build_current:true entry

let analyze ~loaded entry =
  Litany.Engine.run ~rules:Litany_rules.all ~catalog:Litany_rules.all
    ~roster:(Litany.Roster.v [ entry ])
    ~load:(fun _ -> loaded)
    ()

let cases =
  [
    Thumper.bench_with_setup
      ~setup:(fun () -> (resolver (), entry ()))
      "load"
      (fun (resolver, entry) -> load resolver entry);
    Thumper.bench_with_setup
      ~setup:(fun () ->
        let resolver = resolver () in
        let entry = entry () in
        let loaded = load resolver entry in
        (* Pay the demand-gated parse before sampling: the steady-state
           cost is traversal + dispatch, not the one-time decode. *)
        ignore (analyze ~loaded entry);
        (loaded, entry))
      "analyze"
      (fun (loaded, entry) -> analyze ~loaded entry);
    Thumper.bench_with_setup
      ~setup:(fun () -> (resolver (), entry ()))
      "check"
      (fun (resolver, entry) -> analyze ~loaded:(load resolver entry) entry);
  ]

(* The rule-7 drift gate. Rule 7 budgets engine overhead — everything but
   cmt decode — at < 30% of the per-unit lane at corpus scale. The hermetic
   proxy here is the quotient (check − load) / load over the fixture unit:
   engine cost per unit of decode cost. The quotient form keeps uniform
   sensitivity (the overhead *fraction* saturates near 1 on this fixture,
   whose tiny cmt makes the lane engine-heavy: measured fraction ≈ 76%,
   quotient ≈ 3.1, arm64 mac, 2026-08-20). The corpus-scale 30%→40% drift
   class is a ≈ 1.56× engine-cost growth, hermetic quotient ≈ 4.9 — so the
   4.0 ceiling fires first. The ceiling is calibrated to the fixture, not
   the corpus law: the gate catches drift on any machine (including one the
   committed baseline has no section for, where the relative budgets are
   silent); the corpus number stays bench_corpus's to measure. Medians come
   from one quick wall-time measurement of the two cases, taken after
   [Thumper.run] returned (so a confirmed regression has already failed the
   build before the gate). *)
let overhead_per_decode_ceiling = 4.0

let median samples =
  (* Thumper sample vectors are sorted ascending. *)
  match Array.length samples with
  | 0 -> nan
  | n -> samples.(n / 2)

let rule7_gate () =
  let config =
    Thumper.Config.metrics [ Thumper.Metric.wall_time ] Thumper.Config.quick
  in
  let run =
    Thumper.measure ~config ~filter:(`Or [ `Id "load"; `Id "check" ]) cases
  in
  let med case =
    match Thumper.Run.samples run ~case Thumper.Metric.wall_time with
    | Some samples -> median samples
    | None ->
        Printf.printf "rule-7 gate: no wall-time samples for %s\n" case;
        exit 2
  in
  let load_s = med "load" and check_s = med "check" in
  if not (load_s > 0.) then begin
    Printf.printf "rule-7 gate: degenerate load median (%.9f s)\n" load_s;
    exit 2
  end;
  let quotient = (check_s -. load_s) /. load_s in
  if quotient > overhead_per_decode_ceiling then begin
    Printf.printf
      "rule-7 gate: engine overhead %.2fx the decode cost — over the %.1fx \
       ceiling (load %.3f ms, check %.3f ms); rule 7 drift: re-measure the \
       corpus ratio with bench_corpus before touching this ceiling\n"
      quotient overhead_per_decode_ceiling (1000. *. load_s) (1000. *. check_s);
    exit 1
  end;
  Printf.printf
    "rule-7 gate: engine overhead %.2fx the decode cost (ceiling %.1fx)\n"
    quotient overhead_per_decode_ceiling

(* The gate runs only when the invocation checks the whole suite (the
   runtest rule's invocation): a filtered, listing, blessing, or help run
   must not trigger a second measurement. *)
let whole_suite_check argv =
  Array.to_list argv |> List.tl
  |> List.for_all (fun arg -> List.mem arg [ "check"; "--quick"; "--precise" ])

let () =
  Thumper.run "traversal"
    ~budgets:
      [
        Thumper.Budget.no_slower_than 0.15;
        Thumper.Budget.no_more_alloc_than 0.02;
      ]
    cases;
  if whole_suite_check Sys.argv then rule7_gate ()
