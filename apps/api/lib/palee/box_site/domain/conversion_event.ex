defmodule Palee.BoxSite.Domain.ConversionEvent do
  @moduledoc """
  ADR-354 §5: the server-side Meta Conversions API `Lead` event of a form
  submission. Email and phone leave only normalised and SHA-256 hashed; the
  event id is the submission id, so the browser pixel's `eventID` of the
  same submission deduplicates with it.
  """

  @max_attempts 6

  def max_attempts, do: @max_attempts

  @doc "The event payload (without the access token), or nil with nothing to match on."
  def build(%{id: id, email: email, phone: phone, submitted_at: at}, source_url) do
    user_data =
      %{"em" => hashed(normalize_email(email)), "ph" => hashed(normalize_phone(phone))}
      |> Enum.reject(fn {_key, value} -> value == [] end)
      |> Map.new()

    if user_data == %{} do
      nil
    else
      %{
        "event_name" => "Lead",
        "event_time" => DateTime.to_unix(at),
        "event_id" => id,
        "action_source" => "website",
        "event_source_url" => source_url,
        "user_data" => user_data
      }
    end
  end

  defp hashed(nil), do: []
  defp hashed(value), do: [:crypto.hash(:sha256, value) |> Base.encode16(case: :lower)]

  @doc "Meta's normalisation: trimmed, lower case."
  def normalize_email(nil), do: nil
  def normalize_email(email), do: email |> String.trim() |> String.downcase()

  @doc "Meta's normalisation: digits only, country code included (Greek numbers get 30)."
  def normalize_phone(nil), do: nil

  def normalize_phone(phone) do
    digits = String.replace(phone, ~r/[^0-9]/, "")

    cond do
      digits == "" -> nil
      String.starts_with?(phone, "+") -> digits
      String.starts_with?(digits, "00") -> String.replace_prefix(digits, "00", "")
      String.length(digits) == 10 and String.starts_with?(digits, ["2", "69"]) -> "30" <> digits
      true -> digits
    end
  end

  @doc "Changes after the provider answered."
  def after_send(:ok, _attempts, _now),
    do: %{conversion_status: "sent", conversion_payload: nil, conversion_claimed_at: nil}

  def after_send({:error, {:rejected, _reason}}, _attempts, _now),
    do: %{conversion_status: "failed", conversion_payload: nil, conversion_claimed_at: nil}

  def after_send({:error, {:transient, _reason}}, attempts, now) do
    if attempts >= @max_attempts do
      %{conversion_status: "failed", conversion_payload: nil, conversion_claimed_at: nil}
    else
      %{
        conversion_status: "pending",
        conversion_claimed_at: nil,
        conversion_next_at: DateTime.add(now, 300 * attempts, :second)
      }
    end
  end
end
