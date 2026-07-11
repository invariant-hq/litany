(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** The library's interface, and the rule-author SDK.

    [litany] is one wrapped library: every domain is a module of this one, so
    [Litany.Engine] is the engine and [Litany.Driver] the check driver. The
    first two sections below are the SDK — what a rule author sees and what
    carries a compatibility promise; {!section:internals} is the driver
    machinery, exposed for [bin/] and the test suites and promised to nobody.

    [open Litany] is a rule file's single open: it re-exports Litany's own
    modules alongside the compiler's [Typedtree], [Parsetree], [Asttypes],
    [Longident], [Types], [Location], [Path], [Ident], [Predef], [Shape], and
    [Tast_iterator] — the closure the trees lean on, plus the iterator for
    bounded subtree walks — so rules compile against the real trees with one
    dependency — [litany] — in their dune stanza, warning-free under dune's
    default warning set. Strict sets ([-w +40+42]) additionally qualify Litany's
    policy constructors ([Rule.Perf], [Rule.Never]) and tree labels. The
    compiler-libs pin is Litany's, stated once.

    A rule is one value in one file: declare {!Rule.meta}, build the match with
    {!Pat}, return {!Finding} values, attach a {!Fix} when the edit is provable.
    See [doc/dev/design.md] (Domains) for the domain map behind this facade. The
    built-in catalog lives beside it in [Litany_rules] — one module per rule
    plus [Litany_rules.all], each rule a client of exactly this facade.

    Third parties extend by recompiling: a custom [bin/] that passes
    [Litany_rules.all @ My_rules.all] where the stock composition root passes
    the catalog is the whole extension model — no dynlink, which keeps the
    cache's binary-digest key honest. The packaged recipe is the documented thin
    composition root — some 25 lines against [Driver] and a stock adapter, in
    [doc/manual/build-integration.md] (A custom binary). There is deliberately
    no cli library: the recipe serves the need. *)

(** {1:sdk Litany modules}

    The rule-author vocabulary: the seven domains a rule is written against. *)

module Span = Span
module Fix = Fix
module Finding = Finding
module Source = Source
module Unit = Unit
module Pat = Pat
module Rule = Rule

(** {1:compiler Compiler modules}

    Re-exported, not wrapped. Rules see the compiler's own trees; a compiler
    minor is absorbed by Litany's release stream, not by a façade. *)

module Typedtree = Typedtree
module Parsetree = Parsetree
module Asttypes = Asttypes
module Longident = Longident
module Types = Types
module Location = Location
module Path = Path
module Ident = Ident
module Predef = Predef
module Shape = Shape
module Tast_iterator = Tast_iterator

(** {1:internals Driver machinery}

    Not SDK vocabulary and no rule-author compatibility promise: these are the
    domains the check driver, [bin/], and the test suites compose. [open Litany]
    does put them in scope — the price of one wrapped library — but a rule that
    names one is out of contract, and [test/rules/] freezes that discipline by
    grep the way it used to freeze the [Litany_*] spelling. *)

module Adapter = Adapter
module Apply = Apply
module Cache = Cache
module Config_file = Config_file
module Digest0 = Digest0
module Driver = Driver
module Dune_describe = Dune_describe
module Engine = Engine
module Naming = Naming
module Progress = Progress
module Render = Render
module Roster = Roster
module Sexp = Sexp
module Suggest = Suggest
module Suppress = Suppress
module Write = Write
