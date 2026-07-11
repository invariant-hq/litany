(* Cross-unit references inside the fixture library: the item-level dep rows
   another unit's dead-code join consumes, plus unit-level rows for the
   occurrences local reduction leaves unresolved. *)
let greeting = Wit_mli.shout "hey"
let answer_plus_one = Wit_direct.answer + 1
