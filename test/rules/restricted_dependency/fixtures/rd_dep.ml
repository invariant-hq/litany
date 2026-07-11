(* The fixture's own dependency unit: a public value, a submodule the
   suite forbids as [Rd_dep.Internal], a genuine re-export alias of the
   forbidden [Str] unit, and a Re.Str-style wrapper whose own
   declarations merely spell [Str]. *)

let ok = "public"

module Internal = struct
  let secret = 41

  module Deeper = struct
    let deepest = 42
  end
end

(* A genuine re-export: an alias into the forbidden unit — references
   through it carry Str's own declaration UIDs. *)
module Legacy_str = Str

module Compat = struct
  (* Same spelling as the forbidden Str unit, its own declarations — the
     Re.Str precedent: a compatibility wrapper is a distinct identity. *)
  module Str = struct
    let regexp (s : string) = s
  end
end
