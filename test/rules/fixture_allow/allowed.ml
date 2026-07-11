let is_empty xs = (List.length xs = 0) [@litany.allow "needless-list-length: benchmark helper"]
let also_empty xs = List.length xs = 0
let fine = 1 [@@litany.allow "needless-list-length: stale"]
