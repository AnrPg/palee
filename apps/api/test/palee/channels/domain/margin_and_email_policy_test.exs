defmodule Palee.Channels.Domain.MarginAndEmailPolicyTest do
  @moduledoc "ADR-369 (Palee's margin, box price) and ADR-368 (own SMTP connection) rules."

  use ExUnit.Case, async: true

  alias Palee.Channels.Domain.{CostPolicy, EmailConnectionPolicy}

  describe "Palee's margin (ADR-369)" do
    test "the box price is the provider's price plus the margin, rounded up to a cent" do
      assert CostPolicy.price(7, 0) == 7
      assert CostPolicy.price(7, 2500) == 9
      # 7 × 1.01 = 7.07: a margin never rounds to nothing.
      assert CostPolicy.price(7, 100) == 8
      assert CostPolicy.price(14, 5000) == 21
      assert CostPolicy.price(0, 5000) == 0
    end

    test "the counted cost of a message is the charged price with its own margin" do
      assert CostPolicy.counted(%{cost_cents: 10, margin_bps: 2000, estimated_cost_cents: 9}) ==
               12

      assert CostPolicy.counted(%{cost_cents: 10, estimated_cost_cents: 9}) == 10
      assert CostPolicy.counted(%{cost_cents: nil, estimated_cost_cents: 9}) == 9
    end

    test "margins are whole basis points per known channel, 0 when unset" do
      assert {:ok, %{"sms" => 2500, "viber" => 0, "whatsapp" => 0} = margins} =
               CostPolicy.validate_margins(%{sms: 2500})

      refute Map.has_key?(margins, "email")

      assert {:error, {:invalid_fields, %{"sms" => "invalid", "fax" => "invalid"}}} =
               CostPolicy.validate_margins(%{"sms" => -1, "fax" => 10})

      # Email is included in the subscription: no margin on it.
      assert {:error, {:invalid_fields, %{"email" => "invalid"}}} =
               CostPolicy.validate_margins(%{"email" => 1_000})

      assert {:error, {:invalid_fields, %{"sms" => "invalid"}}} =
               CostPolicy.validate_margins(%{"sms" => 100_001})

      assert {:error, {:invalid_fields, %{"sms" => "invalid"}}} =
               CostPolicy.validate_margins(%{"sms" => 12.5})

      assert CostPolicy.margin_bps(%{"sms" => 300}, "sms") == 300
      assert CostPolicy.margin_bps(%{}, "sms") == 0
      assert CostPolicy.margin_bps(nil, "sms") == 0
    end
  end

  describe "own SMTP connection (ADR-368)" do
    @valid %{
      host: "smtp.Provider.com ",
      tls_mode: "tls",
      username: "box",
      secret: "pw",
      from_address: "Hello@Box.GR",
      from_name: "Box"
    }

    test "a valid connection is normalised and starts unchecked" do
      assert {:ok, attrs} = EmailConnectionPolicy.validate(nil, @valid)
      assert attrs.host == "smtp.provider.com"
      assert attrs.from_address == "hello@box.gr"
      # The port follows the TLS mode when not given.
      assert attrs.port == 465
      assert attrs.status == "unchecked"
      assert attrs.enabled
    end

    test "only the connection's own settings need a new check" do
      {:ok, saved} = EmailConnectionPolicy.validate(nil, @valid)
      saved = %{saved | status: "active"}

      assert {:ok, %{status: "active"}} =
               EmailConnectionPolicy.validate(saved, %{from_name: "New name", enabled: false})

      assert {:ok, %{status: "active", secret: "pw"}} =
               EmailConnectionPolicy.validate(saved, %{secret: ""})

      assert {:ok, %{status: "unchecked"}} = EmailConnectionPolicy.validate(saved, %{port: 587})
      assert {:ok, %{status: "unchecked"}} = EmailConnectionPolicy.validate(saved, %{secret: "x"})
    end

    test "header injection, wrong addresses and plain-text SMTP are refused" do
      assert {:error, {:invalid_fields, errors}} =
               EmailConnectionPolicy.validate(nil, %{
                 @valid
                 | from_name: "Box\r\nBcc: all@x.gr",
                   tls_mode: "none"
               })

      assert errors == %{from_name: "invalid", tls_mode: "invalid"}

      assert {:error, {:invalid_fields, %{reply_to: "invalid", from_address: "invalid"}}} =
               EmailConnectionPolicy.validate(
                 nil,
                 Map.merge(@valid, %{reply_to: "a@b", from_address: "x y@box.gr"})
               )
    end

    test "only public host names are allowed" do
      assert EmailConnectionPolicy.host_allowed?("smtp-relay.brevo.com")
      assert EmailConnectionPolicy.host_allowed?("mail.box.gr")

      for host <- ~w(localhost 127.0.0.1 10.0.0.5 mail mail.internal smtp.local db.svc
                     a.cluster.local x.test example.com mail_server.gr) do
        refute EmailConnectionPolicy.host_allowed?(host), host
      end
    end

    test "private, loopback and reserved addresses are refused at connect time" do
      assert EmailConnectionPolicy.public_address?({1, 1, 1, 1})
      assert EmailConnectionPolicy.public_address?({2001, 0x4860, 0, 0, 0, 0, 0, 0x8888})

      for address <- [
            {127, 0, 0, 1},
            {10, 1, 2, 3},
            {172, 20, 0, 1},
            {192, 168, 1, 1},
            {169, 254, 169, 254},
            {100, 64, 0, 1},
            {0, 0, 0, 0},
            {224, 0, 0, 1},
            {0, 0, 0, 0, 0, 0, 0, 1},
            {0xFD00, 0, 0, 0, 0, 0, 0, 1},
            {0xFE80, 0, 0, 0, 0, 0, 0, 1},
            {0, 0, 0, 0, 0, 0xFFFF, 0x7F00, 1}
          ] do
        refute EmailConnectionPolicy.public_address?(address), inspect(address)
      end
    end

    test "only a switched-on, checked connection is used" do
      assert EmailConnectionPolicy.usable?(%{enabled: true, status: "active"})
      refute EmailConnectionPolicy.usable?(%{enabled: false, status: "active"})
      refute EmailConnectionPolicy.usable?(%{enabled: true, status: "unchecked"})
      refute EmailConnectionPolicy.usable?(nil)
    end

    test "the DNS guide names the sender's domain" do
      assert %{domain: "box.gr", steps: [spf, dkim, dmarc, _same]} =
               EmailConnectionPolicy.dns_guidance(%{from_address: "hello@box.gr"})

      assert spf == %{key: "email_dns.spf", record: "TXT", host: "box.gr"}
      assert dkim.host == "<selector>._domainkey.box.gr"
      assert dmarc.host == "_dmarc.box.gr"
      assert %{domain: nil} = EmailConnectionPolicy.dns_guidance(nil)
    end
  end
end
