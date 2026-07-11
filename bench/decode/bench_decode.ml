(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* Decode + witness benchmark over a corpus directory: the M2 loader lane end
   to end (Walk roster -> per-entry Litany.Unit.load, decode-and-drop),
   reported against the M0 baseline of doc/spikes.md (>= ~85 MB/s decode,
   wrong-magic rejects ~0.17 ms).

   Plain executable by design (M3 fold disposition): the corpus is
   machine-local, so there is no committable baseline — the hermetic decode
   case thumper regression-gates is bench/traversal's [load]. Here
   [measure_corpus] is the case body, [Stats] the reporting, reps the
   samples. Run:

     dune exec bench/decode/bench_decode.exe -- _build/_private/default/.pkg

   Optional: [--source-root DIR] (defaults to the corpus dir), [--reps N]
   (defaults to 3). Output is one line per rep plus a median summary. *)

module Stats = struct
  let percentile p xs =
    (* [xs] sorted ascending; nearest-rank. *)
    match Array.length xs with
    | 0 -> 0.
    | n ->
        let rank = int_of_float (ceil (p /. 100. *. float_of_int n)) in
        xs.(max 0 (min (n - 1) (rank - 1)))

  let median xs =
    let sorted = List.sort compare xs in
    List.nth sorted (List.length sorted / 2)
end

type rep = {
  entries : int;
  direct : int;
  derived : int;
  skips : (string * int) list;
  roster_s : float;  (** Walk + grouping + pairing, before any load. *)
  wall_s : float;
  decoded_files : int;
  decoded_bytes : int;
  decode_s : float;
  load_ms : float array;  (** sorted, decoded loads only *)
  reject_files : int;
  reject_s : float;
  reject_ms : float array;  (** sorted, wrong-magic loads only *)
}

let skip_slug : Litany.Unit.Skip.t -> string = function
  | Stale -> "stale"
  | Wrong_magic _ -> "wrong-magic"
  | Missing_source -> "missing-source"
  | Missing_artifact -> "missing-artifact"
  | Derived_needs_build -> "derived-needs-build"
  | Unreadable _ -> "unreadable"
  | Partial_or_packed -> "partial-or-packed"
  | Modified_during_run -> "modified-during-run"

let file_size path =
  match (Unix.stat path).Unix.st_size with
  | size -> size
  | exception Unix.Unix_error _ -> 0

(* One full corpus pass. The decoded population (digest-joined or witness-
   skipped after a successful decode) carries the MB/s number; wrong-magic
   rejects are timed separately — their whole point is being cheap. *)
let measure_corpus ~cmt_root ~source_root () =
  (* The roster phase costs more than the decode lane on large stores
     (~2x here): the baseline must show it, or a walk/pairing regression
     is invisible. It is excluded from the decode MB/s by design — that
     number stays M0-comparable. *)
  let t_roster = Unix.gettimeofday () in
  let roster =
    match Litany.Adapter.Walk.roster ~cmt_root ~source_root with
    | Ok r -> r
    | Error e ->
        Format.eprintf "bench: %a@." Litany.Adapter.Walk.pp_error e;
        exit 2
  in
  let roster_s = Unix.gettimeofday () -. t_roster in
  let resolver = Litany.Naming.Resolver.create ~cmi_dirs:[] in
  let entries = Litany.Roster.entries roster in
  let skips = Hashtbl.create 8 in
  let direct = ref 0 and derived = ref 0 in
  let decoded_files = ref 0 and decoded_bytes = ref 0 in
  let decode_s = ref 0. and reject_s = ref 0. in
  let reject_files = ref 0 in
  let load_ms = ref [] and reject_ms = ref [] in
  let t_start = Unix.gettimeofday () in
  List.iter
    (fun entry ->
      let t0 = Unix.gettimeofday () in
      let outcome = Litany.Unit.load ~resolver ~build_current:false entry in
      let dt = Unix.gettimeofday () -. t0 in
      let decoded =
        match outcome with
        | Ok u ->
            (match Litany.Unit.Witness.kind (Litany.Unit.witness u) with
            | Direct -> incr direct
            | Derived -> incr derived);
            true
        | Error sk -> (
            let slug = skip_slug sk in
            Hashtbl.replace skips slug
              (1 + Option.value (Hashtbl.find_opt skips slug) ~default:0);
            match sk with
            | Wrong_magic _ ->
                incr reject_files;
                reject_s := !reject_s +. dt;
                reject_ms := (dt *. 1000.) :: !reject_ms;
                false
            | Stale | Missing_source | Derived_needs_build | Partial_or_packed
              ->
                true
            | Missing_artifact | Unreadable _ | Modified_during_run -> false)
      in
      if decoded then begin
        incr decoded_files;
        decoded_bytes :=
          !decoded_bytes
          + Option.value ~default:0
              (Option.map file_size (Litany.Roster.Entry.cmt entry));
        decode_s := !decode_s +. dt;
        load_ms := (dt *. 1000.) :: !load_ms
      end)
    entries;
  let wall_s = Unix.gettimeofday () -. t_start in
  let sorted xs =
    let a = Array.of_list xs in
    Array.sort compare a;
    a
  in
  {
    entries = List.length entries;
    direct = !direct;
    derived = !derived;
    skips =
      List.sort compare (Hashtbl.fold (fun k v acc -> (k, v) :: acc) skips []);
    roster_s;
    wall_s;
    decoded_files = !decoded_files;
    decoded_bytes = !decoded_bytes;
    decode_s = !decode_s;
    load_ms = sorted !load_ms;
    reject_files = !reject_files;
    reject_s = !reject_s;
    reject_ms = sorted !reject_ms;
  }

