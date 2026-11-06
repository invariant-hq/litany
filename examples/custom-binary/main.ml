(* The whole custom binary: the stock catalog plus your rules. *)
let () =
  let root = "." in
  let rules = Litany_rules.all @ My_rules.all in
  let progress = Litany.Progress.v ~enabled:true ~jobs:1 in
  let code =
    match Litany.Adapter.Dune.roster ~progress ~root () with
    | Error e -> Litany.Driver.refuse "%a" Litany.Adapter.Dune.pp_error e
    | Ok roster ->
        let cache =
          Litany.Driver.Result_cache.setup ~cache_dir:None ~no_cache:false ~root
            ~rules
        in
        let rebuild () = Litany.Adapter.Dune.roster ~progress ~root () in
        let code =
          Litany.Driver.run_check ~progress ~rebuild:(Some rebuild)
            ~format:Litany.Driver.Text ~jobs:None ~cache roster
            ~build_current:true ~rules ~catalog:rules ~keep:None ~fix:None
            ~explain_withheld:false
        in
        Option.iter
          (fun c -> Litany.Driver.Result_cache.finish c ~stats:false)
          cache;
        code
  in
  exit code
