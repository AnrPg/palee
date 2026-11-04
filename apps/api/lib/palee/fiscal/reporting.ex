defmodule Palee.Fiscal.Reporting do
  @moduledoc """
  Reporting fiscal documents to the tax authority (ADR-243): today the
  Greek myDATA, through the `Fiscal.Ports.AuthorityGateway` of the
  organization's connection environment.

  Issuing a document in a country whose profile names an authority adds a
  `pending` transmission in the same transaction (`enqueue/3`), so a
  document is never issued without its outbox row. Workers then claim due
  rows, map the document (`Domain.MyDataInvoice`), call the gateway outside
  any transaction, and record the attempt, the new state and (once
  accepted) a `document_reported` journal entry with the MARK.

  The document never changes: the MARK, UID and QR link live on the
  transmission and are printed from there.
  """

  alias Palee.Fiscal
  alias Palee.Fiscal.{Connections, FiscalStore, TransmissionStore}
  alias Palee.Fiscal.Domain.{CountryProfile, MyDataInvoice, TransmissionPolicy}

  @authority "mydata"
  @environments ~w(sandbox test production)
  @batch 25

  def environments, do: @environments

  defp gateway(environment) do
    :palee
    |> Application.fetch_env!(:fiscal_authority_gateways)
    |> Map.fetch!(environment)
  end

  # ── Outbox ──────────────────────────────────────────────────────────────

  @doc false
  # Inside the issuing transaction.
  def enqueue(context, document, %DateTime{} = now) do
    with {:ok, profile} <- CountryProfile.fetch(document.country_code) do
      if TransmissionPolicy.required?(profile) do
        context
        |> TransmissionStore.insert_transmission(%{
          document_id: document.id,
          authority: Atom.to_string(profile.authority),
          status: "pending",
          next_attempt_at: now
        })
        |> case do
          {:ok, _transmission} -> :ok
          error -> error
        end
      else
        :ok
      end
    end
  end

  @doc "The transmission of each document id that has one."
  def transmissions_for(context, document_ids),
    do: TransmissionStore.transmissions_for_documents(context, document_ids)

  @doc "Transmissions (newest first) with counts per status; filters: status, limit, offset."
  def list(context, filters \\ %{}), do: TransmissionStore.list_transmissions(context, filters)

  @doc "A transmission with its attempts."
  def get(context, id) do
    case TransmissionStore.get_transmission(context, id) do
      nil ->
        nil

      transmission ->
        Map.put(transmission, :attempts_log, TransmissionStore.list_attempts(context, id))
    end
  end

  @doc """
  Sends what is due (or only `id`): `{:ok, %{accepted, rejected, failed,
  deferred, retrying}}` (counts). Safe to run from several workers at once.

  ADR-530: the claimed documents go to AADE in one `InvoicesDoc`, so a
  claim never outlives `TransmissionPolicy.claim_timeout_seconds/0`
  (guarded by a test). A document whose last attempt ended without an
  answer is first looked up at AADE, and an "already sent" answer is
  resolved the same way, so a lost answer never becomes a rejection or a
  second document. New rejections and failures are told to the staff
  who manage billing, once a day.
  """
  def transmit(context, which \\ :due, %DateTime{} = now) do
    outcomes =
      context
      |> TransmissionStore.claim(which, now, @batch)
      |> Enum.group_by(& &1.authority)
      |> Enum.flat_map(fn {authority, rows} -> transmit_group(context, authority, rows, now) end)

    notify_problems(context, outcomes)

    outcomes
    |> Enum.frequencies()
    |> then(
      &{:ok, Map.merge(%{accepted: 0, rejected: 0, failed: 0, deferred: 0, retrying: 0}, &1)}
    )
  end

  @doc false
  def batch_size, do: @batch

  defp transmit_group(context, authority, rows, now) do
    connection = TransmissionStore.get_connection(context, authority)

    cond do
      is_nil(connection) ->
        Enum.map(rows, &defer(context, &1, :connection_missing, now))

      connection.status == "invalid" ->
        Enum.map(rows, &defer(context, &1, :connection_invalid, now))

      true ->
        rows
        |> Enum.map(&prepare(context, &1))
        |> send_prepared(context, connection, now)
    end
  end

  # What each claimed row needs: a deferral, a result already known (a
  # document myDATA cannot express), or a send.
  defp prepare(context, transmission) do
    document = FiscalStore.get_document(context, transmission.document_id, [])

    case original(context, document) do
      {:wait, _original} ->
        {:defer, transmission}

      {:ok, original} ->
        case MyDataInvoice.build(document, original: original) do
          {:ok, invoice} ->
            {:send, transmission, document, invoice}

          {:error, reason} ->
            {:done, transmission, document,
             {:error, {:rejected, [%{code: Atom.to_string(reason), message: "palee"}]}}, nil}
        end
    end
  end

  defp send_prepared(prepared, context, connection, now) do
    started = System.monotonic_time(:millisecond)
    gateway = gateway(connection.environment)
    claimed = for {:send, transmission, _d, _i} <- prepared, do: transmission.id
    # Each call to the authority starts with a fresh claim (ADR-530).
    beat = fn -> TransmissionStore.touch_claims(context, claimed, latest(now)) end

    deferred =
      for {:defer, transmission} <- prepared,
          do: defer(context, transmission, :original_not_accepted, now)

    # A row that may already be at AADE is looked up before it is sent.
    {found, to_send} =
      prepared
      |> Enum.filter(&match?({:send, _t, _d, _i}, &1))
      |> Enum.map(fn {:send, transmission, document, invoice} = item ->
        if possibly_sent?(transmission) do
          beat.()

          case gateway.find(connection, MyDataInvoice.key(invoice)) do
            {:ok, receipt} -> {:done, transmission, document, {:ok, receipt}, nil}
            :not_found -> item
            {:error, reason} -> {:done, transmission, document, {:error, reason}, nil}
          end
        else
          item
        end
      end)
      |> Enum.split_with(&match?({:done, _t, _d, _r, _i}, &1))

    {results, wire} =
      case to_send do
        [] ->
          {[], %{}}

        items ->
          beat.()
          gateway.submit(connection, Enum.map(items, &elem(&1, 3)))
      end

    # Each attempt keeps its own document's XML; the answer is shared.
    bodies =
      Map.get(wire, :request_bodies) || List.duplicate(wire[:request_body], length(to_send))

    sent =
      [to_send, results, bodies]
      |> Enum.zip()
      |> Enum.map(fn {{:send, transmission, document, invoice}, result, body} ->
        {:done, transmission, document,
         resolve_duplicate(gateway, connection, invoice, result, beat), body}
      end)

    known = for {:done, _t, _d, _r, _i} = item <- prepared, do: item
    duration = System.monotonic_time(:millisecond) - started

    finished =
      Enum.map(known ++ found ++ sent, fn {:done, transmission, document, result, body} ->
        finish(context, connection, transmission, document, result, body, wire, duration, now)
      end)

    if Enum.any?(
         known ++ found ++ sent,
         &match?({:done, _t, _d, {:error, {:unauthorized, _}}, _i}, &1)
       ) do
      Connections.mark_invalid(context, "mydata", "credentials_rejected", "unauthorized", now)
    end

    deferred ++ finished
  end

  # ADR-530: a row may already be at AADE when its last attempt got no
  # answer ("transient"), or when an earlier claim never finished (a worker
  # that died mid-call: the claim expired and the row was claimed again,
  # so `attempts`, which counts only real sends, is above 1). AADE's
  # development API does not refuse a resend; it registers the same UID
  # under a new MARK, so "already sent" cannot be relied on to stop it.
  defp possibly_sent?(%{last_error_code: "transient"}), do: true
  defp possibly_sent?(%{attempts: attempts}) when is_integer(attempts), do: attempts > 1
  defp possibly_sent?(_transmission), do: false

  # "Already sent" (a lost answer): take AADE's MARK; when AADE cannot show
  # it, the original rejection stands.
  defp resolve_duplicate(gateway, connection, invoice, {:error, {:duplicate, errors}}, beat) do
    beat.()

    case gateway.find(connection, MyDataInvoice.key(invoice)) do
      {:ok, receipt} -> {:ok, receipt}
      :not_found -> {:error, {:rejected, errors}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_duplicate(_gateway, _connection, _invoice, result, _beat), do: result

  defp latest(now) do
    wall = DateTime.utc_now()
    if DateTime.compare(wall, now) == :gt, do: wall, else: now
  end

  defp finish(context, connection, transmission, document, result, body, wire, duration, now) do
    changes =
      transmission
      |> TransmissionPolicy.outcome(result, now)
      |> Map.put(:environment, connection.environment)

    attempt = %{
      request_body: body,
      response_status: body && wire[:response_status],
      response_body: body && wire[:response_body],
      attempt: transmission.attempts,
      environment: connection.environment,
      outcome: TransmissionPolicy.attempt_outcome(result),
      error: error_text(result),
      duration_ms: duration,
      started_at: now
    }

    case record(context, transmission, document, changes, attempt, now) do
      {:ok, _saved} ->
        case changes.status do
          "accepted" -> :accepted
          "rejected" -> :rejected
          "failed" -> :failed
          _pending -> :retrying
        end

      _error ->
        :retrying
    end
  end

  # A credit note goes after the document it corrects has its MARK.
  defp original(_context, %{corrects_document_id: nil}), do: {:ok, nil}

  defp original(context, %{corrects_document_id: original_id}) do
    original = FiscalStore.get_document(context, original_id, [])

    case TransmissionStore.transmissions_for_documents(context, [original_id]) do
      %{^original_id => %{status: "accepted", mark: mark}} ->
        {:ok, %{kind: original.kind, mark: mark}}

      %{^original_id => _waiting} ->
        {:wait, original}

      %{} ->
        {:ok, %{kind: original.kind, mark: nil}}
    end
  end

  # ADR-530 (Κ4): documents that will not reach AADE without someone's help.
  defp notify_problems(context, outcomes) do
    count = Enum.count(outcomes, &(&1 in [:rejected, :failed]))
    if count > 0, do: Connections.documents_not_reported(context, @authority, count)
    :ok
  end

  defp record(context, transmission, document, %{status: "accepted"} = changes, attempt, now) do
    FiscalStore.transaction(context, fn ->
      with {:ok, saved} <- TransmissionStore.finish(context, transmission.id, changes, attempt),
           {:ok, _entry} <-
             Fiscal.append(context, %{
               event_type: "document_reported",
               subject_type: "fiscal_document",
               subject_id: document.id,
               actor_id: nil,
               occurred_at: now,
               payload: %{
                 authority: transmission.authority,
                 environment: changes.environment,
                 number: document.number,
                 mark: changes.mark,
                 uid: changes.uid,
                 authentication_code: changes.authentication_code
               }
             }) do
        {:ok, saved}
      end
    end)
  end

  defp record(context, transmission, _document, changes, attempt, _now),
    do: TransmissionStore.finish(context, transmission.id, changes, attempt)

  defp defer(context, transmission, reason, now) do
    TransmissionStore.update_transmission(
      context,
      transmission.id,
      TransmissionPolicy.deferral(transmission, reason, now)
    )

    :deferred
  end

  defp error_text({:ok, _receipt}), do: nil
  defp error_text({:error, reason}), do: reason |> inspect() |> String.slice(0, 1_000)

  @doc """
  Staff send a rejected or failed document again (after fixing the cause).
  `{:ok, transmission}` or `{:error, :not_retryable | :not_found}`.
  """
  def retry(context, document_id, %DateTime{} = now) do
    case TransmissionStore.transmissions_for_documents(context, [document_id]) do
      %{^document_id => transmission} ->
        if TransmissionPolicy.retryable?(transmission),
          do:
            TransmissionStore.update_transmission(
              context,
              transmission.id,
              TransmissionPolicy.retry(now)
            ),
          else: {:error, :not_retryable}

      %{} ->
        {:error, :not_found}
    end
  end

  # ── Connection ──────────────────────────────────────────────────────────

  @doc "The connection as shown to staff (never the key)."
  def connection(context) do
    context
    |> TransmissionStore.get_connection(@authority)
    |> public_connection()
  end

  defp public_connection(nil), do: nil

  defp public_connection(connection) do
    connection
    |> Map.take([:authority, :environment, :user_id, :status, :updated_at])
    |> Map.merge(Connections.public_check(connection))
    |> Map.put(:has_subscription_key, is_binary(connection.subscription_key))
  end

  @doc false
  # ADR-273: «Δοκιμή σύνδεσης» with the connection's own credentials.
  def check_connection(connection), do: gateway(connection.environment).check(connection)

  @doc """
  Saves the myDATA connection. `test` and `production` need the
  business's myDATA user and subscription key; a saved user or key is
  kept when none is sent. Journals the change (without the key) and wakes
  the documents that were waiting for it.
  """
  def save_connection(context, params, actor_id, %DateTime{} = now) do
    before = TransmissionStore.get_connection(context, @authority)

    with {:ok, attrs} <- validate_connection(before, params) do
      FiscalStore.transaction(context, fn ->
        with {:ok, saved} <-
               TransmissionStore.save_connection(
                 context,
                 @authority,
                 attrs
                 |> Map.merge(Connections.saved_fields())
                 |> Map.merge(%{
                   updated_by_id: actor_id,
                   updated_by_platform: params[:updated_by_platform] == true
                 })
               ),
             {:ok, _entry} <-
               Fiscal.append(context, %{
                 event_type: "authority_connection_saved",
                 subject_type: "authority_connection",
                 subject_id: saved.id,
                 actor_id: actor_id,
                 occurred_at: now,
                 payload:
                   %{
                     authority: @authority,
                     environment: saved.environment,
                     user_id: saved.user_id,
                     key_changed: Map.has_key?(attrs, :subscription_key)
                   }
                   |> Connections.platform_mark(params)
               }) do
          TransmissionStore.wake_waiting(context, now)
          {:ok, public_connection(saved)}
        end
      end)
    end
  end

  defp validate_connection(before, params) do
    environment = params[:environment]
    user_id = clean(params[:user_id]) || (before && before.user_id)
    key = params[:subscription_key] |> clean()
    stored_key = before && before.subscription_key

    errors =
      %{}
      |> add_error(environment not in @environments, :environment, "invalid")
      |> add_error(
        environment in ["test", "production"] and is_nil(user_id),
        :user_id,
        "required"
      )
      |> add_error(
        environment in ["test", "production"] and is_nil(key) and is_nil(stored_key),
        :subscription_key,
        "required"
      )
      |> add_error(is_binary(user_id) and String.length(user_id) > 100, :user_id, "too_long")
      |> add_error(is_binary(key) and String.length(key) > 200, :subscription_key, "too_long")

    if errors == %{} do
      {:ok,
       %{environment: environment, user_id: user_id}
       |> then(fn attrs -> if key, do: Map.put(attrs, :subscription_key, key), else: attrs end)}
    else
      {:error, {:invalid_fields, errors}}
    end
  end

  defp add_error(errors, true, field, code), do: Map.put(errors, field, [code])
  defp add_error(errors, false, _field, _code), do: errors

  defp clean(nil), do: nil

  defp clean(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp clean(_value), do: nil
end
