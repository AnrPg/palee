defmodule Palee.Application.TrainingLogSourceAccess do
  @moduledoc """
  Gathers the facts `TrainingLogSourcePolicy` decides on (ADR-451): the club's
  kind, the acting person's role and package. Used by the source picker and
  by `AuthorizeTrainingLogSource`, so the API refuses what the picker hides.

  The package is read once per call; package checks follow the club's
  rollout mode exactly as booking does.
  """

  alias Palee.Finance
  alias Palee.Finance.Domain.{EntitlementPolicy, ProgrammingGrant}
  alias Palee.Execution.Domain.TrainingLogSourcePolicy, as: Policy

  @doc """
  The package facts for `user_id` in `context`. The caller adds what only it
  knows (whether classes, assignments or library workouts are listed).
  """
  def package_facts(%{organization_id: _} = context, user_id) do
    role = Map.get(context, :role)
    entitlement = Finance.get_effective_entitlement(context, user_id)

    [class_package?, library_access?] =
      grants(context, user_id, entitlement, role, [
        {Policy.class_rule(role), Policy.class_request()},
        {Policy.library_rule(role), Policy.library_request()}
      ])

    %{
      box?: box?(context),
      class_package?: class_package?,
      programming_grant?: match?({:ok, _grant}, ProgrammingGrant.of(entitlement)),
      library_access?: library_access?
    }
  end

  @doc "Whether the acting person may log a self-selected library workout here."
  def library_allowed?(%{organization_id: _} = context, user_id) do
    role = Map.get(context, :role)

    case Policy.library_rule(role) do
      :role ->
        true

      :never ->
        false

      rule ->
        entitlement =
          if rule == :explicit_package, do: Finance.get_effective_entitlement(context, user_id)

        [allowed?] =
          grants(context, user_id, entitlement, role, [{rule, Policy.library_request()}])

        allowed?
    end
  end

  def library_allowed?(_context, _user_id), do: false

  # `:package` rules go through the same ledger check as booking
  # (`Finance.check_entitlements/3`), so the club's rollout mode applies to a
  # missing profile or plan exactly as it does there; one query for all.
  defp grants(context, user_id, entitlement, role, rules) do
    package_requests =
      for {:package, request} <- rules, do: Map.put(request, :actor_role, role)

    package_results =
      case package_requests do
        [] -> []
        requests -> Finance.check_entitlements(context, user_id, requests)
      end

    {results, []} =
      Enum.map_reduce(rules, package_results, fn
        {:package, _request}, [result | rest] -> {result == :ok, rest}
        {:role, _request}, rest -> {true, rest}
        {:never, _request}, rest -> {false, rest}
        {:explicit_package, request}, rest -> {explicit?(entitlement, request), rest}
      end)

    results
  end

  defp explicit?(entitlement, request),
    do: EntitlementPolicy.authorize_explicit(entitlement, request) == :ok

  defp box?(%{organization: %{provider_kind: "coach"}}), do: false
  defp box?(_context), do: true
end
