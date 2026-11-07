defmodule Palee.Gamification.TrainingQuoteLocaleTest do
  use Palee.DataCase, async: true

  alias Palee.Gamification

  test "a member gets a quote in their language, stable for the day" do
    date = ~D[2027-01-15]

    for locale <- ~w(el en) do
      quote = Gamification.get_training_quote(date, Ecto.UUID.generate(), locale)
      assert quote.locale == locale
    end

    id = Ecto.UUID.generate()

    assert Gamification.get_training_quote(date, id, "el") ==
             Gamification.get_training_quote(date, id, "el")
  end

  test "an unknown language still sees a quote" do
    assert Gamification.get_training_quote(~D[2027-01-15], Ecto.UUID.generate(), "de")
  end

  test "the flippant quotes are gone" do
    refute Repo.get_by(Palee.Gamification.TrainingQuote, body: "Sweat is just fat crying.")
  end
end
