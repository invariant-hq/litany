The suspicious-file-exists-race cram: check-then-act on the filesystem
through the real binary — a nested dune project built for real inside
the sandbox, selection by exact name (the rule is Restriction, outside
default and all). Cram commands run inside dune, so the shell unsets
INSIDE_DUNE exactly as a user's shell has it.

(Under a GitHub Actions job litany check auto-selects the github report
format; this cram pins the text page, so the selector is unset for the
whole session.)

  $ unset GITHUB_ACTIONS

  $ mkdir -p proj/lib && cd proj
  $ cat > dune-project <<'EOP'
  > (lang dune 3.20)
  > EOP
  $ cat > lib/dune <<'EOP'
  > (library (name racelib) (libraries unix))
  > EOP
  $ cat > lib/racelib.ml <<'EOP'
  > let cleanup path = if Sys.file_exists path then Sys.remove path
  > 
  > let ensure dir = if not (Sys.file_exists dir) then Unix.mkdir dir 0o755
  > 
  > let ensure_quiet dir =
  >   if not (Sys.file_exists dir) then
  >     try Unix.mkdir dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  > 
  > let probe () = if Sys.file_exists "/proc/stat" then "linux" else "macos"
  > EOP

Selected by exact name. The guarded Sys.remove and the negated-guard
Unix.mkdir fire — Stdlib and Unix identities both resolve through the
real build; the handled mkdir (the remedy) and the platform probe stay
silent.

  $ env -u INSIDE_DUNE litany check --select suspicious-file-exists-race
  File "lib/racelib.ml", line 1, characters 22-42:
  1 | let cleanup path = if Sys.file_exists path then Sys.remove path
                            ^^^^^^^^^^^^^^^^^^^^
  Warning 0 [suspicious-file-exists-race]: the exists check races with the guarded operation; perform it and handle the exception
    
  File "lib/racelib.ml", line 3, characters 20-45:
  3 | let ensure dir = if not (Sys.file_exists dir) then Unix.mkdir dir 0o755
                          ^^^^^^^^^^^^^^^^^^^^^^^^^
  Warning 0 [suspicious-file-exists-race]: the exists check races with the guarded operation; perform it and handle the exception
  
  1 rule selected · 1 unit · 2 findings · 0 skipped
  [1]
