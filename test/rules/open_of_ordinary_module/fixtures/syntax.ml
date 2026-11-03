let ( let* ) = Result.bind

let ( and* ) a b =
  match (a, b) with
  | Ok a, Ok b -> Ok (a, b)
  | Error e, _ | _, Error e -> Error e
