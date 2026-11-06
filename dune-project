(lang dune 3.23)

(name litany)

(generate_opam_files true)

(implicit_transitive_deps false)

(source
 (github hyphatech/litany))

(homepage "https://github.com/hyphatech/litany")

(documentation "https://hyphatech.github.io/litany/")

(bug_reports "https://github.com/hyphatech/litany/issues")

(authors "Thibaut Mattio <thibaut.mattio@gmail.com>")

(maintainers "Hypha Technologies Ltd <dev@hyphatech.io>")

(maintenance_intent "(latest)")

(license ISC)




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
    (>= 0.3.1)))
  (ppx_windtrap
   (and
    :with-test
    (>= 0.3.1)))
  (thumper
   (and
    :with-test
    (>= 0.1.0))))
 (tags
  (linter static-analysis developer-tools ocaml)))
