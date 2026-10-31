defmodule Palee.Automations.Domain.DeliveryPolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Automations.Domain.{DeliveryPolicy, RecipeCatalog}

  @noon ~U[2027-07-01 09:00:00Z]

  defp facts(recipe, overrides) do
    recipe = RecipeCatalog.get!(recipe)

    Map.merge(
      %{
        recipe: recipe,
        automation: %{enabled: true},
        recipient: %{kind: :member, user_id: "u1", in_box: true},
        preferences: nil,
        settings: RecipeCatalog.settings(recipe, %{}),
        channels: ["in_app", "email"],
        time_zone: "Europe/Athens",
        now: @noon
      },
      overrides
    )
  end

  test "sends when the recipe is on and the person is reachable" do
    assert {:send, ["in_app", "email"]} = DeliveryPolicy.decide(facts("welcome", %{}))
  end

  test "a recipe switched off cancels" do
    assert {:cancel, "recipe_off"} =
             DeliveryPolicy.decide(facts("welcome", %{automation: %{enabled: false}}))

    assert {:cancel, "recipe_off"} = DeliveryPolicy.decide(facts("welcome", %{automation: nil}))
  end

  test "opt-outs, gone people and former box members are skipped" do
    assert {:skip, "opted_out"} =
             DeliveryPolicy.decide(facts("birthday", %{preferences: %{opted_out_at: @noon}}))

    assert {:skip, "opted_out"} =
             DeliveryPolicy.decide(
               facts("birthday", %{
                 preferences: %{opted_out_at: nil, opted_out_recipes: ["birthday"]}
               })
             )

    assert {:skip, "recipient_gone"} = DeliveryPolicy.decide(facts("welcome", %{recipient: nil}))

    left = %{kind: :member, user_id: "u1", in_box: false}
    assert {:skip, "not_in_box"} = DeliveryPolicy.decide(facts("welcome", %{recipient: left}))
    # A trial visitor is not a box member yet.
    assert {:send, _} = DeliveryPolicy.decide(facts("trial_follow_up", %{recipient: left}))
  end

  test "leads need contact consent, and marketing consent for marketing recipes" do
    lead = %{kind: :lead, lead_id: "l1", consent_contact_at: @noon, consent_marketing_at: nil}

    assert {:send, _} = DeliveryPolicy.decide(facts("trial_follow_up", %{recipient: lead}))

    assert {:skip, "no_consent"} =
             DeliveryPolicy.decide(
               facts("trial_follow_up", %{recipient: %{lead | consent_contact_at: nil}})
             )

    marketing = RecipeCatalog.get!("win_back") |> Map.put(:audience, [:member, :lead])

    assert {:skip, "no_marketing_consent"} =
             DeliveryPolicy.decide(%{facts("win_back", %{recipient: lead}) | recipe: marketing})

    assert {:skip, "audience"} = DeliveryPolicy.decide(facts("welcome", %{recipient: lead}))
  end

  test "inside quiet hours it waits" do
    night = ~U[2027-07-01 20:30:00Z]

    assert {:defer, ~U[2027-07-02 06:00:00Z]} =
             DeliveryPolicy.decide(facts("welcome", %{now: night}))
  end

  test "failures are retried with growing waits, then given up" do
    assert {:retry, ~U[2027-07-01 09:05:00Z]} = DeliveryPolicy.after_failure(1, @noon)
    assert {:retry, ~U[2027-07-01 09:10:00Z]} = DeliveryPolicy.after_failure(2, @noon)
    assert :give_up = DeliveryPolicy.after_failure(5, @noon)
  end
end
