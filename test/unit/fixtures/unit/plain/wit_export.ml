(* Export fixture, mli-backed: the interface hides [scale] and exposes a
   type, a value, and a nested module — rows must come from the interface
   signature, never this derived one. *)
type t = int

let scale = 2
let make n = n * scale

module Sub = struct
  let x = 3
end
