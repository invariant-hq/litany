(*---------------------------------------------------------------------------
   Copyright (c) 2026 Invariant Systems. All rights reserved.
   SPDX-License-Identifier: ISC
  ---------------------------------------------------------------------------*)

(** The built-in rule catalog.

    One module per rule, each a single {!Litany.Rule.t} value built against the
    [Litany] facade alone, plus {!all} — the list the stock composition root
    passes to the engine. Rule identity is the metadata name, never the module:
    configuration, suppression, and output all speak [needless-list-length], not
    [Needless_list_length].

    Third parties compose their own catalog by recompiling:
    [Litany_rules.all @ My_rules.all] in a custom [bin/] (see the extension
    model in [Litany]). *)

(** {1:rules Rules} *)

module Dead_code = Dead_code
module Disable_all_warnings = Disable_all_warnings
module Eta_reducible_forwarding = Eta_reducible_forwarding
module Ignored_result = Ignored_result
module Invalid_function_comparison = Invalid_function_comparison
module Invalid_hashtable_key = Invalid_hashtable_key
module Invalid_nan_comparison = Invalid_nan_comparison
module Manual_boolean_operator = Manual_boolean_operator
module Manual_case_guard = Manual_case_guard
module Manual_eta_lambda = Manual_eta_lambda
module Manual_format_quoting = Manual_format_quoting
module Manual_list_exists = Manual_list_exists
module Manual_list_filter_map = Manual_list_filter_map
module Manual_list_fold = Manual_list_fold
module Manual_list_forall = Manual_list_forall
module Manual_list_map = Manual_list_map
module Manual_option_bind = Manual_option_bind
module Manual_option_map = Manual_option_map
module Manual_option_value = Manual_option_value
module Manual_record_update = Manual_record_update
module Manual_result_bind = Manual_result_bind
module Manual_result_map = Manual_result_map
module Manual_temp_dir = Manual_temp_dir
module Manual_tuple_matching = Manual_tuple_matching
module Missing_final_newline = Missing_final_newline
module Missing_printer = Missing_printer
module Needless_and_binding = Needless_and_binding
module Needless_append_empty = Needless_append_empty
module Needless_fun_match = Needless_fun_match
module Needless_list_length = Needless_list_length
module Needless_list_map_before_concat = Needless_list_map_before_concat
module Needless_mutually_recursive_types = Needless_mutually_recursive_types
module Outdated_str_module = Outdated_str_module
module Quadratic_list_append = Quadratic_list_append
module Quadratic_string_concat_chain = Quadratic_string_concat_chain
module Quadratic_string_concat_fold = Quadratic_string_concat_fold
module Redundant_bind_return = Redundant_bind_return
module Redundant_boolean_comparison = Redundant_boolean_comparison
module Redundant_boolean_operator = Redundant_boolean_operator
module Redundant_conversion_roundtrip = Redundant_conversion_roundtrip
module Redundant_guard_true = Redundant_guard_true
module Redundant_if_bool = Redundant_if_bool
module Redundant_list_roundtrip = Redundant_list_roundtrip
module Redundant_match_bool = Redundant_match_bool
module Redundant_nested_if = Redundant_nested_if
module Redundant_not_not = Redundant_not_not
module Redundant_option_comparison = Redundant_option_comparison
module Redundant_option_roundtrip = Redundant_option_roundtrip
module Redundant_return_bind = Redundant_return_bind
module Restricted_dependency = Restricted_dependency
module Restricted_export_name = Restricted_export_name
module Restricted_global_mutable_state = Restricted_global_mutable_state
module Restricted_public_exception = Restricted_public_exception
module Suspicious_ambiguous_constructors = Suspicious_ambiguous_constructors
module Suspicious_catch_all_handler = Suspicious_catch_all_handler
module Suspicious_duplicate_condition = Suspicious_duplicate_condition
module Suspicious_exit_in_library = Suspicious_exit_in_library
module Suspicious_failwith_in_library = Suspicious_failwith_in_library
module Suspicious_file_exists_race = Suspicious_file_exists_race
module Suspicious_general_float_equality = Suspicious_general_float_equality
module Suspicious_if_same_branches = Suspicious_if_same_branches

module Suspicious_ignored_partial_application =
  Suspicious_ignored_partial_application

module Suspicious_literal_condition = Suspicious_literal_condition
module Suspicious_lost_backtrace = Suspicious_lost_backtrace
module Suspicious_physical_equality = Suspicious_physical_equality

module Suspicious_polymorphic_compare_on_opaque =
  Suspicious_polymorphic_compare_on_opaque

module Suspicious_print_debugging = Suspicious_print_debugging
module Suspicious_rec_without_recursion = Suspicious_rec_without_recursion
module Suspicious_sequence_ignored_value = Suspicious_sequence_ignored_value
module Suspicious_str_formatter = Suspicious_str_formatter
module Suspicious_swallowed_cancellation = Suspicious_swallowed_cancellation
module Suspicious_transposable_arguments = Suspicious_transposable_arguments
module Suspicious_unused_module_binding = Suspicious_unused_module_binding
module Suspicious_variant_arity_tuple = Suspicious_variant_arity_tuple
module Suspicious_wall_clock_elapsed = Suspicious_wall_clock_elapsed
module Trailing_whitespace = Trailing_whitespace
module Unsafe_obj_magic = Unsafe_obj_magic
module Unsafe_partial_stdlib = Unsafe_partial_stdlib
module Unused_export = Unused_export
module Used_underscore_binding = Used_underscore_binding

(** {1:catalog The catalog} *)

val all : Litany.Rule.t list
(** [all] is every built-in rule, in alphabetical order of rule name. Names are
    unique — the engine refuses duplicate names at startup. *)
