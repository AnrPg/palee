defmodule Palee.Infrastructure.Fiscal.MyDataLiveTest do
  @moduledoc """
  ADR-451 (Κ3): the myDATA adapter against AADE's real development API
  (`mydataapidev.aade.gr`), not a stub. Runs only when these are set (the
  `:aade_live` tag is excluded otherwise):

    * `MYDATA_DEV_USER` – the user name of the AADE test registration;
    * `MYDATA_DEV_KEY` – its «Κωδικός API» (subscription key);
    * `MYDATA_DEV_VAT` – the ΑΦΜ it was registered with (AADE accepts
      only documents of that issuer).

  `mix test --only aade_live`. Every run uses a new series, so it can run
  again and again. Nothing here reaches the production API.

  What the first run against AADE showed (2026-11-04):

    * retail receipts (11.x) need `<currency>`, although the XSD marks it
      optional (error 204);
    * the development API does NOT refuse a resend: it registers the same
      UID under a new MARK. So a resend must never happen blindly
      (`Fiscal.Reporting` looks a possibly-sent row up first) and the
      "already sent" code 228 is handled but cannot be confirmed here;
    * `RequestTransmittedDocs` takes `mark=0`, `dateFrom`/`dateTo`
      (dd/MM/yyyy) and `invType`, and filters by them;
    * a few calls in a row get HTTP 429 with `Retry-After` (~30 s), so
      every call here waits and retries on 429 (`paced/1`). In the outbox
      429 is transient and the first backoff (60 s) is longer.
  """

  use ExUnit.Case, async: false

  import Palee.FiscalTestDocuments

  alias Palee.Fiscal.Domain.MyDataInvoice
  alias Palee.Infrastructure.Fiscal.MyDataGateway

  @moduletag :aade_live
  @moduletag timeout: 900_000

  setup do
    previous = Application.get_env(:palee, :mydata)
    Application.put_env(:palee, :mydata, req_options: proxy_options())

    on_exit(fn -> Application.put_env(:palee, :mydata, previous) end)

    %{
      connection: %{
        environment: "test",
        user_id: System.fetch_env!("MYDATA_DEV_USER"),
        subscription_key: System.fetch_env!("MYDATA_DEV_KEY")
      },
      vat: System.fetch_env!("MYDATA_DEV_VAT")
    }
  end

  defp proxy_options do
    case System.get_env("HTTPS_PROXY") || System.get_env("https_proxy") do
      proxy when is_binary(proxy) and proxy != "" ->
        %URI{scheme: scheme, host: host, port: port} = URI.parse(proxy)
        cacertfile = System.get_env("SSL_CERT_FILE")

        [
          connect_options:
            [proxy: {String.to_existing_atom(scheme || "http"), host, port, []}] ++
              if(cacertfile, do: [transport_opts: [cacertfile: cacertfile]], else: [])
        ]

      _none ->
        []
    end
  end

  # AADE's development API allows only a few calls in a row and then
  # answers 429 with `Retry-After` of about half a minute; wait it out.
  defp paced(call, tries \\ 4) do
    Process.sleep(2_000)

    case call.() do
      {:error, {:http, 429}} when tries > 1 -> wait_and(call, tries)
      {[{:error, {:http, 429}} | _], _wire} when tries > 1 -> wait_and(call, tries)
      result -> result
    end
  end

  defp wait_and(call, tries) do
    Process.sleep(35_000)
    paced(call, tries - 1)
  end

  defp receipt(vat, series, sequence, extra \\ %{}) do
    document =
      document(
        Map.merge(
          %{
            series: series,
            sequence: sequence,
            issue_date: Date.utc_today(),
            payment_method: "cash",
            seller: Map.put(seller(), "tax_id", vat)
          },
          extra
        )
      )

    {:ok, invoice} = MyDataInvoice.build(document)
    invoice
  end

  test "«Δοκιμή σύνδεσης» takes the key and refuses a wrong one", %{connection: connection} do
    assert {:ok, %{}} = paced(fn -> MyDataGateway.check(connection) end)

    assert {:error, {:unauthorized, _}} =
             paced(fn -> MyDataGateway.check(%{connection | subscription_key: "wrong-key"}) end)
  end

  test "a batch is registered, a resend keeps the UID and the first MARK is found again", %{
    connection: connection,
    vat: vat
  } do
    series = "PT#{System.os_time(:second)}"
    first = receipt(vat, series, 1)
    second = receipt(vat, series, 2)

    assert {[{:ok, %{mark: mark, uid: uid}}, {:ok, %{mark: other}}], _wire} =
             paced(fn -> MyDataGateway.submit(connection, [first, second]) end)

    assert mark != other

    # The same document again. Production should answer "already sent"
    # (`MyDataGateway.duplicate_codes/0`); the development API registers it
    # again under the same UID. Either way it is the same document.
    case paced(fn -> MyDataGateway.submit(connection, [first]) end) do
      {[{:error, {:duplicate, _errors}}], _wire} -> :ok
      {[{:ok, %{uid: resent_uid}}], _wire} -> assert resent_uid == uid
    end

    # The look-up finds the first registration of the document.
    assert {:ok, %{mark: ^mark, uid: ^uid, qr_url: "https://" <> _}} =
             paced(fn -> MyDataGateway.find(connection, MyDataInvoice.key(first)) end)

    assert :not_found =
             paced(fn ->
               MyDataGateway.find(connection, MyDataInvoice.key(receipt(vat, series, 99)))
             end)
  end
end
