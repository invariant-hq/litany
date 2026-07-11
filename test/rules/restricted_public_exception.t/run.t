The restricted-public-exception cram: the kind and visibility gates end
to end — a nested dune project with a public library (an mli exception,
the positive; an mli-hidden exception, a negative), a private library
and an executable each holding the same interface exception (both
silent), selection by exact name. The fixture is built for real inside
the sandbox; cram commands run inside dune, so the shell unsets
INSIDE_DUNE exactly as a user's shell has it.

(Under a GitHub Actions job litany check auto-selects the github report
format; this cram pins the text page, so the selector is unset for the
whole session.)

  $ unset GITHUB_ACTIONS

  $ mkdir -p proj/pub proj/priv proj/bin && cd proj
  $ cat > dune-project <<'EOP'
  > (lang dune 3.20)
  > (package (name publib))
  > EOP
  $ cat > pub/dune <<'EOP'
  > (library (name publib) (public_name publib))
  > EOP
  $ cat > pub/api.mli <<'EOP'
  > exception Parse_error of string
  > 
  > val parse : string -> int
  > EOP
  $ cat > pub/api.ml <<'EOP'
  > exception Parse_error of string
  > 
  > let parse s =
  >   match int_of_string_opt s with
  >   | Some n -> n
  >   | None -> raise (Parse_error s)
  > EOP
  $ cat > pub/impl.mli <<'EOP'
  > val run : string -> int
  > EOP
  $ cat > pub/impl.ml <<'EOP'
  > exception Internal
  > 
  > let run s = if String.length s = 0 then raise Internal else Api.parse s
  > EOP
  $ cat > priv/dune <<'EOP'
  > (library (name privlib))
  > EOP
  $ cat > priv/privlib.mli <<'EOP'
  > exception Boom
  > 
  > val go : int -> int
  > EOP
  $ cat > priv/privlib.ml <<'EOP'
  > exception Boom
  > 
  > let go n = if n < 0 then raise Boom else n
  > EOP
  $ cat > bin/dune <<'EOP'
  > (executable (name main))
  > EOP
  $ cat > bin/main.ml <<'EOP'
  > exception Fatal
  > 
  > let () = if Array.length Sys.argv > 9 then raise Fatal else print_string "ok"
  > EOP

Selected by exact name — the rule is Restriction, outside default and
all, so only the exact name runs it. The public library's interface
exception fires, anchored at the implementation's declaration; the
exception its mli hides, the private library's byte-identical interface
exception, and the executable's exception never fire.

  $ env -u INSIDE_DUNE litany check --select restricted-public-exception
  pub/api.ml:1:11 warning restricted-public-exception
    exception Parse_error is declared in a public library interface; return a result instead
       1 | exception Parse_error of string
         |           ^^^^^^^^^^^
  
  1 rule selected · 5 units · 1 finding · 0 skipped · 1 facts-only
  [1]

