defmodule Palee.Infrastructure.Fiscal.MyDataLiveTest do
  @moduledoc """
  ADR-451 (Κ3): the myDATA adapter against AADE's real development API
  (`mydataapidev.aade.gr`), not a stub. The `:aade_live` tag is excluded from
  normal runs; `mix test --only aade_live` runs it and needs:

    * `MYDATA_DEV_USER` – the user name of the AADE test registration;
    * `MYDATA_DEV_KEY` – its «Κωδικός API» (subscription key);
    * `MYDATA_DEV_VAT` – the ΑΦΜ it was registered with (AADE accepts
      only documents of that issuer).

  Every run uses a new series, so it can run
  again and again. Nothing here reaches the production API.
  """

  use ExUnit.Case, async: false

  import Palee.FiscalTestDocuments

  alias Palee.Fiscal.Domain.MyDataInvoice
  alias Palee.Infrastructure.Fiscal.MyDataGateway

  @moduletag :aade_live
  @moduletag timeout: 180_000

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

  defp eventually_found(connection, invoice, tries \\ 12) do
    case MyDataGateway.find(connection, MyDataInvoice.key(invoice)) do
      # :not_found while AADE indexes it, 429 when the dev API rate-limits us.
      result when result in [:not_found, {:error, {:http, 429}}] and tries > 1 ->
        Process.sleep(10_000)
        eventually_found(connection, invoice, tries - 1)

      other ->
        other
    end
  end

  test "«Δοκιμή σύνδεσης» takes the key and refuses a wrong one", %{connection: connection} do
    assert {:ok, %{}} = MyDataGateway.check(connection)

    assert {:error, {:unauthorized, _}} =
             MyDataGateway.check(%{connection | subscription_key: "wrong-key"})
  end

  test "a batch is registered, a resend is registered again, and the MARK is found", %{
    connection: connection,
    vat: vat
  } do
    series = "PT#{System.os_time(:second)}"
    first = receipt(vat, series, 1)
    second = receipt(vat, series, 2)

    assert {[{:ok, %{mark: mark}}, {:ok, %{mark: _other}}], _wire} =
             MyDataGateway.submit(connection, [first, second])

    # The same document again. On the ERP channel AADE registers it a
    # second time, with a new MARK and the same UID (seen 2026-11-04), which
    # is why a row whose answer was lost is looked up before it is resent.
    # 233 ("already sent") is what AADE lists for providers.
    second_mark =
      case MyDataGateway.submit(connection, [first]) do
        {[{:error, {:duplicate, _errors}}], _wire} -> mark
        {[{:ok, %{mark: again}}], _wire} -> again
      end

    # AADE lists new documents after a short delay.
    assert {:ok, %{mark: found, qr_url: qr_url}} = eventually_found(connection, first)
    assert found in [mark, second_mark]
    assert is_binary(qr_url)

    assert :not_found = eventually_found(connection, receipt(vat, series, 99), 1)
  end
end
