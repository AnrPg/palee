defmodule Palee.Channels.Domain.PhoneNumberTest do
  use ExUnit.Case, async: true

  alias Palee.Channels.Domain.PhoneNumber

  test "Greek mobiles in every common form become E.164" do
    for input <- [
          "6912345678",
          "69 1234 5678",
          "+30 691-234-5678",
          "0030 6912345678",
          "(+30) 691.234.5678"
        ] do
      assert {:ok, "+306912345678"} = PhoneNumber.normalize(input, "GR")
    end
  end

  test "a number without a country code takes the box's country" do
    assert {:ok, "+35796123456"} = PhoneNumber.normalize("96 123456", "CY")
    assert {:ok, "+447700900123"} = PhoneNumber.normalize("07700 900123", "GB")
  end

  test "landlines and malformed numbers of known countries are refused" do
    assert {:error, :invalid_phone} = PhoneNumber.normalize("2101234567", "GR")
    assert {:error, :invalid_phone} = PhoneNumber.normalize("+302101234567", "GR")
    assert {:error, :invalid_phone} = PhoneNumber.normalize("+30691234567", "GR")
    assert {:error, :invalid_phone} = PhoneNumber.normalize("+35722123456", "GR")
    assert {:error, :invalid_phone} = PhoneNumber.normalize("abc", "GR")
    assert {:error, :invalid_phone} = PhoneNumber.normalize(nil, "GR")
    assert {:error, :invalid_phone} = PhoneNumber.normalize("6912345678", "ZZ")
  end

  test "an international number of another country is accepted as written" do
    assert {:ok, "+12025550123"} = PhoneNumber.normalize("+1 202 555 0123", "GR")
  end

  test "country and mask" do
    assert PhoneNumber.country("+306912345678") == "GR"
    assert PhoneNumber.country("+35796123456") == "CY"
    assert PhoneNumber.country("+12025550123") == nil
    assert PhoneNumber.mask("+306912345678") == "+30 •••••••678"
  end
end
