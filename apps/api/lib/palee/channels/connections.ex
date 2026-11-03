defmodule Palee.Channels.Connections do
  @moduledoc """
  The box's messaging provider (ADR-348 §2, ADR-349).

  `account_mode`:

    * `palee` (the default; product owner, 2026-10-31) – Palee's own
      Brevo account (`config :palee, :channel_managed_accounts`). Palee
      pays Brevo and tracks each box's cost against its monthly cap; how
      boxes are charged for it is configuration (ADR-349 §4);
    * `own` – the box's own Brevo account. Brevo bills the box; its API
      key is encrypted at rest and never returned, logged or exported.

  Delivery receipts and inbound texts reach the box's own webhook URL,
  `/api/webhooks/channels/<organization>/<token>`. The token is an HMAC of
  the organization and a random salt kept on the connection, so the URL
  can be rebuilt for every message and changed by drawing a new salt.
  """

  alias Palee.Channels.ChannelStore
  alias Palee.Channels.Domain.{PhoneNumber, QuietHours}

  @account_modes ~w(own palee)
  @max_budget_cents 1_000_000

  def account_modes, do: @account_modes

  @doc "Configured providers (`%{name => adapter}`)."
  def providers, do: Application.get_env(:palee, :channel_providers, %{})

  @doc "The adapter of a provider."
  def adapter(provider), do: Map.fetch!(providers(), provider)

  @doc "Providers with a Palee-managed account."
  def managed_providers,
    do: :palee |> Application.get_env(:channel_managed_accounts, %{}) |> Map.keys() |> Enum.sort()

  @doc "What the settings screen offers: providers, their channels and modes."
  def catalog do
    providers()
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {name, adapter} ->
      %{
        provider: name,
        channels: adapter.channels(),
        account_modes:
          if(name in managed_providers() or name == "sandbox", do: @account_modes, else: ["own"])
      }
    end)
  end

  @doc "The connection with its decrypted secret, or nil (internal use only)."
  def get(context), do: ChannelStore.get_connection(context)

  @doc """
  The credentials and senders the adapter uses: the box's own, or the
  Palee-managed account's (the box's senders win when it set them).
  """
  def account(%{account_mode: "palee", provider: provider} = connection) do
    managed =
      :palee
      |> Application.get_env(:channel_managed_accounts, %{})
      |> Map.get(provider, [])
      |> Map.new()

    senders =
      connection
      |> Map.take([:sms_sender, :viber_sender, :whatsapp_sender])
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    managed
    |> Map.take([:account_id, :secret, :base_url, :sms_sender, :viber_sender, :whatsapp_sender])
    |> Map.merge(senders)
    |> Map.put(:provider, provider)
  end

  def account(connection) do
    connection
    |> Map.take([:account_id, :secret, :base_url, :sms_sender, :viber_sender, :whatsapp_sender])
    |> Map.put(:provider, connection.provider)
  end

  @doc "The connection as staff see it (never the secret)."
  def public(nil), do: nil

  def public(connection) do
    connection
    |> Map.take([
      :provider,
      :account_mode,
      :account_id,
      :base_url,
      :sms_sender,
      :viber_sender,
      :whatsapp_sender,
      :channels,
      :channel_order,
      :default_country,
      :monthly_budget_cents,
      :currency,
      :status,
      :error_code,
      :last_error,
      :checked_at,
      :updated_at
    ])
    |> Map.merge(%{
      quiet_start: QuietHours.format(connection.quiet_start_minute),
      quiet_end: QuietHours.format(connection.quiet_end_minute),
      has_secret: is_binary(connection.secret),
      webhook_url: webhook_url(connection)
    })
  end

  # ── Saving ──────────────────────────────────────────────────────────────

  @doc """
  Saves the connection. `params` (atom keys; missing keys keep what is
  saved): `provider`, `account_mode`, `account_id`, `secret` (kept when
  not sent), `base_url`, `sms_sender`, `viber_sender`, `whatsapp_sender`,
  `channels`, `channel_order`, `default_country`, `monthly_budget_cents`
  (required once any channel is on; no default, ADR-390), `quiet_start`
  and `quiet_end` (`"HH:MM"`, both nil for none, the default),
  `rotate_webhook` (true draws a new webhook URL).

  `{:ok, connection}` (the stored one) or `{:error, {:invalid_fields, errors}}`.
  """
  def save(context, params, actor_id) do
    before = get(context)

    with {:ok, attrs} <- validate(before, params) do
      attrs =
        attrs
        |> Map.put(:updated_by_id, actor_id)
        |> Map.put(:status, "active")
        |> Map.merge(%{error_code: nil, last_error: nil})
        |> put_salt(before, params[:rotate_webhook] == true)

      ChannelStore.save_connection(context, attrs)
    end
  end

  defp put_salt(attrs, before, rotate?) do
    if rotate? or is_nil(before) or is_nil(before.webhook_salt),
      do: Map.put(attrs, :webhook_salt, :crypto.strong_rand_bytes(24)),
      else: attrs
  end

  defp validate(before, params) do
    current = before || %{}

    value = fn key ->
      if Map.has_key?(params, key), do: params[key], else: Map.get(current, key)
    end

    provider = value.(:provider)
    mode = value.(:account_mode) || "palee"
    secret = clean(params[:secret]) || Map.get(current, :secret)
    adapter = Map.get(providers(), provider)
    channels = value.(:channels) || []
    order = value.(:channel_order) || ["sms", "viber", "whatsapp"]
    country = value.(:default_country) || "GR"
    # ADR-390: no invented cap; the box types its own before a channel goes on.
    budget = value.(:monthly_budget_cents)

    # ADR-390: quiet hours stay off until the box opens them.
    quiet =
      cond do
        Map.has_key?(params, :quiet_start) or Map.has_key?(params, :quiet_end) ->
          QuietHours.parse(params[:quiet_start], params[:quiet_end])

        before ->
          {:ok, {before.quiet_start_minute, before.quiet_end_minute}}

        true ->
          {:ok, {nil, nil}}
      end

    own_needs_secret? = mode == "own" and provider not in [nil, "sandbox"]

    errors =
      %{}
      |> add(is_nil(adapter), :provider, "invalid")
      |> add(mode not in @account_modes, :account_mode, "invalid")
      |> add(
        mode == "palee" and provider != "sandbox" and provider not in managed_providers(),
        :account_mode,
        "not_available"
      )
      |> add(own_needs_secret? and is_nil(secret), :secret, "required")
      |> add(is_binary(secret) and String.length(secret) > 300, :secret, "too_long")
      |> add(not channel_list?(channels, adapter), :channels, "invalid")
      |> add(not channel_list?(order, nil), :channel_order, "invalid")
      |> add(country not in PhoneNumber.countries(), :default_country, "invalid")
      |> add(
        is_list(channels) and channels != [] and is_nil(budget),
        :monthly_budget_cents,
        "required"
      )
      |> add(
        not (is_nil(budget) or
               (is_integer(budget) and budget >= 0 and budget <= @max_budget_cents)),
        :monthly_budget_cents,
        "invalid"
      )
      |> add(match?({:error, _}, quiet), :quiet_hours, "invalid")
      |> add(not sms_sender?(clean(value.(:sms_sender))), :sms_sender, "invalid")
      |> add(not short_text?(clean(value.(:viber_sender)), 60), :viber_sender, "invalid")
      |> add(not short_text?(clean(value.(:whatsapp_sender)), 30), :whatsapp_sender, "invalid")
      |> add(
        sender_missing?(channels, "sms", value.(:sms_sender), provider),
        :sms_sender,
        "required"
      )
      |> add(
        sender_missing?(channels, "viber", value.(:viber_sender), provider),
        :viber_sender,
        "required"
      )
      |> add(
        sender_missing?(channels, "whatsapp", value.(:whatsapp_sender), provider),
        :whatsapp_sender,
        "required"
      )

    if errors == %{} do
      {:ok, {start, finish}} = quiet

      attrs = %{
        provider: provider,
        account_mode: mode,
        account_id: if(mode == "own", do: clean(value.(:account_id))),
        base_url: if(mode == "own", do: clean(value.(:base_url))),
        sms_sender: clean(value.(:sms_sender)),
        viber_sender: clean(value.(:viber_sender)),
        whatsapp_sender: clean(value.(:whatsapp_sender)),
        channels: Enum.uniq(channels),
        channel_order: Enum.uniq(order),
        default_country: country,
        monthly_budget_cents: budget,
        quiet_start_minute: start,
        quiet_end_minute: finish
      }

      {:ok,
       if(mode == "own", do: Map.put(attrs, :secret, secret), else: Map.put(attrs, :secret, nil))}
    else
      {:error, {:invalid_fields, errors}}
    end
  end

  defp channel_list?(list, adapter) when is_list(list) do
    allowed = if adapter, do: adapter.channels(), else: ~w(sms viber whatsapp)
    Enum.all?(list, &(&1 in allowed))
  end

  defp channel_list?(_list, _adapter), do: false

  # The sandbox needs no sender; a real provider needs one per channel.
  defp sender_missing?(_channels, _channel, _sender, "sandbox"), do: false

  defp sender_missing?(channels, channel, sender, _provider),
    do: is_list(channels) and channel in channels and is_nil(clean(sender))

  # An alphanumeric sender (up to 11 letters, digits or spaces with at least
  # one letter) or a number in E.164.
  defp sms_sender?(nil), do: true
  defp sms_sender?("+" <> digits), do: digits =~ ~r/^[1-9][0-9]{7,14}$/
  defp sms_sender?(sender), do: alphanumeric_sender?(sender)

  defp alphanumeric_sender?(sender),
    do: sender =~ ~r/^[A-Za-z0-9 ]{1,11}$/ and sender =~ ~r/[A-Za-z]/

  defp short_text?(nil, _max), do: true
  defp short_text?(value, max), do: String.length(value) <= max

  defp add(errors, true, field, code), do: Map.put_new(errors, field, code)
  defp add(errors, false, _field, _code), do: errors

  defp clean(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp clean(_value), do: nil

  # ── Checking ────────────────────────────────────────────────────────────

  @doc """
  «Δοκιμή σύνδεσης»: asks the provider something harmless with the
  connection's credentials and records the answer. `{:ok, %{ok, error_code,
  details}}` or `{:error, :channels_not_connected}`.
  """
  def check(context, %DateTime{} = now) do
    case get(context) do
      nil ->
        {:error, :channels_not_connected}

      connection ->
        result = adapter(connection.provider).check(account(connection))

        {status, code, details} =
          case result do
            {:ok, details} -> {"active", nil, details}
            {:error, {:unauthorized, _detail}} -> {"invalid", "credentials_rejected", %{}}
            {:error, _other} -> {connection.status, "provider_unavailable", %{}}
          end

        {:ok, _saved} =
          ChannelStore.save_connection(context, %{
            status: status,
            error_code: code,
            last_error: code,
            checked_at: now
          })

        {:ok, %{ok: is_nil(code), error_code: code, details: details}}
    end
  end

  @doc "Marks the connection invalid after the provider refused its credentials."
  def mark_invalid(context, code) do
    ChannelStore.save_connection(context, %{status: "invalid", error_code: code, last_error: code})

    :ok
  end

  # ── Webhook URL ─────────────────────────────────────────────────────────

  @doc "The box's webhook URL, or nil before the connection is saved."
  def webhook_url(%{organization_id: organization_id, webhook_salt: salt}) when is_binary(salt) do
    base = :palee |> Application.fetch_env!(:public_base_url) |> String.trim_trailing("/")
    base <> "/api/webhooks/channels/#{organization_id}/#{webhook_token(organization_id, salt)}"
  end

  def webhook_url(_connection), do: nil

  @doc "Whether `token` is the current webhook token of the connection."
  def valid_webhook_token?(%{organization_id: organization_id, webhook_salt: salt}, token)
      when is_binary(salt) and is_binary(token) do
    expected = webhook_token(organization_id, salt)
    byte_size(expected) == byte_size(token) and Plug.Crypto.secure_compare(expected, token)
  end

  def valid_webhook_token?(_connection, _token), do: false

  defp webhook_token(organization_id, salt) do
    key = Application.fetch_env!(:palee, :channels_webhook_key)

    :hmac
    |> :crypto.mac(:sha256, key, organization_id <> ":" <> salt)
    |> binary_part(0, 24)
    |> Base.url_encode64(padding: false)
  end
end
