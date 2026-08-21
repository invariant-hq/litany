The unit file: the one interface any build system can target. litany units
enumerates the workspace exactly as litany check does and serializes the
roster; litany check --units consumes the file from any producer — no dune
spawned, no build run, no lock taken. The fixture is a real nested dune
project.

(Under a GitHub Actions job litany check auto-selects the github report
format; this cram pins the text page, so the selector is unset for the
whole session.)

  $ unset GITHUB_ACTIONS
  $ mkdir proj && cd proj
  $ cat > dune-project <<'EOP'
  > (lang dune 3.20)
  > EOP
  $ cat > dune <<'EOP'
  > (library (name unitslib))
  > EOP
  $ cat > length.ml <<'EOP'
  > let is_empty xs = List.length xs = 0
  > EOP
  $ cat > clean.ml <<'EOP'
  > let double x = x + x
  > EOP

Inside a dune action litany units refuses to spawn dune — there the argv
is the roster (litany unit), or a saved file is.

  $ litany units
  litany: refusing to spawn dune from inside a dune action (INSIDE_DUNE is set).
  Pass --cmt-root DIR to enumerate prebuilt artifacts.
  [2]

A bare litany units dumps the roster for eyes — the same document as
--save, spelled as human sexps, so reading a dump teaches the format.

  $ env -u INSIDE_DUNE litany units
  (litany-units 1)
  (cmi-dirs _build/default/.unitslib.objs/byte)
  (unit (source length.ml) (cmt _build/default/.unitslib.objs/byte/unitslib__Length.cmt) (library unitslib) (public false) (kind lib))
  (unit (source clean.ml) (cmt _build/default/.unitslib.objs/byte/unitslib__Clean.cmt) (library unitslib) (public false) (kind lib))
  (unit (source _build/default/unitslib.ml-gen) (cmt _build/default/.unitslib.objs/byte/unitslib.cmt) (library unitslib) (public false) (kind lib))

--save writes the canonical unit file: csexp, atoms as length-prefixed raw
bytes (any path round-trips), one form per line, byte-deterministic.

  $ env -u INSIDE_DUNE litany units --save litany.units; echo "exit=$?"
  exit=0
  $ cat litany.units
  (12:litany-units1:1)
  (8:cmi-dirs34:_build/default/.unitslib.objs/byte)
  (4:unit(6:source9:length.ml)(3:cmt55:_build/default/.unitslib.objs/byte/unitslib__Length.cmt)(7:library8:unitslib)(6:public5:false)(4:kind3:lib))
  (4:unit(6:source8:clean.ml)(3:cmt54:_build/default/.unitslib.objs/byte/unitslib__Clean.cmt)(7:library8:unitslib)(6:public5:false)(4:kind3:lib))
  (4:unit(6:source30:_build/default/unitslib.ml-gen)(3:cmt47:_build/default/.unitslib.objs/byte/unitslib.cmt)(7:library8:unitslib)(6:public5:false)(4:kind3:lib))
  $ env -u INSIDE_DUNE litany units --save again.units && cmp litany.units again.units && echo deterministic
  deterministic

litany check --units consumes the file with no dune spawned and no build
run — the lane works even inside a dune action, and a running watch server
beside it is the same story: the lock arbitrates dune-vs-dune, never
litany's reads.

  $ litany check --units litany.units
  File "length.ml", line 1, characters 18-36:
  1 | let is_empty xs = List.length xs = 0
                        ^^^^^^^^^^^^^^^^^^
  Warning 0 [needless-list-length]: comparison through List.length is a needless emptiness test
    fix (safe): compare with []
  
  30 rules selected · 3 units · 1 finding (1 fixable — run `litany check --fix`) · 0 skipped · 1 facts-only
  [1]

A file that does not decode is a positioned refusal — exit 2, nothing
runs.

  $ printf 'garbage' > bad.units
  $ litany check --units bad.units
  litany: bad.units: unit file: byte 0: expected a length prefix
  [2]

So is a missing file.

  $ litany check --units no-such.units
  litany: no-such.units: No such file or directory
  [2]
