(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* The suppression policy over parses of inline sources: payload grammar,
   scope computation, innermost-wins matching, and the demand scan. *)

open Windtrap
module Sup = Litany.Suppress
module D = Sup.Directive
module M = Sup.Malformed
module Span = Litany.Span

let policy src =
  Sup.of_structure ~source_length:(String.length src)
    (Parse.implementation (Lexing.from_string src))

(* [find src sub] is the span of the first occurrence of [sub] in [src] — the
   coordinates assertions and probes use, so tests never hand-count bytes. *)
let find src sub =
  let n = String.length src and m = String.length sub in
  let rec at i =
    if i + m > n then failf "%S does not occur in the source" sub
    else if String.sub src i m = sub then i
    else at (i + 1)
  in
  let start = at 0 in
  Span.v ~start ~stop:(start + m)

let span_t = Testable.make ~pp:Span.pp ~equal:Span.equal

let one_directive src =
  match Sup.directives (policy src) with
  | [ d ] -> d
  | ds -> failf "expected one directive, got %d" (List.length ds)

let one_malformed src =
  let p = policy src in
  match (Sup.directives p, Sup.malformed p) with
  | [], [ m ] -> m
  | ds, ms ->
      failf "expected one malformed alone, got %d directives, %d malformed"
        (List.length ds) (List.length ms)

let problem_name = function
  | M.Unknown_name n -> "unknown-name:" ^ n
  | M.Not_a_string -> "not-a-string"
  | M.Missing_colon -> "missing-colon"
  | M.Missing_rule -> "missing-rule"
  | M.Missing_reason -> "missing-reason"
  | M.Invalid_reason -> "invalid-reason"

let payload_tests =
  group "payload"
    [
      test "parses rule name and reason" (fun () ->
          let d =
            one_directive {|let a = (1 [@litany.allow "flag-int: reason"])|}
          in
          is_true (D.kind d = D.Allow);
          equal string "flag-int" (D.rule d);
          equal string "reason" (D.reason d));
      test "expect is the other kind" (fun () ->
          let d = one_directive {|let a = (1 [@litany.expect "r: fires"])|} in
          is_true (D.kind d = D.Expect));
      test "blanks around the dot still spell the attribute id" (fun () ->
          let d =
            one_directive {|let a = (1 [@litany . allow "flag-int: spaced"])|}
          in
          is_true (D.kind d = D.Allow);
          equal string "flag-int" (D.rule d));
      test "trims horizontal whitespace around rule and reason" (fun () ->
          let d =
            one_directive
              "let a = (1 [@litany.allow \"  flag-int\t:  the reason \t\"])"
          in
          equal string "flag-int" (D.rule d);
          equal string "the reason" (D.reason d));
      test "missing colon is malformed" (fun () ->
          let m =
            one_malformed {|let a = (1 [@litany.allow "no colon here"])|}
          in
          equal string "missing-colon" (problem_name (M.problem m));
          is_true (M.kind m = Some D.Allow);
          equal string
            "malformed allow payload \xe2\x80\x94 missing \":\" (expected \
             \"rule-name: reason\")"
            (M.message m));
      test "missing rule name is malformed" (fun () ->
          let m = one_malformed {|let a = (1 [@litany.allow ": reason"])|} in
          equal string "missing-rule" (problem_name (M.problem m)));
      test "missing reason is malformed — reasons are mandatory" (fun () ->
          let m =
            one_malformed {|let a = (1 [@litany.expect "flag-int:  "])|}
          in
          equal string "missing-reason" (problem_name (M.problem m));
          is_true (M.kind m = Some D.Expect));
      test "a reason spanning lines is invalid" (fun () ->
          let m =
            one_malformed "let a = (1 [@litany.allow \"r: two\\nlines\"])"
          in
          equal string "invalid-reason" (problem_name (M.problem m)));
      test "a payload that is not one string literal is malformed" (fun () ->
          let m = one_malformed {|let a = (1 [@litany.allow])|} in
          equal string "not-a-string" (problem_name (M.problem m));
          let m = one_malformed {|let a = (1 [@litany.allow 42])|} in
          equal string "not-a-string" (problem_name (M.problem m)));
      test "an unknown litany attribute suggests the nearest reserved name"
        (fun () ->
          let m = one_malformed {|let a = (1 [@litany.alow "r: x"])|} in
          is_true (M.kind m = None);
          equal string
            "unknown attribute \"litany.alow\" (did you mean \"litany.allow\"?)"
            (M.message m));
      test "an unknown litany attribute far from both names gets no hint"
        (fun () ->
          let m = one_malformed {|let a = (1 [@litany.root "r: x"])|} in
          equal string "unknown attribute \"litany.root\"" (M.message m));
      test "attributes outside the litany namespace are ignored" (fun () ->
          let p =
            policy {|let[@inline] a = (1 [@warning "-a"]) [@@deprecated]|}
          in
          equal int 0 (List.length (Sup.directives p));
          equal int 0 (List.length (Sup.malformed p)));
    ]

let covering ?(rule = fun _ -> true) src sub =
  Sup.covering (policy src) ~rule (find src sub)

