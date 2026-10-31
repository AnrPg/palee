defmodule Palee.DataQuestions.Domain.Catalogue do
  @moduledoc """
  The read queries a model may pick from to answer a staff question
  (ADR-361), pure. The model never writes SQL: it chooses one of these by
  name and fills typed arguments, which are validated here before anything
  runs.

  Each query is declared like a v4 registry operation (ADR-300): name,
  version, summary and a description written for the model, the JSON
  Schema of its arguments, the capabilities that allow it (ADR-099, any
  one, at gym-wide scope), its risk (always `:read`) and the data classes
  it touches. A person is offered only the queries their own rights allow;
  a coach whose rights are limited to their own clients (`:own`) is not
  offered gym-wide people queries.

  Periods are gym-local days (ADR-176): a named `period` or a custom
  `from`/`to` (ISO dates, at most 366 days).
  """

  @periods ~w(last_7_days last_30_days last_90_days this_month last_month this_year last_year custom)
  @max_period_days 366

  @period_schema %{
    "type" => "string",
    "enum" => @periods,
    "description" =>
      "Gym-local period. Use custom with from and to for any other range. Default last_30_days."
  }
  @date_schema %{"type" => "string", "description" => "ISO date YYYY-MM-DD (only with period custom)"}

  @queries [
    %{
      name: "members_absent",
      version: 1,
      summary: "Active box members who have not come for a number of days",
      description:
        "Active box members with no class attended and no check-in in the last `days` days " <>
          "(or never). Returns how many there are and, per person, an opaque ref (P1, P2…), " <>
          "the last visit date and days since it. Names are never returned. Use it for " <>
          "questions such as 'who hasn't come for 3 weeks?'.",
      capabilities: [:view_directory],
      data_classes: [:personal],
      people: true,
      keywords:
        ~w(absent absence inactive missing come came visit visits weeks days haven't ήρθαν έρχονται έχουν απόντες απουσία ανενεργά εβδομάδες μέρες ημέρες),
      params: %{"days" => {:integer, 7, 365, 21}}
    },
    %{
      name: "member_counts",
      version: 1,
      summary: "How many active box members, and how many joined and left in a period",
      description:
        "Counts: active box members today, members who joined in the period and members who " <>
          "left in the period. Use it for growth and churn questions.",
      capabilities: [:view_membership_status, :view_business_analytics],
      data_classes: [],
      people: false,
      keywords:
        ~w(members count how many active joined new left churn growth μέλη πόσα πόσοι ενεργά νέα γράφτηκαν έφυγαν αποχωρήσεις),
      params: %{"period" => {:period, "last_30_days"}}
    },
    %{
      name: "expiring_subscriptions",
      version: 1,
      summary: "Subscription packages that end in the next days and do not renew",
      description:
        "Active subscription packages ending within `days` days from today that do not renew " <>
          "automatically. Returns the count, a count per package and, per person, an opaque ref, " <>
          "the package and the end date. Names are never returned.",
      capabilities: [:view_membership_status],
      data_classes: [:personal],
      people: true,
      keywords:
        ~w(expiring expire expires ending end renew renewal subscriptions packages λήγουν λήξη τελειώνουν ανανέωση συνδρομές πακέτα),
      params: %{"days" => {:integer, 1, 90, 14}}
    },
    %{
      name: "revenue_by_package",
      version: 1,
      summary: "Money received for subscription packages in a period, per package",
      description:
        "Paid membership payments in the period grouped by package: number of payments and " <>
          "amount (in the currency's units, e.g. 45.5 EUR). Refunded, failed, waived and deleted " <>
          "payments are excluded. Use it for 'revenue by package last month'.",
      capabilities: [:view_finance_reports],
      data_classes: [:financial],
      people: false,
      keywords:
        ~w(revenue income money earned sales paid payments package packages έσοδα εισπράξεις τζίρος πληρωμές πακέτο πακέτα χρήματα),
      params: %{"period" => {:period, "last_month"}}
    },
    %{
      name: "revenue_by_month",
      version: 1,
      summary: "Money received for subscription packages per month",
      description:
        "Paid membership payments per gym-local calendar month for the last `months` months " <>
          "including the current one: number of payments and amount.",
      capabilities: [:view_finance_reports],
      data_classes: [:financial],
      people: false,
      keywords:
        ~w(revenue monthly month months trend income έσοδα μήνα μήνες μηνιαία πορεία εισπράξεις),
      params: %{"months" => {:integer, 1, 24, 6}}
    },
    %{
      name: "attendance_by_class_type",
      version: 1,
      summary: "Classes held and attendance per class type in a period",
      description:
        "Per class type, for classes held in the period (cancelled ones excluded): classes, " <>
          "attendances, average attendance per class and how full classes were (percent of " <>
          "capacity). Use it for 'which classes are busiest'.",
      capabilities: [:view_business_analytics],
      data_classes: [],
      people: false,
      keywords:
        ~w(attendance classes class busiest full capacity type types turnout παρουσίες τμήματα τμήμα γεμάτα πληρότητα συμμετοχή μαθήματα),
      params: %{"period" => {:period, "last_30_days"}}
    }
  ]

  @by_name Map.new(@queries, &{&1.name, &1})

  def queries, do: @queries
  def names, do: Map.keys(@by_name)
  def periods, do: @periods

  def fetch(name) do
    case Map.fetch(@by_name, name) do
      {:ok, query} -> {:ok, query}
      :error -> {:error, :unknown_query}
    end
  end

  @doc "Whether `capabilities` (`%{cap => scope}`) allow the query (gym-wide)."
  def allowed?(%{capabilities: needed}, capabilities) when is_map(capabilities),
    do: Enum.any?(needed, &(Map.get(capabilities, &1) == :all))

  def allowed?(_query, _capabilities), do: false

  @doc "The queries a person with `capabilities` may use."
  def available(capabilities), do: Enum.filter(@queries, &allowed?(&1, capabilities))

  @doc "The JSON Schema of a query's arguments."
  def input_schema(%{params: params}) do
    properties =
      Enum.reduce(params, %{}, fn
        {name, {:integer, min, max, default}}, acc ->
          Map.put(acc, name, %{
            "type" => "integer",
            "minimum" => min,
            "maximum" => max,
            "description" => "Default #{default}."
          })

        {"period", {:period, _default}}, acc ->
          acc
          |> Map.put("period", @period_schema)
          |> Map.put("from", @date_schema)
          |> Map.put("to", @date_schema)
      end)

    %{"type" => "object", "properties" => properties, "required" => []}
  end

  @doc """
  Validates a model's arguments against a query and resolves defaults and
  the period to gym-local dates (given `today`). Unknown arguments are an
  error, so a confused model cannot pass something unchecked.
  """
  def resolve(%{params: params}, args, %Date{} = today) when is_map(args) do
    args = Map.new(args, fn {k, v} -> {to_string(k), v} end)
    known = params |> Map.keys() |> Enum.flat_map(&expand/1)

    case Map.keys(args) -- known do
      [] -> resolve_params(params, args, today)
      unknown -> {:error, {:unknown_arguments, Enum.sort(unknown)}}
    end
  end

  def resolve(_query, _args, _today), do: {:error, :invalid_arguments}

  defp expand("period"), do: ["period", "from", "to"]
  defp expand(name), do: [name]

  defp resolve_params(params, args, today) do
    Enum.reduce_while(params, {:ok, %{}}, fn {name, spec}, {:ok, acc} ->
      case resolve_param(name, spec, args, today) do
        {:ok, values} -> {:cont, {:ok, Map.merge(acc, values)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp resolve_param(name, {:integer, min, max, default}, args, _today) do
    case Map.get(args, name, default) do
      value when is_integer(value) and value >= min and value <= max -> {:ok, %{name => value}}
      value when is_float(value) and value == trunc(value) -> resolve_int(name, trunc(value), min, max)
      _invalid -> {:error, {:invalid_argument, name}}
    end
  end

  defp resolve_param("period", {:period, default}, args, today) do
    case Map.get(args, "period", default) do
      "custom" -> custom_period(args, today)
      period when period in @periods -> {:ok, period_range(period, today)}
      _invalid -> {:error, {:invalid_argument, "period"}}
    end
  end

  defp resolve_int(name, value, min, max) when value >= min and value <= max,
    do: {:ok, %{name => value}}

  defp resolve_int(name, _value, _min, _max), do: {:error, {:invalid_argument, name}}

  defp custom_period(args, today) do
    with {:ok, from} <- date(Map.get(args, "from")),
         {:ok, to} <- date(Map.get(args, "to")),
         true <- Date.compare(from, to) != :gt,
         true <- Date.diff(to, from) < @max_period_days,
         true <- Date.compare(from, today) != :gt do
      {:ok, %{"period" => "custom", "from" => from, "to" => to}}
    else
      _invalid -> {:error, {:invalid_argument, "period"}}
    end
  end

  @doc "The gym-local date range of a named period."
  def period_range(period, today) do
    {from, to} =
      case period do
        "last_7_days" -> {Date.add(today, -6), today}
        "last_30_days" -> {Date.add(today, -29), today}
        "last_90_days" -> {Date.add(today, -89), today}
        "this_month" -> {Date.beginning_of_month(today), today}
        "last_month" -> last_month(today)
        "this_year" -> {Date.new!(today.year, 1, 1), today}
        "last_year" -> {Date.new!(today.year - 1, 1, 1), Date.new!(today.year - 1, 12, 31)}
      end

    %{"period" => period, "from" => from, "to" => to}
  end

  defp last_month(today) do
    first = today |> Date.beginning_of_month() |> Date.add(-1) |> Date.beginning_of_month()
    {first, Date.end_of_month(first)}
  end

  defp date(%Date{} = date), do: {:ok, date}

  defp date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _error -> :error
    end
  end

  defp date(_value), do: :error
end
