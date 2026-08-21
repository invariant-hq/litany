(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(* The one report page, for humans and for dune alike. Every finding is
   an ocamlc-shaped block — the [File "…", line L, characters A-B:] header,
   the quoted line with carets, the [Warning 0 [<rule>]: …] line — in the
   exact grammar dune's vendored ocamlc-loc lexer accepts, so a failing
   dune action's output lands as diagnostics and reaches editors over RPC
   while a terminal reads the same bytes in full. The grammar is
   unforgiving: one wrong byte does not lose one finding in dune's parser,
   it truncates every finding after it, so the helpers below are
   defensive about the fatal shapes (a header-shaped message line, a
   caret line without a quoted line before it) and the whole page is
   built in a buffer and handed to the formatter in one piece —
   deterministic bytes, no pretty-printing engine in the way. *)

(* A message line that itself parses as a [File "…", line N…] header forges
   structure: flush left it truncates the rest of the stream, indented it
   becomes a bogus related entry. Neutralize by doubling the space after
   [File] — the lexer requires the literal [File "], so [File  "] no longer
   matches, and the text stays legible. The check mirrors the lexer's token
   rule prefix: optional blanks, [File "<path>", ] then [line]/[lines] and a
   digit. *)
let defuse_header_forgery line =
  let n = String.length line in
  let skip_blanks i =
    let i = ref i in
    while !i < n && (line.[!i] = ' ' || line.[!i] = '\t') do
      incr i
    done;
    !i
  in
  let has_prefix p i =
    let l = String.length p in
    i + l <= n && String.sub line i l = p
  in
  let start = skip_blanks 0 in
  let forged =
    has_prefix "File \"" start
    &&
    match String.index_from_opt line (start + 6) '"' with
    | None -> false
    | Some q -> (
        has_prefix "\", " q
        &&
        let i = skip_blanks (q + 3) in
        let i =
          if has_prefix "lines " i then Some (i + 6)
          else if has_prefix "line " i then Some (i + 5)
          else None
        in
        match i with
        | Some i -> i < n && line.[i] >= '0' && line.[i] <= '9'
        | None -> false)
  in
  if forged then
    String.sub line 0 (start + 4)
    ^ "  "
    ^ String.sub line (start + 5) (n - start - 5)
  else line

let text ?(color = false) ?(fixes = `Hint) ?(notes_detail = false)
    ~source_of_path ppf rep =
  (* One dial, two derived views: the hint and the applied count cannot
     contradict each other (advising a fix run that already ran). The
     proposed flavor is the corrections lane's — fixes became dune
     corrections, not source writes, and the page must not claim a write
     the tree never saw. *)
  let fix_hint =
    match fixes with `Hint -> true | `Applied _ | `Proposed _ -> false
  in
  let fixes_applied =
    match fixes with
    | `Hint -> None
    | `Applied n -> Some (n, "applied")
    | `Proposed n -> Some (n, "proposed")
  in
  let buf = Buffer.create 1024 in
  let add fmt =
    Printf.ksprintf
      (fun s ->
        Buffer.add_string buf s;
        Buffer.add_char buf '\n')
      fmt
  in
  let sev_color = function
    | Rule.Severity.Error -> "31"
    | Rule.Severity.Warning -> "33"
  in
  (* Styling touches the severity word and the carets only. The [File]
     header stays plain even on a terminal: the lexer's header rule
     admits nothing but blanks before the [File "…"] literal, so a styled
     header is a lost finding — dune strips ANSI before parsing, but the
     contract is pinned against the vendored lexer, not against dune's
     leniency. *)
  let paint code s =
    if color then Printf.sprintf "\027[%sm%s\027[0m" code s else s
  in
  (* No excerpt at all in an offsets-degraded unit: corroboration was waived
     there, so a typed finding's offsets may count preprocessed bytes, and
     [consistent] against the editable bytes is only a coincidence test —
     an excerpt would confidently witness bytes the finding never touched.
     Location and message still render. The gate keys on the degradation's
     claim: a resolution-degraded unit's offsets are fully verified, so its
     excerpts stand. *)
  let excerpt_trusted =
    let offsets_degraded =
      List.filter_map
        (function
          | path, Engine.Report.Offsets -> Some path
          | _, Engine.Report.Resolution _ -> None)
        (Engine.Report.degradations rep)
    in
    fun fname -> not (List.mem fname offsets_degraded)
  in
  (* Continuation lines carry a fixed two-space indent — blank ones too, so
     the parser's min-indent normalization keeps deeper relative indents
     intact — and every one is defused. *)
  let add_continuation lines =
    List.iter (fun l -> add "  %s" (defuse_header_forgery l)) lines
  in
  let first_finding = ref true in
  Engine.Report.iter_findings rep (fun ~rule ~severity f ->
      (* One visually blank line between finding blocks, so a reader can
         see where one diagnostic ends and the next begins. The lexer has
         no terminator but the next header, so the separator folds into
         the previous finding's message as a continuation — it therefore
         carries the fixed two-space indent every continuation line does,
         keeping the parser's min-indent normalization intact (a
         zero-indent blank would drag the minimum to zero and un-indent
         every message line). Pinned by the grammar suite. *)
      if !first_finding then first_finding := false else add "  ";
      let loc = Finding.loc f in
      let p = loc.Location.loc_start and q = loc.Location.loc_end in
      (* Header: [File "<path>", line L, characters A-B:] — [lines L-M] for
         a multi-line span. Columns are the compiler's own convention,
         0-based [pos_cnum - pos_bol], end-exclusive, emitted verbatim:
         dune's [Compound_user_error.make_loc] copies the numbers into the
         diagnostic with no adjustment. The path goes out raw — [%s], not
         [%S] — because the lexer's path charset is any byte but
         double-quote and newline, and escaping would change the bytes
         editors jump to. *)
      let a = p.pos_cnum - p.pos_bol and b = q.pos_cnum - q.pos_bol in
      if p.pos_lnum = q.pos_lnum then
        add "File \"%s\", line %d, characters %d-%d:" p.pos_fname p.pos_lnum a b
      else
        add "File \"%s\", lines %d-%d, characters %d-%d:" p.pos_fname p.pos_lnum
          q.pos_lnum a b;
      (* The excerpt sits between the header and the severity line, where
         the lexer expects ocamlc's own: a [N | <line>] row, then carets
         under the span as blanks and [^] alone — a bar on the caret row
         would end the stream. *)
      (match
         if excerpt_trusted p.pos_fname then source_of_path p.pos_fname
         else None
       with
      | None -> ()
      | Some src -> (
          match Source.line src p.pos_lnum with
          | None -> ()
          | Some sp ->
              let line = Option.value (Source.slice src sp) ~default:"" in
              let gutter = Printf.sprintf "%d | " p.pos_lnum in
              add "%s%s" gutter line;
              (* Carets only when the offsets can be trusted against these
                 bytes; line-anchored findings quote the line alone. *)
              if
                Source.consistent src p && Source.consistent src q
                && p.pos_cnum <= q.pos_cnum
              then
                let lead = p.pos_cnum - Span.start sp in
                let stop = min q.pos_cnum (Span.stop sp) in
                let count = max 1 (stop - p.pos_cnum) in
                add "%s%s"
                  (String.make (String.length gutter + lead) ' ')
                  (paint (sev_color severity) (String.make count '^'))));
      (* Warnings keep structured rule identity in the bracketed code;
         errors repeat it in the message text because dune's
         [Compound_user_error] discards the structured code on the error
         form before editors see it. The first message line rides the
         severity line after the colon, where it cannot be line-initial,
         so it is not defused. *)
      let message =
        match severity with
        | Rule.Severity.Warning -> Finding.message f
        | Rule.Severity.Error -> Finding.message f ^ " [" ^ rule ^ "]"
      in
      let first, rest =
        match String.split_on_char '\n' message with
        | [] -> ("", [])
        | first :: rest -> (first, rest)
      in
      let first = if first = "" then "" else " " ^ first in
      (match severity with
      | Rule.Severity.Warning ->
          add "%s 0 [%s]:%s" (paint (sev_color severity) "Warning") rule first
      | Rule.Severity.Error ->
          add "%s:%s" (paint (sev_color severity) "Error") first);
      add_continuation rest;
      (* The fix promise is one more continuation line — [fix
         (<applicability>): <title>]: a safe fix's line says what [--fix]
         will apply, an unsafe fix's line is the suggestion it only applies
         under [--unsafe]. The parser folds it into the finding's message,
         so editors show it with the diagnostic. *)
      match Finding.fix f with
      | None -> ()
      | Some fx ->
          add_continuation
            (String.split_on_char '\n'
               (Printf.sprintf "fix (%s): %s"
                  (Fix.applicability_to_string (Fix.applicability fx))
                  (Fix.title fx))));
  (* The one aggregation: the counts printed here are the same [Summary] the
     json trailer serializes, so the human page and the machine channel
     cannot disagree on the truth set. *)
  let s = Engine.Summary.of_report rep in
  if s.findings > 0 then Buffer.add_char buf '\n';
  let word n w = if n = 1 then w else w ^ "s" in
  let fixable =
    if s.fixable = 0 then ""
    else if fix_hint then
      Printf.sprintf " (%d fixable — run `litany check --fix`)" s.fixable
    else Printf.sprintf " (%d fixable)" s.fixable
  in
  let by_reason =
    match s.skipped_by_reason with
    | [] -> ""
    | counts ->
        " ("
        ^ String.concat ", "
            (List.map (fun (slug, n) -> Printf.sprintf "%s %d" slug n) counts)
        ^ ")"
  in
  let facts_only =
    if s.facts_only > 0 then Printf.sprintf " · %d facts-only" s.facts_only
    else ""
  in
  let dropped =
    match s.dropped with 0 -> "" | n -> Printf.sprintf " · %d dropped" n
  in
  let degraded =
    match s.degraded with 0 -> "" | n -> Printf.sprintf " · %d degraded" n
  in
  let suppressed =
    match s.suppressed with 0 -> "" | n -> Printf.sprintf " · %d suppressed" n
  in
  (* The selection denominator opens the line: "0 findings" means nothing
     without how many rules looked; degraded is counted here and
     itemized below — reduced guarantees never hide in exit 0. *)
  let applied =
    match fixes_applied with
    | None -> ""
    | Some (n, verb) ->
        Printf.sprintf " · %d %s %s" n (if n = 1 then "fix" else "fixes") verb
  in
  add "%d %s selected · %d %s · %d %s%s%s · %d skipped%s%s%s%s%s"
    s.rules_selected
    (word s.rules_selected "rule")
    s.units (word s.units "unit") s.findings
    (word s.findings "finding")
    fixable applied s.skipped by_reason facts_only dropped degraded suppressed;
  (* The roster lines derive from the per-rule disposition algebra. The
     run-level blocks — not-capable, incomplete, ambiguous — hold for every
     rule identically, so they print once; a collect failure blocks one rule
     alone and prints per rule (its failure row also prints below). *)
  (match
     List.filter_map
       (fun (rule, block) -> Option.map (fun b -> (rule, b)) block)
       (Engine.Report.project_rules rep)
   with
  | [] -> ()
  | (_, Engine.Report.Not_capable) :: _ ->
      add "roster: none (project rules unavailable)"
  | (_, Engine.Report.Incomplete blocking) :: _ ->
      add "roster: project rules withheld (%s)"
        (String.concat "; "
           (List.map
              (fun (path, sk) ->
                Printf.sprintf "%s: %s" path (Unit.Skip.message sk))
              blocking))
  | (_, Engine.Report.Ambiguous dups) :: _ ->
      add "roster: project rules withheld (%s)"
        (String.concat "; "
           (List.map
              (fun (name, paths) ->
                Printf.sprintf "duplicate compilation unit name %s: %s" name
                  (String.concat ", " paths))
              dups))
  | (_, Engine.Report.Collect_failed _) :: _ as blocked ->
      List.iter
        (fun (rule, block) ->
          match block with
          | Engine.Report.Collect_failed paths ->
              add "roster: %s withheld (collect failed on %s)" rule
                (String.concat ", " paths)
          | _ -> ())
        blocked);
  (* Kind-gated local rules structurally silent in this lane ride their own
     withheld channel — silence is enumerated, never absorbed: one [roster:]
     line each,
     after the project dispositions. *)
  List.iter
    (fun (rule, reason) -> add "roster: %s withheld (%s)" rule reason)
    (Engine.Report.withheld_rules rep);
  List.iter
    (fun (path, note) -> add "degraded %s: %s" path note)
    (Engine.Report.degraded rep);
  (* The notes channel carries two populations. Generated-unit census
     ("generated (...)" — the facts-only classifications) is inventory the
     summary's facts-only count already carries, so its per-unit lines print
     only when the explain page was asked for. Every other note is advice
     (tombstone renames, directive prompts) and always prints. The prefix is
     the classifier's own pinned vocabulary, not a content guess; a typed
     note kind belongs to the next payload codec bump (ledger). *)
  let census note =
    String.length note >= 10 && String.equal (String.sub note 0 10) "generated "
  in
  List.iter
    (fun (path, note) ->
      if notes_detail || not (census note) then add "note %s: %s" path note)
    (Engine.Report.notes rep);
  List.iter
    (fun (fl : Engine.Report.failure) ->
      add "rule %s failed on %s: %s" fl.rule fl.unit_path fl.message)
    (Engine.Report.failures rep);
  Format.pp_print_string ppf (Buffer.contents buf)

(* {1 JSON} *)

(* JSON is UTF-8 by definition; litany's paths and fix replacement text are
   raw bytes. The convention: every byte-string field is emitted
   lossily (each invalid sequence replaced by U+FFFD) and, when the
   original was not valid UTF-8, a sibling [<field>_bytes] carries the
   exact bytes hex-encoded — reversible, no invented escaping. *)

(* Length of the UTF-8 scalar encoded at [i], or 0 when the bytes there are
   not a valid encoding — overlongs, surrogates, and > U+10FFFF rejected,
   so the lossy output is valid UTF-8 by construction. *)
let utf8_scalar_len s i =
  let n = String.length s in
  let b k = if i + k < n then Char.code s.[i + k] else -1 in
  let cont k = b k land 0xC0 = 0x80 in
  let c = b 0 in
  if c < 0x80 then 1
  else if c < 0xC2 then 0
  else if c < 0xE0 then if cont 1 then 2 else 0
  else if c < 0xF0 then
    if
      cont 1 && cont 2
      && (not (c = 0xE0 && b 1 < 0xA0))
      && not (c = 0xED && b 1 >= 0xA0)
    then 3
    else 0
  else if c < 0xF5 then
    if
      cont 1 && cont 2 && cont 3
      && (not (c = 0xF0 && b 1 < 0x90))
      && not (c = 0xF4 && b 1 >= 0x90)
    then 4
    else 0
  else 0

let utf8_valid s =
  let n = String.length s in
  let rec go i =
    i >= n
    ||
    let l = utf8_scalar_len s i in
    l > 0 && go (i + l)
  in
  go 0

let utf8_lossy s =
  if utf8_valid s then s
  else begin
    let buf = Buffer.create (String.length s) in
    let n = String.length s in
    let i = ref 0 in
    while !i < n do
      match utf8_scalar_len s !i with
      | 0 ->
          Buffer.add_string buf "\xef\xbf\xbd";
          incr i
      | l ->
          Buffer.add_substring buf s !i l;
          i := !i + l
    done;
    Buffer.contents buf
  end

let add_json_string buf s =
  Buffer.add_char buf '"';
  String.iter
    (fun c ->
      match c with
      | '"' -> Buffer.add_string buf "\\\""
      | '\\' -> Buffer.add_string buf "\\\\"
      | '\n' -> Buffer.add_string buf "\\n"
      | '\r' -> Buffer.add_string buf "\\r"
      | '\t' -> Buffer.add_string buf "\\t"
      | c when Char.code c < 0x20 -> Printf.bprintf buf "\\u%04x" (Char.code c)
      | c -> Buffer.add_char buf c)
    s;
  Buffer.add_char buf '"'

let severity_word = function
  | Rule.Severity.Error -> "error"
  | Rule.Severity.Warning -> "warning"

let json ppf rep =
  let buf = Buffer.create 1024 in
  let str s = add_json_string buf (utf8_lossy s) in
  let raw fmt = Printf.bprintf buf fmt in
  (* ["<key>":"<lossy>"] plus, when [s] is not valid UTF-8, the reversible
     [,"<key>_bytes":"<hex>"] twin. *)
  let bytes_field key s =
    raw "\"%s\":" key;
    str s;
    if not (utf8_valid s) then begin
      raw ",\"%s_bytes\":\"" key;
      String.iter (fun c -> raw "%02x" (Char.code c)) s;
      raw "\""
    end
  in
  (* Positions in the compiler's own convention: 1-based lines, 0-based
     end-exclusive byte columns — the numbers the text page's [File]
     header carries, unadjusted. *)
  let loc_fields (loc : Location.t) =
    let p = loc.Location.loc_start and q = loc.Location.loc_end in
    raw "\"line\":%d,\"col\":%d,\"end_line\":%d,\"end_col\":%d" p.pos_lnum
      (p.pos_cnum - p.pos_bol) q.pos_lnum (q.pos_cnum - q.pos_bol)
  in
  Engine.Report.iter_findings rep (fun ~rule ~severity f ->
      let loc = Finding.loc f in
      Buffer.add_string buf "{\"rule\":";
      str rule;
      raw ",\"severity\":\"%s\"," (severity_word severity);
      bytes_field "file" loc.Location.loc_start.pos_fname;
      Buffer.add_char buf ',';
      loc_fields loc;
      Buffer.add_string buf ",\"message\":";
      str (Finding.message f);
      (match Finding.fix f with
      | None -> ()
      | Some fx ->
          Buffer.add_string buf ",\"fix\":{\"title\":";
          str (Fix.title fx);
          raw ",\"applicability\":\"%s\",\"edits\":["
            (Fix.applicability_to_string (Fix.applicability fx));
          List.iteri
            (fun i (e : Fix.edit) ->
              if i > 0 then Buffer.add_char buf ',';
              raw "{\"start\":%d,\"stop\":%d," (Span.start e.span)
                (Span.stop e.span);
              bytes_field "text" e.text;
              Buffer.add_char buf '}')
            (Fix.edits fx);
          Buffer.add_string buf "]}");
      Buffer.add_string buf "}\n");
  let skipped =
    List.filter_map
      (fun (path, outcome) ->
        match (outcome : Engine.Report.outcome) with
        | Linted | Facts_only -> None
        | Skipped sk -> Some (path, sk))
      (Engine.Report.units rep)
  in
  (* The trailer, schema-versioned: the JSONL schema deliberately carries
     [schema_version] on every record and [failures]/[exit_code] in the
     trailer — exit 3 is driven by failures, so a JSON consumer must see
     them. [schema] is 1; additive keys do not bump it, a change to an
     existing key's meaning does. The counts are [Engine.Summary] —
     the same aggregation the text page prints, serialized field-for-field,
     so the machine channel carries the whole truth set: the selection
     denominator, the linted/facts-only split, and the suppressed count
     included. *)
  let s = Engine.Summary.of_report rep in
  raw
    "{\"summary\":{\"schema\":1,\"rules_selected\":%d,\"findings\":%d,\"fixable\":%d,\"units\":%d,\"linted\":%d,\"facts_only\":%d,\"suppressed\":%d,\"skipped\":["
    s.rules_selected s.findings s.fixable s.units s.linted s.facts_only
    s.suppressed;
  List.iteri
    (fun i (path, sk) ->
      if i > 0 then Buffer.add_char buf ',';
      Buffer.add_char buf '{';
      bytes_field "path" path;
      raw ",\"reason\":\"%s\"" (Unit.Skip.slug sk);
      Buffer.add_char buf '}')
    skipped;
  (* Rule failures dominate the exit law (exit 3): full records, so CI can
     name the failing rule and unit without parsing the text page. *)
  Buffer.add_string buf "],\"failures\":[";
  List.iteri
    (fun i (fl : Engine.Report.failure) ->
      if i > 0 then Buffer.add_char buf ',';
      Buffer.add_string buf "{\"rule\":";
      str fl.rule;
      Buffer.add_char buf ',';
      bytes_field "path" fl.unit_path;
      Buffer.add_string buf ",\"message\":";
      str fl.message;
      Buffer.add_char buf '}')
    (Engine.Report.failures rep);
  Buffer.add_string buf "],\"degraded\":[";
  List.iteri
    (fun i (path, note) ->
      if i > 0 then Buffer.add_char buf ',';
      Buffer.add_char buf '{';
      bytes_field "path" path;
      Buffer.add_string buf ",\"note\":";
      str note;
      Buffer.add_char buf '}')
    (Engine.Report.degraded rep);
  Buffer.add_string buf "],\"notes\":[";
  List.iteri
    (fun i (path, note) ->
      if i > 0 then Buffer.add_char buf ',';
      Buffer.add_char buf '{';
      bytes_field "path" path;
      Buffer.add_string buf ",\"note\":";
      str note;
      Buffer.add_char buf '}')
    (Engine.Report.notes rep);
  raw "],\"dropped\":%d,\"roster\":[" s.dropped;
  (* One object per selected project rule — the disposition algebra,
     structured: [state] is [ran] or the block's kind, with the block's own
     rows beside it. Empty when no project rule was selected. *)
  List.iteri
    (fun i (rule, block) ->
      if i > 0 then Buffer.add_char buf ',';
      Buffer.add_string buf "{\"rule\":";
      str rule;
      (match block with
      | None -> raw ",\"state\":\"ran\""
      | Some Engine.Report.Not_capable -> raw ",\"state\":\"unavailable\""
      | Some (Engine.Report.Incomplete blocking) ->
          raw ",\"state\":\"incomplete\",\"blocking\":[";
          List.iteri
            (fun j (path, sk) ->
              if j > 0 then Buffer.add_char buf ',';
              Buffer.add_char buf '{';
              bytes_field "path" path;
              raw ",\"reason\":\"%s\"" (Unit.Skip.slug sk);
              Buffer.add_char buf '}')
            blocking;
          Buffer.add_char buf ']'
      | Some (Engine.Report.Ambiguous dups) ->
          raw ",\"state\":\"ambiguous\",\"duplicates\":[";
          List.iteri
            (fun j (name, paths) ->
              if j > 0 then Buffer.add_char buf ',';
              Buffer.add_string buf "{\"name\":";
              str name;
              Buffer.add_string buf ",\"paths\":[";
              List.iteri
                (fun k path ->
                  if k > 0 then Buffer.add_char buf ',';
                  str path)
                paths;
              Buffer.add_string buf "]}")
            dups;
          Buffer.add_char buf ']'
      | Some (Engine.Report.Collect_failed paths) ->
          raw ",\"state\":\"collect-failed\",\"paths\":[";
          List.iteri
            (fun j path ->
              if j > 0 then Buffer.add_char buf ',';
              str path)
            paths;
          Buffer.add_char buf ']');
      Buffer.add_char buf '}')
    (Engine.Report.project_rules rep);
  raw "],\"exit\":%d}}\n" s.exit_code;
  Format.pp_print_string ppf (Buffer.contents buf)

(* {1 GitHub workflow annotations} *)

(* The workflow-command escapes, per GitHub's own toolkit: property values
   escape [% CR LF : ,]; message data escapes [% CR LF]. *)
let github_prop s =
  let buf = Buffer.create (String.length s) in
  String.iter
    (fun c ->
      match c with
      | '%' -> Buffer.add_string buf "%25"
      | '\r' -> Buffer.add_string buf "%0D"
      | '\n' -> Buffer.add_string buf "%0A"
      | ':' -> Buffer.add_string buf "%3A"
      | ',' -> Buffer.add_string buf "%2C"
      | c -> Buffer.add_char buf c)
    s;
  Buffer.contents buf

let github_data s =
  let buf = Buffer.create (String.length s) in
  String.iter
    (fun c ->
      match c with
      | '%' -> Buffer.add_string buf "%25"
      | '\r' -> Buffer.add_string buf "%0D"
      | '\n' -> Buffer.add_string buf "%0A"
      | c -> Buffer.add_char buf c)
    s;
  Buffer.contents buf

let github ppf rep =
  let buf = Buffer.create 1024 in
  Engine.Report.iter_findings rep (fun ~rule ~severity f ->
      let loc = Finding.loc f in
      let p = loc.Location.loc_start and q = loc.Location.loc_end in
      let message =
        match Finding.fix f with
        | None -> Finding.message f
        | Some fx ->
            Printf.sprintf "%s fix (%s): %s" (Finding.message f)
              (Fix.applicability_to_string (Fix.applicability fx))
              (Fix.title fx)
      in
      (* Columns are 1-based on this surface (GitHub's convention). On a
         multi-line span the annotation carries [endLine] and no columns —
         GitHub rejects column properties when the lines differ. *)
      if p.pos_lnum = q.pos_lnum then
        Printf.bprintf buf
          "::%s file=%s,line=%d,col=%d,endColumn=%d,title=%s::%s\n"
          (severity_word severity) (github_prop p.pos_fname) p.pos_lnum
          (p.pos_cnum - p.pos_bol + 1)
          (q.pos_cnum - q.pos_bol + 1)
          (github_prop rule) (github_data message)
      else
        Printf.bprintf buf "::%s file=%s,line=%d,endLine=%d,title=%s::%s\n"
          (severity_word severity) (github_prop p.pos_fname) p.pos_lnum
          q.pos_lnum (github_prop rule) (github_data message));
  Format.pp_print_string ppf (Buffer.contents buf)
