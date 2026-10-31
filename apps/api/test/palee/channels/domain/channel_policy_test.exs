defmodule Palee.Channels.Domain.ChannelPolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Channels.Domain.ChannelPolicy

  @t1 ~U[2026-10-01 10:00:00.000000Z]
  @t2 ~U[2026-10-02 10:00:00.000000Z]

  defp facts(overrides) do
    Map.merge(
      %{
        connection: %{channels: ["sms", "viber"], channel_order: ["viber", "sms"]},
        contact: %{opted_out_at: nil},
        consents: [],
        purpose: "service",
        preferred: nil,
        whatsapp_template?: false
      },
      overrides
    )
  end

  defp consent(channel, purpose, granted, withdrawn \\ nil),
    do: %{channel: channel, purpose: purpose, granted_at: granted, withdrawn_at: withdrawn}

  test "the first switched-on channel the person agreed to wins" do
    assert {:ok, "sms"} = ChannelPolicy.choose(facts(%{consents: [consent("sms", "service", @t1)]}))

    assert {:ok, "viber"} =
             ChannelPolicy.choose(
               facts(%{consents: [consent("sms", "service", @t1), consent("viber", "service", @t1)]})
             )

    assert {:ok, "sms"} =
             ChannelPolicy.choose(
               facts(%{
                 preferred: ["sms", "viber"],
                 consents: [consent("sms", "service", @t1), consent("viber", "service", @t1)]
               })
             )
  end

  test "marketing consent never stands in for service consent, nor the reverse" do
    assert {:error, :channel_consent_missing} =
             ChannelPolicy.choose(facts(%{consents: [consent("sms", "marketing", @t1)]}))

    assert {:error, :channel_consent_missing} =
             ChannelPolicy.choose(
               facts(%{purpose: "marketing", consents: [consent("sms", "service", @t1)]})
             )
  end

  test "a withdrawal after the grant wins; a later grant wins again" do
    assert {:error, :channel_consent_missing} =
             ChannelPolicy.choose(facts(%{consents: [consent("sms", "service", @t1, @t2)]}))

    assert {:ok, "sms"} =
             ChannelPolicy.choose(facts(%{consents: [consent("sms", "service", @t2, @t1)]}))
  end

  test "STOP stops every channel" do
    assert {:error, :channel_opted_out} =
             ChannelPolicy.choose(
               facts(%{contact: %{opted_out_at: @t2}, consents: [consent("sms", "service", @t1)]})
             )
  end

  test "a channel the box did not switch on, and WhatsApp without an approved template" do
    assert {:error, :channel_not_enabled} =
             ChannelPolicy.choose(facts(%{preferred: ["whatsapp"]}))

    assert {:error, :whatsapp_template_missing} =
             ChannelPolicy.choose(
               facts(%{
                 connection: %{channels: ["whatsapp"], channel_order: ["whatsapp"]},
                 consents: [consent("whatsapp", "service", @t1)]
               })
             )
  end

  test "STOP words in Greek and English, without accents or case" do
    for text <- ["STOP", "stop", " Stop! ", "ΣΤΟΠ", "στοπ", "Διακοπή", "ΑΠΕΓΓΡΑΦΗ", "unsubscribe"] do
      assert ChannelPolicy.stop_keyword?(text), text
    end

    refute ChannelPolicy.stop_keyword?("please don't stop")
    refute ChannelPolicy.stop_keyword?("ok")
    refute ChannelPolicy.stop_keyword?(nil)
  end
end
