defmodule Palee.Application.DataQuestions.DataQuestions do
  @moduledoc """
  Staff questions over the box's data (ADR-361, CP-F4).

  `ask/3`, in order:

    1. the owner's switch (`data_questions_enabled`, Settings › AI) and at
       least one query the asker's rights allow;
    2. cost limits: the box's monthly budget for the feature, as metered by
       `Palee.AiUsage`, and a daily count per person (`Palee.Llm` budgets);
    3. the tool loop: the model gets only the queries this person may use,
       each run by `DataQuestions.run_query/4` in the box's tenant session,
       re-checking the person's rights on every call;
    4. the answer is checked: citations must be results that exist, and
       every number must be found in the cited data (`grounded`);
    5. one audit row per question, whatever the outcome.

  The model never sees people's names (opaque refs only); the asker gets
  tables built by the server with the names. People results come with a
  follow-up action (message them, CP-C2) when the asker may message
  clients; the action is only offered, a person confirms it elsewhere.
  """

  alias Palee.{AiUsage, DataQuestions, HelpCentre, Llm, Organizations}
  alias Palee.Llm.Domain.Request

  @feature "data_questions"
  @audit_capability :manage_settings

  @doc "What this person can ask: the switch, the queries and the limits."
  def catalogue(context, now \\ DateTime.utc_now()) do
    limits = Llm.feature_limits(:data_questions)
    windows = Llm.budget_windows(now)

    {:ok,
     %{
       enabled: enabled?(context),
       queries:
         context
         |> capabilities()
         |> DataQuestions.available_queries()
         |> Enum.map(fn query ->
           %{
             name: query.name,
             version: query.version,
             summary: query.summary,
             people: query.people,
             arguments: DataQuestions.input_schema(query)
           }
         end),
       daily_limit: limits.daily_per_person,
       asked_today: DataQuestions.count_since(context, context.user_id, windows.day_start)
     }}
  end

  def ask(context, params, now \\ DateTime.utc_now())

  def ask(%{organization_id: _, user_id: user_id} = context, params, now) when is_map(params) do
    queries = context |> capabilities() |> DataQuestions.available_queries()
    locale = HelpCentre.locale(param(params, :locale))

    with :ok <- if(enabled?(context), do: :ok, else: {:error, :data_questions_disabled}),
         :ok <- if(queries == [], do: {:error, :forbidden}, else: :ok),
         {:ok, question} <- DataQuestions.validate_question(param(params, :question)),
         :ok <- within_budget(context, question, locale, now) do
      answer(context, user_id, question, locale, queries, now)
    end
  end

  def ask(_context, _params, _now), do: {:error, :bad_request}

  @doc "My questions, newest first; `scope: all` lists the box's (owner, admin)."
  def list(context, params) do
    filters =
      case {param(params, :scope), auditor?(context)} do
        {"all", true} -> %{}
        {"all", false} -> :forbidden
        _mine -> %{user_id: context.user_id}
      end

    case filters do
      :forbidden ->
        {:error, :forbidden}

      filters ->
        {:ok,
         %{
           questions:
             context
             |> DataQuestions.list(Map.put(filters, :limit, 50))
             |> Enum.map(&view(&1, [], []))
         }}
    end
  end

  def show(context, id) do
    case DataQuestions.get(context, id) do
      %{user_id: user_id} = question when user_id == context.user_id ->
        {:ok, view(question, [], [])}

      %{} = question ->
        if auditor?(context), do: {:ok, view(question, [], [])}, else: {:error, :not_found}

      nil ->
        {:error, :not_found}
    end
  end

  # -- the question --------------------------------------------------------

  defp answer(context, user_id, question, locale, queries, now) do
    id = Ecto.UUID.generate()
    today = Organizations.local_date(context, now)
    zone = Organizations.organization_timezone(context.organization_id)
    started = System.monotonic_time(:millisecond)

    request = %Request{
      system: DataQuestions.system_prompt(%{today: today, locale: locale, zone: zone}),
      messages: [%{role: :user, text: question}],
      tools: Enum.map(queries, &tool/1),
      response_schema: DataQuestions.answer_schema(),
      max_output_tokens: 1_024
    }

    execute = fn name, args, step -> execute(context, name, args, step, today, zone) end

    options = %{
      agent: @feature,
      metering: %{
        operation_id: id,
        feature: @feature,
        organization_id: context.organization_id,
        user_id: user_id
      }
    }

    base = %{
      id: id,
      user_id: user_id,
      question: question,
      locale: locale,
      inserted_at: now
    }

    case Llm.run_tools(request, execute, options, max_rounds: 3, max_calls_per_round: 4) do
      {:ok, run} ->
        finish(context, base, run, question, started)

      {:error, reason} ->
        record_failure(context, base, reason, started)
        {:error, failure(reason)}
    end
  end

  defp finish(context, base, run, question, started) do
    steps = run.steps
    results = Enum.filter(steps, &Map.has_key?(&1, :content))
    refs = Enum.map(results, & &1.ref)

    with {:ok, json} <- Llm.decode_json(run.response),
         {:ok, evaluated} <- DataQuestions.evaluate_answer(json, refs) do
      cited = Enum.filter(results, &(&1.ref in evaluated.citations))

      allowed =
        Enum.flat_map(cited, &DataQuestions.result_numbers(&1.content)) ++
          DataQuestions.numbers_in(question)

      unsupported = DataQuestions.unsupported_numbers(evaluated.answer, allowed)

      citations =
        Enum.map(cited, fn step ->
          %{
            "ref" => step.ref,
            "query" => step.tool,
            "arguments" => step.content["arguments"],
            "summary" => step.content["summary"]
          }
        end)

      attrs =
        Map.merge(base, %{
          status: evaluated.status,
          answer: evaluated.answer,
          grounded: evaluated.status == "answered" and unsupported == [],
          unsupported_numbers: unsupported,
          citations: citations,
          steps: steps |> Enum.take(20) |> Enum.map(&audit_step/1),
          rounds: run.rounds,
          model: model(run),
          input_tokens: run.usage.input_tokens + run.usage.cached_input_tokens,
          output_tokens: run.usage.output_tokens + run.usage.thinking_tokens,
          duration_ms: System.monotonic_time(:millisecond) - started
        })

      with {:ok, stored} <- DataQuestions.record(context, attrs) do
        {:ok, view(stored, tables(results), actions(context, results))}
      end
    else
      {:error, reason} ->
        record_failure(
          context,
          Map.put(base, :steps, steps |> Enum.take(20) |> Enum.map(&audit_step/1)),
          reason,
          started
        )

        {:error, failure(reason)}
    end
  end

  # One tool call. The person's rights are checked again here: the model
  # can only name queries it was given, but nothing it says is trusted.
  defp execute(context, name, args, step, today, zone) do
    ref = "q#{step}"

    with {:ok, query} <- DataQuestions.fetch_query(name),
         true <-
           DataQuestions.query_allowed?(query, capabilities(context)) || {:error, :forbidden},
         {:ok, params} <- DataQuestions.resolve_arguments(query, args, today),
         {:ok, raw} <-
           DataQuestions.run_query(context, name, Map.put(params, "today", today), zone) do
      content = DataQuestions.model_content(ref, query, params, raw)

      {:ok, content,
       %{
         ref: ref,
         content: content,
         table: DataQuestions.result_table(ref, query, raw),
         people: DataQuestions.result_people(query, raw),
         rows: length(raw.rows)
       }}
    else
      {:error, {:unknown_arguments, _names}} -> {:error, :invalid_arguments}
      {:error, {:invalid_argument, _name}} -> {:error, :invalid_arguments}
      {:error, {:query_failed, _message}} -> {:error, :query_failed}
      {:error, code} when is_atom(code) -> {:error, code}
      _other -> {:error, :query_failed}
    end
  end

  defp tool(query) do
    Llm.tool(%{
      name: query.name,
      description: query.summary <> ". " <> query.description,
      input_schema: DataQuestions.input_schema(query),
      keywords: query.keywords
    })
  end

  # -- limits ----------------------------------------------------------------

  defp within_budget(context, question, locale, now) do
    limits = Llm.feature_limits(:data_questions)
    windows = Llm.budget_windows(now)
    spent = AiUsage.usage_summary(context, %{from: windows.month_start, feature: @feature})

    usage = %{
      spent_nano_usd: spent.cost_nano_usd,
      used_today: DataQuestions.count_since(context, context.user_id, windows.day_start)
    }

    case Llm.check_budget(limits, usage) do
      :ok ->
        :ok

      {:error, reason} = error ->
        {:ok, _refused} =
          DataQuestions.record(context, %{
            user_id: context.user_id,
            question: question,
            locale: locale,
            status: "refused",
            error_code: Atom.to_string(reason),
            inserted_at: now
          })

        error
    end
  end

  defp record_failure(context, base, reason, started) do
    _ =
      DataQuestions.record(
        context,
        Map.merge(base, %{
          status: "failed",
          error_code: reason |> failure() |> Atom.to_string(),
          duration_ms: System.monotonic_time(:millisecond) - started
        })
      )

    :ok
  end

  defp failure(reason)
       when reason in [:llm_not_configured, :llm_quota_exhausted, :llm_unavailable],
       do: reason

  defp failure(_reason), do: :llm_invalid_answer

  # -- shapes ----------------------------------------------------------------

  defp view(question, tables, actions) do
    %{
      id: question.id,
      status: question.status,
      error_code: question.error_code,
      question: question.question,
      locale: question.locale,
      answer: question.answer,
      grounded: question.grounded,
      unsupported_numbers: question.unsupported_numbers || [],
      citations: question.citations || [],
      queries: Enum.map(question.steps || [], &(Map.get(&1, "tool") || Map.get(&1, :tool))),
      tables: tables,
      actions: actions,
      asked_by_id: question.user_id,
      asked_at: question.inserted_at
    }
  end

  defp tables(results), do: Enum.map(results, & &1.table)

  defp actions(context, results) do
    if Map.get(capabilities(context), :message_clients) == :all do
      results
      |> Enum.filter(&(&1.people != []))
      |> Enum.map(fn step ->
        %{
          kind: "message_people",
          ref: step.ref,
          user_ids: step.people,
          count: length(step.people)
        }
      end)
    else
      []
    end
  end

  # What the audit log keeps of a step: never the rows or names.
  defp audit_step(step) do
    step
    |> Map.take([:step, :tool, :args, :ref, :rows, :error])
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
  end

  defp model(%{response: %{model: model}}) when is_binary(model),
    do: "#{model} (#{DataQuestions.prompt_version()})"

  defp model(_run), do: DataQuestions.prompt_version()

  defp enabled?(context), do: context |> AiUsage.get_settings() |> AiUsage.data_questions_ready?()

  defp auditor?(context), do: Map.get(capabilities(context), @audit_capability) == :all

  defp capabilities(%{capabilities: capabilities}) when is_map(capabilities), do: capabilities
  defp capabilities(_context), do: %{}

  defp param(params, key) when is_map(params),
    do: Map.get(params, key, Map.get(params, Atom.to_string(key)))

  defp param(_params, _key), do: nil
end
