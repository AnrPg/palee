defmodule Palee.Channels.SendingTest do
  @moduledoc """
  ADR-348..351 end to end under Row Level Security: the connection, a
  member's number and consent, the outbox (idempotency, quiet hours,
  budget cap, consent checked again at send time, retries), the webhook
  (receipts once each, STOP) and the Brevo adapter (stubbed HTTP).
  """

  use Palee.DataCase, async: false

  @moduletag :rls_enforced

  import Palee.AnalyticsHelpers, only: [organization_fixture: 0, member_context: 1]

  alias Palee.{Channels, Repo}
  alias Palee.Channels.Unsubscribe
  alias Palee.Application.Channels.{AutomationSmsChannel, ChannelContacts, SendThroughChannel}
  alias Palee.Infrastructure.Channels.SandboxChannel

  # 12:00 in Athens.
  @noon ~U[2026-11-10 10:00:00.000000Z]
  # 22:30 in Athens.
  @late ~U[2026-11-10 20:30:00.000000Z]

  setup do
    {organization, owner, context} = bypass_rls(fn -> organization_fixture() end)
    {member, _member_context} = bypass_rls(fn -> member_context(organization) end)

    env = %{now: @noon, time_zone: "Europe/Athens", box_name: "CF Αθήνα"}

    %{organization: organization, owner: owner, context: context, member: member, env: env}
  end

  defp connect(ctx, attrs \\ %{}) do
    {:ok, connection} =
      Channels.save_connection(
        ctx.context,
        Map.merge(%{provider: "sandbox", channels: ["sms"], monthly_budget_cents: 2000}, attrs),
        ctx.owner.id
      )

    connection
  end

  defp contact(ctx, consents \\ [{"sms", "service"}]) do
    {:ok, contact} =
      Channels.save_contact(ctx.context, {:user, ctx.member.id}, %{phone: "6912345678"}, "GR")

    Enum.reduce(consents, contact, fn {channel, purpose}, _acc ->
      {:ok, updated} =
        Channels.set_consent(
          ctx.context,
          contact.id,
          %{
            channel: channel,
            purpose: purpose,
            granted: true,
            source: "person",
            text_version: "v1"
          },
          ctx.member.id,
          @noon
        )

      updated
    end)
  end

  defp request(ctx, overrides \\ %{}) do
    Map.merge(
      %{
        person: {:user, ctx.member.id},
        template_key: "class_cancelled",
        variables: %{"class" => "WOD", "when" => "Τρι 18:00"},
        idempotency_key: "k-#{System.unique_integer([:positive])}",
        source: "automation"
      },
      overrides
    )
  end

  test "nothing goes before the box connects a provider and the person agrees", ctx do
    assert {:error, :channels_not_connected} = Channels.send(ctx.context, request(ctx), ctx.env)

    connect(ctx)
    assert {:error, :channel_contact_missing} = Channels.send(ctx.context, request(ctx), ctx.env)

    contact(ctx, [])
    assert {:error, :channel_consent_missing} = Channels.send(ctx.context, request(ctx), ctx.env)

    # Marketing consent never stands in for service consent.
    contact(ctx, [{"sms", "marketing"}])
    assert {:error, :channel_consent_missing} = Channels.send(ctx.context, request(ctx), ctx.env)
  end

  test "a box in demo mode sends nothing, and sends once activated", ctx do
    connect(ctx)
    contact(ctx)

    demo =
      bypass_rls(fn ->
        ctx.organization |> Ecto.Changeset.change(activation: "demo") |> Repo.update!()
      end)

    demo_env = SendThroughChannel.env(%{organization_id: ctx.organization.id}, @noon)
    assert demo_env.demo

    assert {:error, :channels_demo_mode} =
             Channels.send(ctx.context, request(ctx), demo_env)

    demo_context = Map.put(ctx.context, :organization, demo)

    assert {:error, :channels_demo_mode} =
             SendThroughChannel.preview(
               demo_context,
               %{user_id: ctx.member.id, template_key: "class_cancelled", source: "staff"},
               @noon
             )

    bypass_rls(fn ->
      demo |> Ecto.Changeset.change(activation: "active") |> Repo.update!()
    end)

    active_env = SendThroughChannel.env(%{organization_id: ctx.organization.id}, @noon)
    refute active_env.demo
    assert {:ok, _message} = Channels.send(ctx.context, request(ctx), active_env)
  end

  test "a message is queued once per key, rendered in the person's language and sent", ctx do
    connect(ctx)
    contact(ctx)
    req = request(ctx)

    assert {:ok, message} = Channels.send(ctx.context, req, ctx.env)
    assert message.status == "queued"
    assert message.channel == "sms"
    assert message.to_phone == "+306912345678"
    assert message.body =~ "CF Αθήνα: Το μάθημα WOD στις Τρι 18:00 ακυρώθηκε"
    assert message.segments == 2
    assert message.estimated_cost_cents == 14

    assert {:ok, again} = Channels.send(ctx.context, req, ctx.env)
    assert again.id == message.id

    assert {:error, :idempotency_key_reused} =
             Channels.send(ctx.context, %{req | template_key: "booking_reminder"}, ctx.env)

    assert {:ok, %{sent: 1}} = Channels.deliver(ctx.context, :due, @noon)

    sent = Channels.get_message(ctx.context, message.id)
    assert sent.status == "sent"
    assert sent.provider_message_id == "sbx_" <> message.id
    assert [%{kind: "attempt", status: "sent"}] = sent.events
  end

  test "quiet hours start at 21:00–09:00, the box can close them, and only marketing waits",
       ctx do
    # ANR 2026-11-03: open from the start.
    connection = connect(ctx)
    assert {connection.quiet_start_minute, connection.quiet_end_minute} == {21 * 60, 9 * 60}
    connect(ctx, %{quiet_start: nil, quiet_end: nil})
    contact(ctx, [{"sms", "service"}, {"sms", "marketing"}])

    marketing =
      request(ctx, %{template_key: "win_back", variables: %{"text" => "Σε περιμένουμε!"}})

    assert {:ok, at_once} = Channels.send(ctx.context, marketing, %{ctx.env | now: @late})
    assert at_once.next_attempt_at == @late
    assert at_once.hold_reason == nil

    connect(ctx, %{quiet_start: "21:00", quiet_end: "09:00"})

    assert {:ok, held} =
             Channels.send(ctx.context, %{marketing | idempotency_key: "late-offer"}, %{
               ctx.env
               | now: @late
             })

    assert held.hold_reason == "quiet_hours"
    assert held.next_attempt_at == ~U[2026-11-11 07:00:00.000000Z]

    # Service messages (a class cancelled, a reminder) always go, urgent or not.
    assert {:ok, service} = Channels.send(ctx.context, request(ctx), %{ctx.env | now: @late})
    assert service.next_attempt_at == @late
    assert service.hold_reason == nil

    assert {:ok, urgent} =
             Channels.send(ctx.context, request(ctx, %{urgent: true}), %{ctx.env | now: @late})

    assert urgent.next_attempt_at == @late
    assert {:ok, %{sent: 3}} = Channels.deliver(ctx.context, :due, @late)
    assert {:ok, %{sent: 1}} = Channels.deliver(ctx.context, :due, ~U[2026-11-11 07:00:01Z])
  end

  test "quiet hours follow the recipient's own clock, else the box's", ctx do
    # ANR 2026-11-03: 21:00–09:00 relative to the person's time zone.
    connect(ctx)
    contact(ctx, [{"sms", "marketing"}])

    offer = fn key ->
      request(ctx, %{
        template_key: "win_back",
        variables: %{"text" => "Έλα!"},
        idempotency_key: key
      })
    end

    member_id = ctx.member.id

    # 20:30 UTC is 22:30 in Athens (the box) but 20:30 in London: it goes now.
    london = Map.put(ctx.env, :recipient_time_zone, fn ^member_id -> "Europe/London" end)
    assert {:ok, now} = Channels.send(ctx.context, offer.("london"), %{london | now: @late})
    assert now.hold_reason == nil

    # In Tokyo it is 05:30: it waits for 09:00 Tokyo time.
    tokyo = Map.put(ctx.env, :recipient_time_zone, fn _id -> "Asia/Tokyo" end)
    assert {:ok, held} = Channels.send(ctx.context, offer.("tokyo"), %{tokyo | now: @late})
    assert held.hold_reason == "quiet_hours"
    assert held.next_attempt_at == ~U[2026-11-11 00:00:00.000000Z]

    # Unknown zone: the box's clock (22:30 Athens) holds it until 09:00 Athens.
    unknown = Map.put(ctx.env, :recipient_time_zone, fn _id -> nil end)
    assert {:ok, boxed} = Channels.send(ctx.context, offer.("unknown"), %{unknown | now: @late})
    assert boxed.next_attempt_at == ~U[2026-11-11 07:00:00.000000Z]
  end

  test "a person's zone is used only when the device reported a real one", ctx do
    alias Palee.Application.Channels.SendThroughChannel
    assert SendThroughChannel.recipient_time_zone(nil) == nil
    {:ok, _user} = Palee.Identity.update_time_zone(ctx.member.id, "Europe/Berlin")
    assert SendThroughChannel.recipient_time_zone(ctx.member.id) == "Europe/Berlin"
    {:ok, _user} = Palee.Identity.update_time_zone(ctx.member.id, "Etc/UTC")
    assert SendThroughChannel.recipient_time_zone(ctx.member.id) == nil
  end

  test "the box types its own cap: SMS cannot go on without one, and nothing is sent", ctx do
    # ADR-390: no invented 20 € default.
    assert {:error, {:invalid_fields, %{monthly_budget_cents: "required"}}} =
             Channels.save_connection(
               ctx.context,
               %{provider: "sandbox", channels: ["sms"]},
               ctx.owner.id
             )

    assert {:error, {:invalid_fields, %{monthly_budget_cents: "invalid"}}} =
             Channels.save_connection(
               ctx.context,
               %{provider: "sandbox", channels: ["sms"], monthly_budget_cents: -1},
               ctx.owner.id
             )

    # Connecting with every channel off needs no cap yet.
    assert {:ok, %{monthly_budget_cents: nil}} =
             Channels.save_connection(
               ctx.context,
               %{provider: "sandbox", channels: []},
               ctx.owner.id
             )

    # A row left without a cap (a connection saved before the rule) sends nothing.
    bypass_rls(fn ->
      Repo.query!(
        "UPDATE channel_connections SET channels = '{sms}' WHERE organization_id = $1",
        [Ecto.UUID.dump!(ctx.organization.id)]
      )
    end)

    contact(ctx)
    assert {:error, :channel_budget_missing} = Channels.send(ctx.context, request(ctx), ctx.env)

    assert {:error, :channel_budget_missing} =
             Channels.preview(ctx.context, request(ctx), ctx.env)

    assert {:ok, %{monthly_budget_cents: 1500}} =
             Channels.save_connection(ctx.context, %{monthly_budget_cents: 1500}, ctx.owner.id)

    assert {:ok, _message} = Channels.send(ctx.context, request(ctx), ctx.env)
  end

  test "the monthly budget cap refuses what would pass it", ctx do
    connect(ctx, %{monthly_budget_cents: 20})
    contact(ctx)

    assert {:ok, _first} = Channels.send(ctx.context, request(ctx), ctx.env)
    assert {:error, :channel_budget_exceeded} = Channels.send(ctx.context, request(ctx), ctx.env)

    assert {:ok, %{spent_cents: 14, cap_cents: 20, messages: 1}} =
             Channels.usage(ctx.context, nil, ctx.env)
  end

  test "a consent withdrawn while the message waits cancels it", ctx do
    connect(ctx)
    contact = contact(ctx)
    {:ok, message} = Channels.send(ctx.context, request(ctx), %{ctx.env | now: @late})

    {:ok, _contact} =
      Channels.set_consent(
        ctx.context,
        contact.id,
        %{channel: "sms", purpose: "service", granted: false, source: "person"},
        ctx.member.id,
        DateTime.add(@late, 60, :second)
      )

    assert {:ok, %{cancelled: 1}} = Channels.deliver(ctx.context, :due, ~U[2026-11-11 07:00:01Z])

    assert %{status: "cancelled", error_code: "channel_consent_missing"} =
             Channels.get_message(ctx.context, message.id)
  end

  test "a refused number fails, an outage retries with backoff, staff can retry", ctx do
    connect(ctx)
    contact(ctx)

    {:ok, _contact} =
      Channels.save_contact(ctx.context, {:user, ctx.member.id}, %{phone: "6912345999"}, "GR")

    {:ok, message} = Channels.send(ctx.context, request(ctx), ctx.env)
    assert {:ok, %{retrying: 1}} = Channels.deliver(ctx.context, :due, @noon)

    waiting = Channels.get_message(ctx.context, message.id)
    assert waiting.status == "queued"
    assert waiting.error_code == "provider_unavailable"
    assert waiting.next_attempt_at == DateTime.add(@noon, 60, :second)

    {:ok, _contact} =
      Channels.save_contact(ctx.context, {:user, ctx.member.id}, %{phone: "6912345000"}, "GR")

    {:ok, refused} = Channels.send(ctx.context, request(ctx), ctx.env)
    assert {:ok, %{failed: 1}} = Channels.deliver(ctx.context, refused.id, @noon)

    assert %{status: "failed", error_code: "provider_rejected"} =
             Channels.get_message(ctx.context, refused.id)

    assert {:ok, %{status: "queued", attempts: 0}} =
             Channels.retry(ctx.context, refused.id, @noon)

    assert {:error, :channel_not_retryable} = Channels.retry(ctx.context, message.id, @noon)
  end

  test "marketing SMS end with a short unsubscribe link; service messages carry none", ctx do
    connect(ctx)
    contact = contact(ctx, [{"sms", "service"}, {"sms", "marketing"}])

    assert {:ok, message} =
             Channels.send(
               ctx.context,
               request(ctx, %{template_key: "win_back", variables: %{"text" => "Σε περιμένουμε!"}}),
               ctx.env
             )

    assert message.purpose == "marketing"
    token = Unsubscribe.token(contact.id)
    assert String.length(token) == 30
    assert Unsubscribe.url(contact.id) == "http://localhost:4000/u/" <> token
    assert String.ends_with?(message.body, " Διακοπή: " <> Unsubscribe.url(contact.id))
    refute message.body =~ "STOP"

    assert {:ok, service} = Channels.send(ctx.context, request(ctx), ctx.env)
    refute service.body =~ "/u/"
  end

  test "the link withdraws only the marketing SMS consent, once, and is logged", ctx do
    connect(ctx)
    contact = contact(ctx, [{"sms", "service"}, {"sms", "marketing"}])
    token = Unsubscribe.token(contact.id)

    assert {:ok, %{withdrawn: false, contact: %{id: id}}} = Channels.find_unsubscribe(token)
    assert id == contact.id

    later = DateTime.add(@noon, 60, :second)
    assert {:ok, %{withdrawn: true}} = Channels.unsubscribe(token, later)

    refute Channels.consented?(ctx.context, %{user_id: ctx.member.id}, "sms", "marketing")
    assert Channels.consented?(ctx.context, %{user_id: ctx.member.id}, "sms", "service")

    stored = Channels.find_contact(ctx.context, {:user, ctx.member.id})
    marketing = Enum.find(stored.consents, &(&1.purpose == "marketing"))
    assert marketing.source == "unsubscribe_link"
    assert marketing.withdrawn_at == later
    assert is_nil(stored.opted_out_at)

    # Tapping again changes nothing.
    assert {:ok, %{withdrawn: true}} = Channels.unsubscribe(token, DateTime.add(later, 60))
    again = Channels.find_contact(ctx.context, {:user, ctx.member.id})
    assert Enum.find(again.consents, &(&1.purpose == "marketing")).withdrawn_at == later

    marketing_request =
      request(ctx, %{template_key: "win_back", variables: %{"text" => "Σε περιμένουμε!"}})

    assert {:error, :channel_consent_missing} =
             Channels.send(ctx.context, marketing_request, ctx.env)

    # A changed or made-up token finds nobody.
    <<first, rest::binary>> = token
    forged = <<if(first == ?A, do: ?B, else: ?A)>> <> rest
    assert {:error, :not_found} = Channels.find_unsubscribe(forged)
    assert {:error, :not_found} = Channels.unsubscribe("nonsense", later)

    assert {:error, :not_found} =
             Channels.find_unsubscribe(Unsubscribe.token(Ecto.UUID.generate()))
  end

  describe "webhook" do
    setup ctx do
      connection = connect(ctx)
      contact(ctx)
      {:ok, message} = Channels.send(ctx.context, request(ctx), ctx.env)
      {:ok, _counts} = Channels.deliver(ctx.context, :due, @noon)

      token =
        connection |> Channels.public_connection() |> Map.fetch!(:webhook_url) |> Path.basename()

      %{message: message, token: token, connection: connection}
    end

    defp webhook(ctx, token, params, signature \\ nil) do
      raw = Jason.encode!(params)
      signature = signature || SandboxChannel.signature(%{}, raw)

      Channels.handle_webhook(
        %{organization_id: ctx.organization.id},
        token,
        %{params: params, raw_body: raw, headers: [{"x-palee-signature", signature}]},
        DateTime.add(@noon, 30, :second)
      )
    end

    test "a receipt is applied once", ctx do
      params = %{"message_id" => "sbx_" <> ctx.message.id, "status" => "delivered"}

      assert {:ok, %{receipts: 1}} = webhook(ctx, ctx.token, params)
      assert {:ok, %{receipts: 0}} = webhook(ctx, ctx.token, params)

      assert %{status: "delivered", events: events} =
               Channels.get_message(ctx.context, ctx.message.id)

      assert Enum.map(events, & &1.kind) == ["attempt", "receipt"]
    end

    test "a wrong token or signature is refused", ctx do
      params = %{"message_id" => "sbx_" <> ctx.message.id, "status" => "delivered"}
      assert {:error, :not_found} = webhook(ctx, "wrong", params)
      assert {:error, :invalid_signature} = webhook(ctx, ctx.token, params, "00")
    end

    test "a STOP reply stops every channel for that number", ctx do
      assert {:ok, %{stops: 1}} =
               webhook(ctx, ctx.token, %{"from" => "+306912345678", "text" => "Στοπ"})

      contact = Channels.find_contact(ctx.context, {:user, ctx.member.id})
      assert contact.opted_out_at
      assert Enum.all?(contact.consents, &(&1.source == "stop_keyword"))
      assert {:error, :channel_opted_out} = Channels.send(ctx.context, request(ctx), ctx.env)

      refute Channels.consented?(ctx.context, %{user_id: ctx.member.id}, "sms", "service")
    end
  end

  describe "Brevo" do
    setup ctx do
      previous = Application.get_env(:palee, :channel_managed_accounts)

      Application.put_env(:palee, :channel_managed_accounts, %{
        "brevo" => [secret: "xkeysib-palee", sms_sender: "Palee"]
      })

      Req.Test.set_req_test_to_shared(Palee.ChannelsHttp)

      on_exit(fn -> Application.put_env(:palee, :channel_managed_accounts, previous) end)
      ctx
    end

    test "the box's own key is stored encrypted and never shown", ctx do
      Req.Test.stub(Palee.ChannelsHttp, fn conn ->
        assert conn.request_path == "/v3/account"
        assert Plug.Conn.get_req_header(conn, "api-key") == ["xkeysib-own"]
        Req.Test.json(conn, %{"plan" => [%{"type" => "sms", "credits" => 250}]})
      end)

      {:ok, %{check: check, connection: public}} =
        Palee.Application.Channels.ChannelSettings.save(ctx.context, %{
          "provider" => "brevo",
          "account_mode" => "own",
          "secret" => "xkeysib-own",
          "sms_sender" => "CFAthina",
          "channels" => ["sms"],
          "monthly_budget_cents" => 3000
        })

      assert check.ok
      assert check.details == %{sms_credits: 250}
      assert public.has_secret
      refute Map.has_key?(public, :secret)

      raw =
        bypass_rls(fn ->
          Repo.query!("SELECT secret FROM channel_connections WHERE organization_id = $1", [
            Ecto.UUID.dump!(ctx.organization.id)
          ])
        end)

      [[stored]] = raw.rows
      refute stored == "xkeysib-own"

      assert {:error, {:invalid_fields, %{channels: "invalid"}}} =
               Channels.save_connection(ctx.context, %{channels: ["viber"]}, ctx.owner.id)
    end

    test "Palee's account sends, receipts and STOP come back on the webhook", ctx do
      connection = connect(ctx, %{provider: "brevo", sms_sender: "CFAthina"})
      assert connection.account_mode == "palee"
      contact(ctx)

      test_pid = self()

      Req.Test.stub(Palee.ChannelsHttp, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        send(
          test_pid,
          {:brevo, conn.request_path, Plug.Conn.get_req_header(conn, "api-key"),
           Jason.decode!(body)}
        )

        conn
        |> Plug.Conn.put_status(201)
        |> Req.Test.json(%{"messageId" => 1_234_567, "usedCredits" => 2})
      end)

      {:ok, message} = Channels.send(ctx.context, request(ctx), ctx.env)
      assert {:ok, %{sent: 1}} = Channels.deliver(ctx.context, :due, @noon)

      assert_received {:brevo, "/v3/transactionalSMS/sms", ["xkeysib-palee"], payload}
      assert payload["recipient"] == "306912345678"
      assert payload["sender"] == "CFAthina"
      assert payload["type"] == "transactional"
      assert payload["unicodeEnabled"] == true
      assert payload["webUrl"] =~ "/api/webhooks/channels/#{ctx.organization.id}/"

      assert %{status: "sent", provider_message_id: "1234567"} =
               Channels.get_message(ctx.context, message.id)

      token = Path.basename(payload["webUrl"])
      context = %{organization_id: ctx.organization.id}

      receipt = %{"messageId" => 1_234_567, "msg_status" => "delivered", "to" => "306912345678"}

      assert {:ok, %{receipts: 1}} =
               Channels.handle_webhook(
                 context,
                 token,
                 %{params: receipt, raw_body: "", headers: []},
                 @noon
               )

      assert %{status: "delivered"} = Channels.get_message(ctx.context, message.id)

      reply = %{
        "messageId" => 1_234_567,
        "msg_status" => "replied",
        "to" => "306912345678",
        "reply" => "STOP"
      }

      assert {:ok, %{stops: 1}} =
               Channels.handle_webhook(
                 context,
                 token,
                 %{params: reply, raw_body: "", headers: []},
                 @noon
               )
    end

    test "out of Brevo credits waits and retries", ctx do
      connect(ctx, %{provider: "brevo", sms_sender: "CFAthina"})
      contact(ctx)

      Req.Test.stub(Palee.ChannelsHttp, fn conn ->
        conn |> Plug.Conn.put_status(402) |> Req.Test.json(%{"code" => "not_enough_credits"})
      end)

      {:ok, message} = Channels.send(ctx.context, request(ctx), ctx.env)
      assert {:ok, %{retrying: 1}} = Channels.deliver(ctx.context, :due, @noon)

      assert %{status: "queued", error_code: "provider_unavailable"} =
               Channels.get_message(ctx.context, message.id)
    end
  end

  test "the narrow API and the automations' sms channel", ctx do
    connect(ctx)

    assert {:ok, _result} =
             ChannelContacts.record(ctx.context, %{
               "lead_id" => Ecto.UUID.generate(),
               "phone" => "+35796123456",
               "consents" => [%{"channel" => "sms", "purpose" => "marketing", "granted" => true}],
               "source" => "form",
               "text_version" => "lead-form-v1"
             })

    contact(ctx)

    assert {:ok, %{status: "queued", channel: "sms"}} =
             SendThroughChannel.call(
               ctx.context,
               %{
                 "user_id" => ctx.member.id,
                 "template_key" => "box_message",
                 "variables" => %{"text" => "Το box κλείνει νωρίς σήμερα"},
                 "idempotency_key" => "api-1",
                 "source" => "staff"
               },
               @noon
             )

    recipient = %{kind: :member, user_id: ctx.member.id, organization_id: ctx.organization.id}
    assert AutomationSmsChannel.reachable?(recipient)

    assert {:ok, id} =
             AutomationSmsChannel.deliver(%{
               organization_id: ctx.organization.id,
               delivery_id: "d-1",
               recipe: "welcome",
               purpose: :service,
               recipient: recipient,
               body: "Καλώς ήρθες!",
               url: nil,
               box_name: "CF Αθήνα"
             })

    assert is_binary(id)

    assert {:error, {:permanent, :channel_consent_missing}} =
             AutomationSmsChannel.deliver(%{
               organization_id: ctx.organization.id,
               delivery_id: "d-2",
               purpose: :marketing,
               recipient: recipient,
               body: "Προσφορά",
               box_name: "CF Αθήνα"
             })
  end
end
