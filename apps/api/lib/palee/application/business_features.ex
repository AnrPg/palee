defmodule Palee.Application.BusinessFeatures do
  @moduledoc """
  The use case behind `GET /api/org/:slug/me/features` (ADR-470): which
  optional features this business has switched on, so every screen hides
  what depends on a feature that is off.

  It reads one fact per feature through each context's public API (a few
  small reads, each scoped to the business) and leaves every rule to the
  pure `Organizations.Domain.BusinessFeatures`. The answer holds booleans
  only, so every member of the business may read it.
  """

  alias Palee.{Facility, Finance, Organizations, Payments, Perks, Spaces, Trials}
  alias Palee.Finance.Domain.PackageType
  alias Palee.Organizations.Domain.BusinessFeatures
  alias Palee.Payments.Domain.AccountOptions

  @doc "Every feature key (the API schema lists them all)."
  defdelegate keys, to: BusinessFeatures

  @doc """
  `%{key => boolean}` for every key in `BusinessFeatures.keys/0`.
  `location_ids`: the page's branch filter, or nil for the whole business.
  """
  def status(
        %{organization_id: organization_id} = context,
        location_ids \\ nil,
        now \\ DateTime.utc_now()
      ) do
    BusinessFeatures.evaluate(
      facts(context),
      Organizations.local_today(organization_id, now),
      location_ids
    )
  end

  defp facts(context) do
    offer = Payments.package_offer(context)
    finance_settings = Finance.get_finance_settings(context) || %{}

    %{
      payments_active: offer.available,
      payment_purposes: AccountOptions.resolve(offer.options)["purposes"],
      referral_program_active: not is_nil(Finance.active_referral_program(context)),
      promotion_campaigns: Finance.list_promotion_campaigns(context),
      promotion_codes: Finance.list_promotion_codes(context, nil),
      published_perks: context |> Perks.list_perks(%{statuses: ["published"]}) |> length(),
      trials_enabled: Trials.policy(context).enabled == true,
      active_locations: context |> Facility.list_locations() |> length(),
      floor_plans: Spaces.list_floor_plans(context),
      enabled_modules:
        Map.get(finance_settings, :package_modules) || PackageType.default_modules()
    }
  end
end
