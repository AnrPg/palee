defmodule Palee.Channels.OwnEmailTest do
  @moduledoc """
  ADR-368 under Row Level Security: a box's own SMTP email provider. The
  password is encrypted and never shown or exported; «Δοκιμή σύνδεσης»
  decides whether mail may go through it; the box's own messages go
  through it (outside Palee's daily budget) while platform mail always goes
  through Palee's mailer; a refused password falls back to Palee.
  """

  use Palee.DataCase, async: false

  @moduletag :rls_enforced

  import Palee.AnalyticsHelpers, only: [organization_fixture: 0]
  import Palee.EmailCase
  import Swoosh.TestAssertions

  alias Palee.{Channels, Email, Repo}
  alias Palee.Application.Channels.ChannelEmailSettings

  @now ~U[2026-11-10 10:00:00.000000Z]

  @smtp %{
    host: "smtp.mailprovider.com",
    port: 587,
    tls_mode: "starttls",
    username: "box@cfathina.gr",
    secret: "s3cret-smtp",
    from_address: "Hello@CFAthina.gr",
    from_name: "CF Αθήνα",
    reply_to: "desk@cfathina.gr"
  }

  setup do
    {organization, owner, context} = bypass_rls(fn -> organization_fixture() end)
    %{organization: organization, owner: owner, context: context}
  end

  defp connect(ctx, attrs \\ %{}, check? \\ true) do
    {:ok, connection} =
      Channels.save_email_connection(ctx.context, Map.merge(@smtp, attrs), ctx.owner.id)

    if check?, do: {:ok, %{ok: true}} = Channels.check_email_connection(ctx.context, @now)
    connection
  end

  defp box_email(ctx, to \\ "member@box.test") do
    {:ok, message} =
      Email.enqueue(
        :box_automation,
        to,
        %{subject: "Καλώς ήρθες", body: "Σε περιμένουμε.", box_name: "CF Αθήνα"},
        organization_id: ctx.organization.id,
        idempotency_key: "box_automation:#{System.unique_integer([:positive])}"
      )

    message
  end

  test "only the box's own messages may take its route; platform mail never does" do
    box_kinds =
      Palee.Email.Templates.all()
      |> Enum.filter(fn {_kind, template} -> template.origin() == :box end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    # ADR-392: the booking email with its calendar invite is the box's own.
    # ADR-396: so is the reminder of a debt owed to the box.
    assert box_kinds ==
             ~w(booking_invite box_automation corporate_invoice_issued corporate_invoice_reminder debt_reminder fiscal_document)a

    for {kind, template} <- Palee.Email.Templates.all(), template.category() != :transactional do
      assert template.origin() == :platform, "#{kind} is platform mail"
    end
  end

  test "the password is stored encrypted and never shown; a connection change needs a check",
       ctx do
    assert %{connection: nil, ports: [25, 465, 587, 2525], tls_modes: ["starttls", "tls"]} =
             ChannelEmailSettings.show(ctx.context)

    connect(ctx, %{}, false)

    %{connection: public, dns_guidance: guidance} = ChannelEmailSettings.show(ctx.context)
    assert public.has_secret
    refute Map.has_key?(public, :secret)
    assert public.from_address == "hello@cfathina.gr"
    assert public.status == "unchecked"
    refute public.in_use
    assert guidance.domain == "cfathina.gr"

    assert Enum.map(guidance.steps, & &1.key) ==
             ~w(email_dns.spf email_dns.dkim email_dns.dmarc email_dns.same_domain)

    [[stored]] =
      bypass_rls(fn ->
        Repo.query!(
          "SELECT secret FROM channel_email_connections WHERE organization_id = $1",
          [Ecto.UUID.dump!(ctx.organization.id)]
        ).rows
      end)

    refute stored == "s3cret-smtp"
    refute String.contains?(stored, "s3cret-smtp")

    {:ok, %{check: %{ok: true}, connection: checked}} = ChannelEmailSettings.check(ctx.context)
    assert %{status: "active", in_use: true} = checked

    # A new sender name keeps the check; a new password needs a new one, and
    # leaving the password out keeps it.
    {:ok, %{connection: renamed}} =
      ChannelEmailSettings.save(ctx.context, %{"from_name" => "CrossFit Αθήνα"})

    assert %{status: "active", has_secret: true} = renamed

    {:ok, %{connection: changed}} =
      ChannelEmailSettings.save(ctx.context, %{"secret" => "another-secret"})

    assert changed.status == "unchecked"
  end

  test "invalid settings are refused field by field", ctx do
    assert {:error, {:invalid_fields, errors}} =
             Channels.save_email_connection(
               ctx.context,
               %{host: "127.0.0.1", port: 8025, tls_mode: "none", from_address: "nope"},
               ctx.owner.id
             )

    assert errors == %{
             host: "invalid",
             port: "invalid",
             tls_mode: "invalid",
             username: "required",
             secret: "required",
             from_address: "invalid"
           }

    assert {:error, {:invalid_fields, %{host: "invalid"}}} =
             Channels.save_email_connection(
               ctx.context,
               Map.put(@smtp, :host, "mail.internal"),
               ctx.owner.id
             )
  end

  test "«Δοκιμή σύνδεσης» records a refused password or an unreachable host", ctx do
    assert {:error, :email_connection_missing} = ChannelEmailSettings.check(ctx.context)

    connect(ctx, %{secret: "wrong-password"}, false)

    assert {:ok, %{check: %{ok: false, error_code: "credentials_rejected"}, connection: public}} =
             ChannelEmailSettings.check(ctx.context)

    assert %{status: "invalid", in_use: false} = public

    {:ok, _} = ChannelEmailSettings.save(ctx.context, %{"host" => "down.mailprovider.com"})

    assert {:ok, %{check: %{ok: false, error_code: "unreachable"}}} =
             ChannelEmailSettings.check(ctx.context)
  end

  test "the box's own email goes through its SMTP, outside Palee's daily budget", ctx do
    connect(ctx)
    message = box_email(ctx)

    assert deliver_enqueued_emails(@now) == 1

    assert_received {:channel_email_sent, sent}
    assert sent.from == {"CF Αθήνα", "hello@cfathina.gr"}
    assert sent.reply_to == "desk@cfathina.gr"
    assert sent.host == "smtp.mailprovider.com"
    assert sent.to == "member@box.test"
    assert sent.message_id == message.message_id
    refute Map.has_key?(sent, :secret)
    assert_no_email_sent()

    assert %{status: "sent", sent_via: "own"} = Palee.Email.message_store().get(message.id)
    assert Palee.Email.message_store().count_sent_since(~U[2026-11-10 00:00:00Z]) == 0
  end

  test "platform mail and an unchecked or switched-off connection go through Palee", ctx do
    connect(ctx)

    # Platform mail of the same box never uses the box's provider.
    {:ok, platform} =
      Email.enqueue(:sample_notice, "member@box.test", %{name: "Jo", url: "https://palee.app/x"},
        organization_id: ctx.organization.id
      )

    assert deliver_enqueued_emails(@now) == 1
    refute_received {:channel_email_sent, _}
    assert_email_sent(subject: "Hello Jo")
    assert %{sent_via: "palee"} = Palee.Email.message_store().get(platform.id)

    {:ok, _} = ChannelEmailSettings.save(ctx.context, %{"enabled" => false})
    box_email(ctx)
    assert deliver_enqueued_emails(@now) == 1
    refute_received {:channel_email_sent, _}
    assert_email_sent(subject: "Καλώς ήρθες")

    {:ok, _} = ChannelEmailSettings.save(ctx.context, %{"enabled" => true, "port" => 2525})
    box_email(ctx)
    assert deliver_enqueued_emails(@now) == 1
    refute_received {:channel_email_sent, _}
    assert_email_sent(subject: "Καλώς ήρθες")
  end

  test "a password refused at send time marks the connection invalid and Palee sends", ctx do
    connect(ctx)

    # The password changed at the provider after the check.
    {:ok, _} =
      Palee.Channels.ChannelStore.save_email_connection(ctx.context, %{secret: "wrong-password"})

    message = box_email(ctx)
    assert deliver_enqueued_emails(@now) == 1
    refute_received {:channel_email_sent, _}
    assert_email_sent(subject: "Καλώς ήρθες")
    assert %{sent_via: "palee"} = Palee.Email.message_store().get(message.id)

    assert %{status: "invalid", error_code: "credentials_rejected"} =
             Channels.email_connection(ctx.context)
  end

  test "a recipient the box's provider refuses fails for good; an outage is retried", ctx do
    connect(ctx)
    refused = box_email(ctx, "nobody@reject.test")

    assert {:cancel, _} = Email.deliver(refused.id, %{attempt: 1, max_attempts: 8}, @now)
    assert %{status: "failed"} = Palee.Email.message_store().get(refused.id)

    {:ok, _} =
      Palee.Channels.ChannelStore.save_email_connection(ctx.context, %{
        host: "down.mailprovider.com"
      })

    later = box_email(ctx)

    assert {:error, {:transient, :unreachable}} =
             Email.deliver(later.id, %{attempt: 1, max_attempts: 8}, @now)

    assert %{status: "queued", attempts: 1} = Palee.Email.message_store().get(later.id)
  end

  test "removing it sends the box's email through Palee again", ctx do
    connect(ctx)
    assert :ok = ChannelEmailSettings.delete(ctx.context)
    assert %{connection: nil} = ChannelEmailSettings.show(ctx.context)

    box_email(ctx)
    assert deliver_enqueued_emails(@now) == 1
    refute_received {:channel_email_sent, _}
  end

  test "another box never sees the connection, and the export leaves the password out", ctx do
    connect(ctx)
    {_other, _owner, other_context} = bypass_rls(fn -> organization_fixture() end)

    assert Channels.email_connection(other_context) == nil

    purge_context = %Palee.TenantData.PurgeContext{
      organization_id: ctx.organization.id,
      purge_id: Ecto.UUID.generate(),
      user_id: ctx.owner.id
    }

    assert {:ok, export} = Channels.export_tenant_data(purge_context)
    encoded = inspect(export, limit: :infinity, printable_limit: :infinity)
    assert encoded =~ "smtp.mailprovider.com"
    refute encoded =~ "s3cret-smtp"
  end
end
