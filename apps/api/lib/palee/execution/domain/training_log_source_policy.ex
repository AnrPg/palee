defmodule Palee.Execution.Domain.TrainingLogSourcePolicy do
  @moduledoc """
  Which «Καταγραφή προπόνησης» sources a person may use in one club (ADR-451),
  pure.

  ANR (2026-11-04): the source chips follow the person's role and package.

    * `class` (Τμήμα) - a box member whose package covers classes (judged
      under the club's rollout mode, like booking), an athlete only with an
      explicit class grant, or anyone who
      still has a class of the last 30 days to log (a guest, staff who
      trained, a package that just ended).
    * `assigned_workout` (Προπόνηση που ανατέθηκε) - a package with online
      programming or personal training (ADR-225, strict), or an assignment of
      the last 30 days still to log (it was assigned while the grant held).
    * `library_workout` (Προπόνηση από τη βιβλιοθήκη) - the same rule as
      starting a self-selected WOD: staff who author the library
      (owner, admin, coach); a member whose package includes the workout
      library (rollout mode); an athlete only with an explicit library grant
      (ADR-029: athletes follow what they are assigned). The club must also
      have at least one published workout, or the chip leads nowhere.
    * `freeform` (Ελεύθερη) - always.

  Callers gather the facts; this module only decides.
  """

  @order ~w(class assigned_workout library_workout freeform)
  @staff_roles [:owner, :admin, :coach]

  @type facts :: %{
          optional(:box?) => boolean(),
          optional(:class_package?) => boolean(),
          optional(:classes_to_log?) => boolean(),
          optional(:programming_grant?) => boolean(),
          optional(:assignments_to_log?) => boolean(),
          optional(:library_access?) => boolean(),
          optional(:library_published?) => boolean()
        }

  @doc "Every source type in display order."
  def order, do: @order

  @doc "The source types this person may log, in display order; `freeform` is always last."
  def available(facts) when is_map(facts) do
    Enum.filter(@order, &allowed?(&1, facts))
  end

  @doc "Whether one source type is open to the person."
  def allowed?("freeform", _facts), do: true

  def allowed?("class", facts),
    do: flag(facts, :classes_to_log?) or (flag(facts, :box?) and flag(facts, :class_package?))

  def allowed?("assigned_workout", facts),
    do: flag(facts, :programming_grant?) or flag(facts, :assignments_to_log?)

  def allowed?("library_workout", facts),
    do: flag(facts, :library_access?) and flag(facts, :library_published?)

  def allowed?(_unknown, _facts), do: false

  @doc """
  How a role reaches the workout library:

    * `:role` - staff author it, so the role is enough
    * `:package` - the package decides, under the club's rollout mode
    * `:explicit_package` - only an explicit package grant (no rollout leniency)
    * `:never`
  """
  def library_rule(role) when role in @staff_roles, do: :role
  def library_rule(:member), do: :package
  def library_rule(:athlete), do: :explicit_package
  def library_rule(_role), do: :never

  @doc """
  How a role reaches «Τμήμα» without a class left to log (same values as
  `library_rule/1`; staff log the classes they booked, so `:never` here).
  """
  def class_rule(:member), do: :package
  def class_rule(:athlete), do: :explicit_package
  def class_rule(_role), do: :never

  @doc "The ledger request for attending classes (mirrors `BookingPolicy.entitlement_request/1`)."
  def class_request, do: %{channel: :in_person, capability: :book_classes}

  @doc "The ledger request for a self-selected library workout (mirrors executions)."
  def library_request, do: %{channel: :workout_library, capability: :execute_library_workouts}

  defp flag(facts, key), do: Map.get(facts, key) == true
end
