defmodule Palee.Infrastructure.Fiscal.MyDataGatewayTest do
  @moduledoc """
  ADR-452: the myDATA adapter matches several answers to their invoices by
  `index`, turns AADE's "already sent" into `:duplicate`, and finds a
  registered document across pages of `RequestTransmittedDocs`.
  """

  use ExUnit.Case, async: false

  alias Palee.Infrastructure.Fiscal.MyDataGateway

  @connection %{environment: "test", user_id: "u", subscription_key: "k"}
  @key %{
    issuer_vat: "090000045",
    series: "A",
    aa: "7",
    issue_date: ~D[2027-02-01],
    invoice_type: "11.2"
  }

  defp invoice(aa), do: [{"invoiceHeader", [{"series", "A"}, {"aa", aa}]}]

  defp doc(series, aa, mark) do
    "<invoice><uid>U#{aa}</uid><mark>#{mark}</mark><issuer><vatNumber>090000045</vatNumber></issuer>" <>
      "<invoiceHeader><series>#{series}</series><aa>#{aa}</aa><issueDate>2027-02-01</issueDate>" <>
      "<invoiceType>11.2</invoiceType></invoiceHeader></invoice>"
  end

  test "answers come back in the order of the invoices, whatever order AADE uses" do
    Req.Test.stub(Palee.FiscalHttp, fn conn ->
      Plug.Conn.send_resp(conn, 200, """
      <ResponseDoc>
        <response><index>2</index><statusCode>ValidationError</statusCode>
          <errors><error><message>already sent</message><code>233</code></error></errors></response>
        <response><index>1</index><invoiceMark>400000000000001</invoiceMark><statusCode>Success</statusCode></response>
      </ResponseDoc>
      """)
    end)

    assert {[
              {:ok, %{mark: "400000000000001"}},
              {:error, {:duplicate, [%{code: "233"}]}},
              {:error, :empty_response}
            ],
            %{request_bodies: [_one, _two, _three]}} =
             MyDataGateway.submit(@connection, [invoice("1"), invoice("2"), invoice("3")])
  end

  test "refused credentials fail every invoice of the call" do
    Req.Test.stub(Palee.FiscalHttp, fn conn -> Plug.Conn.send_resp(conn, 401, "") end)

    assert {[{:error, {:unauthorized, {:http, 401}}}, {:error, {:unauthorized, {:http, 401}}}],
            _wire} =
             MyDataGateway.submit(@connection, [invoice("1"), invoice("2")])
  end

  test "find follows the continuation token to the next page" do
    test_pid = self()

    Req.Test.stub(Palee.FiscalHttp, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      send(test_pid, {:query, conn.query_params})

      body =
        case conn.query_params["nextPartitionKey"] do
          nil ->
            "<RequestedDoc><continuationToken><nextPartitionKey>P</nextPartitionKey>" <>
              "<nextRowKey>R</nextRowKey></continuationToken><invoicesDoc>#{doc("A", "6", "400000000000006")}</invoicesDoc></RequestedDoc>"

          "P" ->
            "<RequestedDoc><invoicesDoc>#{doc("A", "7", "400000000000007")}</invoicesDoc></RequestedDoc>"
        end

      Plug.Conn.send_resp(conn, 200, body)
    end)

    assert {:ok, %{mark: "400000000000007", uid: "U7"}} = MyDataGateway.find(@connection, @key)

    assert_received {:query,
                     %{
                       "mark" => "0",
                       "dateFrom" => "01/02/2027",
                       "dateTo" => "01/02/2027",
                       "invType" => "11.2"
                     }}

    assert_received {:query, %{"nextPartitionKey" => "P", "nextRowKey" => "R"}}
  end

  test "find takes the first registration when a resend got a second MARK" do
    Req.Test.stub(Palee.FiscalHttp, fn conn ->
      cancelled =
        String.replace(
          doc("A", "7", "400000000000099"),
          "</mark>",
          "</mark><cancelledByMark>400000000000100</cancelledByMark>"
        )

      Plug.Conn.send_resp(
        conn,
        200,
        "<RequestedDoc><invoicesDoc>#{doc("A", "7", "400000000000012")}" <>
          "#{doc("A", "7", "400000000000011")}#{cancelled}</invoicesDoc></RequestedDoc>"
      )
    end)

    assert {:ok, %{mark: "400000000000011"}} = MyDataGateway.find(@connection, @key)
  end

  test "find says not found, and passes refused credentials on" do
    Req.Test.stub(Palee.FiscalHttp, fn conn ->
      Plug.Conn.send_resp(
        conn,
        200,
        "<RequestedDoc><invoicesDoc>#{doc("B", "7", "1")}</invoicesDoc></RequestedDoc>"
      )
    end)

    assert :not_found = MyDataGateway.find(@connection, @key)

    Req.Test.stub(Palee.FiscalHttp, fn conn -> Plug.Conn.send_resp(conn, 403, "") end)
    assert {:error, {:unauthorized, {:http, 403}}} = MyDataGateway.find(@connection, @key)
  end
end
