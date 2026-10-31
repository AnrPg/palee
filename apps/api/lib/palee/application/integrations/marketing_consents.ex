defmodule Palee.Application.Integrations.MarketingConsents do
  @moduledoc """
  A member's own yes or no to the box's marketing email (ADR-380, GDPR art.
  6(1)(a) and 7): off by default, asked in plain words, as easy to take back
  as to give, and never set by staff. A change syncs the box's list soon,
  when the box has one.
  """

  alias Palee.Application.Integrations.AudienceSync
  alias Palee.{Integrations, Organizations}

  def show(context),
    do:
      Map.put(
        Integrations.consent(context, context.user_id),
        :list_connected,
        connected?(context)
      )

  @doc "`{:ok, consent}`; `granted` must be true or false."
  def update(context, params, now \\ DateTime.utc_now()) do
    granted = Map.get(params, :granted, Map.get(params, "granted"))

    with :member <- Organizations.membership_standing(context.organization_id, context.user_id),
         {:ok, consent} <-
           Integrations.set_consent(context, context.user_id, granted, "member_app", now) do
      if connected?(context) do
        with :ok <- Integrations.request_sync(context, now), do: AudienceSync.schedule(context)
      end

      {:ok, Map.put(consent, :list_connected, connected?(context))}
    else
      {:error, _reason} = error -> error
      _not_member -> {:error, :forbidden}
    end
  end

  defp connected?(context), do: not is_nil(Integrations.connection(context))
end
