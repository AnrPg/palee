defmodule Palee.Finance.Domain.PackageStart do
  @moduledoc """
  ADR-795: when a package starts. Pure rules; the stores do the writing.

  A box (or an independent coach) chooses `package_starts_with`:

    * `"first_session"` (default): the period and the next payment count
      from the member's first completed class or WOD. Until then the
      subscription waits (`awaiting_first_session`), for as long as it takes;
    * `"payment"`: from the purchase or the desk payment, as before.

  When the first session comes, the terms the member bought (the
  subscription's snapshot) are compared with the package now. Each change is
  classified with ADR-770's directions:

    * the price went up: `important` (it needs the member's action);
    * a term is worse for the member: `serious`;
    * the name changed, the price went down or a term is better: `warning`.

  The highest one names the whole review. Billing period, purchase-only and
  structural terms never reach a bought package (as for holders, ADR-770), so
  they are neither shown nor taken.
  """

  alias Palee.Finance.Domain.PackageTermChanges

  @modes ~w(first_session payment)
  @rank %{"warning" => 0, "serious" => 1, "important" => 2}

  @doc "The two choices of the box setting."
  def modes, do: @modes

  @doc """
  The box setting's default (ANR, 2026-11-28: `first_session`) for a box
  that has not chosen. The test suite runs the boxes that predate ADR-795 in
  `payment` (`config :palee, :package_starts_default`); ADR-795's own tests
  choose explicitly.
  """
  def default_mode, do: Application.get_env(:palee, :package_starts_default, "first_session")

  @doc "Bounds an allowance counted over the subscription period uses while it waits."
  def waiting_period_end, do: ~D[9999-12-31]

  @doc """
  Whether a new assignment waits for the first session: the box starts
  packages that way and the caller did not fix a start day itself (imports,
  seasons, backfills and benefits do, and start at once).
  """
  def waits?(mode, params) when is_map(params) do
    mode == "first_session" and blank?(params["starts_on"]) and
      params["starts_with"] != "payment"
  end

  def waits?(_mode, _params), do: false

  @doc """
  The changes between what the member bought and the package now, each with
  its severity: `[%{key, from, to, severity}]`, name first, then ADR-770's
  order. `bought` and `current` are `%{name, price_cents, billing_period,
  params}`.
  """
  def changes(bought, current) do
    before =
      PackageTermChanges.package_terms(
        bought.price_cents,
        bought.billing_period,
        bought.params
      )

    now =
      PackageTermChanges.package_terms(
        current.price_cents,
        # A bought package keeps its billing period (ADR-770 `never`).
        bought.billing_period,
        current.params
      )

    recurring? = PackageTermChanges.recurring?(bought.billing_period)

    terms =
      before
      |> PackageTermChanges.changes(now)
      |> Enum.filter(&takeable?(&1, recurring?))
      |> Enum.map(&Map.put(&1, :severity, severity(&1)))

    name =
      if present(bought.name) != present(current.name) and present(current.name),
        do: [%{key: "name", from: bought.name, to: current.name, severity: "warning"}],
        else: []

    name ++ terms
  end

  # Price: always shown (1δ: the first period keeps the bought price). Fields:
  # the ones ADR-770 would ever give a holder.
  defp takeable?(%{key: key}, _recurring?) do
    cond do
      key == PackageTermChanges.price_key() -> true
      key == PackageTermChanges.billing_period_key() -> false
      true -> PackageTermChanges.timing(key, nil, nil, true) not in [:never, :purchase_only]
    end
  end

  @doc "The severity of one change (see the moduledoc)."
  def severity(%{key: key, from: from, to: to}) do
    cond do
      key == "name" ->
        "warning"

      key == PackageTermChanges.price_key() ->
        if is_integer(from) and is_integer(to) and to < from, do: "warning", else: "important"

      PackageTermChanges.direction(key, from, to) == :worse ->
        "serious"

      true ->
        "warning"
    end
  end

  @doc "The highest severity of a list of changes, nil when there are none."
  def overall([]), do: nil

  def overall(changes) do
    changes
    |> Enum.map(& &1.severity)
    |> Enum.max_by(&Map.fetch!(@rank, &1))
  end

  @doc """
  The fields and price a started package takes: every shown term but the
  price (1δ: the price applies from the next payment).
  """
  def taken(changes) do
    fields =
      changes
      |> Enum.reject(&(&1.key in ["name", PackageTermChanges.price_key()]))
      |> Map.new(&{&1.key, &1.to})

    price =
      Enum.find_value(changes, fn change ->
        change.key == PackageTermChanges.price_key() && change.to
      end)

    %{fields: fields, next_price_cents: price}
  end

  @doc "Changes as stored and sent (string keys, JSON values)."
  def serialize(changes) do
    Enum.map(changes, fn change ->
      %{
        "key" => change.key,
        "from" => change.from,
        "to" => change.to,
        "severity" => change.severity
      }
    end)
  end

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present(_value), do: nil

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
