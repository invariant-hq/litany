(* A vendored stub of the [Eio] compilation unit: [Pat.from_unit "Eio"]
   matches by compilation-unit name, so this fixture-local library
   stands in for the real one — the vendoring reading the view
   documents. Nothing here runs; the fixture only compiles. *)

module Cancel = struct
  exception Cancelled of exn
end

module Path = struct
  let read_dir path = [ path ]
  let stat path = String.length path
end
