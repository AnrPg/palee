defmodule Palee.ReviewAsks.Domain.ReviewReportPolicy do
  @moduledoc """
  ADR-397: «Αναφορά» on the in-app reviews of a box, decided only by the
  Palee team. Pure: callers bring the facts and the time.

    * Any member of the box who can read its reviews may report one, and the
      box itself (staff who speak as the box, `message_from_box`); nobody
      reports their own review. One open report per person and review, at
      most 10 reports per person and box in 24 hours.
    * A report never changes what anyone sees: the review stays up, counted
      in the average, until the Palee team decides. So a box can never hide a
      review on its own, nor by asking friends to report it.
    * The Palee team decides per review, for every open report on it:
      `keep` (no violation), `hide` (reversible: the text stays, nobody but
      the author sees it) or `remove` (the text and the box's reply go). A
      hide or remove names its ground and a statement the author receives
      (DSA Art. 17); every reporter hears the outcome (DSA Art. 16(5)).
    * The Palee team may later `restore` a hidden review, with a statement
      the author receives too. A removed text is kept 6 months after the
      decision, then only the decision remains.
  """

  @reasons ~w(offensive personal_data not_genuine spam illegal other)
  @roles ~w(member box)
  @outcomes ~w(keep hide remove)
  @needs_note ~w(illegal other)
  @max_note 500
  @max_statement 1_000
  @daily_limit 10

  @status_by_outcome %{"keep" => "kept", "hide" => "hidden", "remove" => "removed"}
  @removed_text_days 183

  def reasons, do: @reasons
  def roles, do: @roles
  def outcomes, do: @outcomes
  def grounds, do: ["no_violation" | @reasons]
  def statuses, do: ["open" | Map.values(@status_by_outcome)]
  def daily_limit, do: @daily_limit
  def max_note, do: @max_note
  def max_statement, do: @max_statement

  @doc "Before when a removed review's text and the notes on it are cleared (6 months)."
  def removed_text_before(now), do: DateTime.add(now, -@removed_text_days * 24 * 3600, :second)

  @doc """
  Validates a report (string keys): `{:ok, %{reason, note}}` or
  `{:error, {:invalid_fields, errors}}`. A note is optional, except for
  `illegal` and `other`, where the reason alone says too little (DSA
  Art. 16(2)(a) asks for an explanation).
  """
  def report(params) when is_map(params) do
    reason = Map.get(params, "reason")

    case {reason in @reasons, text(Map.get(params, "note"), @max_note)} do
      {false, _note} ->
        {:error, {:invalid_fields, %{reason: "invalid"}}}

      {true, :error} ->
        {:error, {:invalid_fields, %{note: "too_long"}}}

      {true, {:ok, nil}} when reason in @needs_note ->
        {:error, {:invalid_fields, %{note: "required"}}}

      {true, {:ok, note}} ->
        {:ok, %{reason: reason, note: note}}
    end
  end

  def report(_params), do: {:error, {:invalid_fields, %{reason: "invalid"}}}

  @doc """
  `:ok` when `reporter_id` may report `review`: not their own, and only a
  review that is up (a hidden or removed one is not shown to report).
  """
  def may_report(%{user_id: author_id}, reporter_id) when author_id == reporter_id,
    do: {:error, :cannot_report_own_review}

  def may_report(%{moderation: moderation}, _reporter_id) when is_binary(moderation),
    do: {:error, :box_review_not_found}

  def may_report(%{}, _reporter_id), do: :ok

  @doc "`:ok` while the person filed fewer than the daily limit in the last 24 hours."
  def within_limit(count) when is_integer(count) and count < @daily_limit, do: :ok
  def within_limit(_count), do: {:error, :review_report_limit}

  @doc "Since when the daily limit counts."
  def limit_since(now), do: DateTime.add(now, -24 * 3600, :second)

  @doc "`:ok` unless the Palee team moderated the review (no edit, no reply)."
  def editable(%{moderation: moderation}) when is_binary(moderation),
    do: {:error, :review_moderated}

  def editable(_review), do: :ok

  @doc """
  Validates the Palee team's decision (string keys):
  `{:ok, %{outcome, ground, statement}}`. `keep` has the ground
  `no_violation` and an optional statement; `hide` and `remove` need a
  ground from the report reasons and a statement for the author.
  """
  def decision(params) when is_map(params) do
    outcome = Map.get(params, "outcome")
    ground = Map.get(params, "ground")

    with true <- outcome in @outcomes || {:error, {:invalid_fields, %{outcome: "invalid"}}},
         {:ok, statement} <- statement(Map.get(params, "statement")),
         {:ok, ground} <- ground(outcome, ground),
         :ok <- statement_present(outcome, statement) do
      {:ok, %{outcome: outcome, ground: ground, statement: statement}}
    end
  end

  def decision(_params), do: {:error, {:invalid_fields, %{outcome: "invalid"}}}

  defp statement(value) do
    case text(value, @max_statement) do
      {:ok, statement} -> {:ok, statement}
      :error -> {:error, {:invalid_fields, %{statement: "too_long"}}}
    end
  end

  defp ground("keep", value) when value in [nil, "no_violation"], do: {:ok, "no_violation"}
  defp ground("keep", _value), do: {:error, {:invalid_fields, %{ground: "invalid"}}}
  defp ground(_outcome, value) when value in @reasons, do: {:ok, value}
  defp ground(_outcome, _value), do: {:error, {:invalid_fields, %{ground: "invalid"}}}

  defp statement_present("keep", _statement), do: :ok
  defp statement_present(_outcome, nil), do: {:error, {:invalid_fields, %{statement: "required"}}}
  defp statement_present(_outcome, _statement), do: :ok

  @doc """
  Validates a restore of a hidden review (string keys): a statement for the
  author is required. `{:ok, %{outcome: "restore", ground: "no_violation", statement}}`.
  """
  def restore(params) when is_map(params) do
    case statement(Map.get(params, "statement")) do
      {:ok, nil} -> {:error, {:invalid_fields, %{statement: "required"}}}
      {:ok, text} -> {:ok, %{outcome: "restore", ground: "no_violation", statement: text}}
      error -> error
    end
  end

  def restore(_params), do: {:error, {:invalid_fields, %{statement: "required"}}}

  @doc "What the decision does to the review."
  def review_changes("keep", _now), do: %{moderation: nil, moderated_at: nil}
  def review_changes("restore", _now), do: %{moderation: nil, moderated_at: nil}
  def review_changes("hide", now), do: %{moderation: "hidden", moderated_at: now}

  def review_changes("remove", now) do
    %{
      moderation: "removed",
      moderated_at: now,
      body: nil,
      reply_body: nil,
      replied_at: nil,
      replied_by_id: nil
    }
  end

  @doc "The status every open report on the review closes with."
  def report_status(outcome), do: Map.fetch!(@status_by_outcome, outcome)

  @doc """
  What the restriction rests on (DSA Art. 17(3)(d)/(e)): the law for
  `illegal`, Palee's terms for every other ground, nothing for `keep`.
  """
  def legal_basis("no_violation"), do: nil
  def legal_basis("illegal"), do: "law"
  def legal_basis(ground) when ground in @reasons, do: "terms"

  @doc """
  The statement of reasons as the author reads it (DSA Art. 17(3)): what
  was restricted, the ground and its basis, the facts in Palee's words,
  that a person decided (no automated means), and where to seek redress:
  Palee's moderation contact, or the courts.
  """
  def statement_of_reasons(%{outcome: outcome, ground: ground} = decision, contact \\ nil) do
    %{
      outcome: outcome,
      ground: ground,
      legal_basis: legal_basis(ground),
      statement: decision.statement,
      after_report: (decision.reports_count || 0) > 0,
      automated: false,
      decided_at: decision.decided_at,
      redress: ~w(contact_palee court),
      contact: contact
    }
  end

  defp text(nil, _max), do: {:ok, nil}

  defp text(value, max) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" -> {:ok, nil}
      String.length(value) > max -> :error
      true -> {:ok, value}
    end
  end

  defp text(_value, _max), do: :error
end
