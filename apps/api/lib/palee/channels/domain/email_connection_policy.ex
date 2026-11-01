defmodule Palee.Channels.Domain.EmailConnectionPolicy do
  @moduledoc """
  The rules of a box's own email provider over SMTP (ADR-368).

  Every email provider speaks SMTP, so one connection shape fits all of
  them: a host, a port, a TLS mode, a user name and a password, the address
  and name the box's emails come from and an optional reply-to.

    * TLS is never optional: `starttls` (587, 25, 2525: the connection is
      upgraded before logging in) or `tls` (465: TLS from the first byte).
      The server's certificate is verified against the host name.
    * Only the ports mail providers use are accepted (25, 465, 587, 2525),
      and the host must be a public name, never an address, `localhost` or
      an internal domain, so the check cannot be pointed at Palee's own
      network.
    * Which emails may use it is decided by the email's template
      (`Palee.Email.Template` `origin: :box`): the box's own messages
      (automations, receipts and invoices it sends). The platform's mail
      (verification, password reset, security notices, invitations to Palee
      accounts) always goes through Palee.
  """

  @ports [25, 465, 587, 2525]
  @tls_modes ~w(starttls tls)
  @statuses ~w(unchecked active invalid)

  @internal_suffixes ~w(.local .localhost .internal .intranet .lan .home .corp .svc .cluster.local
                        .test .example .invalid)

  def ports, do: @ports
  def tls_modes, do: @tls_modes
  def statuses, do: @statuses

  @doc "The port that usually goes with a TLS mode."
  def default_port("tls"), do: 465
  def default_port(_starttls), do: 587

  @doc """
  Validates what staff save, merged over what is saved (`current`, a map or
  nil). The password is kept when not sent. `{:ok, attrs}` or
  `{:error, {:invalid_fields, errors}}`.
  """
  def validate(current, params) do
    current = current || %{}

    value = fn key ->
      if Map.has_key?(params, key), do: clean(params[key]), else: Map.get(current, key)
    end

    host = value.(:host) |> downcase()
    tls_mode = value.(:tls_mode) || "starttls"
    port = value.(:port) || default_port(tls_mode)
    username = value.(:username)
    secret = clean(params[:secret]) || Map.get(current, :secret)
    from_address = value.(:from_address) |> downcase()
    from_name = value.(:from_name)
    reply_to = value.(:reply_to) |> downcase()

    enabled =
      if is_boolean(params[:enabled]),
        do: params[:enabled],
        else: Map.get(current, :enabled, true)

    errors =
      %{}
      |> add(not host_allowed?(host), :host, if(is_nil(host), do: "required", else: "invalid"))
      |> add(port not in @ports, :port, "invalid")
      |> add(tls_mode not in @tls_modes, :tls_mode, "invalid")
      |> add(is_nil(username), :username, "required")
      |> add(is_binary(username) and not header_safe?(username, 254), :username, "invalid")
      |> add(is_nil(secret), :secret, "required")
      |> add(is_binary(secret) and String.length(secret) > 500, :secret, "too_long")
      |> add(is_nil(from_address), :from_address, "required")
      |> add(is_binary(from_address) and not address?(from_address), :from_address, "invalid")
      |> add(is_binary(from_name) and not header_safe?(from_name, 120), :from_name, "invalid")
      |> add(is_binary(reply_to) and not address?(reply_to), :reply_to, "invalid")

    if errors == %{} do
      attrs = %{
        host: host,
        port: port,
        tls_mode: tls_mode,
        username: username,
        secret: secret,
        from_address: from_address,
        from_name: from_name,
        reply_to: reply_to,
        enabled: enabled
      }

      {:ok, Map.put(attrs, :status, status_after_save(current, attrs))}
    else
      {:error, {:invalid_fields, errors}}
    end
  end

  # A change to where or how Palee logs in needs a new check before mail goes
  # through it; renaming the sender or switching it on and off does not.
  @connection_keys [:host, :port, :tls_mode, :username, :secret]

  defp status_after_save(current, attrs) do
    unchanged? = Enum.all?(@connection_keys, &(Map.get(current, &1) == Map.get(attrs, &1)))

    case Map.get(current, :status) do
      status when unchanged? and status in ["active", "invalid"] -> status
      _changed -> "unchecked"
    end
  end

  @doc "Whether mail may go through the connection now: switched on and checked."
  def usable?(%{enabled: true, status: "active"}), do: true
  def usable?(_connection), do: false

  @doc """
  Whether `host` is a public host name (not an IP address, `localhost` or an
  internal or reserved domain).
  """
  def host_allowed?(host) when is_binary(host) do
    labels = String.split(host, ".")

    byte_size(host) <= 253 and length(labels) >= 2 and
      Enum.all?(labels, &(&1 =~ ~r/^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/)) and
      not (List.last(labels) =~ ~r/^[0-9]+$/) and
      not Enum.any?(@internal_suffixes, &String.ends_with?("." <> host, &1)) and
      host not in ["localhost", "example.com", "example.org", "example.net"]
  end

  def host_allowed?(_host), do: false

  @doc """
  Whether an IP address (a tuple from `:inet`) is one the SMTP adapter may
  connect to: no loopback, private, link-local, shared or reserved range.
  """
  def public_address?({a, b, _c, _d}) do
    not (a in [0, 10, 127] or a >= 224 or (a == 100 and b in 64..127) or
           (a == 169 and b == 254) or (a == 172 and b in 16..31) or (a == 192 and b == 168) or
           (a == 198 and b in 18..19))
  end

  def public_address?({first, _, _, _, _, _, _, _} = address) do
    not (address in [{0, 0, 0, 0, 0, 0, 0, 0}, {0, 0, 0, 0, 0, 0, 0, 1}] or
           Bitwise.band(first, 0xFE00) == 0xFC00 or Bitwise.band(first, 0xFFC0) == 0xFE80 or
           Bitwise.band(first, 0xFF00) == 0xFF00 or
           match?({0, 0, 0, 0, 0, 0xFFFF, _, _}, address))
  end

  def public_address?(_address), do: false

  @doc """
  The DNS records the box should have so its mail is not marked as spam, as
  message keys the guide screen translates (`email_dns.*`), with the sender
  domain to fill in.
  """
  def dns_guidance(connection) do
    domain =
      case connection && connection.from_address do
        address when is_binary(address) -> address |> String.split("@") |> List.last()
        _none -> nil
      end

    %{
      domain: domain,
      steps: [
        %{key: "email_dns.spf", record: "TXT", host: domain},
        %{
          key: "email_dns.dkim",
          record: "TXT",
          host: domain && "<selector>._domainkey." <> domain
        },
        %{key: "email_dns.dmarc", record: "TXT", host: domain && "_dmarc." <> domain},
        %{key: "email_dns.same_domain", record: nil, host: nil}
      ]
    }
  end

  @doc "The address part is one `local@domain.tld` with no spaces or line breaks."
  def address?(value) when is_binary(value),
    do:
      byte_size(value) <= 254 and
        value =~
          ~r/^[a-z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/

  def address?(_value), do: false

  defp header_safe?(value, max), do: String.length(value) <= max and not (value =~ ~r/[\r\n\x00]/)

  defp add(errors, true, field, code), do: Map.put_new(errors, field, code)
  defp add(errors, false, _field, _code), do: errors

  defp downcase(nil), do: nil
  defp downcase(value), do: String.downcase(value)

  defp clean(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp clean(value) when is_integer(value) or is_boolean(value), do: value
  defp clean(_value), do: nil
end
