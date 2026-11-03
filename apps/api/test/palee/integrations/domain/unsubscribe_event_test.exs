defmodule Palee.Integrations.Domain.UnsubscribeEventTest do
  use ExUnit.Case, async: true

  alias Palee.Integrations.Domain.UnsubscribeEvent

  test "Mailchimp: only unsubscribe, only for the box's list" do
    form = %{"type" => "unsubscribe", "data" => %{"email" => "a@b.gr", "list_id" => "abc"}}
    assert UnsubscribeEvent.emails("mailchimp", "abc", form) == ["a@b.gr"]
    assert UnsubscribeEvent.emails("mailchimp", "other", form) == []
    assert UnsubscribeEvent.emails("mailchimp", "abc", %{form | "type" => "cleaned"}) == []
    assert UnsubscribeEvent.emails("mailchimp", "abc", %{"type" => "subscribe"}) == []
  end

  test "Brevo: unsubscribed for the list, or from every list" do
    event = %{"event" => "unsubscribed", "email" => "a@b.gr", "list_id" => [7, 9]}
    assert UnsubscribeEvent.emails("brevo", "7", event) == ["a@b.gr"]
    assert UnsubscribeEvent.emails("brevo", "8", event) == []
    assert UnsubscribeEvent.emails("brevo", "8", Map.delete(event, "list_id")) == ["a@b.gr"]
    assert UnsubscribeEvent.emails("brevo", "7", %{event | "event" => "delivered"}) == []
  end

  test "nonsense is ignored" do
    assert UnsubscribeEvent.emails("brevo", "7", %{"event" => "unsubscribed", "email" => "x"}) ==
             []

    assert UnsubscribeEvent.emails("mailchimp", "abc", "text") == []
    assert UnsubscribeEvent.emails("unknown", "abc", %{}) == []
  end
end
