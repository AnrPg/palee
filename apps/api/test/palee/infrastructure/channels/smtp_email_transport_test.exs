defmodule Palee.Infrastructure.Channels.SmtpEmailTransportTest do
  @moduledoc """
  ADR-368: the real SMTP transport never connects to Palee's own network.
  (Talking to a provider is covered by the sandbox transport in the
  integration tests; no test here leaves the machine.)
  """

  use ExUnit.Case, async: true

  alias Palee.Infrastructure.Channels.SmtpEmailTransport

  @smtp %{
    host: "localhost",
    port: 587,
    tls_mode: "starttls",
    username: "box",
    secret: "pw",
    from_address: "hello@box.gr",
    from_name: "Box",
    reply_to: nil
  }

  @email %{
    to: "member@box.gr",
    subject: "Hi",
    text: "Hi",
    html: "<p>Hi</p>",
    message_id: "<1@box.gr>"
  }

  test "a host that resolves to a loopback address is refused before connecting" do
    assert {:error, :host_not_allowed} = SmtpEmailTransport.check(@smtp)
    assert {:error, :host_not_allowed} = SmtpEmailTransport.deliver(@smtp, @email)
  end
end