let mb bytes = float_of_int bytes /. (1024. *. 1024.)

let mb_per_s rep =
  if rep.decode_s = 0. then 0. else mb rep.decoded_bytes /. rep.decode_s

let report i rep =
  Printf.printf
    "rep %d: entries %d | admitted %d (direct %d, derived %d) | wall %.2f s\n" i
    rep.entries (rep.direct + rep.derived) rep.direct rep.derived rep.wall_s;
  Printf.printf "  roster: %.2f s (walk + pairing; not part of decode MB/s)\n"
    rep.roster_s;
  Printf.printf "  decoded: %d files, %.1f MB in %.2f s -> %.1f MB/s\n"
    rep.decoded_files (mb rep.decoded_bytes) rep.decode_s (mb_per_s rep);
  Printf.printf "  per-file load: p50 %.3f ms, p90 %.3f ms, p99 %.3f ms\n"
    (Stats.percentile 50. rep.load_ms)
    (Stats.percentile 90. rep.load_ms)
    (Stats.percentile 99. rep.load_ms);
  if rep.reject_files > 0 then
    Printf.printf "  wrong-magic: %d files, p50 %.3f ms, total %.2f s\n"
      rep.reject_files
      (Stats.percentile 50. rep.reject_ms)
      rep.reject_s;
  Printf.printf "  joins: %s\n"
    (if rep.skips = [] then "all admitted"
     else
       String.concat ", "
         (List.map (fun (slug, n) -> Printf.sprintf "%s %d" slug n) rep.skips))

(* [--raw]: pure [Cmt_format.read] over the same corpus, no witness, no
   roster pairing — the number directly comparable to the M0 decode
   baseline; the default mode's MB/s additionally carries the loader's
   witness join. *)
let measure_raw ~cmt_root () =
  let entries =
    Litany.Adapter.Walk.roster ~cmt_root ~source_root:cmt_root |> function
    | Ok r -> Litany.Roster.entries r
    | Error _ -> []
  in
  let files = ref 0 and bytes = ref 0 and total_s = ref 0. in
  let ms = ref [] in
  List.iter
    ((fun entry ->
      match Litany.Roster.Entry.cmt entry with
      | None -> ()
      | Some cmt -> (
          let t0 = Unix.gettimeofday () in
          match Cmt_format.read cmt with
          | _ ->
              let dt = Unix.gettimeofday () -. t0 in
              incr files;
              bytes := !bytes + file_size cmt;
              total_s := !total_s +. dt;
              ms := (dt *. 1000.) :: !ms
          | exception _ -> ()))
      [@litany.allow
        "suspicious-catch-all-handler: an unreadable artifact is a skipped \
         sample, not a failure"])
    entries;
  let sorted = Array.of_list !ms in
  Array.sort compare sorted;
  Printf.printf
    "raw decode: %d files, %.1f MB in %.2f s -> %.1f MB/s (p50 %.3f ms, p90 \
     %.3f ms)\n"
    !files (mb !bytes) !total_s
    (if !total_s = 0. then 0. else mb !bytes /. !total_s)
    (Stats.percentile 50. sorted)
    (Stats.percentile 90. sorted)

let () =
  let corpus = ref None and source_root = ref None and reps = ref 3 in
  let raw = ref false in
  let rec parse = function
    | [] -> ()
    | "--source-root" :: dir :: rest ->
        source_root := Some dir;
        parse rest
    | "--reps" :: n :: rest ->
        reps := int_of_string n;
        parse rest
    | "--raw" :: rest ->
        raw := true;
        parse rest
    | dir :: rest when !corpus = None ->
        corpus := Some dir;
        parse rest
    | arg :: _ ->
        prerr_endline ("bench_decode: unknown argument " ^ arg);
        exit 2
  in
  parse (List.tl (Array.to_list Sys.argv));
  match !corpus with
  | None ->
      prerr_endline
        "usage: bench_decode CORPUS_DIR [--source-root DIR] [--reps N]";
      exit 2
  | Some cmt_root when !raw ->
      Printf.printf "corpus: %s (raw decode)\n%!" cmt_root;
      for _ = 1 to !reps do
        measure_raw ~cmt_root ();
        flush stdout
      done
  | Some cmt_root ->
      let source_root = Option.value !source_root ~default:cmt_root in
      Printf.printf "corpus: %s (source root %s)\n%!" cmt_root source_root;
      let all = ref [] in
      for i = 1 to !reps do
        let rep = measure_corpus ~cmt_root ~source_root () in
        all := rep :: !all;
        report i rep;
        flush stdout
      done;
      let reps = List.rev !all in
      Printf.printf
        "median of %d: roster %.2f s, decode %.1f MB/s, load p50 %.3f ms, p90 \
         %.3f ms\n"
        (List.length reps)
        (Stats.median (List.map (fun r -> r.roster_s) reps))
        (Stats.median (List.map mb_per_s reps))
        (Stats.median (List.map (fun r -> Stats.percentile 50. r.load_ms) reps))
        (Stats.median (List.map (fun r -> Stats.percentile 90. r.load_ms) reps));
      (* Portable memory guard: the OCaml heap top. Process RSS additionally
         carries allocator retention over the decode churn (see m2-notes);
         track it with /usr/bin/time -l when it matters. *)
      Printf.printf "heap: top %d MB (process RSS via /usr/bin/time -l)\n"
        ((Gc.quick_stat ()).Gc.top_heap_words * 8 / 1048576)
