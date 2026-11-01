defmodule Palee.Channels.EmailConnections do
  @moduledoc """
  The box's own email provider over SMTP (ADR-368), the advanced option:
  by default Palee sends the box's email itself.

  When the connection is switched on and its last «Δοκιμή σύνδεσης»
  passed (`status: active`), the box's own email (automations, receipts,
  invoices: templates with `origin: :box`) goes out through it, from the
  box's address. Otherwise, or when the provider refuses the password, it
  goes through Palee's mailer as before. Platform mail never uses it.

  The password is encrypted at rest (`EncryptedBinary`) and is never
  returned (`has_secret` only), logged, journaled or exported.
  """

  alias Palee.Channels.ChannelStore
  alias Palee.Channels.Domain.EmailConnectionPolicy

  defp transport, do: Application.fetch_env!(:palee, :channel_email_transport)

  @doc "The connection with its decrypted password, or nil (internal use only)."
  def get(context), do: ChannelStore.get_email_connection(context)

  @doc "The connection as staff see it (never the password)."
  def public(nil), do: nil

  def public(connection) do
    connection
    |> Map.take([
      :host,
      :port,
      :tls_mode,
      :username,
      :from_address,
      :from_name,
      :reply_to,
      :enabled,
      :status,
      :error_code,
      :checked_at,
      :updated_at
    ])
    |> Map.merge(%{
      has_secret: is_binary(connection.secret),
      in_use: EmailConnectionPolicy.usable?(connection)
    })
  end

  @doc "What the settings screen offers: ports, TLS modes and the DNS guide."
  def options(connection) do
    %{
      ports: EmailConnectionPolicy.ports(),
      tls_modes: EmailConnectionPolicy.tls_modes(),
      dns_guidance: EmailConnectionPolicy.dns_guidance(connection)
    }
  end

  @doc """
  Saves the connection. `params` (atom keys; missing keys keep what is
  saved): `host`, `port`, `tls_mode`, `username`, `secret` (kept when not
  sent), `from_address`, `from_name`, `reply_to`, `enabled`. A change to the
  host, port, TLS mode, user name or password needs a new check
  (`status: unchecked`) before mail goes through it.

  `{:ok, connection}` or `{:error, {:invalid_fields, errors}}`.
  """
  def save(context, params, actor_id) do
    with {:ok, attrs} <- EmailConnectionPolicy.validate(get(context), params) do
      attrs =
        if attrs.status == "unchecked",
          do: Map.merge(attrs, %{error_code: nil, checked_at: nil}),
          else: attrs

      ChannelStore.save_email_connection(context, Map.put(attrs, :updated_by_id, actor_id))
    end
  end

  @doc "Removes the connection: the box's email goes through Palee again."
  def delete(context), do: ChannelStore.delete_email_connection(context)

  @doc """
  «Δοκιμή σύνδεσης»: connects, logs in and quits without sending, then
  records the answer. `{:ok, %{ok, error_code}}` or
  `{:error, :email_connection_missing}`.
  """
  def check(context, %DateTime{} = now) do
    case get(context) do
      nil ->
        {:error, :email_connection_missing}

      connection ->
        {status, code} =
          case transport().check(smtp(connection)) do
            {:ok, _details} -> {"active", nil}
            {:error, reason} -> {"invalid", error_code(reason)}
          end

        {:ok, _saved} =
          ChannelStore.save_email_connection(context, %{
            status: status,
            error_code: code,
            checked_at: now
          })

        {:ok, %{ok: is_nil(code), error_code: code}}
    end
  end

  @doc """
  Sends one rendered outbox email through the box's SMTP when it may be
  used. `{:ok, receipt}`, `{:error, reason}` (the outbox retries or gives
  up, see `Ports.EmailTransport`) or `:unavailable` (not connected, switched
  off, unchecked, or the provider just refused the password, which marks
  the connection invalid): the caller sends through Palee instead.
  """
  def deliver(context, email) do
    connection = get(context)

    if connection && EmailConnectionPolicy.usable?(connection) do
      case transport().deliver(smtp(connection), email) do
        {:ok, receipt} ->
          {:ok, receipt}

        {:error, :unauthorized} ->
          mark_invalid(context, "credentials_rejected")
          :unavailable

        {:error, :host_not_allowed} ->
          mark_invalid(context, "host_not_allowed")
          :unavailable

        {:error, reason} ->
          {:error, reason}
      end
    else
      :unavailable
    end
  end

  defp mark_invalid(context, code) do
    {:ok, _saved} =
      ChannelStore.save_email_connection(context, %{status: "invalid", error_code: code})

    :ok
  end

  defp smtp(connection),
    do:
      Map.take(connection, [
        :host,
        :port,
        :tls_mode,
        :username,
        :secret,
        :from_address,
        :from_name,
        :reply_to
      ])

  defp error_code(:unauthorized), do: "credentials_rejected"
  defp error_code(:host_not_allowed), do: "host_not_allowed"
  defp error_code({:transient, :tls_failed}), do: "tls_failed"
  defp error_code({:transient, :timeout}), do: "timeout"
  defp error_code({:transient, :unreachable}), do: "unreachable"
  defp error_code(_other), do: "provider_unavailable"
end
