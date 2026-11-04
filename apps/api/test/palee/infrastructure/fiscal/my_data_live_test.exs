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

  test "«Δοκιμή σύνδεσης» takes the key and refuses a wrong one", %{connection: connection} do
    assert {:ok, %{}} = MyDataGateway.check(connection)

    assert {:error, {:unauthorized, _}} =
             MyDataGateway.check(%{connection | subscription_key: "wrong-key"})
  end

  test "a batch is registered, a resend is a duplicate and the MARK is found again", %{
    connection: connection,
    vat: vat
  } do
    series = "PT#{System.os_time(:second)}"
    first = receipt(vat, series, 1)
    second = receipt(vat, series, 2)

    assert {[{:ok, %{mark: mark}}, {:ok, %{mark: _other}}], _wire} =
             MyDataGateway.submit(connection, [first, second])

    # The same document again: AADE must say "already sent", in the code
    # the adapter knows (`MyDataGateway.duplicate_codes/0`).
    assert {[{:error, {:duplicate, _errors}}], _wire} = MyDataGateway.submit(connection, [first])

    assert {:ok, %{mark: ^mark}} = MyDataGateway.find(connection, MyDataInvoice.key(first))

    assert :not_found =
             MyDataGateway.find(connection, MyDataInvoice.key(receipt(vat, series, 99)))
  end
end
