defmodule Palee.Fiscal.ReportingTest do
  @moduledoc """
  ADR-243 end to end: issuing a Greek document queues its myDATA report;
  workers defer without a connection, send through the sandbox or AADE's
  API (stubbed), keep the attempt log, journal the MARK, retry transient
  errors with backoff, stop on rejections and send credit notes after their
  originals. Runs with Row Level Security enforced.
  """

  use Palee.DataCase, async: false

  @moduletag :rls_enforced

  import Palee.AnalyticsHelpers, only: [organization_fixture: 0]

  alias Palee.{Fiscal, Repo}
  alias Palee.Fiscal.Reporting

  @now ~U[2027-02-01 10:00:00.000000Z]

  @identity %{
    legal_name: "CrossFit Αθήνα ΙΚΕ",
    country_code: "GR",
    tax_id: "090000045",
    tax_office: "Α' Αθηνών",
    street: "Ερμού",
    building_number: "10",
    postal_code: "10563",
    city: "Αθήνα"
  }

  @success """
  <?xml version="1.0" encoding="utf-8"?>
  <ResponseDoc><response><index>1</index><invoiceUid>ABC123</invoiceUid>
  <invoiceMark>400001234567890</invoiceMark><qrUrl>https://mydataapidev.aade.gr/qr?q=1</qrUrl>
  <statusCode>Success</statusCode></response></ResponseDoc>
  """

  @rejected """
  <?xml version="1.0" encoding="utf-8"?>
  <ResponseDoc><response><index>1</index><statusCode>ValidationError</statusCode>
  <errors><error><message>Invalid VAT number</message><code>102</code></error></errors>
  </response></ResponseDoc>
  """

  setup do
    {organization, owner, context} = bypass_rls(fn -> organization_fixture() end)
    {:ok, %{complete: true}} = Fiscal.save_identity(context, @identity, owner.id, @now)

    previous = Application.get_env(:palee, :mydata)

    Application.put_env(:palee, :mydata,
      req_options: [plug: {Req.Test, __MODULE__}, retry: false],
      base_urls: %{"test" => "https://mydata.test", "production" => "https://mydata.prod"}
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:palee, :mydata, previous),
        else: Application.delete_env(:palee, :mydata)
    end)

    %{organization: organization, owner: owner, context: context}
  end

  defp issue(context, owner, key, extra \\ %{}, at \\ @now) do
    {:ok, document, :issued} =
      Fiscal.issue(
        context,
        Map.merge(
          %{
            kind: "receipt",
            issue_date: ~D[2027-02-01],
            idempotency_key: key,
            payment_method: "cash",
            lines: [%{description: "Μηνιαία συνδρομή", quantity: 1, unit_price_cents: 6000}]
          },
          extra
        ),
        owner.id,
        at
      )

    document
  end

  defp transmission(context, document),
    do: context |> Reporting.transmissions_for([document.id]) |> Map.fetch!(document.id)

  defp connect(context, owner, environment, extra \\ %{}) do
    {:ok, connection} =
      Reporting.save_connection(
        context,
        Map.merge(%{environment: environment}, extra),
        owner.id,
        @now
      )

    connection
  end

  test "a Greek document is queued and waits for a connection without spending attempts", %{
    context: context,
    owner: owner
  } do
    document = issue(context, owner, "k-1")
    assert %{status: "pending", attempts: 0} = transmission(context, document)

    assert {:ok, %{deferred: 1}} = Reporting.transmit(context, :due, @now)

    assert %{status: "pending", attempts: 0, last_error_code: "connection_missing"} =
             row = transmission(context, document)

    assert DateTime.compare(row.next_attempt_at, @now) == :gt
    assert {:ok, %{deferred: 0, accepted: 0}} = Reporting.transmit(context, :due, @now)
  end

  test "the sandbox accepts, the MARK is journaled and the journal stays valid", %{
    context: context,
    owner: owner
  } do
    document = issue(context, owner, "k-1")
    Reporting.transmit(context, :due, @now)

    connection = connect(context, owner, "sandbox")
    assert connection.environment == "sandbox"
    refute connection.has_subscription_key

    assert {:ok, %{accepted: 1}} = Reporting.transmit(context, :due, @now)

    assert %{status: "accepted", mark: "9000" <> _, uid: uid, environment: "sandbox"} =
             row = transmission(context, document)

    assert byte_size(uid) == 40

    assert [%{outcome: "accepted", request_body: xml, attempt: 1}] =
             Reporting.get(context, row.id).attempts_log

    assert xml =~ "<invoiceType>11.2</invoiceType>"

    entries = Fiscal.archive(context, ~D[2027-02-01], ~D[2027-02-01], owner.id, @now)
    assert {:ok, _zip} = entries
    assert {:ok, %{valid: true}} = Fiscal.verify_journal(context, owner.id, @now)

    events =
      bypass_rls(fn ->
        Repo.query!("SELECT event_type, payload FROM fiscal_journal_entries ORDER BY position").rows
      end)

    assert Enum.any?(events, fn [type, payload] ->
             type == "document_reported" and payload["mark"] == row.mark
           end)

    assert Enum.any?(events, fn [type, payload] ->
             type == "authority_connection_saved" and
               not Map.has_key?(payload, "subscription_key")
           end)
  end

  test "AADE: success, rejection and refused credentials", %{context: context, owner: owner} do
    test_pid = self()

    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      send(
        test_pid,
        {:request, conn.request_path, Plug.Conn.get_req_header(conn, "aade-user-id"), body}
      )

      case Plug.Conn.get_req_header(conn, "ocp-apim-subscription-key") do
        ["wrong"] -> Plug.Conn.send_resp(conn, 401, "")
        ["reject"] -> Plug.Conn.send_resp(conn, 200, @rejected)
        _ -> Plug.Conn.send_resp(conn, 200, @success)
      end
    end)

    assert {:error, {:invalid_fields, %{user_id: ["required"], subscription_key: ["required"]}}} =
             Reporting.save_connection(context, %{environment: "test"}, owner.id, @now)

    connect(context, owner, "test", %{user_id: "boxuser", subscription_key: "wrong"})
    first = issue(context, owner, "k-1")
    assert {:ok, %{retrying: 1}} = Reporting.transmit(context, :due, @now)

    assert %{status: "pending", attempts: 0, last_error_code: "connection_invalid"} =
             transmission(context, first)

    assert %{status: "invalid"} = Reporting.connection(context)

    # Still invalid: deferred without calling AADE again.
    assert {:ok, %{deferred: 0}} = Reporting.transmit(context, :due, @now)

    # A new key wakes the waiting documents.
    connect(context, owner, "test", %{user_id: "boxuser", subscription_key: "good"})
    assert %{status: "active", has_subscription_key: true} = Reporting.connection(context)
    assert {:ok, %{accepted: 1}} = Reporting.transmit(context, :due, @now)

    assert %{
             status: "accepted",
             mark: "400001234567890",
             qr_url: "https://mydataapidev.aade.gr/qr?q=1"
           } =
             transmission(context, first)

    assert_received {:request, "/SendInvoices", ["boxuser"], body}
    assert body =~ "<vatNumber>090000045</vatNumber>"

    connect(context, owner, "test", %{user_id: "boxuser", subscription_key: "reject"})
    second = issue(context, owner, "k-2")
    assert {:ok, %{rejected: 1}} = Reporting.transmit(context, :due, @now)

    assert %{
             status: "rejected",
             last_error_code: "102",
             last_error_message: "102: Invalid VAT number"
           } =
             transmission(context, second)

    # Retry after fixing the cause; a key kept from before is reused.
    connect(context, owner, "test", %{user_id: "boxuser", subscription_key: "good"})
    assert {:ok, %{status: "pending", attempts: 0}} = Reporting.retry(context, second.id, @now)
    assert {:error, :not_retryable} = Reporting.retry(context, first.id, @now)
    assert {:ok, %{accepted: 1}} = Reporting.transmit(context, :due, @now)
  end

  test "transient errors back off and end as failed", %{context: context, owner: owner} do
    Req.Test.stub(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 503, "busy") end)
    connect(context, owner, "production", %{user_id: "u", subscription_key: "k"})
    document = issue(context, owner, "k-1")

    assert {:ok, %{retrying: 1}} = Reporting.transmit(context, :due, @now)
    row = transmission(context, document)
    assert %{status: "pending", attempts: 1, last_error_code: "transient"} = row
    assert DateTime.diff(row.next_attempt_at, @now) == 60

    # Not due yet.
    assert {:ok, %{retrying: 0}} = Reporting.transmit(context, :due, @now)

    later =
      Enum.reduce(2..20, @now, fn _attempt, at ->
        at = DateTime.add(at, 2, :day)
        Reporting.transmit(context, :due, at)
        at
      end)

    assert %{status: "failed", attempts: 20} = transmission(context, document)
    assert {:ok, %{status: "pending"}} = Reporting.retry(context, document.id, later)
  end

  test "a credit note waits for its original's MARK", %{context: context, owner: owner} do
    original = issue(context, owner, "k-1")

    {:ok, credit, :issued} =
      Fiscal.credit(context, original.id, :all, ~D[2027-02-01], "c-1", owner.id, @now)

    # Claim the credit note alone first: its original has no MARK yet.
    credit_row = transmission(context, credit)
    connect(context, owner, "sandbox")
    assert {:ok, %{deferred: 1}} = Reporting.transmit(context, credit_row.id, @now)

    assert %{status: "pending", last_error_code: "original_not_accepted", attempts: 0} =
             transmission(context, credit)

    assert {:ok, %{accepted: 1}} =
             Reporting.transmit(context, transmission(context, original).id, @now)

    assert {:ok, %{accepted: 1}} =
             Reporting.transmit(context, :due, DateTime.add(@now, 601, :second))

    assert [%{request_body: xml}] = Reporting.get(context, credit_row.id).attempts_log
    assert xml =~ "<invoiceType>11.4</invoiceType>"
    assert xml =~ "<correlatedInvoices>" <> transmission(context, original).mark
  end

  test "attempt rows are insert-only and documents of other countries are not reported", %{
    context: context,
    owner: owner
  } do
    connect(context, owner, "sandbox")
    document = issue(context, owner, "k-1")
    Reporting.transmit(context, :due, @now)
    %{id: id} = transmission(context, document)
    {:ok, raw} = Ecto.UUID.dump(id)

    bypass_rls(fn ->
      assert_raise Postgrex.Error, ~r/insert-only/, fn ->
        Repo.query!(
          "UPDATE fiscal_transmission_attempts SET outcome = 'rejected' WHERE transmission_id = $1",
          [raw]
        )
      end
    end)

    {:ok, _} =
      Fiscal.save_identity(
        context,
        %{country_code: "DE", tax_id: nil, vat_number: "DE136695976"},
        owner.id,
        @now
      )

    other = issue(context, owner, "k-de")
    assert context |> Reporting.transmissions_for([other.id]) == %{}
  end

  # ── ADR-530 ─────────────────────────────────────────────────────────────

  defmodule Notifier do
    @moduledoc false
    @behaviour Palee.Fiscal.Ports.ConnectionNotifier

    @impl true
    def connection_failed(_context, kind, code),
      do: send(self(), {:connection_failed, kind, code}) && :ok

    @impl true
    def documents_not_reported(_context, kind, count),
      do: send(self(), {:documents_not_reported, kind, count}) && :ok
  end

  defp use_notifier(_context) do
    previous = Application.fetch_env!(:palee, :fiscal_connection_notifier)
    Application.put_env(:palee, :fiscal_connection_notifier, Notifier)
    on_exit(fn -> Application.put_env(:palee, :fiscal_connection_notifier, previous) end)
    :ok
  end

  defp responses(entries) do
    body =
      Enum.map_join(entries, fn
        {index, :ok, mark} ->
          "<response><index>#{index}</index><invoiceUid>U#{index}</invoiceUid>" <>
            "<invoiceMark>#{mark}</invoiceMark><qrUrl>https://q/#{index}</qrUrl>" <>
            "<statusCode>Success</statusCode></response>"

        {index, :error, code} ->
          "<response><index>#{index}</index><statusCode>ValidationError</statusCode>" <>
            "<errors><error><message>e#{code}</message><code>#{code}</code></error></errors></response>"
      end)

    ~s(<?xml version="1.0" encoding="utf-8"?><ResponseDoc>#{body}</ResponseDoc>)
  end

  defp transmitted(document, mark) do
    ~s(<?xml version="1.0" encoding="utf-8"?><RequestedDoc><invoicesDoc><invoice>) <>
      "<uid>UID-FOUND</uid><mark>#{mark}</mark>" <>
      "<issuer><vatNumber>090000045</vatNumber></issuer><invoiceHeader>" <>
      "<series>#{document.series}</series><aa>#{document.sequence}</aa>" <>
      "<issueDate>#{Date.to_iso8601(document.issue_date)}</issueDate>" <>
      "<invoiceType>11.2</invoiceType></invoiceHeader></invoice></invoicesDoc></RequestedDoc>"
  end

  describe "ADR-530" do
    setup :use_notifier

    test "due documents go to AADE in one InvoicesDoc, each with its own result", %{
      context: context,
      owner: owner
    } do
      test_pid = self()

      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:sent, conn.request_path, body})

        Plug.Conn.send_resp(
          conn,
          200,
          responses([
            {1, :ok, "400000000000001"},
            {2, :error, "102"},
            {3, :ok, "400000000000003"}
          ])
        )
      end)

      connect(context, owner, "production", %{user_id: "u", subscription_key: "k"})
      [first, second, third] = for key <- ~w(b-1 b-2 b-3), do: issue(context, owner, key)

      assert {:ok, %{accepted: 2, rejected: 1}} = Reporting.transmit(context, :due, @now)
      assert_received {:sent, "/SendInvoices", body}
      refute_received {:sent, _path, _body}
      assert body |> String.split("<invoice>") |> length() == 4

      assert %{status: "accepted", mark: "400000000000001"} = transmission(context, first)
      assert %{status: "rejected", last_error_code: "102"} = transmission(context, second)
      assert %{status: "accepted", mark: "400000000000003"} = transmission(context, third)

      # Each attempt keeps only its own document.
      %{attempts_log: [attempt]} = Reporting.get(context, transmission(context, second).id)
      assert attempt.request_body |> String.split("<invoice>") |> length() == 2

      assert_received {:documents_not_reported, "mydata", 1}
    end

    test "after a lost answer the document is looked up at AADE, never sent twice", %{
      context: context,
      owner: owner
    } do
      test_pid = self()
      connect(context, owner, "production", %{user_id: "u", subscription_key: "k"})
      document = issue(context, owner, "lost-1")

      # AADE registers the document, but the answer is lost.
      Req.Test.stub(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 504, "") end)
      assert {:ok, %{retrying: 1}} = Reporting.transmit(context, :due, @now)
      assert %{status: "pending", last_error_code: "transient"} = transmission(context, document)

      Req.Test.stub(__MODULE__, fn conn ->
        send(test_pid, {:request, conn.method, conn.request_path, conn.query_string})

        Plug.Conn.send_resp(conn, 200, transmitted(document, "400000000000777"))
      end)

      later = DateTime.add(@now, 120, :second)
      assert {:ok, %{accepted: 1}} = Reporting.transmit(context, :due, later)

      assert_received {:request, "GET", "/RequestTransmittedDocs", query}
      assert query =~ "dateFrom=01%2F02%2F2027"
      refute_received {:request, "POST", _path, _query}

      assert %{status: "accepted", mark: "400000000000777", uid: "UID-FOUND"} =
               transmission(context, document)
    end

    test "a row whose worker died mid-call is looked up before it is sent again", %{
      context: context,
      owner: owner
    } do
      test_pid = self()
      connect(context, owner, "production", %{user_id: "u", subscription_key: "k"})
      document = issue(context, owner, "dead-1")

      # A worker claims the row and dies while AADE registers it: nothing
      # is recorded, and the claim expires.
      bypass_rls(fn ->
        Palee.Infrastructure.Fiscal.EctoTransmissionStore.claim(context, :due, @now, 25)
      end)

      Req.Test.stub(__MODULE__, fn conn ->
        send(test_pid, {:request, conn.method, conn.request_path})
        Plug.Conn.send_resp(conn, 200, transmitted(document, "400000000000555"))
      end)

      stale =
        DateTime.add(@now, Palee.Fiscal.Domain.TransmissionPolicy.claim_timeout_seconds() + 1)

      assert {:ok, %{accepted: 1}} = Reporting.transmit(context, :due, stale)

      assert_received {:request, "GET", "/RequestTransmittedDocs"}
      refute_received {:request, "POST", _path}
      assert %{status: "accepted", mark: "400000000000555"} = transmission(context, document)
    end

    test "a lookup that finds nothing sends the document again", %{context: context, owner: owner} do
      connect(context, owner, "production", %{user_id: "u", subscription_key: "k"})
      document = issue(context, owner, "lost-2")
      Req.Test.stub(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 503, "") end)
      Reporting.transmit(context, :due, @now)

      Req.Test.stub(__MODULE__, fn
        %{method: "GET"} = conn ->
          Plug.Conn.send_resp(conn, 200, "<RequestedDoc><invoicesDoc/></RequestedDoc>")

        conn ->
          Plug.Conn.send_resp(conn, 200, responses([{1, :ok, "400000000000888"}]))
      end)

      assert {:ok, %{accepted: 1}} = Reporting.transmit(context, :due, DateTime.add(@now, 120))
      assert %{mark: "400000000000888"} = transmission(context, document)
    end

    test "AADE's 'already sent' answer takes the registered MARK; unknown stays rejected", %{
      context: context,
      owner: owner
    } do
      connect(context, owner, "production", %{user_id: "u", subscription_key: "k"})
      found = issue(context, owner, "dup-1")

      Req.Test.stub(__MODULE__, fn
        %{method: "GET"} = conn ->
          Plug.Conn.send_resp(conn, 200, transmitted(found, "400000000000999"))

        conn ->
          Plug.Conn.send_resp(conn, 200, responses([{1, :error, "233"}]))
      end)

      assert {:ok, %{accepted: 1}} = Reporting.transmit(context, :due, @now)
      assert %{status: "accepted", mark: "400000000000999"} = transmission(context, found)
      refute_received {:documents_not_reported, _kind, _count}

      missing = issue(context, owner, "dup-2")

      Req.Test.stub(__MODULE__, fn
        %{method: "GET"} = conn ->
          Plug.Conn.send_resp(conn, 200, "<RequestedDoc><invoicesDoc/></RequestedDoc>")

        conn ->
          Plug.Conn.send_resp(conn, 200, responses([{1, :error, "233"}]))
      end)

      assert {:ok, %{rejected: 1}} = Reporting.transmit(context, :due, @now)
      assert %{status: "rejected", last_error_code: "233"} = transmission(context, missing)
      assert_received {:documents_not_reported, "mydata", 1}
    end

    test "a claim always outlives the longest call to AADE" do
      config = Application.get_env(:palee, :mydata, [])
      claim_ms = Palee.Fiscal.Domain.TransmissionPolicy.claim_timeout_seconds() * 1_000

      # Every call starts with a fresh claim; the longest is one send or a
      # look-up through all its pages.
      assert Keyword.get(config, :receive_timeout, 30_000) < claim_ms

      assert Keyword.get(config, :check_timeout, 15_000) *
               Palee.Infrastructure.Fiscal.MyDataGateway.max_lookup_pages() < claim_ms
    end
  end

  test "the cron sweep hands each box to its own run (ADR-530)", %{context: context, owner: owner} do
    # Background jobs are off in tests, so each box's run happens inline.
    connect(context, owner, "sandbox")
    document = issue(context, owner, "k-cron", %{}, DateTime.utc_now())

    assert :ok = Palee.Workers.TransmitFiscalDocumentsJob.perform(%Oban.Job{args: %{}})
    assert %{status: "accepted"} = transmission(context, document)
  end

  test "the worker sends one tenant's due documents", %{context: context, owner: owner} do
    connect(context, owner, "sandbox")
    document = issue(context, owner, "k-1", %{}, DateTime.utc_now())

    assert :ok =
             Palee.Workers.TransmitFiscalDocumentsJob.perform(%Oban.Job{
               args: %{"organization_id" => context.organization_id, "transmission_id" => nil}
             })

    assert %{status: "accepted"} = transmission(context, document)
  end
end
