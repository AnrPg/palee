defmodule Palee.Email.Commands.DeliverEmail do
  @moduledoc """
  One delivery attempt of an outbox message (ADR-203), run by
  `Palee.Workers.DeliverEmailJob`. Returns what the job should answer Oban:

    * `:ok` - sent, or nothing left to do (gone, already sent, suppressed,
      given up);
    * `{:snooze, seconds}` - over today's budget: `deferred` to the next UTC
      day;
    * `{:error, reason}` - the provider failed; retried with backoff;
    * `{:cancel, reason}` - permanent failure (an SMTP 5xx, an unreadable
      body): `failed` without retrying.

  The body is cleared once the email is sent or given up on, so the outbox
  keeps no readable link longer than it must.

  ADR-368: a box's own email (template `origin: :box`) goes through the
  box's own SMTP provider when it has one in use (`sent_via: own`), outside
  Palee's daily budget; otherwise, and for all platform mail, through
  Palee's mailer (`sent_via: palee`).
  """

  require Logger

  alias Palee.Email.Domain.{Address, DeliveryPolicy, SendingPolicy}
  alias Palee.Email.Message
  alias Palee.Infrastructure.Security.DataCipher

  @done ~w(sent suppressed failed)

  def call(message_id, %{attempt: attempt, max_attempts: max_attempts}, %DateTime{} = now) do
    store = Palee.Email.message_store()

    case store.get(message_id) do
      nil -> :ok
      %Message{status: status} when status in @done -> :ok
      message -> attempt(store, message, attempt >= max_attempts, now)
    end
  end

  defp attempt(store, message, last?, now) do
    cond do
      refused?(store, message) ->
        {:ok, message} = store.update(message, %{status: "suppressed", encrypted_body: nil})
        Palee.Email.emit(:suppressed, message)
        :ok

      box_mail?(message) ->
        through_box(store, message, last?, now)

      true ->
        through_palee(store, message, last?, now)
    end
  end

  # ADR-368: the box's own message goes through the box's own SMTP provider
  # when it has one in use; it is not Palee's mail, so Palee's daily budget
  # does not apply. Without one it goes through Palee's mailer.
  defp box_mail?(%Message{organization_id: organization_id, kind: kind})
       when is_binary(organization_id) do
    case Palee.Email.Templates.fetch(kind) do
      {:ok, template} -> template.origin() == :box
      {:error, _unknown} -> false
    end
  end

  defp box_mail?(_message), do: false

  defp through_box(store, message, last?, now) do
    case body(message) do
      {:ok, body} ->
        case Palee.Email.box_sender().deliver(message.organization_id, outgoing(message, body)) do
          :unavailable -> through_palee(store, message, last?, now)
          result -> settle(store, message, result, "own", last?, now)
        end

      error ->
        settle(store, message, error, "own", last?, now)
    end
  end

  defp through_palee(store, message, last?, now) do
    case on_send(store, String.to_existing_atom(message.category), now) do
      {:send, sent_today} ->
        with :ok <- send(store, message, last?, now) do
          warn_budget(sent_today + 1)
        end

      {:defer, until} ->
        {:ok, message} = store.update(message, %{status: "deferred", scheduled_at: until})
        Palee.Email.emit(:deferred, message)
        {:snooze, max(DateTime.diff(until, now), 1)}
    end
  end

  # Suppressed since enqueue, or (transactional mail) unsubscribed from
  # its kind since (ADR-212).
  defp refused?(store, message) do
    digest = Address.digest(message.to_address)

    store.suppressed?(digest) or
      (message.category == "transactional" and store.opted_out?(digest, message.kind))
  end

  defp on_send(store, category, now) do
    sent_today = store.count_sent_since(SendingPolicy.day_start(now))

    case SendingPolicy.on_send(category, sent_today, Palee.Email.budget(), now) do
      :send -> {:send, sent_today}
      deferred -> deferred
    end
  end

  # ADR-212: one log line the day sending crosses 80% of the budget, for
  # servers without the Prometheus alert (palee_email_sent_today).
  defp warn_budget(sent_today) do
    budget = Palee.Email.budget()

    if SendingPolicy.budget_warning?(sent_today, budget) do
      Logger.warning(
        "email_budget_warning sent_today=#{sent_today} daily_budget=#{budget.daily_budget} hard_cap=#{budget.hard_cap}"
      )
    end

    :ok
  end

  defp send(store, message, last?, now) do
    result =
      with {:ok, body} <- body(message) do
        Palee.Email.sender().deliver(outgoing(message, body))
      end

    settle(store, message, result, "palee", last?, now)
  end

  defp outgoing(message, %{"text" => text, "html" => html} = body) do
    %{
      to: message.to_address,
      subject: message.subject,
      text: text,
      html: html,
      message_id: message.message_id,
      headers: Map.get(body, "headers") || %{},
      attachments: attachments(body)
    }
  end

  defp settle(store, message, result, via, last?, now) do
    case result do
      {:ok, _metadata} ->
        {:ok, message} =
          store.update(message, %{
            status: "sent",
            sent_at: now,
            sent_via: via,
            attempts: message.attempts + 1,
            last_error: nil,
            encrypted_body: nil,
            scheduled_at: nil
          })

        Palee.Email.emit(:sent, message)
        :ok

      {:error, reason} ->
        failed(store, message, reason, last?)
    end
  end

  defp failed(store, message, reason, last?) do
    permanent? = DeliveryPolicy.permanent?(reason)
    error = DeliveryPolicy.describe(reason)

    if permanent? or last? do
      {:ok, message} =
        store.update(message, %{
          status: "failed",
          attempts: message.attempts + 1,
          last_error: error,
          encrypted_body: nil
        })

      Palee.Email.emit(:failed, message, %{reason: error})
      if permanent?, do: {:cancel, reason}, else: {:error, reason}
    else
      {:ok, _message} =
        store.update(message, %{
          status: "queued",
          attempts: message.attempts + 1,
          last_error: error
        })

      Logger.warning(
        "email_delivery_retry message=#{message.id} kind=#{message.kind} reason=#{error}"
      )

      {:error, reason}
    end
  end

  # ADR-265: files stored base64 in the encrypted body.
  defp attachments(%{"attachments" => [_ | _] = attachments}) do
    Enum.flat_map(attachments, fn
      %{"filename" => filename, "content_type" => type, "data" => data} ->
        case Base.decode64(data) do
          {:ok, binary} -> [%{filename: filename, content_type: type, data: binary}]
          :error -> []
        end

      _other ->
        []
    end)
  end

  defp attachments(_body), do: []

  defp body(%Message{encrypted_body: nil}), do: {:error, :undecryptable}

  defp body(%Message{encrypted_body: encrypted}) do
    with {:ok, json} <- DataCipher.decrypt(encrypted),
         {:ok, %{"text" => _, "html" => _} = body} <- Jason.decode(json) do
      {:ok, body}
    else
      _unreadable -> {:error, :undecryptable}
    end
  end
end
