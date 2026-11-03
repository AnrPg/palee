defmodule Palee.Application.RankCertificates do
  @moduledoc """
  «Δίπλωμα» of a rank award as a PDF (ADR-377), for the coach and for the
  person. Option Γ (ADR-377 addendum): the box's uploaded logo at the top
  (only the name without one, or when it is a WebP or a link to another
  site: nothing is fetched from the network) and the awarding coach's
  signature kept with the award (`signature_id`), above the line with their
  name.
  """

  require Logger

  alias Palee.{Identity, Organizations, Ranks}
  alias Palee.Application.{DiplomaSignatures, TenantObjectStorage}
  alias Palee.Pdf
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
          awarded_by: award.awarded_by_id && coach_name(award.awarded_by_id),
          number: award.certificate_number,
          revoked: not is_nil(award.revoked_at),
          logo: logo(organization_id),
          signature: award.awarded_by_id && DiplomaSignatures.pdf_image(award.signature_id)
        }

        {:ok,
         %{
           filename: "diploma-#{award.certificate_number}.pdf",
           data: Ranks.certificate_pdf(view, Fonts.sans())
         }}
    end
  end

  # The uploaded logo (ADR-121) as a PDF image, or nil.
  defp logo(organization_id) do
    with %{brand_logo_object_key: key} when is_binary(key) <-
           Organizations.get_organization_settings(organization_id),
         {:ok, bytes} <- download_logo(organization_id, key),
         {:ok, image} <- Pdf.Image.parse(bytes) do
      image
    else
      _none -> nil
    end
  end

  defp download_logo(organization_id, key) do
    path = Path.join(System.tmp_dir!(), "palee-logo-#{System.unique_integer([:positive])}")

    try do
      case TenantObjectStorage.download_box_file(organization_id, :branding, key, path) do
        :ok ->
          File.read(path)

        {:error, reason} = error ->
          Logger.warning("diploma_logo_unavailable reason=#{inspect(reason)}")
          error
      end
    after
      File.rm(path)
    end
  end

  # The signature line needs a name: the nickname when there is no display name.
  defp coach_name(user_id) do
    case Identity.find_by_id(user_id) do
      %{display_name: name} when is_binary(name) and name != "" -> name
      %{nickname: name} when is_binary(name) and name != "" -> name
      _missing -> nil
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
