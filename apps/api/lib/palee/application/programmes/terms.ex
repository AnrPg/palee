defmodule Palee.Application.Programmes.Terms do
  @moduledoc """
  The texts a buyer agrees to when buying a programme (ADR-371): the
  request to start (when the start date is today or a withdrawal right
  exists) and the seller's refund rule. Versioned and hashed into the
  purchase's withdrawal record. The wording is a draft for legal review.
  """

  alias Palee.Fiscal
  alias Palee.Payments.Domain.Withdrawal

  @version "2026-10-programme-v1"
  @days Withdrawal.days()

  @start_now %{
    "el" =>
      "Ζητώ να ξεκινήσει το πρόγραμμα προπόνησης την ημερομηνία που διάλεξα. Γνωρίζω ότι μπορώ να υπαναχωρήσω μέσα σε 14 ημέρες από την αγορά, πληρώνοντας μόνο το μέρος που έχει ήδη ξεκινήσει.",
    "en" =>
      "I ask for the training programme to start on the date I chose. I understand that I can withdraw within 14 days of buying it and pay only for the part that has already started."
  }

  @rules %{
    "before_start" => %{
      "el" => "Πλήρης επιστροφή χρημάτων μέχρι την ημέρα έναρξης.",
      "en" => "Full refund until the start date."
    },
    "withdrawal_only" => %{
      "el" => "Επιστροφή χρημάτων μόνο μέσα στην προθεσμία υπαναχώρησης.",
      "en" => "Refunds only within the withdrawal period."
    },
    "pro_rata" => %{
      "el" => "Επιστροφή για τις ημέρες που δεν έχουν έρθει, μέχρι το τέλος του προγράμματος.",
      "en" => "Refund of the days not yet reached, until the programme ends."
    }
  }

  def version, do: @version
  def days, do: @days

  def language(language) when language in ["el", "en"], do: language
  def language(_language), do: "en"

  def start_now_text(language), do: Map.fetch!(@start_now, language(language))

  def rule_text(policy, language),
    do: @rules |> Map.fetch!(policy) |> Map.fetch!(language(language))

  @doc "Whether the seller's country gives buyers a right of withdrawal (unknown: yes)."
  def withdrawal_applies?(context) do
    case Fiscal.identity_status(context) do
      %{identity: %{country_code: country}} when is_binary(country) ->
        Withdrawal.applies?(country)

      _none ->
        true
    end
  end

  @doc """
  The record kept on the purchase: `{:ok, map}` or
  `{:error, :programme_start_consent_required}` when the law applies and the
  buyer did not ask to start.
  """
  def record(true = _applies, params, %DateTime{} = now) do
    if params[:start_now] == true do
      language = language(params[:language])

      {:ok,
       %{
         "applies" => true,
         "version" => @version,
         "text_hash" => hash(start_now_text(language)),
         "start_now_requested_at" => DateTime.to_iso8601(now),
         "deadline" => now |> DateTime.add(@days * 86_400, :second) |> DateTime.to_iso8601()
       }}
    else
      {:error, :programme_start_consent_required}
    end
  end

  def record(false, _params, _now), do: {:ok, %{"applies" => false}}

  defp hash(text), do: :sha256 |> :crypto.hash(text) |> Base.encode16(case: :lower)
end
