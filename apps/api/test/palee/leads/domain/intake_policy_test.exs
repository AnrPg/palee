defmodule Palee.Leads.Domain.IntakePolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Leads.Domain.IntakePolicy

  @now ~U[2027-05-02 10:00:00Z]

  describe "normalize/1" do
    test "trims, lowercases the email and keeps the phone as + and digits" do
      assert {:ok, lead} =
               IntakePolicy.normalize(%{
                 "name" => "  Μαρία Π. ",
                 "email" => " Maria@Example.COM ",
                 "phone" => "+30 694 123 4567",
                 "interests" => ["trial", "trial", " "]
               })

      assert lead.name == "Μαρία Π."
      assert lead.email == "maria@example.com"
      assert lead.phone == "+306941234567"
      assert lead.interests == ["trial"]
    end

    test "needs a name and an email or a phone" do
      assert {:error, {:invalid_fields, %{"name" => "required"}}} =
               IntakePolicy.normalize(%{"email" => "a@b.gr"})

      assert {:error, {:invalid_fields, %{"contact" => "email_or_phone_required"}}} =
               IntakePolicy.normalize(%{"name" => "Νίκος"})

      assert {:error, {:invalid_fields, %{"email" => "invalid"}}} =
               IntakePolicy.normalize(%{"name" => "Νίκος", "email" => "not-an-email"})

      assert {:error, {:invalid_fields, %{"phone" => "invalid"}}} =
               IntakePolicy.normalize(%{"name" => "Νίκος", "phone" => "12"})
    end
  end

  describe "consent/3" do
    test "inbound sources need contact consent" do
      assert {:error, {:invalid_fields, %{"consent" => "contact_required"}}} =
               IntakePolicy.consent(%{"marketing" => true}, "form", @now)

      assert {:ok, %{consent_contact_at: @now, consent_marketing_at: nil}} =
               IntakePolicy.consent(%{"contact" => true}, "form", @now)
    end

    test "staff-entered leads imply contact consent; marketing is separate" do
      assert {:ok, %{consent_contact_at: @now, consent_marketing_at: @now, consent_text_version: "v2"}} =
               IntakePolicy.consent(%{contact: true, marketing: true, text_version: "v2"}, "manual", @now)

      assert {:ok, %{consent_marketing_at: nil}} = IntakePolicy.consent(nil, "manual", @now)
    end

    test "a consent time in the future is the time it arrived" do
      assert {:ok, %{consent_contact_at: @now}} =
               IntakePolicy.consent(%{contact: true, given_at: "2099-01-01T00:00:00Z"}, "form", @now)
    end
  end

  describe "spam_check/2" do
    test "a filled hidden field, a fast form or links are spam" do
      assert {:error, :spam} = IntakePolicy.spam_check(%{"website" => "x"}, @now)

      assert {:error, :spam} =
               IntakePolicy.spam_check(%{"form_started_at" => DateTime.to_iso8601(@now)}, @now)

      assert {:error, :spam} = IntakePolicy.spam_check(%{"name" => "buy http://x.io"}, @now)

      assert {:error, :spam} =
               IntakePolicy.spam_check(
                 %{"message" => "http://a.io http://b.io www.c.io"},
                 @now
               )
    end

    test "a person filling the form in is not" do
      started = DateTime.add(@now, -40, :second) |> DateTime.to_unix() |> to_string()

      assert :ok =
               IntakePolicy.spam_check(
                 %{"name" => "Ελένη", "message" => "see https://palee.gr", "form_started_at" => started},
                 @now
               )
    end
  end
end
