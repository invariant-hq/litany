(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** Inline functions that only forward their arguments.

    Reports an inline [fun] in argument position of a full, unlabeled
    application — any arity — whose parameters are distinct plain unlabeled
    variables and whose body applies an independent identifier to exactly those
    parameters, by declaration identity, once each in order without labels:
    [List.map (fun x -> succ x) xs], including partial forwards like
    [fun x -> add x]. Anchored at the wrapper, one finding per forwarding
    argument.

    Named [let] forwarders and the [let g x = f x] sugar stay clean (a named
    forwarder is usually deliberate), as do arguments of labeled applications,
    reordered, duplicated, missing, extra, or labeled arguments,
    labeled/optional/non-variable parameters, parameter-bound callees, shadowed
    same-spelling variables, curried multi-stage wrappers, and [function]
    bodies. No fix: removing the wrapper changes closure allocation and can make
    physical identity observable. The rationale is style and that identity,
    never speed — verified OCaml 5.5.0 arm64 non-flambda: [fun x -> succ x]
    compiles to cmm byte-identical to [succ], and small callees inline into the
    wrapper. *)

val rule : Litany.Rule.t
(** [rule] is [needless-identity-function]. *)
