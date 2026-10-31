defmodule Palee.Application.RankCertificates do
  @moduledoc "«Δίπλωμα» of a rank award as a PDF (ADR-377), for the coach and for the person."

  alias Palee.{Identity, Organizations, Ranks}
  alias Palee.Pdf.Fonts

  @doc "`{:ok, %{filename, data}}`; `only_user_id` limits it to that person's awards."
  def call(%{organization_id: organization_id} = context, award_id, only_user_id \\ nil) do
    found =
      Ranks.with_context(context, fn ->
        with %{} = award <- Ranks.get_award(award_id),
             true <- is_nil(only_user_id) or award.user_id == only_user_id,
             %{} = ladder <- Ranks.get_ladder(award.ladder_id) do
          {award, ladder}
        else
          _missing -> nil
        end
      end)

    case found do
      nil ->
        {:error, :not_found}

      {award, ladder} ->
        rank = Enum.find(ladder.ranks, &(&1.id == award.rank_id))

        view = %{
          box: organization_name(award.user_id, organization_id),
          person: display_name(award.user_id),
          ladder: ladder.name,
          rank: rank && rank.name,
          color: if(ladder.style == "belt", do: rank && rank.color),
          stripes: award.stripes,
          awarded_on: award.awarded_on,
          awarded_by: award.awarded_by_id && display_name(award.awarded_by_id),
          number: award.certificate_number,
          revoked: not is_nil(award.revoked_at)
        }

        {:ok, %{filename: "diploma-#{award.certificate_number}.pdf", data: Ranks.certificate_pdf(view, Fonts.sans())}}
    end
  end

  defp display_name(user_id) do
    case Identity.find_by_id(user_id) do
      %{display_name: name} when is_binary(name) -> name
      _missing -> nil
    end
  end

  defp organization_name(user_id, organization_id) do
    user_id
    |> Organizations.list_memberships()
    |> Enum.find_value(fn %{organization: organization} ->
      if organization.id == organization_id, do: organization.name
    end)
  end
end