let scope_tests =
  group "scopes"
    [
      test "an attached directive scopes to its node's span" (fun () ->
          let src = {|let a = (41 [@litany.allow "r: here"])
let b = 42|} in
          (match covering src "41" with
          | Some d -> equal string "here" (D.reason d)
          | None -> fail "the attribute's own node is covered");
          is_true (covering src "42" = None));
      test "the scope of a parenthesized expression includes the parens"
        (fun () ->
          let src = {|let a = (41 [@litany.allow "r: x"])|} in
          equal span_t
            (find src {|(41 [@litany.allow "r: x"])|})
            (D.scope (one_directive src)));
      test "an item attribute scopes to the whole binding" (fun () ->
          let src = {|let c = 43 [@@litany.allow "r: item"]
let d = 44|} in
          (match covering src "43" with
          | Some d -> equal string "item" (D.reason d)
          | None -> fail "the binding is covered");
          is_true (covering src "44" = None));
      test "the innermost of nested scopes wins" (fun () ->
          let src =
            {|let a = (41 [@litany.allow "r: inner"]) [@@litany.allow "r: outer"]|}
          in
          match covering src "41" with
          | Some d -> equal string "inner" (D.reason d)
          | None -> fail "nested scopes both cover the node");
      test "between equal scopes the later attribute wins" (fun () ->
          let src =
            {|let a = (41 [@litany.allow "r: first"] [@litany.allow "r: second"])|}
          in
          match covering src "41" with
          | Some d -> equal string "second" (D.reason d)
          | None -> fail "the node is covered");
      test "a floating directive scopes to the rest of the file" (fun () ->
          let src = {|let a = 41
[@@@litany.allow "r: below"]
let b = 42|} in
          is_true (covering src "41" = None);
          (match covering src "42" with
          | Some d -> equal string "below" (D.reason d)
          | None -> fail "code below the floating attribute is covered");
          equal span_t
            (Span.v
               ~start:(Span.start (find src "[@@@litany.allow"))
               ~stop:(String.length src))
            (D.scope (one_directive src)));
      test "covering respects the rule predicate" (fun () ->
          let src = {|let a = (41 [@litany.allow "r: x"])|} in
          is_true
            (Sup.covering (policy src)
               ~rule:(fun r -> r = "other")
               (find src "41")
            = None));
      test "directives are in source order" (fun () ->
          let src =
            {|let a = (1 [@litany.allow "one: x"])
let b = (2 [@litany.expect "two: y"])|}
          in
          equal (list string) [ "one"; "two" ]
            (List.map D.rule (Sup.directives (policy src))));
      test "an unrecognized carrier falls back to the attribute's own span"
        (fun () ->
          (* Class declarations are outside the recognized carrier set: the
             directive scopes to its own attribute span, matches nothing
             real, and the audit surfaces it. *)
          let src = {|class c = object end [@@litany.allow "r: class"]|} in
          let d = one_directive src in
          equal span_t (D.span d) (D.scope d);
          is_true (covering src "object" = None));
    ]

let scan_tests =
  group "scan"
    [
      test "a written directive is spelled" (fun () ->
          is_true (Sup.spelled {|let a = (1 [@litany.allow "r: x"])|});
          is_true (Sup.spelled {|[@@@litany.expect "r: x"]|}));
      test "a typo inside the namespace still answers true" (fun () ->
          is_true (Sup.spelled {|let a = (1 [@litany.alow "r: x"])|}));
      test "blanks or comments around the dot still answer true" (fun () ->
          (* An attribute id is a token sequence: the dot may be separated
             from [litany] by blanks or comments, so the needle is the token,
             not ["litany."]. Both sources parse as one directive. *)
          is_true (Sup.spelled {|let a = (1 [@litany . allow "r: x"])|});
          is_true (Sup.spelled "let a = (1 [@litany\n. allow \"r: x\"])"));
      test "no attribute opener, no demand" (fun () ->
          is_false (Sup.spelled "let a = 1 (* litany.allow *)"));
      test "no litany namespace, no demand" (fun () ->
          is_false (Sup.spelled {|let[@inline] a = (1 [@warning "-a"])|}));
    ]

let deletion_tests =
  group "deletion"
    [
      test "widens over the blanks before an inline attribute" (fun () ->
          let src = "let fine = 1 [@@litany.allow \"r: stale\"]\n" in
          let d = one_directive src in
          (* The line keeps its binding, so only the attribute and the blank
             before it go; the ending stays. *)
          equal span_t
            (find src " [@@litany.allow \"r: stale\"]")
            (D.deletion ~source:src d));
      test "a floating attribute on its own line deletes the whole line"
        (fun () ->
          let src = "let a = 1\n[@@@litany.allow \"r: file\"]\nlet b = 2\n" in
          let d = one_directive src in
          equal span_t
            (find src "[@@@litany.allow \"r: file\"]\n")
            (D.deletion ~source:src d));
      test "an indented own-line attribute deletes indentation and ending"
        (fun () ->
          let src =
            "module M = struct\n  [@@@litany.allow \"r: scoped\"]\nend\n"
          in
          let d = one_directive src in
          equal span_t
            (find src "  [@@@litany.allow \"r: scoped\"]\n")
            (D.deletion ~source:src d));
      test "a CRLF line ending is taken whole" (fun () ->
          let src = "[@@@litany.allow \"r: x\"]\r\nlet a = 1\r\n" in
          let d = one_directive src in
          equal span_t
            (find src "[@@@litany.allow \"r: x\"]\r\n")
            (D.deletion ~source:src d));
      test "an attribute at end of file without a newline runs to the end"
        (fun () ->
          let src = "let a = 1\n[@@@litany.allow \"r: x\"]" in
          let d = one_directive src in
          equal span_t
            (find src "[@@@litany.allow \"r: x\"]")
            (D.deletion ~source:src d));
    ]

