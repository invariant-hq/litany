(* Fixture for disable-all-warnings: positives carry the FIRE marker; the
   rest are the prior implementation's negative payloads and lookalike attributes. *)

(* The three standalone disable-everything spellings, floating and
   attached, under both attribute names. *)
[@@@warning "-a" (* FIRE *)]
[@@@warning "-A" (* FIRE *)]
[@@@warning "a" (* FIRE *)]
[@@@ocaml.warning "-a" (* FIRE *)]

let attached = (1 [@warning "-a" (* FIRE *)])

(* Selective, compound, and enabling specifications stay clean. *)
[@@@warning "-27"]
[@@@warning "-a+31"]
[@@@warning "+27"]

(* Lookalike attribute names stay clean. *)
[@@@warnerror "-a"]
[@@@warningx "-a"]

(* Adopted from the prior implementation's suite. The compiler's
   own illegal-payload warning (47) is disabled first — a selective payload,
   itself a documented negative — so the malformed payloads below compile. *)
[@@@warning "-47"]

(* Whitespace is meaningful: boundary whitespace is not the standalone
   spelling (old: "does not ignore boundary or internal whitespace"). *)
[@@@warning " -a"]
[@@@warning "-a "]

(* The decoded escape spells the same bytes: the payload is read as the
   decoded literal, so "\045a" is exactly "-a". *)
[@@@warning "\045a" (* FIRE *)]

(* Non-string and multi-item payloads stay clean. *)
[@@@warning 42]
[@@@warning "-a" "-b"]

let used = attached + 1
