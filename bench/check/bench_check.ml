(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* End-to-end benchmark of the M8 check lane: the shipped [litany] binary
   over a corpus at -j 1/2/4/8 (byte-comparing every page), then the cache
   lane cold vs warm. The M8 acceptance numbers live in doc/m8-notes.md,
   against the prototype evidence of doc/m8-workers-evidence.md.

   Plain executable, spawning the binary — the worker fork and the cache IO
   are exactly what is being measured, so nothing here goes through the
   libraries. Run:

     bench_check.exe LITANY CORPUS [--reps N] [--select TOKENS]

   LITANY is the litany binary to drive (e.g. _build/default/bin/main.exe),
   CORPUS a directory of prebuilt artifacts (used as both --root and
   --cmt-root). [--reps] defaults to 3 (medians reported); [--select]
   defaults to all,nursery — the full catalog, the prototype's workload. *)

let median xs =
  let sorted = List.sort compare xs in
  List.nth sorted (List.length sorted / 2)

let tmp_name =
  let counter = ref 0 in
  fun stem ->
    incr counter;
    Filename.concat
      (Filename.get_temp_dir_name ())
      (Printf.sprintf "bench-check-%d-%s-%d" (Unix.getpid ()) stem !counter)

(* [run litany args ~out] spawns [litany args] with stdout to [out] and
   stderr to a scratch file, and is the wall time. Exit 0 (clean) and 1
   (findings) are both healthy; anything else aborts the bench. *)
let run litany args ~out =
  let err = tmp_name "err" in
  let out_fd = Unix.openfile out [ O_WRONLY; O_CREAT; O_TRUNC ] 0o600 in
  let err_fd = Unix.openfile err [ O_WRONLY; O_CREAT; O_TRUNC ] 0o600 in
  let argv = Array.of_list (litany :: args) in
  let t0 = Unix.gettimeofday () in
  let pid = Unix.create_process litany argv Unix.stdin out_fd err_fd in
  let _, status = Unix.waitpid [] pid in
  let wall = Unix.gettimeofday () -. t0 in
  Unix.close out_fd;
  Unix.close err_fd;
  (match status with
  | Unix.WEXITED (0 | 1) -> ()
  | status ->
      let describe =
        (* [waitpid] reports OCaml's [Sys.sig*] numbering, not the OS's —
           name the common ones (mirrors [Cli_parallel.signal_name]). *)
        let signal_name n =
          match
            List.assoc_opt n
              [
                (Sys.sigabrt, "SIGABRT");
                (Sys.sigbus, "SIGBUS");
                (Sys.sigfpe, "SIGFPE");
                (Sys.sighup, "SIGHUP");
                (Sys.sigill, "SIGILL");
                (Sys.sigint, "SIGINT");
                (Sys.sigkill, "SIGKILL");
                (Sys.sigpipe, "SIGPIPE");
                (Sys.sigquit, "SIGQUIT");
                (Sys.sigsegv, "SIGSEGV");
                (Sys.sigterm, "SIGTERM");
              ]
          with
          | Some name -> name
          | None -> Printf.sprintf "signal %d (ocaml numbering)" n
        in
        match status with
        | Unix.WEXITED n -> Printf.sprintf "exited %d" n
        | Unix.WSIGNALED n -> Printf.sprintf "killed by %s" (signal_name n)
        | Unix.WSTOPPED n -> Printf.sprintf "stopped by %s" (signal_name n)
      in
      Printf.eprintf "bench-check: litany %s (%s); stderr follows\n%s\n"
        (String.concat " " args) describe
        (In_channel.with_open_bin err In_channel.input_all);
      exit 2);
  Sys.remove err;
  wall

let file_equal a b =
  In_channel.with_open_bin a In_channel.input_all
  = In_channel.with_open_bin b In_channel.input_all

let () =
  let litany = ref None
  and corpus = ref None
  and reps = ref 3
  and select = ref "all,nursery" in
  let rec parse = function
    | [] -> ()
    | "--reps" :: n :: rest ->
        reps := int_of_string n;
        parse rest
    | "--select" :: s :: rest ->
        select := s;
        parse rest
    | arg :: rest when !litany = None ->
        litany := Some arg;
        parse rest
    | arg :: rest when !corpus = None ->
        corpus := Some arg;
        parse rest
    | arg :: _ ->
        prerr_endline ("bench-check: unknown argument " ^ arg);
        exit 2
  in
  parse (List.tl (Array.to_list Sys.argv));
  let litany, corpus =
    match (!litany, !corpus) with
    | Some l, Some c -> (l, c)
    | _ ->
        prerr_endline
          "usage: bench_check LITANY CORPUS [--reps N] [--select TOKENS]";
        exit 2
  in
  let base =
    [
      "check";
      "--root";
      corpus;
      "--cmt-root";
      corpus;
      "--no-build";
      "--select";
      !select;
    ]
  in
  (* Workers: medians per -j over [reps] runs, every page byte-compared
     against the -j 1 reference. One discarded warmup primes the FS cache. *)
  let reference = tmp_name "ref" in
  ignore (run litany (base @ [ "-j"; "1"; "--no-cache" ]) ~out:reference);
  let j1 = ref 0. in
  List.iter
    (fun j ->
      let walls =
        List.init !reps (fun _ ->
            let out = tmp_name "page" in
            let wall =
              run litany (base @ [ "-j"; string_of_int j; "--no-cache" ]) ~out
            in
            if not (file_equal reference out) then begin
              Printf.eprintf "bench-check: page at -j %d differs from -j 1\n" j;
              exit 2
            end;
            Sys.remove out;
            wall)
      in
      let m = median walls in
      if j = 1 then j1 := m;
      Printf.printf
        "RESULT lane=workers jobs=%d reps=%d median_s=%.2f speedup=%.2fx \
         identical=yes\n\
         %!"
        j !reps m (!j1 /. m))
    [ 1; 2; 4; 8 ];
  (* Cache: one cold run into a fresh --cache-dir, then warm medians; the
     warm page must equal the cold page (and so the -j 1 reference). *)
  let cache_dir = tmp_name "cache" in
  let cached = base @ [ "-j"; "1"; "--cache-dir"; cache_dir ] in
  let cold_out = tmp_name "cold" in
  let cold = run litany cached ~out:cold_out in
  if not (file_equal reference cold_out) then begin
    prerr_endline "bench-check: cold cached page differs";
    exit 2
  end;
  let warms =
    List.init !reps (fun _ ->
        let out = tmp_name "warm" in
        let wall = run litany cached ~out in
        if not (file_equal reference out) then begin
          prerr_endline "bench-check: warm page differs";
          exit 2
        end;
        Sys.remove out;
        wall)
  in
  Printf.printf
    "RESULT lane=cache cold_s=%.2f warm_median_s=%.2f warm_speedup=%.2fx \
     identical=yes\n\
     %!"
    cold (median warms)
    (cold /. median warms);
  Sys.remove cold_out;
  Sys.remove reference;
  (* Best-effort scratch cleanup; the cache dir is bench-local. *)
  ignore (Sys.command (Filename.quote_command "rm" [ "-rf"; cache_dir ]))
