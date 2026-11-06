(*---------------------------------------------------------------------------
   Copyright (c) 2026 Hypha Technologies Ltd.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

open Windtrap
module Rule = Litany.Rule
module Support = Rules_test_support

let rule = Litany_rules.Wildcard_over_owned_variant.rule
let source = "fixtures/fix_wov_cases.ml"
let cmt = "fixtures/.fix_wov.objs/byte/fix_wov__Fix_wov_cases.cmt"
let atom s = { Litany.Sexp.desc = Litany.Sexp.Atom s; line = 1; col = 1 }
let form xs = { Litany.Sexp.desc = Litany.Sexp.List xs; line = 1; col = 1 }

let configured payload =
  match Rule.configure rule payload with
  | Ok r -> r
  | Error e -> failf "schema refused: %s" (Rule.Options.to_string e)

let refused payload =
  match Rule.configure rule payload with
  | Ok _ -> fail "schema accepted; expected a refusal"
  | Error e -> e.Rule.Options.message

(* The 1-based line of a byte offset into the fixture. *)
let line_of offset =
  let text = In_channel.with_open_bin source In_channel.input_all in
  let n = ref 1 in
  String.iteri (fun i c -> if i < offset && Char.equal c '\n' then incr n) text;
  !n

(* The 1-based line of the fixture holding [sub]. *)
let line_containing sub =
  let rec find n = function
    | [] -> failf "no line of the fixture holds %S" sub
    | l :: rest ->
        let k = String.length sub in
        let rec at i =
          i + k <= String.length l
          && (String.equal (String.sub l i k) sub || at (i + 1))
        in
        if at 0 then n else find (n + 1) rest
  in
  find 1
    (String.split_on_char '\n'
       (In_channel.with_open_bin source In_channel.input_all))

let lines r =
  List.map
    (fun (_, _, start, _) -> line_of start)
    (Support.shape (Support.report r ~source ~cmt))

let () =
  Windtrap.run "wildcard-over-owned-variant"
    [
      test "declares its one metadata record" (fun () ->
          equal string "wildcard-over-owned-variant" (Rule.name rule);
          is_true ~msg:"group is Restriction"
            (Rule.group rule = Rule.Restriction);
          is_true ~msg:"nursery" (Rule.stability rule = Rule.Stability.Nursery);
          is_true ~msg:"fix promise is Never" (Rule.fix rule = Rule.Never);
          is_true ~msg:"local rule" (not (Rule.is_project rule));
          equal string "1.1" (Rule.since rule));
      test "fires exactly on the marked wildcard arms" (fun () ->
          Support.check_markers rule ~source ~cmt);
      test "a library the option names is owned too" (fun () ->
          let owning =
            configured [ form [ atom "owned"; atom "fix_wov_other" ] ]
          in
          let other =
            List.filter
              (fun l -> not (List.mem l (Support.fire_lines ~source)))
              (lines owning)
          in
          equal (list int) ~msg:"other_library's wildcards fire, aliased too"
            [
              line_containing "match c with Red";
              line_containing "match c with Aliased_other.Red";
            ]
            other);
      test "the schema refuses what it cannot read" (fun () ->
          is_true ~msg:"empty owned"
            (String.length (refused [ form [ atom "owned" ] ]) > 0);
          is_true ~msg:"owned twice"
            (String.length
               (refused [ form [ atom "owned"; atom "a"; atom "a" ] ])
            > 0);
          is_true ~msg:"unknown option"
            (String.length (refused [ form [ atom "own"; atom "a" ] ]) > 0));
    ]
