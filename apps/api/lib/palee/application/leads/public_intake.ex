defmodule Palee.Application.Leads.PublicIntake do
  @moduledoc """
  ADR-345: the box's public «Ενδιαφέρομαι» form and join links
  (`PaleeWeb.PublicLeadController`), for people without a Palee account.
  Only a published box page (ADR-142) takes enquiries, by its slug or a
  former one.

  What protects it: a rate limit per address in front (router), the spam
  rules of `IntakePolicy.spam_check/2` (hidden field, too fast, links), and
  required contact consent with the version of the text shown. Spam gets
  the same answer as a real enquiry and stores nothing. The answer never
  says whether the address was known to the box.
  """

  require Logger

  alias Palee.Application.Leads.CaptureLead
  alias Palee.{Leads, Organizations}

  @public_sources ~w(form join_link)

  @doc "`{:ok, :received}` or `{:error, :not_found | {:invalid_fields, map}}`."
  def call(slug, params, now \\ Leads.now()) when is_binary(slug) and is_map(params) do
    with %{organization_id: organization_id} <-
           Organizations.public_box_by_slug(slug) || {:error, :not_found},
         :ok <- not_spam(params, now),
         {:ok, _result} <-
           CaptureLead.call(%{organization_id: organization_id}, attrs(params), now: now) do
      {:ok, :received}
    else
      :spam -> {:ok, :received}
      {:error, _reason} = error -> error
    end
  end

  defp not_spam(params, now) do
    case Leads.spam_check(params, now) do
      :ok ->
        :ok

      {:error, :spam} ->
        :telemetry.execute([:palee, :leads, :spam], %{count: 1}, %{})
        :spam
    end
  end

  defp attrs(params) do
    source = if params["source"] in @public_sources, do: params["source"], else: "form"

    %{
      "name" => params["name"],
      "email" => params["email"],
      "phone" => params["phone"],
      "message" => params["message"],
      "locale" => params["locale"],
      "interests" => params["interests"],
      "campaign" => params["campaign"],
      "source" => source,
      "consent" => params["consent"],
      "details" => %{"kind" => params["kind"], "preferred_time" => params["preferred_time"]}
    }
  end
end
