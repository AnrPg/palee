defmodule Palee.Ranks.Domain.TenantDataPolicy do
  @moduledoc """
  Ranks tenant data policy (ADR-117, ADR-377): a box's ladders and the
  promotions it gave are the box's records; a purged box takes them with
  it (after the export it is offered).
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "ranks",
            purge_order: 63,
            disposition: :purge,
            basis:
              "Belts and levels are the box's teaching records; nothing requires keeping them after the box leaves.",
            tables: [
              %{table: "rank_skill_checks"},
              %{table: "rank_awards"},
              %{table: "ranks"},
              %{table: "rank_ladders"}
            ]
          })

  def policy, do: @policy
end
