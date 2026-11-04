defmodule Palee.Channels.Domain.VendorRulesTest do
  @moduledoc "ADR-396: what each SMS vendor a box brings itself needs."

  use ExUnit.Case, async: true

  alias Palee.Channels.Domain.VendorRules

  @sid "AC" <> String.duplicate("a1", 16)

  test "the vendors and their required fields" do
    assert VendorRules.vendors() == ~w(brevo twilio vonage infobip yuboto apifon)
    refute VendorRules.vendor?("sandbox")
    assert VendorRules.required("twilio") == [:account_id, :secret]
    assert VendorRules.required("infobip") == [:secret, :base_url]
    assert VendorRules.required("yuboto") == [:secret]
    assert VendorRules.fields("vonage") == [:account_id, :secret, :webhook_secret]
  end

  test "missing and malformed credentials name their field" do
    assert VendorRules.credential_errors("twilio", %{}) == %{
             account_id: "required",
             secret: "required"
           }

    assert VendorRules.credential_errors("twilio", %{account_id: "AC12", secret: "t"}) == %{
             account_id: "invalid"
           }

    assert VendorRules.credential_errors("twilio", %{account_id: @sid, secret: "t"}) == %{}

    assert VendorRules.credential_errors("vonage", %{account_id: "abc", secret: "s"}) == %{}

    assert VendorRules.credential_errors("infobip", %{
             secret: "k",
             base_url: "https://evil.example"
           }) ==
             %{base_url: "invalid"}

    assert VendorRules.credential_errors("apifon", %{account_id: "token"}) == %{
             secret: "required"
           }

    assert VendorRules.credential_errors("brevo", %{secret: String.duplicate("x", 301)}) == %{
             secret: "invalid"
           }
  end

  test "Infobip's base URL is only Infobip's own host" do
    assert VendorRules.infobip_base_url?("https://abc12.api.infobip.com")
    assert VendorRules.infobip_base_url?("https://abc12.api.infobip.com/")
    refute VendorRules.infobip_base_url?("http://abc12.api.infobip.com")
    refute VendorRules.infobip_base_url?("https://abc12.api.infobip.com.evil.io")
    refute VendorRules.infobip_base_url?("https://abc12.api.infobip.com:8443")
    refute VendorRules.infobip_base_url?("https://user@abc12.api.infobip.com")
    refute VendorRules.infobip_base_url?("https://abc12.api.infobip.com/sms")
    refute VendorRules.infobip_base_url?(nil)
  end

  test "senders: a name of 11, a number, and Twilio's Messaging Service" do
    for vendor <- VendorRules.vendors() do
      assert VendorRules.sender?(vendor, nil)
      assert VendorRules.sender?(vendor, "CF Athina")
      assert VendorRules.sender?(vendor, "+306912345678")
      refute VendorRules.sender?(vendor, "CrossFitAthina")
      refute VendorRules.sender?(vendor, "Αθήνα")
      refute VendorRules.sender?(vendor, "12345")
    end

    service = "MG" <> String.duplicate("0f", 16)
    assert VendorRules.sender?("twilio", service)
    refute VendorRules.sender?("vonage", service)
    assert VendorRules.sender?("twilio", "MGym")
    refute VendorRules.sender?("twilio", "MG" <> String.duplicate("zz", 16))
  end
end
