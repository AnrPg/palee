defmodule Palee.BoxSite.Domain.ConsentPolicy do
  @moduledoc """
  ADR-354: consent before any tracking on a box's website.

    * Categories: `necessary` (always on; Palee sets no tracking cookie),
      `analytics` (GA4) and `marketing` (Meta Pixel, ad tags).
    * Accepting and refusing are equally easy; nothing is pre-ticked.
    * A choice lasts #{182} days, or until the box adds a tag
      (`banner_version` bumps).
    * The log keeps a pseudonymous visitor id and the choice only, and is
      deleted #{730} days after each row was recorded.
  """

  @categories ~w(necessary analytics marketing)
  @actions ~w(accept_all reject_all custom withdraw)
  @validity_days 182
  @retention_days 730

  def categories, do: @categories
  def actions, do: @actions
  def validity_days, do: @validity_days
  def retention_days, do: @retention_days

  @doc """
  A log row for a visitor's choice: `{:ok, attrs}` or
  `{:error, {:invalid_fields, errors}}`. The banner version must be the
  box's current one, so a stale page cannot record consent to tags it
  never showed.
  """
  def record(params, current_banner_version, now) do
    action = Map.get(params, "action")
    visitor = Map.get(params, "visitor_id")
    version = Map.get(params, "banner_version")

    errors =
      %{}
      |> put_if(action not in @actions, :action, "invalid")
      |> put_if(not match?({:ok, _}, Ecto.UUID.cast(visitor || "")), :visitor_id, "invalid")
      |> put_if(version != current_banner_version, :banner_version, "outdated")

    if errors == %{} do
      {analytics, marketing} = choices(action, params)

      {:ok,
       %{
         visitor_id: visitor,
         banner_version: version,
         analytics: analytics,
         marketing: marketing,
         action: action,
         recorded_at: now,
         expires_at: DateTime.add(now, @validity_days * 86_400, :second)
       }}
    else
      {:error, {:invalid_fields, errors}}
    end
  end

  defp choices("accept_all", _params), do: {true, true}
  defp choices(action, _params) when action in ["reject_all", "withdraw"], do: {false, false}

  defp choices("custom", params),
    do: {Map.get(params, "analytics") == true, Map.get(params, "marketing") == true}

  defp put_if(errors, true, field, code), do: Map.put(errors, field, code)
  defp put_if(errors, _false, _field, _code), do: errors

  @doc """
  What a visitor's latest log row still allows now: `%{analytics, marketing}`,
  all false when there is none, it expired or the banner changed since.
  """
  def effective(nil, _banner_version, _now), do: %{analytics: false, marketing: false}

  def effective(consent, banner_version, now) do
    if consent.banner_version == banner_version and
         DateTime.compare(consent.expires_at, now) == :gt,
       do: %{analytics: consent.analytics, marketing: consent.marketing},
       else: %{analytics: false, marketing: false}
  end

  @doc """
  The tags that may load for a choice (ADR-354 §2): GA4 with analytics, the
  Meta Pixel with marketing, GTM with either (under Consent Mode defaults
  denied). Only tags the box set are listed.
  """
  def allowed_tags(tags, %{analytics: analytics, marketing: marketing}) do
    [
      {:ga4_measurement_id, analytics},
      {:meta_pixel_id, marketing},
      {:gtm_container_id, analytics or marketing}
    ]
    |> Enum.filter(fn {tag, allowed} -> allowed and Map.get(tags, tag) != nil end)
    |> Enum.map(&elem(&1, 0))
  end

  @doc "Log rows recorded before this moment are deleted."
  def retention_cutoff(now), do: DateTime.add(now, -@retention_days * 86_400, :second)
end
