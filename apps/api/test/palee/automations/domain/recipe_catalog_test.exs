defmodule Palee.Automations.Domain.RecipeCatalogTest do
  use ExUnit.Case, async: true

  alias Palee.Automations.Domain.{RecipeCatalog, RecipeTexts}

  test "the six ready recipes, each with a text in every app language" do
    assert RecipeCatalog.keys() ==
             ~w(welcome trial_follow_up missed_classes renewal_reminder birthday win_back)

    supported = Palee.Identity.Domain.Locale.supported() |> Enum.sort()
    assert RecipeTexts.locales() == supported

    for key <- RecipeCatalog.keys(), locale <- supported do
      {subject, body} = RecipeTexts.default(key, locale)
      assert {:ok, _} = RecipeTexts.validate(subject, :subject), "#{key}/#{locale} subject"
      assert {:ok, _} = RecipeTexts.validate(body, :body), "#{key}/#{locale} body"
    end
  end

  test "settings are bounded and keep the defaults" do
    recipe = RecipeCatalog.get!("missed_classes")

    assert %{
             "days_absent" => 10,
             "quiet_from" => "21:00",
             "quiet_until" => "09:00",
             "send_hour" => 10
           } =
             RecipeCatalog.settings(recipe, %{})

    assert %{"days_absent" => 14, "send_hour" => 18} =
             RecipeCatalog.settings(recipe, %{"days_absent" => 14, "send_hour" => 18})

    assert %{"days_absent" => 10} = RecipeCatalog.settings(recipe, %{"days_absent" => 400})

    assert {:ok, _} =
             RecipeCatalog.validate_settings(recipe, %{
               "days_absent" => 7,
               "quiet_from" => "22:00"
             })

    assert {:error, {:invalid_fields, %{"settings.days_absent" => "invalid"}}} =
             RecipeCatalog.validate_settings(recipe, %{"days_absent" => 2})

    assert {:error, _} = RecipeCatalog.validate_settings(recipe, %{"quiet_from" => "25:00"})
    assert {:error, _} = RecipeCatalog.validate_settings(recipe, %{"colour" => 1})
  end

  test "texts render their placeholders and refuse unknown ones" do
    assert RecipeTexts.render("Γεια {first_name}, {days} μέρες {nope}", %{
             "first_name" => "Ελένη",
             "days" => 12
           }) ==
             "Γεια Ελένη, 12 μέρες"

    assert {:error, "unknown_placeholder"} = RecipeTexts.validate("Hi {name}", :body)
    assert {:ok, nil} = RecipeTexts.validate("  ", :body)
    assert {:error, "too_long"} = RecipeTexts.validate(String.duplicate("a", 121), :subject)
  end
end
