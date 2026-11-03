defmodule Palee.Pantheon.Domain.TenantDataPolicy do
  @moduledoc """
  Pantheon tenant data retention and purge policy (ADR-117).

  Declares the tables this context owns, in delete (dependency) order, and
  how they are treated when a tenant is purged.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "pantheon",
            purge_order: 40,
            disposition: :purge,
            basis:
              "Personal records and coach display choices are member training data with no retention obligation.",
            tables: [
              # ADR-395: a coach's per-box choice of what a client's fitness card shows.
              %{table: "fitness_display_overrides"},
              %{table: "user_pr_history", rls: {:user_via, "user_pr_records", "pr_record_id"}},
              %{table: "user_pr_records", rls: :user}
            ]
          })

  def policy, do: @policy
end
