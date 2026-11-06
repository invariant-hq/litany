(* Modules of binding operators beside something else, one per case below,
   since the rule reads a use of a module wherever the unit makes it. *)
module type Operators = sig
  val ( let* ) : ('a, 'e) result -> ('a -> ('b, 'e) result) -> ('b, 'e) result
end

module Operators : Operators = struct
  let ( let* ) = Result.bind
end

module Constructor = struct
  include Operators

  type t = A | B
end

module Field = struct
  include Operators

  type t = { f : int }
end

module Member = struct
  include Operators

  module Sub = struct
    let v = 1
  end
end

module Type_only = struct
  include Operators

  type t = int
end

module Written_out = struct
  include Operators

  let helper = 1
end

module Nothing_through = struct
  include Operators
end

module Unused = struct
  include Operators
end
