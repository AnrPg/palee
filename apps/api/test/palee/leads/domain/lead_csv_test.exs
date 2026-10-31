defmodule Palee.Leads.Domain.LeadCsvTest do
  use ExUnit.Case, async: true

  alias Palee.Leads.Domain.LeadCsv

  test "finds Greek and English headers and reports bad rows" do
    csv = """
    Ονοματεπώνυμο;Email;Κινητό;Σημειώσεις
    Γιώργος Π.;giorgos@example.com;6941234567;Θέλει πρωινά
    ;nobody@example.com;;
    Άννα;;;
    """

    assert {:ok, [first, second, third]} = LeadCsv.parse(csv)
    assert %{row: 2, attrs: %{name: "Γιώργος Π.", phone: "6941234567", message: "Θέλει πρωινά"}} = first
    assert %{row: 3, errors: %{"name" => "required"}} = second
    assert %{row: 4, errors: %{"contact" => "email_or_phone_required"}} = third
  end

  test "joins first and last name columns" do
    csv = "first_name,last_name,email\nMaria,Papa,maria@example.com\n"
    assert {:ok, [%{attrs: %{name: "Maria Papa"}}]} = LeadCsv.parse(csv)
  end

  test "a file without a name column is refused" do
    assert {:error, :missing_name_column} = LeadCsv.parse("email,phone\na@b.gr,123\n")
  end
end
