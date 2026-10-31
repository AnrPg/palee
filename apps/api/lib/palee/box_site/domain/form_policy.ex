defmodule Palee.BoxSite.Domain.FormPolicy do
  @moduledoc """
  ADR-353: the website's trial and contact forms. Validates what a visitor
  sent, recognises bots (honeypot, filled in too fast), builds the lead
  intake (the `LeadIntake` port's contract) and paces delivery retries.
  """

  @kinds ~w(trial contact)
  @min_fill_ms 2_000
  @max_attempts 12
  @max_backoff 21_600
  @failed_retention_days 30
  @attribution_keys ~w(utm_source utm_medium utm_campaign utm_term utm_content referrer_host landing_path)
  @locales ~w(el en de fr es it pt nl ru uk ar tr)
  @email ~r/^[^\s@]{1,64}@[^\s@]+\.[^\s@]{2,}$/
  @phone ~r/^\+?[0-9 ()\-.]{6,24}$/

  @doc "The personal fields cleared once a submission is delivered or given up."
  def personal_fields, do: [:name, :email, :phone, :message, :preferred_time]

  def kinds, do: @kinds
  def max_attempts, do: @max_attempts
  def failed_retention_days, do: @failed_retention_days
  def attribution_keys, do: @attribution_keys

  @doc "True when the post looks like a bot: it is accepted and dropped."
  def spam?(params) do
    honeypot = Map.get(params, "website")
    elapsed = Map.get(params, "elapsed_ms")

    (is_binary(honeypot) and String.trim(honeypot) != "") or
      (is_integer(elapsed) and elapsed < @min_fill_ms)
  end

  @doc """
  `{:ok, attrs}` ready to store, or `{:error, {:invalid_fields, errors}}`;
  `{:error, :unknown_form}` for a kind that does not exist.
  """
  def validate(kind, _params, _now) when kind not in @kinds, do: {:error, :unknown_form}

  def validate(kind, params, now) do
    name = text(params, "name", 80)
    email = params |> text("email", 160) |> then(&(&1 && String.downcase(&1)))
    phone = params |> text("phone", 32) |> then(&(&1 && String.replace(&1, ~r/[\s().\-]/, "")))
    message = text(params, "message", 2_000)

    errors =
      %{}
      |> require_field(:name, name)
      |> check(:email, email && not Regex.match?(@email, email), "invalid")
      |> check(:phone, phone && not Regex.match?(@phone, Map.get(params, "phone", "")), "invalid")
      |> check(:email, is_nil(email) and is_nil(phone), "email_or_phone")
      |> check(:message, kind == "contact" and is_nil(message), "required")
      |> check(:privacy_ack, Map.get(params, "privacy_ack") != true, "required")
      |> check(:class_type_id, not uuid_or_nil?(Map.get(params, "class_type_id")), "invalid")
      |> check(:visitor_id, not uuid_or_nil?(Map.get(params, "visitor_id")), "invalid")

    if errors == %{} do
      {:ok,
       %{
         kind: kind,
         name: name,
         email: email,
         phone: phone,
         message: message,
         preferred_time: text(params, "preferred_time", 120),
         class_type_id: Map.get(params, "class_type_id"),
         locale: locale(Map.get(params, "locale")),
         marketing_opt_in: Map.get(params, "marketing_opt_in") == true,
         visitor_id: Map.get(params, "visitor_id"),
         attribution: attribution(Map.get(params, "attribution")),
         consent_text_version: text(params, "consent_text_version", 40),
         consent_text_hash: text(params, "consent_text_hash", 80),
         submitted_at: now,
         status: "pending",
         next_attempt_at: now
       }}
    else
      {:error, {:invalid_fields, errors}}
    end
  end

  defp text(params, key, max) do
    case Map.get(params, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> String.slice(trimmed, 0, max)
        end

      _other ->
        nil
    end
  end

  defp require_field(errors, field, nil), do: Map.put(errors, field, "required")
  defp require_field(errors, _field, _value), do: errors

  defp check(errors, field, true, code), do: Map.put_new(errors, field, code)
  defp check(errors, _field, _falsy, _code), do: errors

  defp uuid_or_nil?(nil), do: true
  defp uuid_or_nil?(value) when is_binary(value), do: match?({:ok, _}, Ecto.UUID.cast(value))
  defp uuid_or_nil?(_value), do: false

  defp locale(value) when value in @locales, do: value
  defp locale(_value), do: "el"

  defp attribution(%{} = map) do
    map = Map.new(map, fn {key, value} -> {to_string(key), value} end)

    for key <- @attribution_keys,
        value = Map.get(map, key),
        is_binary(value) and value != "",
        into: %{},
        do: {key, String.slice(value, 0, 200)}
  end

  defp attribution(_other), do: %{}

  @doc "The `LeadIntake.submit/2` intake of a stored submission (ADR-353 §2)."
  def intake(submission) do
    %{
      submission_id: submission.id,
      kind: submission.kind,
      source: "website_form",
      name: submission.name,
      email: submission.email,
      phone: submission.phone,
      message: submission.message,
      preferred_time: submission.preferred_time,
      class_type_id: submission.class_type_id,
      locale: submission.locale,
      marketing_opt_in: submission.marketing_opt_in,
      submitted_at: submission.submitted_at,
      attribution: atomize(submission.attribution || %{}),
      consent: %{
        text_version: submission.consent_text_version,
        text_hash: submission.consent_text_hash
      }
    }
  end

  defp atomize(map) do
    Map.new(@attribution_keys, fn key -> {String.to_existing_atom(key), Map.get(map, key)} end)
  end

  @doc "Changes after the leads port answered."
  def after_delivery({:ok, %{lead_id: lead_id}}, _submission, now) do
    %{status: "delivered", lead_id: lead_id, delivered_at: now, last_error: nil, claimed_at: nil}
    |> Map.merge(redaction(now))
  end

  def after_delivery({:error, {:rejected, reason}}, _submission, _now),
    do: %{status: "failed", last_error: error_text(reason), claimed_at: nil, next_attempt_at: nil}

  def after_delivery({:error, {:transient, reason}}, submission, now) do
    if submission.attempts >= @max_attempts do
      %{status: "failed", last_error: error_text(reason), claimed_at: nil, next_attempt_at: nil}
    else
      %{
        status: "pending",
        last_error: error_text(reason),
        claimed_at: nil,
        next_attempt_at: DateTime.add(now, backoff(submission.attempts), :second)
      }
    end
  end

  @doc "Seconds to wait after `attempts` tries: 1 min doubling up to 6 h."
  def backoff(attempts) when attempts >= 1,
    do: min(60 * Integer.pow(2, attempts - 1), @max_backoff)

  def backoff(_attempts), do: 60

  @doc "Clears the personal fields (ADR-353 §4)."
  def redaction(now) do
    personal_fields() |> Map.new(&{&1, nil}) |> Map.put(:redacted_at, now)
  end

  defp error_text(reason), do: reason |> inspect() |> String.slice(0, 120)
end
