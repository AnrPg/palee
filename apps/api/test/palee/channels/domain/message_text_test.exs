defmodule Palee.Channels.Domain.MessageTextTest do
  use ExUnit.Case, async: true

  alias Palee.Channels.Domain.MessageText

  test "GSM texts go 160 characters in one part, 153 per part after that" do
    assert MessageText.encoding("Class at 18:00") == :gsm7
    assert MessageText.segments("sms", String.duplicate("a", 160)) == 1
    assert MessageText.segments("sms", String.duplicate("a", 161)) == 2
    assert MessageText.segments("sms", String.duplicate("a", 306)) == 2
    assert MessageText.segments("sms", String.duplicate("a", 307)) == 3
  end

  test "extension characters count twice" do
    assert MessageText.segments("sms", String.duplicate("€", 80)) == 1
    assert MessageText.segments("sms", String.duplicate("€", 81)) == 2
  end

  test "lower-case Greek is UCS-2: 70 characters, 67 per part" do
    assert MessageText.encoding("Καλησπέρα") == :ucs2
    assert MessageText.segments("sms", String.duplicate("α", 70)) == 1
    assert MessageText.segments("sms", String.duplicate("α", 71)) == 2
    assert MessageText.segments("sms", String.duplicate("α", 134)) == 2
  end

  test "upper-case Greek letters of the GSM alphabet stay GSM" do
    assert MessageText.encoding("ΔΦΓΛΩΠΨΣΘΞ") == :gsm7
  end

  test "Viber and WhatsApp count as one message" do
    assert MessageText.segments("viber", String.duplicate("α", 500)) == 1
    assert MessageText.segments("whatsapp", String.duplicate("α", 500)) == 1
  end
end
