defmodule Palee.Channels.OwnVendorsTest do
  @moduledoc """
  ADR-396 under Row Level Security: a box saves its own Twilio, Vonage,
  Infobip, Yuboto or Apifon account (each vendor's fields, secrets
  encrypted and never shown, nothing carried over from another vendor),
  sends through it with the cap and consent rules of ADR-349/390, and the
  vendor's signed receipts come back on the box's webhook.
  """

  use Palee.DataCase, async: false

  @moduletag :rls_enforced

  import Palee.AnalyticsHelpers, only: [organization_fixture: 0, member_context: 1]

  alias Palee.{Channels, Repo}
  alias Palee.Application.Channels.ChannelSettings
  alias Palee.Infrastructure.Channels.{TwilioChannel, VonageChannel}

  @noon ~U[2026-11-10 10:00:00.000000Z]
  @sid "AC" <> String.duplicate("0a", 16)

  setup do
    {organization, owner, context} = bypass_rls(fn -> organization_fixture() end)
    {member, _member_context} = bypass_rls(fn -> member_context(organization) end)
    Req.Test.set_req_test_to_shared(Palee.ChannelsHttp)

    %{
      organization: organization,
      owner: owner,
      context: context,
      member: member,
      env: %{now: @noon, time_zone: "Europe/Athens", box_name: "CF Αθήνα"}
    }
  end

  defp save(ctx, attrs), do: Channels.save_connection(ctx.context, attrs, ctx.owner.id)

  defp stored(ctx, column) do
    %{rows: [[value]]} =
      bypass_rls(fn ->
        Repo.query!("SELECT #{column} FROM channel_connections WHERE organization_id = $1", [
          Ecto.UUID.dump!(ctx.organization.id)
        ])
      end)

    value
  end

  test "each vendor asks for its own fields", ctx do
    assert {:error, {:invalid_fields, %{account_id: "required", secret: "required"}}} =
             save(ctx, %{provider: "twilio", account_mode: "own"})

    assert {:error, {:invalid_fields, %{account_id: "invalid"}}} =
             save(ctx, %{provider: "twilio", account_mode: "own", account_id: "AC1", secret: "t"})

    assert {:error, {:invalid_fields, %{base_url: "invalid"}}} =
             save(ctx, %{
               provider: "infobip",
               account_mode: "own",
               secret: "k",
               base_url: "https://169.254.169.254"
             })

    assert {:error, {:invalid_fields, %{account_mode: "not_available"}}} =
             save(ctx, %{provider: "yuboto", account_mode: "palee"})

    assert {:error, {:invalid_fields, %{sms_sender: "invalid"}}} =
             save(ctx, %{
               provider: "vonage",
               account_mode: "own",
               account_id: "k",
               secret: "s",
               sms_sender: "MG" <> String.duplicate("0f", 16)
             })

    assert {:ok, _twilio_service} =
             save(ctx, %{
               provider: "twilio",
               account_mode: "own",
               account_id: @sid,
               secret: "t",
               sms_sender: "MG" <> String.duplicate("0f", 16)
             })
  end

  test "secrets are encrypted, never shown, and never carried to another vendor", ctx do
    Req.Test.stub(Palee.ChannelsHttp, &Req.Test.json(&1, %{"value" => 12.5}))

    {:ok, %{connection: public, check: check}} =
      ChannelSettings.save(ctx.context, %{
        "provider" => "vonage",
        "account_mode" => "own",
        "account_id" => "vk1",
        "secret" => "vs-secret",
        "webhook_secret" => "sig-secret",
        "base_url" => "https://ignored.example"
      })

    assert check.ok
    assert public.has_secret and public.has_webhook_secret
    refute Map.has_key?(public, :secret) or Map.has_key?(public, :webhook_secret)
    assert public.account_id == "vk1"
    assert public.base_url == nil
    refute stored(ctx, "secret") =~ "vs-secret"
    refute stored(ctx, "webhook_secret") =~ "sig-secret"

    # Same vendor: the secrets stay when not sent.
    assert {:ok, kept} = save(ctx, %{provider: "vonage", sms_sender: "CFAthina"})
    assert kept.secret == "vs-secret" and kept.webhook_secret == "sig-secret"

    # Another vendor starts from nothing.
    assert {:error, {:invalid_fields, %{secret: "required"}}} =
             save(ctx, %{provider: "yuboto", account_mode: "own"})

    assert {:ok, yuboto} = save(ctx, %{provider: "yuboto", account_mode: "own", secret: "y"})
    assert yuboto.account_id == nil and yuboto.webhook_secret == nil

    # Back to Palee's account clears them all.
    assert {:ok, palee} = save(ctx, %{provider: "sandbox", account_mode: "palee"})
    assert palee.secret == nil and palee.account_id == nil
  end

  test "a refused Twilio token marks the connection invalid", ctx do
    Req.Test.stub(Palee.ChannelsHttp, fn conn ->
      conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"code" => 20_003})
    end)

    {:ok, %{check: check, connection: public}} =
      ChannelSettings.save(ctx.context, %{
        "provider" => "twilio",
        "account_mode" => "own",
        "account_id" => @sid,
        "secret" => "wrong"
      })

    refute check.ok
    assert check.error_code == "credentials_rejected"
    assert public.status == "invalid"
  end

  test "Twilio sends with the cap and consent rules and its signed receipt comes back", ctx do
    {:ok, connection} =
      save(ctx, %{
        provider: "twilio",
        account_mode: "own",
        account_id: @sid,
        secret: "tw-token",
        sms_sender: "CFAthina",
        channels: ["sms"],
        monthly_budget_cents: 2000
      })

    {:ok, contact} =
      Channels.save_contact(ctx.context, {:user, ctx.member.id}, %{phone: "6912345678"}, "GR")

    {:ok, _consent} =
      Channels.set_consent(
        ctx.context,
        contact.id,
        %{
          channel: "sms",
          purpose: "service",
          granted: true,
          source: "person",
          text_version: "v1"
        },
        ctx.member.id,
        @noon
      )

    test_pid = self()

    Req.Test.stub(Palee.ChannelsHttp, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:twilio, conn.request_path, URI.decode_query(body)})
      conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{"sid" => "SM42"})
    end)

    {:ok, message} =
      Channels.send(
        ctx.context,
        %{
          person: {:user, ctx.member.id},
          template_key: "class_cancelled",
          variables: %{"class" => "WOD", "when" => "Τρι 18:00"},
          idempotency_key: "k-twilio",
          source: "automation"
        },
        ctx.env
      )

    assert {:ok, %{sent: 1}} = Channels.deliver(ctx.context, :due, @noon)
    assert_received {:twilio, "/2010-04-01/Accounts/" <> _rest, form}
    assert form["To"] == "+306912345678"
    url = form["StatusCallback"]
    assert url == Channels.public_connection(connection).webhook_url

    params = %{"MessageSid" => "SM42", "MessageStatus" => "delivered"}
    token = Path.basename(url)
    org = %{organization_id: ctx.organization.id}

    forged = %{params: params, raw_body: "", headers: [{"x-twilio-signature", "AAAA"}]}
    assert {:error, :invalid_signature} = Channels.handle_webhook(org, token, forged, @noon)

    signed = %{
      forged
      | headers: [{"x-twilio-signature", TwilioChannel.signature("tw-token", url, params)}]
    }

    assert {:ok, %{receipts: 1}} = Channels.handle_webhook(org, token, signed, @noon)
    assert %{status: "delivered"} = Channels.get_message(ctx.context, message.id)
  end

  test "Vonage receipts must be signed once the signature secret is saved", ctx do
    {:ok, connection} =
      save(ctx, %{
        provider: "vonage",
        account_mode: "own",
        account_id: "vk1",
        secret: "vs",
        webhook_secret: "sig"
      })

    token =
      connection |> Channels.public_connection() |> Map.fetch!(:webhook_url) |> Path.basename()

    org = %{organization_id: ctx.organization.id}
    params = %{"messageId" => "V9", "status" => "delivered", "timestamp" => "1"}

    assert {:error, :invalid_signature} =
             Channels.handle_webhook(
               org,
               token,
               %{params: params, raw_body: "", headers: []},
               @noon
             )

    sig = VonageChannel.digest(:sha256, "sig", VonageChannel.signed_data(params))

    # Signed, but no message of this box has that id: nothing changes.
    assert {:ok, %{receipts: 0}} =
             Channels.handle_webhook(
               org,
               token,
               %{params: Map.put(params, "sig", sig), raw_body: "", headers: []},
               @noon
             )
  end
end
