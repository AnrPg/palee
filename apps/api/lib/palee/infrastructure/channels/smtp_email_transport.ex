defmodule Palee.Infrastructure.Channels.SmtpEmailTransport do
  @moduledoc """
  A box's own SMTP provider (ADR-368), through `Swoosh.Adapters.SMTP` with
  the connection's settings per message (never the application's mailer
  config).

    * TLS is always on and verified (`Palee.Mailer.tls_options/1`: TLS 1.2+,
      the peer checked against the CA store and the host name): `starttls`
      upgrades before logging in, `tls` speaks TLS from the first byte.
    * Before connecting, the host is resolved and every address must be
      public (`EmailConnectionPolicy.public_address?/1`), so a box cannot
      point Palee at its own network.
    * Each call runs in a task with a deadline (gen_smtp waits up to 20
      minutes for a reply), so a silent server cannot hold a worker.
    * Errors are reduced to `Ports.EmailTransport`'s; the password is never
      logged or put in an error.
  """

  @behaviour Palee.Channels.Ports.EmailTransport

  require Logger

  import Swoosh.Email

  alias Palee.Channels.Domain.EmailConnectionPolicy
  alias Swoosh.Adapters.SMTP

  @connect_timeout 15_000
  @check_deadline 30_000
  @deliver_deadline 90_000
  @extra_headers ~w(List-Unsubscribe List-Unsubscribe-Post)

  @impl true
  def check(smtp) do
    with :ok <- public_host(smtp.host) do
      run(@check_deadline, fn ->
        case :gen_smtp_client.open(options(smtp)) do
          {:ok, socket} ->
            :gen_smtp_client.close(socket)
            {:ok, %{host: smtp.host}}

          {:error, type, reason} ->
            {:error, reduce({type, reason})}

          {:error, reason} ->
            {:error, reduce(reason)}
        end
      end)
    end
  end

  @impl true
  def deliver(smtp, email) do
    with :ok <- public_host(smtp.host) do
      message = build(smtp, email)

      run(@deliver_deadline, fn ->
        case SMTP.deliver(message, options(smtp)) do
          {:ok, receipt} -> {:ok, receipt}
          {:error, reason} -> {:error, reduce(reason)}
        end
      end)
    end
  end

  defp build(smtp, email) do
    new()
    |> to(email.to)
    |> from({smtp[:from_name] || "", smtp.from_address})
    |> subject(email.subject)
    |> text_body(email.text)
    |> html_body(email.html)
    |> header("Message-ID", email.message_id)
    |> reply(smtp[:reply_to], smtp[:from_name])
    |> extra_headers(Map.get(email, :headers) || %{})
    |> attachments(Map.get(email, :attachments) || [])
  end

  defp reply(email, nil, _name), do: email
  defp reply(email, address, name), do: reply_to(email, {name || "", address})

  defp extra_headers(email, headers) do
    headers
    |> Map.take(@extra_headers)
    |> Enum.reduce(email, fn {name, value}, email ->
      header(email, name, String.replace(value, ~r/[\r\n]+/, ""))
    end)
  end

  defp attachments(email, files) do
    Enum.reduce(files, email, fn file, email ->
      attachment(
        email,
        Swoosh.Attachment.new({:data, file.data},
          filename: file.filename,
          content_type: file.content_type
        )
      )
    end)
  end

  defp options(smtp) do
    tls_options = Palee.Mailer.tls_options(smtp.host)
    implicit? = smtp.tls_mode == "tls"

    [
      relay: smtp.host,
      port: smtp.port,
      username: smtp.username,
      password: smtp.secret,
      auth: :always,
      ssl: implicit?,
      tls: if(implicit?, do: :never, else: :always),
      tls_options: tls_options,
      sockopts: if(implicit?, do: tls_options, else: []),
      hostname: smtp.from_address |> String.split("@") |> List.last(),
      no_mx_lookups: true,
      retries: 0,
      timeout: @connect_timeout
    ]
  end

  # Every address the host resolves to must be public.
  defp public_host(host) do
    name = String.to_charlist(host)

    addresses =
      Enum.flat_map([:inet, :inet6], fn family ->
        case :inet.getaddrs(name, family) do
          {:ok, list} -> list
          {:error, _reason} -> []
        end
      end)

    cond do
      addresses == [] -> {:error, {:transient, :unreachable}}
      Enum.all?(addresses, &EmailConnectionPolicy.public_address?/1) -> :ok
      true -> {:error, :host_not_allowed}
    end
  end

  defp run(deadline, fun) do
    task = Task.async(fn -> catch_exit(fun) end)

    case Task.yield(task, deadline) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _timeout -> {:error, {:transient, :timeout}}
    end
  end

  defp catch_exit(fun) do
    fun.()
  rescue
    error ->
      Logger.warning("own SMTP call raised: #{inspect(error.__struct__)}")
      {:error, {:transient, :unexpected}}
  catch
    :exit, reason ->
      Logger.warning("own SMTP call exited: #{inspect(reason, limit: 5)}")
      {:error, {:transient, :unreachable}}
  end

  # gen_smtp's errors (Swoosh wraps `{:error, type, detail}` as
  # `{:error, {type, detail}}`) reduced to the port's.
  defp reduce({_type, {:permanent_failure, _host, :auth_failed}}), do: :unauthorized

  defp reduce({_type, {:permanent_failure, _host, :ssl_not_started}}),
    do: {:transient, :tls_failed}

  defp reduce({_type, {:permanent_failure, _host, message}}) when is_binary(message),
    do: {:permanent_failure, String.slice(message, 0, 200)}

  defp reduce({_type, {:temporary_failure, _host, :tls_failed}}), do: {:transient, :tls_failed}
  defp reduce({_type, {:missing_requirement, _host, :tls}}), do: {:transient, :tls_failed}
  defp reduce({_type, {:missing_requirement, _host, :auth}}), do: {:transient, :auth_unavailable}
  defp reduce({_type, {:network_failure, _host, {:error, :timeout}}}), do: {:transient, :timeout}
  defp reduce({_type, {:network_failure, _host, _reason}}), do: {:transient, :unreachable}

  defp reduce({_type, {:temporary_failure, _host, message}}) when is_binary(message),
    do: {:transient, String.slice(message, 0, 200)}

  defp reduce({:bad_option, reason}), do: {:transient, {:bad_option, reason}}
  defp reduce(_other), do: {:transient, :unexpected}
end
