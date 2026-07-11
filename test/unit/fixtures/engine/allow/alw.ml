let a = (41 [@litany.allow "flag-int: identity is the point"])
let b = 42
let c = ("s" [@litany.allow "flag-int: nothing to see"])
let d = (43 [@litany.expect "flag-int: fires"])
let e = ("t" [@litany.expect "flag-int: silent"])
