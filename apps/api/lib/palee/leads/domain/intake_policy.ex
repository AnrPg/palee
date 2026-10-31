defmodule Palee.Leads.Domain.IntakePolicy do
  @moduledoc """
  ADR-345: what a lead must carry to be kept, and how the public form is
  protected from spam. Pure.

  **Normalising.** Names are trimmed and at most 120 characters, emails
  lowercased and checked, phones kept as `+` and digits (7 to 16 digits),
  messages at most 2,000 characters. A lead needs a name and an email or a
  phone; nothing else is required (data minimisation).

  **Consent.** Contact consent is what lets the box answer the enquiry; it
  is required on every inbound source and implied when staff type a lead in
  (they spoke to the person). Marketing consent is separate and optional:
  only with it do marketing recipes (birthday, win-back) reach a lead. Both
  record the moment, plus the version and hash of the text the person saw.

  **Spam (public form only).** A request is spam when the hidden field is
  filled (`website`), when it was sent less than `min_fill_seconds/0` after
  the form opened, or when the name holds a link or the message more than
  two. Spam is answered like a success so bots learn nothing; nothing is
  stored. Rate limits per address sit in front of the endpoint.
  """

  @max_name 120
  @max_message 2_000
  @max_ref 200
  @min_fill_seconds 3
  @max_links 2
  @email ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/
  @link ~r/(https?:\/\/|www\.)/i

  def min_fill_seconds, do: @min_fill_seconds

  @doc """
  Normalised lead fields from caller input (atom or string keys), or
  `{:error, {:invalid_fields, %{field => reason}}}`.
  """
  @spec normalize(map()) :: {:ok, map()} | {:error, {:invalid_fields, map()}}
  def normalize(attrs) when is_map(attrs) do
    name = attrs |> get(:name) |> clean() |> truncate(@max_name)
    email = attrs |> get(:email) |> clean() |> downcase()
    phone = attrs |> get(:phone) |> phone()

    errors =
      %{}
      |> require_name(name)
      |> check_email(email)
      |> check_phone(attrs |> get(:phone) |> clean(), phone)
      |> require_contact(email, phone)

    if errors == %{} do
      {:ok,
       %{
         name: name,
         email: email,
         phone: phone,
         message: attrs |> get(:message) |> clean() |> truncate(@max_message),
         locale: attrs |> get(:locale) |> clean() |> truncate(8),
         source_ref: attrs |> get(:source_ref) |> clean() |> truncate(@max_ref),
         campaign: attrs |> get(:campaign) |> clean() |> truncate(@max_ref),
         interests: interests(get(attrs, :interests))
       }}
    else
      {:error, {:invalid_fields, errors}}
    end
  end

  def normalize(_attrs), do: {:error, {:invalid_fields, %{"name" => "required"}}}

  @doc """
  The consent fields to store from caller input `consent` (`contact`,
  `marketing`, `text_version`, `text_hash`, `given_at`) at `now`. Inbound
  sources must carry contact consent; staff-entered ones imply it.
  """
  @spec consent(map() | nil, String.t(), DateTime.t()) ::
          {:ok, map()} | {:error, {:invalid_fields, map()}}
  def consent(consent, source, now) do
    consent = consent || %{}
    given_at = given_at(get(consent, :given_at), now)
    contact? = truthy?(get(consent, :contact))

    if inbound?(source) and not contact? do
      {:error, {:invalid_fields, %{"consent" => "contact_required"}}}
    else
      {:ok,
       %{
         consent_contact_at: given_at,
         consent_marketing_at: if(truthy?(get(consent, :marketing)), do: given_at),
         consent_text_version: consent |> get(:text_version) |> clean() |> truncate(40),
         consent_text_hash: consent |> get(:text_hash) |> clean() |> truncate(128)
       }}
    end
  end

  @doc "Whether a lead from this source came in by itself (consent required)."
  def inbound?(source), do: source in Palee.Leads.Domain.Pipeline.inbound_sources()

  @doc """
  `:ok`, or `{:error, :spam}` for a public form submission. `started_at` is
  when the form opened (ISO 8601 or unix seconds), as the page sent it.
  """
  @spec spam_check(map(), DateTime.t()) :: :ok | {:error, :spam}
  def spam_check(params, now) do
    cond do
      present?(get(params, :website)) -> {:error, :spam}
      too_fast?(get(params, :form_started_at), now) -> {:error, :spam}
      links(get(params, :name)) > 0 -> {:error, :spam}
      links(get(params, :message)) > @max_links -> {:error, :spam}
      true -> :ok
    end
  end

  defp too_fast?(nil, _now), do: false

  defp too_fast?(started, now) do
    case started_at(started) do
      %DateTime{} = at -> DateTime.diff(now, at) < @min_fill_seconds
      nil -> false
    end
  end

  defp started_at(value) when is_integer(value), do: from_unix(value)

  defp started_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} ->
        at

      _error ->
        case Integer.parse(value) do
          {seconds, ""} -> from_unix(seconds)
          _other -> nil
        end
    end
  end

  defp started_at(_value), do: nil

  defp from_unix(seconds) do
    case DateTime.from_unix(seconds) do
      {:ok, at} -> at
      _error -> nil
    end
  end

  defp links(text) when is_binary(text), do: @link |> Regex.scan(text) |> length()
  defp links(_text), do: 0

  defp require_name(errors, nil), do: Map.put(errors, "name", "required")
  defp require_name(errors, _name), do: errors

  defp check_email(errors, nil), do: errors

  defp check_email(errors, email),
    do:
      if(Regex.match?(@email, email) and byte_size(email) <= 254,
        do: errors,
        else: Map.put(errors, "email", "invalid")
      )

  defp check_phone(errors, nil, _phone), do: errors
  defp check_phone(errors, _raw, nil), do: Map.put(errors, "phone", "invalid")
  defp check_phone(errors, _raw, _phone), do: errors

  defp require_contact(errors, nil, nil) do
    if Map.has_key?(errors, "email") or Map.has_key?(errors, "phone"),
      do: errors,
      else: Map.put(errors, "contact", "email_or_phone_required")
  end

  defp require_contact(errors, _email, _phone), do: errors

  @doc "A phone as `+` and digits, or nil when it is not one."
  def phone(value) when is_binary(value) do
    trimmed = String.trim(value)
    plus = if String.starts_with?(trimmed, "+"), do: "+", else: ""
    digits = String.replace(trimmed, ~r/[^\d]/u, "")
    allowed? = Regex.match?(~r/^\+?[\d\s().\-\/]+$/u, trimmed)

    if allowed? and String.length(digits) in 7..16, do: plus <> digits, else: nil
  end

  def phone(_value), do: nil

  defp interests(list) when is_list(list) do
    list
    |> Enum.map(&clean/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&truncate(&1, 40))
    |> Enum.uniq()
    |> Enum.take(10)
  end

  defp interests(_other), do: []

  defp given_at(%DateTime{} = at, _now), do: at

  defp given_at(value, now) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> if DateTime.compare(at, now) == :gt, do: now, else: at
      _error -> now
    end
  end

  defp given_at(_value, now), do: now

  defp truthy?(value), do: value in [true, "true", "1", 1, "on", "yes"]

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(nil), do: false
  defp present?(_value), do: true

  defp get(map, key) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp get(_map, _key), do: nil

  defp clean(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp clean(_value), do: nil

  defp downcase(nil), do: nil
  defp downcase(value), do: String.downcase(value)

  defp truncate(nil, _max), do: nil
  defp truncate(value, max), do: String.slice(value, 0, max)
end
