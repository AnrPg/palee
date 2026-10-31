defmodule Palee.HelpDesk.DomainTest do
  @moduledoc "ADR-363: conversation states, hand-off tickets and the assistant's answer check, pure."

  use ExUnit.Case, async: true

  alias Palee.HelpDesk.Domain.{Assistant, ConversationPolicy}

  @articles [
    %{
      slug: "guide-shop-staff",
      title: "Run your shop",
      summary: "S",
      body: "B",
      guide_id: "shop_staff",
      locale: "en"
    },
    %{
      slug: "feature-finance",
      title: "Finance",
      summary: "S",
      body: "B",
      guide_id: nil,
      locale: "en"
    }
  ]

  test "a person's message moves the conversation" do
    assert ConversationPolicy.after_person_message(%{status: "assistant"}, false) == "assistant"

    assert ConversationPolicy.after_person_message(%{status: "answered_by_palee"}, true) ==
             "waiting_for_palee"

    assert ConversationPolicy.after_person_message(%{status: "resolved"}, true) ==
             "waiting_for_palee"

    assert ConversationPolicy.after_person_message(%{status: "resolved"}, false) == "assistant"
  end

  test "screens drop queries and refuse odd paths; client facts are whitelisted" do
    assert ConversationPolicy.screen("/admin/shop?tab=stock") == "/admin/shop"
    assert ConversationPolicy.screen("javascript:alert(1)") == nil

    assert ConversationPolicy.client_context(%{"app_version" => "3.1.0", "cookie" => "x"}) == %{
             "app_version" => "3.1.0"
           }
  end

  test "a hand-off ticket carries the note, first question, screen and articles tried" do
    conversation = %{
      id: "c",
      user_id: "u",
      subject: "Shop",
      screen_path: "/admin/shop",
      locale: "el"
    }

    messages = [
      %{author: "person", body: "Πώς βάζω προϊόν;", citations: []},
      %{author: "assistant", body: "…", citations: [%{"slug" => "guide-shop-staff"}]}
    ]

    assert {:ok, ticket} =
             ConversationPolicy.ticket(conversation, messages, %{
               "note" => "Δεν δουλεύει",
               "priority" => "urgent"
             })

    assert ticket.summary == "Δεν δουλεύει\n\nΠώς βάζω προϊόν;"
    assert ticket.articles_tried == ["guide-shop-staff"]
    assert ticket.priority == "urgent" and ticket.status == "open"

    assert {:error, {:invalid_fields, %{priority: _}}} =
             ConversationPolicy.ticket(conversation, messages, %{"priority" => "now"})
  end

  test "ticket updates stamp solving and keep valid states" do
    ticket = %{status: "open", priority: "normal", solved_at: nil}
    now = ~U[2026-10-31 10:00:00Z]

    assert {:ok, %{status: "solved", solved_at: ^now}} =
             ConversationPolicy.ticket_update(ticket, %{"status" => "solved"}, now)

    assert {:error, _} = ConversationPolicy.ticket_update(ticket, %{"status" => "closed"}, now)

    assert ConversationPolicy.conversation_status_for_ticket("waiting_on_box") ==
             "answered_by_palee"
  end

  test "the assistant may cite only given articles and suggest only their guides" do
    assert {:ok,
            %{
              confident: true,
              guide_id: "shop_staff",
              citations: [%{"slug" => "guide-shop-staff"}]
            }} =
             Assistant.evaluate(
               %{
                 "answer" => "Πάτα «Νέο προϊόν».",
                 "citations" => ["guide-shop-staff", "made-up"],
                 "confident" => true,
                 "guide_id" => "shop_staff"
               },
               @articles
             )

    assert {:ok, %{confident: false, guide_id: nil}} =
             Assistant.evaluate(
               %{
                 "answer" => "x",
                 "citations" => ["made-up"],
                 "confident" => true,
                 "guide_id" => "finance_offers"
               },
               @articles
             )

    assert {:error, :llm_invalid_answer} = Assistant.evaluate(%{"answer" => " "}, @articles)
  end

  test "documents are cleaned and capped; history keeps the last turns" do
    [doc | _] = Assistant.documents([%{hd(@articles) | body: String.duplicate("x", 5_000)}])
    assert String.length(doc.text) <= 3_000
    assert doc.id == "guide-shop-staff"

    messages =
      for i <- 1..10,
          do: %{author: if(rem(i, 2) == 1, do: "person", else: "assistant"), body: "m#{i}"}

    turns = Assistant.turns(messages)
    assert length(turns) == Assistant.history()
    assert List.last(turns) == %{role: :assistant, text: "m10", tool_calls: [], turn: nil}
  end
end
