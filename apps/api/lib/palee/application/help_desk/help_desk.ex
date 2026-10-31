defmodule Palee.Application.HelpDesk.HelpDesk do
  @moduledoc """
  In-app support for a box's staff (ADR-363, CP-G3). A person writes from
  any staff screen; the AI first line answers from help-centre articles
  only (retrieved for the question and the screen), citing them and
  offering the in-app guide of a cited article. When it cannot answer, or
  the person wants a human, `hand_off/4` opens a ticket for the Palee team
  with the conversation, the screen, the articles tried and the app facts.

  Conversations are the person's own: nobody else in the box reads them.
  The assistant sees the question, the screen path and the articles,
  never the box's data. Limits: a monthly budget per box and a daily count
  of messages per person (`:ai_features, :help_desk`); past them, or when
  the provider is down, the person is offered the hand-off instead.

  Every reply carries `assistant`: `answered`, `not_confident`,
  `no_articles`, `limit_reached`, `unavailable` or `skipped` (the Palee
  team has the conversation), so the screen can say what happened.
  """

  alias Palee.{AiUsage, HelpDesk, Llm}
  alias Palee.Application.HelpCentre.HelpArticles
  alias Palee.Llm.Domain.Request

  @feature "help_desk"

  def list(context) do
    {:ok,
     %{
       conversations:
         context |> HelpDesk.list_conversations(context.user_id) |> Enum.map(&summary/1)
     }}
  end

  def show(context, id) do
    with {:ok, conversation} <- own(context, id) do
      {:ok, view(context, conversation, nil)}
    end
  end

  def start(context, params, now \\ DateTime.utc_now())

  def start(%{user_id: user_id} = context, params, now) when is_map(params) do
    with {:ok, text} <- HelpDesk.validate_message(param(params, :message)),
         {:ok, conversation} <-
           HelpDesk.create_conversation(context, %{
             user_id: user_id,
             status: "assistant",
             locale: Palee.HelpCentre.locale(param(params, :locale)),
             screen_path: HelpDesk.screen(param(params, :screen_path)),
             subject: HelpDesk.subject(text),
             last_message_at: now
           }),
         {:ok, _message} <- person_message(context, conversation, text, now) do
      outcome = assistant_reply(context, conversation, now)
      {:ok, view(context, conversation.id, outcome)}
    end
  end

  def start(_context, _params, _now), do: {:error, :bad_request}

  def post_message(context, id, params, now \\ DateTime.utc_now()) do
    with {:ok, conversation} <- own(context, id),
         {:ok, text} <- HelpDesk.validate_message(param(params, :message)),
         ticket = HelpDesk.ticket_for_conversation(context, id),
         status = HelpDesk.after_person_message(conversation, not is_nil(ticket)),
         {:ok, conversation} <-
           HelpDesk.update_conversation(context, id, %{status: status, last_message_at: now}),
         {:ok, _message} <- person_message(context, conversation, text, now),
         :ok <- reopen_ticket(context, ticket) do
      outcome =
        if HelpDesk.assistant_turn?(status),
          do: assistant_reply(context, conversation, now),
          else: "skipped"

      {:ok, view(context, id, outcome)}
    end
  end

  @doc "Hands the conversation to the Palee team (idempotent)."
  def hand_off(context, id, params, now \\ DateTime.utc_now()) do
    params = stringify(params)

    with {:ok, conversation} <- own(context, id) do
      case HelpDesk.ticket_for_conversation(context, id) do
        nil ->
          messages = HelpDesk.list_messages(context, id)

          with {:ok, attrs} <- HelpDesk.new_ticket(conversation, messages, params),
               {:ok, ticket} <- HelpDesk.create_ticket(context, attrs),
               {:ok, _conversation} <-
                 HelpDesk.update_conversation(context, id, %{
                   status: "waiting_for_palee",
                   last_message_at: now
                 }) do
            :telemetry.execute([:palee, :help_desk, :ticket_opened], %{count: 1}, %{
              organization_id: context.organization_id,
              ticket_id: ticket.id,
              priority: ticket.priority
            })

            {:ok, view(context, id, nil)}
          end

        _ticket ->
          {:ok, view(context, id, nil)}
      end
    end
  end

  def resolve(context, id, now \\ DateTime.utc_now()) do
    with {:ok, _conversation} <- own(context, id),
         {:ok, _conversation} <- HelpDesk.update_conversation(context, id, %{status: "resolved"}) do
      case HelpDesk.ticket_for_conversation(context, id) do
        %{status: status} = ticket when status != "solved" ->
          {:ok, _ticket} =
            HelpDesk.update_ticket(context, ticket.id, %{status: "solved", solved_at: now})

        _none_or_solved ->
          :ok
      end

      {:ok, view(context, id, nil)}
    end
  end

  # -- the assistant ---------------------------------------------------------

  defp assistant_reply(context, conversation, now) do
    messages = HelpDesk.list_messages(context, conversation.id)
    question = last_person_text(messages)

    articles =
      HelpArticles.retrieve(question,
        locale: conversation.locale,
        screen: conversation.screen_path,
        limit: 4
      )

    with :ok <- within_budget(context, now),
         [_ | _] <- articles do
      request = %Request{
        system:
          HelpDesk.assistant_system(%{
            locale: conversation.locale,
            screen: conversation.screen_path
          }),
        messages: HelpDesk.assistant_turns(messages),
        documents: HelpDesk.assistant_documents(articles),
        response_schema: HelpDesk.assistant_schema(),
        max_output_tokens: 800
      }

      options = %{
        agent: @feature,
        metering: %{
          operation_id: Ecto.UUID.generate(),
          feature: @feature,
          organization_id: context.organization_id,
          user_id: context.user_id
        }
      }

      with {:ok, response} <- Llm.generate(request, options),
           {:ok, json} <- Llm.decode_json(response),
           {:ok, answer} <- HelpDesk.evaluate_answer(json, articles),
           {:ok, _message} <-
             HelpDesk.add_message(context, %{
               conversation_id: conversation.id,
               author: "assistant",
               body: answer.body,
               citations: answer.citations,
               guide_id: answer.guide_id,
               confident: answer.confident,
               inserted_at: now
             }) do
        if answer.confident, do: "answered", else: "not_confident"
      else
        _error -> "unavailable"
      end
    else
      [] -> "no_articles"
      {:error, _limit} -> "limit_reached"
    end
  end

  defp within_budget(context, now) do
    limits = Llm.feature_limits(:help_desk)
    windows = Llm.budget_windows(now)
    spent = AiUsage.usage_summary(context, %{from: windows.month_start, feature: @feature})

    Llm.check_budget(limits, %{
      spent_nano_usd: spent.cost_nano_usd,
      # The message just written is counted, so the limit is inclusive.
      used_today:
        HelpDesk.count_person_messages_since(context, context.user_id, windows.day_start) - 1
    })
  end

  # -- helpers ---------------------------------------------------------------

  defp person_message(context, conversation, text, now) do
    HelpDesk.add_message(context, %{
      conversation_id: conversation.id,
      author: "person",
      author_id: context.user_id,
      body: text,
      inserted_at: now
    })
  end

  defp reopen_ticket(context, %{status: status} = ticket) when status != "open" do
    case HelpDesk.update_ticket(context, ticket.id, %{status: "open", solved_at: nil}) do
      {:ok, _ticket} -> :ok
      error -> error
    end
  end

  defp reopen_ticket(_context, _ticket), do: :ok

  defp own(context, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        case HelpDesk.get_conversation(context, id) do
          %{user_id: user_id} = conversation when user_id == context.user_id ->
            {:ok, conversation}

          _other ->
            {:error, :not_found}
        end

      :error ->
        {:error, :not_found}
    end
  end

  defp view(context, id, outcome) when is_binary(id) do
    view(context, HelpDesk.get_conversation(context, id), outcome)
  end

  defp view(context, conversation, outcome) do
    ticket = HelpDesk.ticket_for_conversation(context, conversation.id)

    conversation
    |> summary()
    |> Map.merge(%{
      assistant: outcome,
      can_hand_off: is_nil(ticket),
      ticket: ticket && %{id: ticket.id, status: ticket.status, priority: ticket.priority},
      messages: context |> HelpDesk.list_messages(conversation.id) |> Enum.map(&message/1)
    })
  end

  defp summary(conversation) do
    %{
      id: conversation.id,
      status: conversation.status,
      subject: conversation.subject,
      locale: conversation.locale,
      screen_path: conversation.screen_path,
      last_message_at: conversation.last_message_at,
      started_at: conversation.inserted_at
    }
  end

  defp message(message) do
    %{
      id: message.id,
      author: message.author,
      body: message.body,
      citations: message.citations || [],
      guide_id: message.guide_id,
      confident: message.confident,
      sent_at: message.inserted_at
    }
  end

  defp last_person_text(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value("", fn
      %{author: "person", body: body} -> body
      _other -> nil
    end)
  end

  defp stringify(params) when is_map(params),
    do: Map.new(params, fn {k, v} -> {to_string(k), v} end)

  defp stringify(_params), do: %{}

  defp param(params, key), do: Map.get(params, key, Map.get(params, Atom.to_string(key)))
end
