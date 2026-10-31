defmodule Palee.Application.Channels.ChannelSettings do
  @moduledoc """
  Staff › Ρυθμίσεις › Μηνύματα SMS/Viber (ADR-348/349/350): the provider
  connection, «Δοκιμή σύνδεσης», the month's cost against the budget cap,
  quiet hours and the wording of messages. The secret is never returned.
  """

  alias Palee.Application.Channels.SendThroughChannel
  alias Palee.Channels

  @doc "`%{connection, providers, usage}`."
  def show(context, now \\ DateTime.utc_now()) do
    {:ok, usage} = Channels.usage(context, nil, SendThroughChannel.env(context, now))

    %{
      connection: context |> Channels.connection() |> Channels.public_connection(),
      providers: Channels.provider_catalog(),
      usage: usage
    }
  end

  @doc "Saves the connection, then checks it: `{:ok, %{connection, check}}`."
  def save(context, params, now \\ DateTime.utc_now()) do
    attrs =
      [
        :provider,
        :account_mode,
        :account_id,
        :secret,
        :base_url,
        :sms_sender,
        :viber_sender,
        :whatsapp_sender,
        :channels,
        :channel_order,
        :default_country,
        :monthly_budget_cents,
        :quiet_start,
        :quiet_end,
        :rotate_webhook
      ]
      |> Enum.filter(&has?(params, &1))
      |> Map.new(&{&1, param(params, &1)})

    with {:ok, _saved} <- Channels.save_connection(context, attrs, Map.get(context, :user_id)),
         {:ok, check} <- Channels.check_connection(context, now) do
      SendThroughChannel.schedule(context)

      {:ok,
       %{
         connection: context |> Channels.connection() |> Channels.public_connection(),
         check: check
       }}
    end
  end

  @doc "«Δοκιμή σύνδεσης» again."
  def check(context, now \\ DateTime.utc_now()) do
    with {:ok, check} <- Channels.check_connection(context, now) do
      {:ok,
       %{
         connection: context |> Channels.connection() |> Channels.public_connection(),
         check: check
       }}
    end
  end

  @doc "The spend of a month (`YYYY-MM`, the box's clock) against the cap."
  def usage(context, params, now \\ DateTime.utc_now()),
    do: Channels.usage(context, param(params, :month), SendThroughChannel.env(context, now))

  def templates(context), do: %{templates: Channels.list_templates(context)}

  def save_template(context, key, params) do
    attrs =
      [:locale, :channel, :body, :provider_template_id, :approval_status, :variable_names]
      |> Map.new(&{&1, param(params, &1)})
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    Channels.save_template(context, key, attrs, Map.get(context, :user_id))
  end

  def delete_template(context, key, params) do
    Channels.delete_template(context, key, param(params, :locale), param(params, :channel))
  end

  defp has?(params, key), do: Map.has_key?(params, key) or Map.has_key?(params, Atom.to_string(key))

  defp param(params, key) when is_map(params),
    do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end
