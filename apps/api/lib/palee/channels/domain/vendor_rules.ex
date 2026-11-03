defmodule Palee.Channels.Domain.VendorRules do
  @moduledoc """
  What each SMS vendor a box may bring itself needs (ADR-396): the
  credential fields, how they look, and which senders the vendor takes.
  Pure; `Channels.Connections` asks it while saving.

  | Vendor  | `account_id`       | `secret`     | `base_url`                     | `webhook_secret` |
  |---------|--------------------|--------------|--------------------------------|------------------|
  | brevo   | –                  | API key      | –                              | –                |
  | twilio  | Account SID (AC…)  | Auth Token   | –                              | –                |
  | vonage  | API key            | API secret   | –                              | signature secret (optional) |
  | infobip | –                  | API key      | `https://<id>.api.infobip.com` | –                |
  | yuboto  | –                  | OMNI API key | –                              | –                |
  | apifon  | API token          | secret key   | –                              | –                |

  Senders (ADR-349/390 kept for every vendor): up to 11 Latin letters,
  digits or spaces with at least one letter, or a number in E.164. Twilio
  also takes a Messaging Service SID (`MG…`), which picks the sender itself.
  """

  @vendors ~w(brevo twilio vonage infobip yuboto apifon)

  @doc "The vendors a box may bring itself."
  def vendors, do: @vendors

  @doc "Whether `provider` is one of them."
  def vendor?(provider), do: provider in @vendors

  @doc "The credential fields a vendor needs, required ones first."
  def required(provider) do
    case provider do
      "twilio" -> [:account_id, :secret]
      "vonage" -> [:account_id, :secret]
      "infobip" -> [:secret, :base_url]
      "apifon" -> [:account_id, :secret]
      _brevo_or_yuboto -> [:secret]
    end
  end

  @doc "The fields a vendor uses at all (the others are cleared on save)."
  def fields("vonage"), do: [:account_id, :secret, :webhook_secret]
  def fields(provider), do: required(provider)

  @doc """
  Field errors of the credentials (`%{field => code}`) for a vendor: a
  missing required one is `required`, a malformed one `invalid`.
  """
  def credential_errors(provider, credentials) do
    provider
    |> fields()
    |> Enum.reduce(%{}, fn field, errors ->
      value = Map.get(credentials, field)

      cond do
        is_nil(value) and field in required(provider) -> Map.put(errors, field, "required")
        is_nil(value) -> errors
        valid?(provider, field, value) -> errors
        true -> Map.put(errors, field, "invalid")
      end
    end)
  end

  defp valid?("twilio", :account_id, sid), do: sid =~ ~r/^AC[0-9a-fA-F]{32}$/
  defp valid?(_provider, :base_url, url), do: infobip_base_url?(url)
  defp valid?(_provider, :secret, secret), do: String.length(secret) <= 300
  defp valid?(_provider, _field, value), do: String.length(value) <= 120

  @doc """
  Infobip's personal base URL: `https://<id>.api.infobip.com` (no path). Only
  Infobip's own hosts, so a box cannot point Palee's calls anywhere else.
  """
  def infobip_base_url?(url) when is_binary(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: "https", host: host, path: path, query: nil, userinfo: nil, port: 443}}
      when is_binary(host) and path in [nil, "", "/"] ->
        host =~ ~r/^[a-z0-9-]+\.api\.infobip\.com$/

      _other ->
        false
    end
  end

  def infobip_base_url?(_url), do: false

  @doc "Whether the vendor takes `sender` (nil is no sender)."
  def sender?(_provider, nil), do: true

  def sender?("twilio", "MG" <> rest) when byte_size(rest) == 32,
    do: rest =~ ~r/^[0-9a-fA-F]{32}$/

  def sender?(_provider, "+" <> digits), do: digits =~ ~r/^[1-9][0-9]{7,14}$/

  def sender?(_provider, sender),
    do: sender =~ ~r/^[A-Za-z0-9 ]{1,11}$/ and sender =~ ~r/[A-Za-z]/
end
