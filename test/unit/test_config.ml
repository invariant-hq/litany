(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Config = Litany.Config_file
module Sexp = Litany.Config_file.Sexp
module Glob = Litany.Config_file.Glob
module Error = Litany.Config_file.Error

let ok src =
  match Config.parse src with
  | Ok t -> t
  | Error e -> failf "unexpected config error: %s" (Error.to_string e)

let err src =
  match Config.parse src with
  | Ok _ -> fail "expected a config error"
  | Error e -> Error.to_string e

let err_names ?(selection = []) ?(rules = []) src =
  match Config.check_names (ok src) ~selection ~rules with
  | Ok () -> fail "expected a name error"
  | Error e -> Error.to_string e

let values atoms = List.map (fun (a : Config.atom) -> a.value) atoms

let glob s =
  match Glob.of_string s with
  | Ok g -> g
  | Error why -> failf "glob %S refused: %s" s why

let glob_err s =
  match Glob.of_string s with
  | Ok _ -> fail "expected a glob error"
  | Error why -> why

let golden name src expected =
  test name (fun () -> equal string expected (err src))

(* {1 Reading} *)

let full_example =
  String.concat "\n"
    [
      "(lint";
      " (select default)";
      " (extend style unused-export)";
      " (ignore manual-eta-lambda)";
      " (closed-world false))";
      "";
      "(rule line-length";
      " (max 100))";
      "";
      "(per-path";
      " (paths vendor/**)";
      " (ignore all)";
      " (reason \"vendored code\"))";
      "";
    ]

let reading_tests =
  group "reading"
    [
      test "an empty file is the zero configuration" (fun () ->
          let t = ok "" in
          equal int 1 (Config.version t);
          equal (list string) [] (values (Config.select t));
          equal (list string) [] (values (Config.extend t));
          equal (list string) [] (values (Config.ignored t));
          is_false (Config.closed_world t);
          equal int 0 (List.length (Config.rules t));
          equal int 0 (List.length (Config.per_paths t)));
      test "empty equals the zero-configuration default" (fun () ->
          equal int (Config.version Config.empty) (Config.version (ok ""));
          equal (list string)
            (values (Config.select Config.empty))
            (values (Config.select (ok ""))));
      test "comments and blank lines alone are a clean file" (fun () ->
          let t = ok "; a comment\n\n  ; another\n" in
          equal int 0 (List.length (Config.rules t)));
      test "the full example parses whole" (fun () ->
          let t = ok full_example in
          equal (list string) [ "default" ] (values (Config.select t));
          equal (list string)
            [ "style"; "unused-export" ]
            (values (Config.extend t));
          equal (list string) [ "manual-eta-lambda" ]
            (values (Config.ignored t));
          is_false (Config.closed_world t);
          (match Config.rules t with
          | [ r ] ->
              equal string "line-length" (Config.Rule_options.name r).value;
              equal int 1 (List.length (Config.Rule_options.options r))
          | _ -> fail "expected one (rule ...) form");
          match Config.per_paths t with
          | [ p ] ->
              equal (list string) [ "vendor/**" ]
                (List.map
                   (fun (_, g) -> Glob.to_string g)
                   (Config.Per_path.globs p));
              equal (list string) [ "all" ] (values (Config.Per_path.ignored p));
              equal (option string) (Some "vendored code")
                (Config.Per_path.reason p)
          | _ -> fail "expected one (per-path ...) form");
      test "the version header is read and must be 1" (fun () ->
          let t = ok "(litany-config 1)\n(lint (closed-world true))" in
          equal int 1 (Config.version t);
          is_true (Config.closed_world t));
      test "an empty (lint) form is legal" (fun () ->
          let t = ok "(lint)" in
          equal (list string) [] (values (Config.select t)));
      test "quoted and bare atoms are equivalent" (fun () ->
          let t = ok "(lint (select \"default\" all))" in
          equal (list string) [ "default"; "all" ] (values (Config.select t)));
      test "string escapes unescape in reasons" (fun () ->
          let t =
            ok "(per-path (paths v) (ignore all) (reason \"a\\\"b\\n\\t\\\\\"))"
          in
          match Config.per_paths t with
          | [ p ] ->
              equal (option string) (Some "a\"b\n\t\\")
                (Config.Per_path.reason p)
          | _ -> fail "expected one (per-path ...) form");
      test "per-path forms repeat in file order" (fun () ->
          let t =
            ok
              "(per-path (paths a) (ignore all))\n\
               (per-path (paths b) (ignore all))"
          in
          equal (list string) [ "a"; "b" ]
            (List.map
               (fun p ->
                 Glob.to_string (snd (List.hd (Config.Per_path.globs p))))
               (Config.per_paths t)));
      test "Per_path.matches consults every glob" (fun () ->
          let t = ok "(per-path (paths vendor/** gen/*.ml) (ignore all))" in
          match Config.per_paths t with
          | [ p ] ->
              is_true (Config.Per_path.matches p "vendor/x.ml");
              is_true (Config.Per_path.matches p "gen/x.ml");
              is_false (Config.Per_path.matches p "src/x.ml")
          | _ -> fail "expected one (per-path ...) form");
      test "CRLF line ends are whitespace" (fun () ->
          let t = ok "(lint\r\n (select all))" in
          equal (list string) [ "all" ] (values (Config.select t)));
    ]

(* {1 Positions} *)

let position_tests =
  group "positions"
    [
      test "selection tokens carry their line and column" (fun () ->
          match Config.select (ok "(lint (select default))") with
          | [ a ] ->
              equal string "default" a.value;
              equal int 1 a.line;
              equal int 15 a.col
          | _ -> fail "expected one token");
      test "rule options are opaque positioned sexps" (fun () ->
          match Config.rules (ok "(rule x (max 100))") with
          | [ r ] -> (
              equal string "x" (Config.Rule_options.name r).value;
              equal int 7 (Config.Rule_options.name r).col;
              match Config.Rule_options.options r with
              | [ { Sexp.desc = Sexp.List [ m; v ]; line; col } ] -> (
                  equal int 1 line;
                  equal int 9 col;
                  match (m.Sexp.desc, v.Sexp.desc) with
                  | Sexp.Atom "max", Sexp.Atom "100" ->
                      equal int 10 m.Sexp.col;
                      equal int 14 v.Sexp.col
                  | _ -> fail "unexpected option atoms")
              | _ -> fail "expected one (max 100) option")
          | _ -> fail "expected one rule");
      test "error accessors expose position and message" (fun () ->
          match Config.parse "(linr)" with
          | Ok _ -> fail "expected an error"
          | Error e ->
              equal int 1 (Error.line e);
              equal int 2 (Error.column e);
              equal string "unknown form \"linr\" (did you mean \"lint\"?)"
                (Error.message e);
              equal string
                "conf/litany:1:2: unknown form \"linr\" (did you mean \
                 \"lint\"?)"
                (Error.to_string ~file:"conf/litany" e));
    ]

(* {1 Error goldens — every message the domain can produce} *)

let lexer_goldens =
  group "errors: lexing"
    [
      golden "unterminated string" "\"abc" "litany:1:1: unterminated string";
      golden "escape then EOF is unterminated" "\"a\\"
        "litany:1:1: unterminated string";
      golden "unknown escape" "\"x\\qy\""
        "litany:1:3: unknown escape \"\\q\" in string";
      golden "unmatched closing paren" ")" "litany:1:1: unmatched \")\"";
      golden "unclosed paren points at its opening" "(lint"
        "litany:1:1: unclosed \"(\"";
      golden "unclosed nested paren points at the innermost" "(lint (select"
        "litany:1:7: unclosed \"(\"";
    ]

let form_goldens =
  group "errors: forms"
    [
      golden "a bare atom is not a form" "check"
        "litany:1:1: expected a (...) form";
      golden "an empty list has no form name" "()"
        "litany:1:1: expected a form name";
      golden "a list-headed list has no form name" "((select))"
        "litany:1:1: expected a form name";
      golden "unknown form with a suggestion" "(linr)"
        "litany:1:2: unknown form \"linr\" (did you mean \"lint\"?)";
      golden "unknown form near per-path" "(pre-path)"
        "litany:1:2: unknown form \"pre-path\" (did you mean \"per-path\"?)";
      golden "unknown form without a suggestion" "(wibble)"
        "litany:1:2: unknown form \"wibble\"";
      golden "comments do not disturb positions" "; c\n(linr)"
        "litany:2:2: unknown form \"linr\" (did you mean \"lint\"?)";
      golden "a tab is one byte column" "\t(linr)"
        "litany:1:3: unknown form \"linr\" (did you mean \"lint\"?)";
    ]

let header_goldens =
  group "errors: header"
    [
      golden "the header must come first" "(lint)\n(litany-config 1)"
        "litany:2:2: (litany-config ...) must be the first form";
      golden "a second header is not first either"
        "(litany-config 1)\n(litany-config 1)"
        "litany:2:2: (litany-config ...) must be the first form";
      golden "the header takes one version" "(litany-config)"
        "litany:1:2: (litany-config ...) expects one integer version";
      golden "the version is an integer" "(litany-config one)"
        "litany:1:2: (litany-config ...) expects one integer version";
      golden "the header takes exactly one version" "(litany-config 1 2)"
        "litany:1:2: (litany-config ...) expects one integer version";
      golden "an absurd version count is refused"
        "(litany-config 99999999999999999999)"
        "litany:1:2: (litany-config ...) expects one integer version";
      golden "a future version is refused" "(litany-config 2)"
        "litany:1:16: unsupported config version 2 (this litany reads version \
         1)";
    ]

let lint_goldens =
  group "errors: lint"
    [
      golden "duplicate (lint) form" "(lint)\n(lint)"
        "litany:2:2: duplicate (lint ...) form";
      golden "unknown key with a suggestion"
        "(lint\n (select default)\n (selct x))"
        "litany:3:3: unknown key \"selct\" in (lint ...) (did you mean \
         \"select\"?)";
      golden "unknown key without a suggestion" "(lint (zzz))"
        "litany:1:8: unknown key \"zzz\" in (lint ...)";
      golden "duplicate key" "(lint (select a) (select b))"
        "litany:1:19: duplicate key \"select\" in (lint ...)";
      golden "duplicate closed-world"
        "(lint (closed-world true) (closed-world false))"
        "litany:1:28: duplicate key \"closed-world\" in (lint ...)";
      golden "bare items are refused" "(lint foo)"
        "litany:1:7: expected a (key ...) form in (lint ...)";
      golden "selection tokens are atoms" "(lint (select (foo)))"
        "litany:1:15: expected a rule or group name";
      golden "closed-world wants a boolean" "(lint (closed-world maybe))"
        "litany:1:8: (closed-world ...) expects true or false";
      golden "closed-world wants exactly one boolean" "(lint (closed-world))"
        "litany:1:8: (closed-world ...) expects true or false";
    ]

let rule_goldens =
  group "errors: rule"
    [
      golden "a rule form needs a name" "(rule)"
        "litany:1:2: (rule ...) expects a rule name";
      golden "a rule name is an atom" "(rule (max 100))"
        "litany:1:7: (rule ...) expects a rule name";
      golden "one options form per rule" "(rule x)\n(rule x)"
        "litany:2:7: duplicate (rule \"x\") form";
    ]

let per_path_goldens =
  group "errors: per-path"
    [
      golden "unknown key with a suggestion"
        "(per-path (path vendor/**) (ignore all))"
        "litany:1:12: unknown key \"path\" in (per-path ...) (did you mean \
         \"paths\"?)";
      golden "bare items are refused" "(per-path foo)"
        "litany:1:11: expected a (key ...) form in (per-path ...)";
      golden "duplicate key" "(per-path (paths a) (paths b) (ignore all))"
        "litany:1:22: duplicate key \"paths\" in (per-path ...)";
      golden "paths is required" "(per-path (ignore all))"
        "litany:1:2: (per-path ...) requires (paths ...)";
      golden "ignore is required" "(per-path (paths vendor/**))"
        "litany:1:2: (per-path ...) requires (ignore ...)";
      golden "paths wants at least one glob" "(per-path (paths) (ignore all))"
        "litany:1:12: (paths ...) expects at least one glob";
      golden "ignore wants at least one token" "(per-path (paths v) (ignore))"
        "litany:1:22: (ignore ...) expects at least one rule or group name";
      golden "globs are atoms" "(per-path (paths (a)) (ignore all))"
        "litany:1:18: expected a glob";
      golden "ignore tokens are atoms" "(per-path (paths a) (ignore (x)))"
        "litany:1:29: expected a rule or group name";
      golden "reason wants one string"
        "(per-path (paths v) (ignore all) (reason))"
        "litany:1:35: (reason ...) expects one string";
      golden "reason wants exactly one string"
        "(per-path (paths v) (ignore all) (reason a b))"
        "litany:1:35: (reason ...) expects one string";
    ]

let glob_goldens =
  let bad g = "(per-path (paths " ^ g ^ ") (ignore all))" in
  group "errors: globs"
    [
      golden "empty glob" (bad "\"\"")
        "litany:1:18: invalid glob \"\": empty glob";
      golden "absolute glob" (bad "/a")
        "litany:1:18: invalid glob \"/a\": absolute glob";
      golden "trailing slash" (bad "a/")
        "litany:1:18: invalid glob \"a/\": trailing '/'";
      golden "empty component" (bad "a//b")
        "litany:1:18: invalid glob \"a//b\": empty component";
      golden "dot component" (bad ".")
        "litany:1:18: invalid glob \".\": '.' component";
      golden "dotdot component" (bad "a/../b")
        "litany:1:18: invalid glob \"a/../b\": '..' component";
      golden "backslash" (bad "a\\b")
        "litany:1:18: invalid glob \"a\\\\b\": backslash";
      golden "NUL byte" (bad "a\000b")
        "litany:1:18: invalid glob \"a\\000b\": NUL byte";
      golden "triple star" (bad "***")
        "litany:1:18: invalid glob \"***\": '**' must be a whole component";
      golden "embedded doublestar" (bad "a**b")
        "litany:1:18: invalid glob \"a**b\": '**' must be a whole component";
      golden "adjacent doublestars" (bad "**/**")
        "litany:1:18: invalid glob \"**/**\": adjacent '**' components";
    ]

let check_names_tests =
  let selection = [ "all"; "default"; "nursery"; "style"; "line-length" ] in
  let rules = [ "line-length" ] in
  group "check-names"
    [
      test "a valid configuration checks clean" (fun () ->
          match
            Config.check_names (ok full_example)
              ~selection:
                [
                  "all";
                  "default";
                  "style";
                  "unused-export";
                  "manual-eta-lambda";
                ]
              ~rules:[ "line-length" ]
          with
          | Ok () -> ()
          | Error e -> failf "unexpected error: %s" (Error.to_string e));
      test "unknown selection token, with a suggestion" (fun () ->
          equal string
            "litany:1:15: unknown rule or group \"styel\" (did you mean \
             \"style\"?)"
            (err_names ~selection ~rules "(lint (select styel))"));
      test "unknown selection token, without a suggestion" (fun () ->
          equal string "litany:1:15: unknown rule or group \"zzzzzz\""
            (err_names ~selection ~rules "(lint (ignore zzzzzz))"));
      test "extend is checked too" (fun () ->
          equal string
            "litany:1:15: unknown rule or group \"styel\" (did you mean \
             \"style\"?)"
            (err_names ~selection ~rules "(lint (extend styel))"));
      test "per-path ignore tokens are checked" (fun () ->
          equal string
            "litany:1:29: unknown rule or group \"styel\" (did you mean \
             \"style\"?)"
            (err_names ~selection ~rules "(per-path (paths v) (ignore styel))"));
      test "rule heads are checked against the rule vocabulary" (fun () ->
          equal string
            "litany:1:7: unknown rule \"lin-length\" (did you mean \
             \"line-length\"?)"
            (err_names ~selection ~rules "(rule lin-length (max 100))"));
    ]

(* {1 Glob semantics} *)

let glob_matching_tests =
  group "glob matching"
    [
      test "a final ** wants one or more components" (fun () ->
          let g = glob "vendor/**" in
          is_true (Glob.matches g "vendor/x.ml");
          is_true (Glob.matches g "vendor/a/x.ml");
          is_false (Glob.matches g "vendor");
          is_false (Glob.matches g "avendor/x.ml"));
      test "a non-final ** spans zero or more components" (fun () ->
          let g = glob "a/**/b.ml" in
          is_true (Glob.matches g "a/b.ml");
          is_true (Glob.matches g "a/x/b.ml");
          is_true (Glob.matches g "a/x/y/b.ml");
          is_false (Glob.matches g "a/b.mlx"));
      test "** alone matches everything" (fun () ->
          let g = glob "**" in
          is_true (Glob.matches g "a");
          is_true (Glob.matches g "a/b/c"));
      test "* stays within one component" (fun () ->
          let g = glob "src/*.ml" in
          is_true (Glob.matches g "src/a.ml");
          is_true (Glob.matches g "src/.ml");
          is_false (Glob.matches g "src/a/b.ml");
          is_false (Glob.matches g "a.ml"));
      test "? matches exactly one byte" (fun () ->
          let g = glob "a?c" in
          is_true (Glob.matches g "abc");
          is_false (Glob.matches g "ac");
          is_false (Glob.matches g "abbc"));
      test "matching is anchored, both ends" (fun () ->
          let g = glob "b.ml" in
          is_false (Glob.matches g "a/b.ml");
          is_true (Glob.matches g "b.ml"));
      test "matching is case-sensitive bytes" (fun () ->
          is_false (Glob.matches (glob "A.ml") "a.ml"));
      test "a dot is an ordinary byte" (fun () ->
          is_true (Glob.matches (glob "*") ".hidden"));
      test "non-canonical candidate paths are refused" (fun () ->
          let g = glob "a" in
          List.iter
            (fun path ->
              raises_match (Exn.invalid_arg ~substring:"non-canonical")
                (fun () -> Glob.matches g path))
            [ ""; "/a"; "a/"; "a//b"; "a/./b"; "a/../b"; "a\000b" ]);
      test "of_string reasons stand alone" (fun () ->
          equal string "empty glob" (glob_err "");
          equal string "'**' must be a whole component" (glob_err "x/y**"));
      test "to_string is the spelling" (fun () ->
          equal string "a/**/b.ml" (Glob.to_string (glob "a/**/b.ml")));
    ]

(* {1 Properties} *)

let gen_component = Gen.(string_of ~size:(int_range 1 6) (char_range 'a' 'z'))

let gen_path =
  Gen.(
    let+ first = gen_component
    and+ rest = list ~size:(int_range 0 3) gen_component in
    String.concat "/" (first :: rest))

let property_tests =
  group "properties"
    [
      prop "parse is total and errors are positioned" Gen.string (fun s ->
          match Config.parse s with
          | Ok _ -> ()
          | Error e ->
              is_true (Error.line e >= 1);
              is_true (Error.column e >= 1));
      prop "a literal glob matches its own path and nothing longer" gen_path
        (fun path ->
          match Glob.of_string path with
          | Error _ -> ()
          | Ok g ->
              is_true (Glob.matches g path);
              is_false (Glob.matches g (path ^ "x"));
              is_false (Glob.matches g ("x" ^ path)));
      prop "of_string preserves the spelling" gen_path (fun path ->
          match Glob.of_string path with
          | Error _ -> ()
          | Ok g -> equal string path (Glob.to_string g));
      prop "a final ** matches any tail and never the base alone"
        Gen.(pair gen_path gen_path)
        (fun (base, tail) ->
          match (Glob.of_string base, Glob.of_string tail) with
          | Ok _, Ok _ -> (
              match Glob.of_string (base ^ "/**") with
              | Error why -> fail why
              | Ok g ->
                  is_true (Glob.matches g (base ^ "/" ^ tail));
                  is_false (Glob.matches g base))
          | _ -> ());
      prop "a leading ** spans zero or more components"
        Gen.(pair gen_component (list ~size:(int_range 0 3) gen_component))
        (fun (last, middle) ->
          if last = "" || List.mem "" middle then ()
          else
            match Glob.of_string ("**/" ^ last) with
            | Error why -> fail why
            | Ok g ->
                is_true (Glob.matches g (String.concat "/" (middle @ [ last ]))));
      prop "* spans exactly one whole component" gen_component (fun c ->
          if c = "" then ()
          else begin
            let g = glob "*" in
            is_true (Glob.matches g c);
            is_false (Glob.matches g (c ^ "/" ^ c))
          end);
      prop "? matches byte for byte" gen_component (fun c ->
          if c = "" then ()
          else begin
            let g = glob (String.make (String.length c) '?') in
            is_true (Glob.matches g c);
            is_false (Glob.matches g (c ^ "a"))
          end);
      prop "select tokens round-trip with exact columns"
        Gen.(list ~size:(int_range 0 4) gen_component)
        (fun tokens ->
          if List.mem "" tokens then ()
          else
            let src =
              "(lint (select"
              ^ String.concat "" (List.map (fun t -> " " ^ t) tokens)
              ^ "))"
            in
            let atoms = Config.select (ok src) in
            equal (list string) tokens (values atoms);
            List.iter
              (fun (a : Config.atom) ->
                equal int 1 a.line;
                equal string a.value
                  (String.sub src (a.col - 1) (String.length a.value)))
              atoms);
    ]

let () =
  Windtrap.run "litany_config"
    [
      reading_tests;
      position_tests;
      lexer_goldens;
      form_goldens;
      header_goldens;
      lint_goldens;
      rule_goldens;
      per_path_goldens;
      glob_goldens;
      check_names_tests;
      glob_matching_tests;
      property_tests;
    ]
