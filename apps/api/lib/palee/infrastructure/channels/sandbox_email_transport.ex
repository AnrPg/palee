defmodule Palee.Infrastructure.Channels.SandboxEmailTransport do
  @moduledoc """
  The sandbox SMTP transport (ADR-368): nothing leaves Palee. Used in
  development and tests.

    * the password `wrong-password` is refused (`:unauthorized`);
    * a host starting with `down.` is unreachable (`{:transient, :unreachable}`);
    * a host starting with `private.` resolves to a private address
      (`:host_not_allowed`);
    * a recipient at `@reject.test` is refused for good
      (`{:permanent_failure, _}`).

  Every email it accepts is sent to the calling process as
  `{:channel_email_sent, %{from, reply_to, host, to, subject, message_id}}`,
  so tests can assert which route an email took (never the password).
  """

  @behaviour Palee.Channels.Ports.EmailTransport

  @impl true
  def check(smtp) do
    with :ok <- reach(smtp) do
      {:ok, %{host: smtp.host}}
    end
  end

  @impl true
  def deliver(smtp, email) do
    cond do
      (error = reach(smtp)) != :ok ->
        error

      String.ends_with?(email.to, "@reject.test") ->
        {:error, {:permanent_failure, "550 sandbox: no such user"}}

      true ->
        send(
          self(),
          {:channel_email_sent,
           %{
             from: {smtp[:from_name], smtp.from_address},
             reply_to: smtp[:reply_to],
             host: smtp.host,
             to: email.to,
             subject: email.subject,
             message_id: email.message_id
           }}
        )

        {:ok, "250 sandbox accepted"}
    end
  end

  defp reach(%{host: "private." <> _rest}), do: {:error, :host_not_allowed}
  defp reach(%{host: "down." <> _rest}), do: {:error, {:transient, :unreachable}}
  defp reach(%{secret: "wrong-password"}), do: {:error, :unauthorized}
  defp reach(_smtp), do: :ok
end
