The restricted-dependency cram: the configured deny-list end to end —
a nested dune project, a litany config with (forbid ... (use ...))
forms, selection by exact name, and the schema's refusals. The fixture
is built for real inside the sandbox; cram commands run inside dune, so
the shell unsets INSIDE_DUNE exactly as a user's shell has it.

(Under a GitHub Actions job litany check auto-selects the github report
format; this cram pins the text page, so the selector is unset for the
whole session.)

  $ unset GITHUB_ACTIONS

  $ mkdir -p proj/vendor && cd proj
  $ cat > dune-project <<'EOP'
  > (lang dune 3.20)
  > EOP
  $ cat > dune <<'EOP'
  > (library (name rd_cram) (libraries legacylib))
  > EOP
  $ cat > vendor/dune <<'EOP'
  > (library (name legacylib) (wrapped false))
  > EOP
  $ cat > vendor/legacy.ml <<'EOP'
  > let token = "legacy"
  > 
  > module Internal = struct
  >   let secret = 42
  > end
  > EOP
  $ cat > app.ml <<'EOP'
  > let a = Legacy.token
  > let b = Legacy.Internal.secret
  > let f () = invalid_arg "boom"
  > let cast (x : int) : int = Obj.magic x
  > 
  > module Legacy = struct
  >   let token = "local"
  > end
  > 
  > let c = Legacy.token
  > EOP

The workspace policy: a whole vendored unit, one stdlib value, and a
module reached through a Stdlib alias, each ban naming its replacement.

  $ cat > litany <<'EOP'
  > (rule restricted-dependency
  >  (forbid Legacy
  >   (use "the supported api module"))
  >  (forbid Stdlib.invalid_arg
  >   (use "Import.invalid_arg' — house messages carry module and function"))
  >  (forbid Stdlib.Obj
  >   (use "a typed interface")))
  > EOP

Configured but not selected: the rule is Restriction — outside default
and all — so a plain check runs none of it and says so.

  $ env -u INSIDE_DUNE litany check 2>&1 | grep -E "restricted-dependency|rules selected"
  litany: rule "restricted-dependency" is configured but not selected
  30 rules selected · 3 units · 0 findings · 0 skipped · 1 facts-only

Selected by exact name: every reference resolving to a forbidden
declaration fires, the message carrying the configured use remedy
verbatim. The local module named Legacy at the bottom of app.ml shadows
the vendored unit — its references resolve to local declarations and
stay clean.

  $ env -u INSIDE_DUNE litany check --select restricted-dependency
  app.ml:1:9 warning restricted-dependency
    Legacy is a restricted module; use the supported api module
       1 | let a = Legacy.token
         |         ^^^^^^^^^^^^
  app.ml:2:9 warning restricted-dependency
    Legacy is a restricted module; use the supported api module
       2 | let b = Legacy.Internal.secret
         |         ^^^^^^^^^^^^^^^^^^^^^^
  app.ml:3:12 warning restricted-dependency
    Stdlib.invalid_arg is a restricted value; use Import.invalid_arg' — house messages carry module and function
       3 | let f () = invalid_arg "boom"
         |            ^^^^^^^^^^^
  app.ml:4:28 warning restricted-dependency
    Stdlib.Obj is a restricted module; use a typed interface
       4 | let cast (x : int) : int = Obj.magic x
         |                            ^^^^^^^^^
  
  1 rule selected · 3 units · 4 findings · 0 skipped · 1 facts-only
  [1]


Unconfigured selection is inert by contract: with no (rule ...) form
the deny-list is empty, nothing is forbidden, and the run is clean —
and says so: selected-but-unconfigured is the mirror of the
configured-but-unselected trap, warned on the same channel.

  $ rm litany
  $ env -u INSIDE_DUNE litany check --select restricted-dependency 2>&1 | head -2
  litany: rule "restricted-dependency" is selected but not configured; it reports nothing without a (rule restricted-dependency ...) form
  1 rule selected · 3 units · 0 findings · 0 skipped · 1 facts-only

A forbid without its (use ...) remedy is a positioned refusal — the
mandatory-remedy contract — and nothing runs.

  $ cat > litany <<'EOP'
  > (rule restricted-dependency
  >  (forbid Legacy))
  > EOP
  $ env -u INSIDE_DUNE litany check --select restricted-dependency
  litany: litany:2:2: forbid Legacy wants a (use "<replacement>") remedy — every ban names its replacement
  [2]

A forbidden path that does not resolve here matches nothing — one house
config serves workspaces that lack the library entirely.

  $ cat > litany <<'EOP'
  > (rule restricted-dependency
  >  (forbid Base.Fn.id
  >   (use "Fun.id")))
  > EOP
  $ env -u INSIDE_DUNE litany check --select restricted-dependency 2>&1 | head -1
  1 rule selected · 3 units · 0 findings · 0 skipped · 1 facts-only
