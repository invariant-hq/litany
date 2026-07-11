(lang dune 3.23)

(name litany)

(generate_opam_files true)

(implicit_transitive_deps false)

(source
 (github invariant-hq/litany))

(homepage "https://github.com/invariant-hq/litany")

(documentation "https://github.com/invariant-hq/litany#readme")

(bug_reports "https://github.com/invariant-hq/litany/issues")

(authors "Thibaut Mattio <thibaut.mattio@gmail.com>")

(maintainers "Thibaut Mattio <thibaut.mattio@gmail.com>")

(maintenance_intent "(latest)")

(license ISC)

(pin
 (url "git+https://github.com/invariant-hq/thumper.git")
 (package
  (name thumper)))

(pin
 (url "git+https://github.com/invariant-hq/windtrap.git")
 (package
  (name windtrap)))

(pin
 (url "git+https://github.com/invariant-hq/windtrap.git")
 (package
  (name ppx_windtrap)))

(package
 (name litany)
 (synopsis "A linter for OCaml")
 (description
 "Litany examines OCaml sources and reports style and correctness issues, so they can be faced and fixed rather than silenced.")
 (depends
  dune
  (ocaml
   (and
    (>= 5.5.0)
    (< 5.6.0)))
  (cmdliner
   (>= 2.0.0))
  (windtrap
   (and
    :with-test
    (>= 0.2.0)))
  (ppx_windtrap
   (and
    :with-test
    (>= 0.2.0)))
  (thumper :with-test))
 (tags
  (linter static-analysis developer-tools ocaml org:invariant-hq)))