(* Fuzz totality and bounds — the prior implementation's
   suppression-scanner property, kept as spec: the scanner is total over
   0–1024 random bytes and every reported span is in bounds. The current scanner
   splits into the lexical demand scan ([spelled]), the policy compiler over
   a parse, and the lexical deletion widening ([Directive.deletion]) — the
   hand-rolled text-scanning half is exactly the bug class M4 found one of,
   so the property pins all of it: nothing raises, and every span the policy
   reports (attribute, scope, deletion, malformed) lies within the source. *)

let gen_bytes =
  Gen.string_of ~size:(Gen.int_range 0 1024) (Gen.char_range '\x00' '\xff')

(* Directive-shaped sources with adversarial payloads: [%S] embeds any
   payload bytes as a valid literal, so the source always parses and the
   payload grammar — not the OCaml lexer — is what the bytes exercise. *)
let gen_directive_source =
  let open Gen in
  let* payload = string_of ~size:(int_range 0 64) (char_range '\x00' '\xff') in
  let+ form = of_list [ `Attached; `Item; `Floating ]
  and+ kind = of_list [ "allow"; "expect"; "alow" ] in
  match form with
  | `Attached -> Printf.sprintf "let a = (1 [@litany.%s %S])" kind payload
  | `Item -> Printf.sprintf "let a = 1 [@@litany.%s %S]\nlet b = 2" kind payload
  | `Floating ->
      Printf.sprintf "let a = 1\n[@@@litany.%s %S]\nlet b = 2" kind payload

let in_bounds ~len sp =
  is_true ~msg:"start >= 0" (Span.start sp >= 0);
  is_true ~msg:"stop >= start" (Span.stop sp >= Span.start sp);
  is_true ~msg:"stop <= length" (Span.stop sp <= len)

let check_policy_spans src =
  match
    Sup.of_structure ~source_length:(String.length src)
      (Parse.implementation (Lexing.from_string src))
  with
  | exception (Syntaxerr.Error _ | Lexer.Error _) -> ()
  | p ->
      let len = String.length src in
      List.iter
        (fun d ->
          in_bounds ~len (D.span d);
          in_bounds ~len (D.scope d);
          in_bounds ~len (D.deletion ~source:src d))
        (Sup.directives p);
      List.iter (fun m -> in_bounds ~len (M.span m)) (Sup.malformed p)

(* A directive's observable shape, for the determinism comparison. *)
let directive_repr d =
  ( (match D.kind d with D.Allow -> "allow" | D.Expect -> "expect"),
    D.rule d,
    D.reason d,
    (Span.start (D.span d), Span.stop (D.span d)),
    (Span.start (D.scope d), Span.stop (D.scope d)) )

let malformed_repr m =
  (M.message m, (Span.start (M.span m), Span.stop (M.span m)))

let opaque name =
  Testable.make ~pp:(fun ppf _ -> Format.pp_print_string ppf name) ~equal:( = )

(* The mli's definition of [spelled], written independently: both needles as
   substrings. *)
let naive_spelled src =
  let holds needle =
    let n = String.length src and m = String.length needle in
    let rec at i = i + m <= n && (String.sub src i m = needle || at (i + 1)) in
    at 0
  in
  holds "[@" && holds "litany"

let property_tests =
  group "fuzz"
    [
      prop "the demand scan is total and agrees with the substring oracle"
        gen_bytes (fun src -> equal bool (naive_spelled src) (Sup.spelled src));
      prop
        "policy compilation is total and every span is in bounds over random \
         bytes"
        gen_bytes check_policy_spans;
      prop
        "directive-shaped sources: spans in bounds, compilation deterministic"
        gen_directive_source (fun src ->
          check_policy_spans src;
          let compile () =
            Sup.of_structure ~source_length:(String.length src)
              (Parse.implementation (Lexing.from_string src))
          in
          let a = compile () and b = compile () in
          equal
            (list (opaque "<directive>"))
            (List.map directive_repr (Sup.directives a))
            (List.map directive_repr (Sup.directives b));
          equal
            (list (opaque "<malformed>"))
            (List.map malformed_repr (Sup.malformed a))
            (List.map malformed_repr (Sup.malformed b)));
    ]

let () =
  run "litany_suppress"
    [ payload_tests; scope_tests; scan_tests; deletion_tests; property_tests ]
