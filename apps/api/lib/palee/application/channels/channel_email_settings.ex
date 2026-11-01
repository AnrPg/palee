defmodule Palee.Application.Channels.ChannelEmailSettings do
  @moduledoc """
  Staff › Ρυθμίσεις › «Δικός μου πάροχος email» (ADR-368), the advanced
  option: by default Palee sends the box's email. The box's own SMTP
  provider (host, port, TLS, user name, password, sender, reply-to),
  «Δοκιμή σύνδεσης» and the DNS records the guide reminds the box of. The
  password is never returned.
  """

  alias Palee.Channels

  @fields [
    :host,
    :port,
    :tls_mode,
    :username,
    :secret,
    :from_address,
    :from_name,
    :reply_to,
    :enabled
  ]

  @doc "`%{connection, ports, tls_modes, dns_guidance}` (connection nil: Palee sends)."
  def show(context) do
    connection = Channels.email_connection(context)

    connection
    |> Channels.email_connection_options()
    |> Map.put(:connection, Channels.public_email_connection(connection))
  end

  @doc "Saves the connection (it needs a check before mail goes through it): `{:ok, show}`."
  def save(context, params) do
    attrs =
      @fields
      |> Enum.filter(&has?(params, &1))
      |> Map.new(&{&1, param(params, &1)})

    with {:ok, _saved} <-
           Channels.save_email_connection(context, attrs, Map.get(context, :user_id)) do
      {:ok, show(context)}
    end
  end

  @doc "«Δοκιμή σύνδεσης»: connect, log in, quit; nothing is sent. `{:ok, %{connection, check}}`."
  def check(context, now \\ DateTime.utc_now()) do
    with {:ok, check} <- Channels.check_email_connection(context, now) do
      {:ok,
       %{
         connection: context |> Channels.email_connection() |> Channels.public_email_connection(),
         check: check
       }}
    end
  end

  @doc "Removes the box's own provider: its email goes through Palee again."
  def delete(context), do: Channels.delete_email_connection(context)

  defp has?(params, key),
    do: Map.has_key?(params, key) or Map.has_key?(params, Atom.to_string(key))

  defp param(params, key) when is_map(params),
    do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end
