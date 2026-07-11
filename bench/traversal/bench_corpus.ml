(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* Engine overhead at corpus scale: walk a corpus directory (bench/decode's
   lane), load every entry, and run the launch catalog over each admitted
   unit — reporting per-unit analyze time and the ratio the plan budgets
   (rule 7: engine overhead, everything but cmt decode, < 30% of runtime).

   Plain executable like bench/decode: the corpus is machine-local, so the
   numbers land in doc/m3-notes.md, not a committed baseline. Run:

     dune exec bench/traversal/bench_corpus.exe -- _build/_private/default/.pkg

   Optional: [--source-root DIR] (defaults to the corpus dir), [--reps N]
   (defaults to 3), [--rules a,b,c] (filter the catalog by rule name — the
   per-substrate cost breakdown). *)

let percentile p xs =
  match Array.length xs with
  | 0 -> 0.
  | n ->
      let rank = int_of_float (ceil (p /. 100. *. float_of_int n)) in
      xs.(max 0 (min (n - 1) (rank - 1)))

type rep = {
  entries : int;
  admitted : int;
  findings : int;
  dropped : int;
  load_s : float;
  analyze_s : float;
  analyze_ms : float array;  (** sorted, admitted units only *)
}

let measure ~cmt_root ~source_root ~rules () =
  let roster =
    match Litany.Adapter.Walk.roster ~cmt_root ~source_root with
    | Ok r -> r
    | Error e ->
        Format.eprintf "bench: %a@." Litany.Adapter.Walk.pp_error e;
        exit 2
  in
  let resolver =
    Litany.Naming.Resolver.create
      ~cmi_dirs:(Litany.Roster.cmi_dirs roster @ [ Config.standard_library ])
  in
  let entries = Litany.Roster.entries roster in
  let admitted = ref 0 and findings = ref 0 and dropped = ref 0 in
  let load_s = ref 0. and analyze_s = ref 0. in
  let analyze_ms = ref [] in
  List.iter
    (fun entry ->
      let t0 = Unix.gettimeofday () in
      match Litany.Unit.load ~resolver ~build_current:false entry with
      | Error _ -> load_s := !load_s +. (Unix.gettimeofday () -. t0)
      | Ok u ->
          load_s := !load_s +. (Unix.gettimeofday () -. t0);
          incr admitted;
          let t1 = Unix.gettimeofday () in
          let rep =
            Litany.Engine.run ~rules ~catalog:rules
              ~roster:(Litany.Roster.v [ entry ])
              ~load:(fun _ -> Ok u)
              ()
          in
          let dt = Unix.gettimeofday () -. t1 in
          analyze_s := !analyze_s +. dt;
          analyze_ms := (dt *. 1000.) :: !analyze_ms;
          findings :=
            !findings + List.length (Litany.Engine.Report.findings rep);
          dropped := !dropped + Litany.Engine.Report.dropped rep)
    entries;
  let sorted =
    let a = Array.of_list !analyze_ms in
    Array.sort compare a;
    a
  in
  {
    entries = List.length entries;
    admitted = !admitted;
    findings = !findings;
    dropped = !dropped;
    load_s = !load_s;
    analyze_s = !analyze_s;
    analyze_ms = sorted;
  }

let report i r =
  let total = r.load_s +. r.analyze_s in
  Printf.printf "rep %d: entries %d | admitted %d | findings %d (dropped %d)\n"
    i r.entries r.admitted r.findings r.dropped;
  Printf.printf
    "  load %.2f s + analyze %.2f s = %.2f s -> engine overhead %.1f%%\n"
    r.load_s r.analyze_s total
    (if total = 0. then 0. else 100. *. r.analyze_s /. total);
  Printf.printf "  per-unit analyze: p50 %.3f ms, p90 %.3f ms, p99 %.3f ms\n"
    (percentile 50. r.analyze_ms)
    (percentile 90. r.analyze_ms)
    (percentile 99. r.analyze_ms)

let () =
  let corpus = ref None and source_root = ref None and reps = ref 3 in
  let selected = ref None in
  let rec parse = function
    | [] -> ()
    | "--source-root" :: dir :: rest ->
        source_root := Some dir;
        parse rest
    | "--reps" :: n :: rest ->
        reps := int_of_string n;
        parse rest
    | "--rules" :: names :: rest ->
        selected := Some (String.split_on_char ',' names);
        parse rest
    | dir :: rest when !corpus = None ->
        corpus := Some dir;
        parse rest
    | arg :: _ ->
        prerr_endline ("bench_corpus: unknown argument " ^ arg);
        exit 2
  in
  parse (List.tl (Array.to_list Sys.argv));
  match !corpus with
  | None ->
      prerr_endline
        "usage: bench_corpus CORPUS_DIR [--source-root DIR] [--reps N] \
         [--rules a,b,c]";
      exit 2
  | Some cmt_root ->
      let source_root = Option.value !source_root ~default:cmt_root in
      let rules =
        match !selected with
        | None -> Litany_rules.all
        | Some names ->
            List.filter
              (fun r -> List.mem (Litany.Rule.name r) names)
              Litany_rules.all
      in
      Printf.printf "corpus: %s (source root %s, %d rules)\n%!" cmt_root
        source_root (List.length rules);
      for i = 1 to !reps do
        report i (measure ~cmt_root ~source_root ~rules ());
        flush stdout
      done;
      Printf.printf "heap: top %d MB\n"
        ((Gc.quick_stat ()).Gc.top_heap_words * 8 / 1048576)
