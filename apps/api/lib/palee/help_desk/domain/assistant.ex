defmodule Palee.HelpDesk.Domain.Assistant do
  @moduledoc """
  The AI first line of support (ADR-363), pure: its instructions, the
  documents it may answer from and the check of its answer.

  It answers only from help-centre articles retrieved for the question
  (no tools, no box data): the articles go in as quoted documents, the
  answer must cite at least one of them by slug, and may suggest the
  in-app guide of a cited article (ADR-193) to open on the screen. An
  answer citing nothing, or saying it is not confident, offers the hand-off
  to a person instead.
  """

  alias Palee.Llm.Domain.Untrusted

  @version "hd-1"
  @max_answer 2_000
  @max_document 3_000
  @history 6

  @answer_schema %{
    "type" => "object",
    "properties" => %{
      "answer" => %{"type" => "string", "description" => "Short answer in the person's language"},
      "citations" => %{
        "type" => "array",
        "items" => %{"type" => "string"},
        "description" => "Slugs of the articles the answer comes from"
      },
      "confident" => %{
        "type" => "boolean",
        "description" => "false when the articles do not answer the question"
      },
      "guide_id" => %{
        "type" => "string",
        "description" => "The guide_id of a cited article worth starting, or empty"
      }
    },
    "required" => ["answer", "citations", "confident"]
  }

  def version, do: @version
  def answer_schema, do: @answer_schema
  def history, do: @history

  def system(%{locale: locale, screen: screen}) do
    """
    You are the first line of Palee's in-app support for gym staff. Answer only from the \
    reference documents (Palee help-centre articles). Answer in the language with code \
    "#{locale}" unless the person clearly writes in another one.
    The person is on the screen #{screen || "(unknown)"}.

    Rules:
    - Use only the documents. If they do not answer the question, say so in one sentence, \
    set confident to false and suggest talking to the Palee team.
    - Keep it short: a few sentences or steps. Use the app's own button and screen names \
    as the documents write them.
    - Cite the slug of every document you use. If a cited document has a guide_id, you may \
    return it so the app can start that walkthrough.
    - Never ask for passwords, card numbers or other secrets. You cannot change anything \
    in the gym's account.
    #{Untrusted.rule()}
    """
  end

  @doc "Articles as documents for the model (cleaned, capped)."
  def documents(articles) do
    Enum.map(articles, fn article ->
      %{
        id: article.slug,
        title: Untrusted.text(article.title, 160),
        text:
          Untrusted.text(
            "#{article.summary}\n#{article.body}" <>
              if(article.guide_id, do: "\n(guide_id: #{article.guide_id})", else: ""),
            @max_document
          )
      }
    end)
  end

  @doc "The last messages of a conversation, as model turns (oldest first)."
  def turns(messages) do
    messages
    |> Enum.take(-@history)
    |> Enum.map(fn
      %{author: "person", body: body} -> %{role: :user, text: body}
      %{body: body} -> %{role: :assistant, text: body, tool_calls: [], turn: nil}
    end)
  end

  @doc """
  Checks the model's JSON against the articles it was given:
  `{:ok, %{body, citations, guide_id, confident}}` or
  `{:error, :llm_invalid_answer}`.
  """
  def evaluate(%{"answer" => answer} = json, articles) when is_binary(answer) do
    by_slug = Map.new(articles, &{&1.slug, &1})

    cited =
      json
      |> Map.get("citations", [])
      |> List.wrap()
      |> Enum.filter(&Map.has_key?(by_slug, &1))
      |> Enum.uniq()
      |> Enum.map(&Map.fetch!(by_slug, &1))

    guides = cited |> Enum.map(& &1.guide_id) |> Enum.reject(&is_nil/1)
    guide = if Map.get(json, "guide_id") in guides, do: Map.get(json, "guide_id")
    body = Untrusted.text(answer, @max_answer)

    if body == "" do
      {:error, :llm_invalid_answer}
    else
      {:ok,
       %{
         body: body,
         citations:
           Enum.map(cited, &%{"slug" => &1.slug, "title" => &1.title, "locale" => &1.locale}),
         guide_id: guide,
         confident: Map.get(json, "confident") != false and cited != []
       }}
    end
  end

  def evaluate(_json, _articles), do: {:error, :llm_invalid_answer}
end
