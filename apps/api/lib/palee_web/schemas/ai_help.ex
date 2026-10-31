defmodule PaleeWeb.Schemas.AiHelp do
  @moduledoc """
  OpenAPI schemas of W6 (v3.1): questions over the box's data (ADR-361),
  the help centre (ADR-362) and in-app support with its AI first line and
  the Palee team's ticket queue (ADR-363).
  """

  alias OpenApiSpex.{MediaType, RequestBody, Schema}
  alias Palee.{DataQuestions, HelpCentre, HelpDesk}

  @uuid %Schema{type: :string, format: :uuid}
  @datetime %Schema{type: :string, format: :"date-time"}
  @nullable_datetime %Schema{type: :string, format: :"date-time", nullable: true}
  @nullable_string %Schema{type: :string, nullable: true}
  @nullable_uuid %Schema{type: :string, format: :uuid, nullable: true}
  @any_object %Schema{type: :object, additionalProperties: true}

  def uuid, do: @uuid

  def body(schema),
    do: %RequestBody{required: true, content: %{"application/json" => %MediaType{schema: schema}}}

  defp object(title, properties, required),
    do: %Schema{
      title: title,
      type: :object,
      properties: properties,
      required: Enum.sort(required)
    }

  defp request(title, properties, required),
    do: %{object(title, properties, required) | additionalProperties: false}

  defp list(schema), do: %Schema{type: :array, items: schema}
  defp enum(values), do: %Schema{type: :string, enum: values}
  defp nullable_enum(values), do: %Schema{type: :string, enum: values, nullable: true}
  defp locale, do: enum(HelpCentre.locales())

  # -- data questions (ADR-361) ----------------------------------------------

  def data_question_request do
    request(
      "DataQuestionRequest",
      %{
        question: %Schema{type: :string, minLength: 1, maxLength: 500},
        locale: %Schema{type: :string, maxLength: 10, description: "Answer language (12 locales)"}
      },
      [:question]
    )
  end

  def data_query do
    object(
      "DataQuery",
      %{
        name: enum(DataQuestions.query_names()),
        version: %Schema{type: :integer},
        summary: %Schema{type: :string},
        people: %Schema{type: :boolean, description: "Its results list people (names shown only to staff)"},
        arguments: %{@any_object | description: "JSON Schema of the arguments"}
      },
      [:arguments, :name, :people, :summary, :version]
    )
  end

  def data_catalogue do
    object(
      "DataQuestionCatalogue",
      %{
        enabled: %Schema{type: :boolean, description: "Settings › AI switch (owner)"},
        queries: list(data_query()),
        daily_limit: %Schema{type: :integer, nullable: true},
        asked_today: %Schema{type: :integer}
      },
      [:asked_today, :daily_limit, :enabled, :queries]
    )
  end

  defp citation do
    object(
      "DataQuestionCitation",
      %{
        ref: %Schema{type: :string, description: "q1, q2… as written in the answer"},
        query: %Schema{type: :string},
        arguments: @any_object,
        summary: @any_object
      },
      [:arguments, :query, :ref, :summary]
    )
  end

  defp table do
    object(
      "DataQuestionTable",
      %{
        ref: %Schema{type: :string},
        query: %Schema{type: :string},
        columns: list(%Schema{type: :string}),
        rows: list(@any_object)
      },
      [:columns, :query, :ref, :rows]
    )
  end

  defp action do
    object(
      "DataQuestionAction",
      %{
        kind: enum(["message_people"]),
        ref: %Schema{type: :string},
        user_ids: list(@uuid),
        count: %Schema{type: :integer}
      },
      [:count, :kind, :ref, :user_ids]
    )
  end

  def data_question do
    object(
      "DataQuestion",
      %{
        id: @uuid,
        status: enum(~w(answered unanswerable failed refused)),
        error_code: @nullable_string,
        question: %Schema{type: :string},
        locale: %Schema{type: :string},
        answer: @nullable_string,
        grounded: %Schema{
          type: :boolean,
          description: "Every number in the answer was found in the cited data"
        },
        unsupported_numbers: list(%Schema{type: :string}),
        citations: list(citation()),
        queries: list(%Schema{type: :string}),
        tables: %{
          list(table())
          | description: "Built by the server, only in the answer to the question (never stored)"
        },
        actions: list(action()),
        asked_by_id: @nullable_uuid,
        asked_at: @datetime
      },
      [
        :actions,
        :answer,
        :asked_at,
        :asked_by_id,
        :citations,
        :error_code,
        :grounded,
        :id,
        :locale,
        :queries,
        :question,
        :status,
        :tables,
        :unsupported_numbers
      ]
    )
  end

  def data_questions,
    do: object("DataQuestionList", %{questions: list(data_question())}, [:questions])

  # -- help centre (ADR-362) -------------------------------------------------

  def help_article do
    object(
      "HelpArticle",
      %{
        slug: %Schema{type: :string},
        locale: locale(),
        title: %Schema{type: :string},
        summary: %Schema{type: :string},
        body: %Schema{type: :string, description: "Markdown without HTML"},
        audience: enum(HelpCentre.audiences()),
        feature_key: @nullable_string,
        guide_id: %{@nullable_string | description: "In-app guide it can start (ADR-193)"},
        screens: list(%Schema{type: :string}),
        complete: %Schema{type: :boolean, description: "Fully translated"},
        fallback: %Schema{type: :boolean, description: "Shown in English: no translation yet"},
        updated_at: @nullable_datetime
      },
      [
        :audience,
        :body,
        :complete,
        :fallback,
        :feature_key,
        :guide_id,
        :locale,
        :screens,
        :slug,
        :summary,
        :title,
        :updated_at
      ]
    )
  end

  def help_articles,
    do:
      object(
        "HelpArticleList",
        %{locale: locale(), articles: list(help_article())},
        [:articles, :locale]
      )

  def console_article do
    %{
      help_article()
      | title: "HelpArticleConsole",
        properties:
          Map.merge(help_article().properties, %{
            id: @uuid,
            status: enum(HelpCentre.statuses()),
            source: enum(~w(seed palee)),
            version: %Schema{type: :integer},
            keywords: list(%Schema{type: :string}),
            position: %Schema{type: :integer},
            published_at: @nullable_datetime
          }),
        required:
          Enum.sort(
            help_article().required ++
              [:id, :keywords, :position, :published_at, :source, :status, :version]
          )
    }
  end

  def console_articles,
    do: object("HelpArticleConsoleList", %{articles: list(console_article())}, [:articles])

  def help_article_request do
    request(
      "HelpArticleWrite",
      %{
        title: %Schema{type: :string, minLength: 1, maxLength: 160},
        summary: %Schema{type: :string, minLength: 1, maxLength: 500},
        body: %Schema{type: :string, maxLength: 20_000},
        audience: enum(HelpCentre.audiences()),
        feature_key: @nullable_string,
        guide_id: @nullable_string,
        screens: %{list(%Schema{type: :string, maxLength: 200}) | maxItems: 20},
        keywords: %{list(%Schema{type: :string, maxLength: 60}) | maxItems: 30},
        status: enum(HelpCentre.statuses()),
        position: %Schema{type: :integer, minimum: 0, maximum: 10_000}
      },
      []
    )
  end

  def flag(title, key),
    do: object(title, %{key => %Schema{type: :boolean}}, [key])

  # -- help desk (ADR-363) ---------------------------------------------------

  defp client_context do
    request(
      "HelpDeskClientContext",
      %{
        app_version: %Schema{type: :string, maxLength: 80},
        platform: %Schema{type: :string, maxLength: 80},
        browser: %Schema{type: :string, maxLength: 80},
        viewport: %Schema{type: :string, maxLength: 80}
      },
      []
    )
  end

  def start_request do
    request(
      "HelpDeskStart",
      %{
        message: %Schema{type: :string, minLength: 1, maxLength: 2_000},
        screen_path: %Schema{type: :string, maxLength: 300, description: "The app path asked from"},
        locale: %Schema{type: :string, maxLength: 10}
      },
      [:message]
    )
  end

  def message_request do
    request(
      "HelpDeskMessageWrite",
      %{message: %Schema{type: :string, minLength: 1, maxLength: 2_000}},
      [:message]
    )
  end

  def hand_off_request do
    request(
      "HelpDeskHandOff",
      %{
        note: %Schema{type: :string, maxLength: 1_000},
        priority: enum(HelpDesk.priorities()),
        client_context: client_context()
      },
      []
    )
  end

  defp article_citation do
    object(
      "HelpDeskCitation",
      %{slug: %Schema{type: :string}, title: %Schema{type: :string}, locale: %Schema{type: :string}},
      [:locale, :slug, :title]
    )
  end

  def help_desk_message do
    object(
      "HelpDeskMessage",
      %{
        id: @uuid,
        author: enum(~w(person assistant palee)),
        body: %Schema{type: :string},
        citations: list(article_citation()),
        guide_id: @nullable_string,
        confident: %Schema{type: :boolean, nullable: true},
        sent_at: @datetime
      },
      [:author, :body, :citations, :confident, :guide_id, :id, :sent_at]
    )
  end

  defp conversation_properties do
    %{
      id: @uuid,
      status: enum(HelpDesk.statuses()),
      subject: %Schema{type: :string},
      locale: %Schema{type: :string},
      screen_path: @nullable_string,
      last_message_at: @datetime,
      started_at: @datetime
    }
  end

  @conversation_required [:id, :last_message_at, :locale, :screen_path, :started_at, :status, :subject]

  def conversation_summary,
    do: object("HelpDeskConversationSummary", conversation_properties(), @conversation_required)

  def conversations,
    do:
      object(
        "HelpDeskConversationList",
        %{conversations: list(conversation_summary())},
        [:conversations]
      )

  def conversation do
    object(
      "HelpDeskConversation",
      Map.merge(conversation_properties(), %{
        assistant:
          nullable_enum(~w(answered not_confident no_articles limit_reached unavailable skipped)),
        can_hand_off: %Schema{type: :boolean},
        ticket: %Schema{
          title: "HelpDeskTicketRef",
          type: :object,
          nullable: true,
          properties: %{
            id: @uuid,
            status: enum(HelpDesk.ticket_statuses()),
            priority: enum(HelpDesk.priorities())
          },
          required: [:id, :priority, :status]
        },
        messages: list(help_desk_message())
      }),
      @conversation_required ++ [:assistant, :can_hand_off, :messages, :ticket]
    )
  end

  defp ticket_properties do
    %{
      id: @uuid,
      organization_id: @uuid,
      status: enum(HelpDesk.ticket_statuses()),
      priority: enum(HelpDesk.priorities()),
      summary: %Schema{type: :string},
      screen_path: @nullable_string,
      locale: %Schema{type: :string},
      client_context: @any_object,
      articles_tried: list(%Schema{type: :string}),
      requester_id: @nullable_uuid,
      assignee_id: @nullable_uuid,
      first_response_at: @nullable_datetime,
      solved_at: @nullable_datetime,
      opened_at: @datetime,
      updated_at: @datetime
    }
  end

  @ticket_required [
    :articles_tried,
    :assignee_id,
    :client_context,
    :first_response_at,
    :id,
    :locale,
    :opened_at,
    :organization_id,
    :priority,
    :requester_id,
    :screen_path,
    :solved_at,
    :status,
    :summary,
    :updated_at
  ]

  def ticket, do: object("HelpDeskTicket", ticket_properties(), @ticket_required)
  def tickets, do: object("HelpDeskTicketList", %{tickets: list(ticket())}, [:tickets])

  def ticket_detail do
    object(
      "HelpDeskTicketDetail",
      Map.merge(ticket_properties(), %{
        conversation:
          object(
            "HelpDeskTicketConversation",
            %{
              id: @uuid,
              status: enum(HelpDesk.statuses()),
              subject: %Schema{type: :string},
              started_at: @datetime
            },
            [:id, :started_at, :status, :subject]
          ),
        messages: list(help_desk_message())
      }),
      @ticket_required ++ [:conversation, :messages]
    )
  end

  def reply_request do
    request(
      "HelpDeskReply",
      %{
        body: %Schema{type: :string, minLength: 1, maxLength: 4_000},
        status: enum(~w(waiting_on_box solved))
      },
      [:body]
    )
  end

  def ticket_update_request do
    request(
      "HelpDeskTicketUpdate",
      %{
        status: enum(HelpDesk.ticket_statuses()),
        priority: enum(HelpDesk.priorities()),
        assignee_id: @nullable_uuid
      },
      []
    )
  end
end
