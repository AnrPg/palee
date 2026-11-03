defmodule Palee.Infrastructure.Channels.OwnSmsVendorsTest do
  @moduledoc """
  ADR-396: the adapters of the SMS vendors a box brings itself, over
  stubbed HTTP (`Req.Test`): what each sends, how its answers and errors
  map onto the port, its «Δοκιμή σύνδεσης» and its webhook (signature
  checked where the vendor signs). Credentials never appear in an error.
  """

  # Shares the Req.Test stub name with the channels suites that use shared mode.
  use ExUnit.Case, async: false

  alias Palee.Infrastructure.Channels.{
    ApifonChannel,
    InfobipChannel,
    TwilioChannel,
    VonageChannel,
    YubotoChannel
  }

  @id "6c1c3f8e-2b0f-4d8e-9a59-6a1f3d2b7c10"
  @callback "https://palee.app/api/webhooks/channels/org/tok"

  defp outgoing(overrides \\ %{}) do
    Map.merge(
      %{
        id: @id,
        channel: "sms",
        to: "+306912345678",
        body: "Το μάθημα ακυρώθηκε",
        purpose: "service",
        template: nil,
        callback_url: @callback
      },
      overrides
    )
  end

  defp capture(answer) do
    test_pid = self()

    Req.Test.stub(Palee.ChannelsHttp, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:request, conn.method, conn.request_path, conn.query_string, conn.req_headers, body})
      answer.(conn)
    end)
  end

  defp status(conn, code, body), do: conn |> Plug.Conn.put_status(code) |> Req.Test.json(body)

  defp refute_secret(result, secrets) do
    text = inspect(result)
    for secret <- secrets, do: refute(text =~ secret)
    result
  end

  describe "Twilio" do
    @sid "AC" <> String.duplicate("0a", 16)
    @account %{provider: "twilio", account_id: @sid, secret: "tw-token", sms_sender: "CFAthina"}

    test "sends with basic auth and the status callback" do
      capture(&status(&1, 201, %{"sid" => "SM123", "status" => "queued", "price" => nil}))

      assert {:ok, %{provider_message_id: "SM123", cost_cents: nil}} =
               TwilioChannel.send_message(@account, outgoing())

      assert_received {:request, "POST", path, _query, headers, body}
      assert path == "/2010-04-01/Accounts/#{@sid}/Messages.json"
      assert {"authorization", "Basic " <> Base.encode64("#{@sid}:tw-token")} in headers
      form = URI.decode_query(body)
      assert form["To"] == "+306912345678"
      assert form["From"] == "CFAthina"
      assert form["StatusCallback"] == @callback
    end

    test "a Messaging Service picks the sender" do
      service = "MG" <> String.duplicate("1b", 16)
      capture(&status(&1, 201, %{"sid" => "SM1"}))
      TwilioChannel.send_message(%{@account | sms_sender: service}, outgoing())
      assert_received {:request, _method, _path, _query, _headers, body}
      assert URI.decode_query(body)["MessagingServiceSid"] == service
    end

    test "errors map onto the port without the token" do
      capture(&status(&1, 400, %{"code" => 21_211, "message" => "Invalid 'To'"}))

      assert {:error, {:rejected, "twilio_21211"}} =
               @account |> TwilioChannel.send_message(outgoing()) |> refute_secret(["tw-token"])

      capture(&status(&1, 401, %{"code" => 20_003, "message" => "Authenticate"}))
      assert {:error, {:unauthorized, "twilio_http_401"}} = TwilioChannel.send_message(@account, outgoing())

      capture(&status(&1, 503, %{}))
      assert {:error, {:transient, "twilio_http_503"}} = TwilioChannel.send_message(@account, outgoing())

      assert {:error, {:rejected, "sms_sender_missing"}} =
               TwilioChannel.send_message(%{@account | sms_sender: nil}, outgoing())

      assert {:error, {:unauthorized, _}} = TwilioChannel.send_message(%{provider: "twilio"}, outgoing())
    end

    test "check reads the account" do
      capture(&Req.Test.json(&1, %{"status" => "active"}))
      assert {:ok, %{account_status: "active"}} = TwilioChannel.check(@account)
      assert_received {:request, "GET", "/2010-04-01/Accounts/" <> _, _query, _headers, _body}
    end

    test "webhook: signed status callbacks only" do
      params = %{"MessageSid" => "SM123", "MessageStatus" => "undelivered", "ErrorCode" => "30003"}
      signature = TwilioChannel.signature("tw-token", @callback, params)
      request = %{url: @callback, params: params, headers: [{"x-twilio-signature", signature}], raw_body: ""}

      assert {:ok, [%{type: :status, status: "failed", error_code: "30003", event_key: "twilio:SM123:undelivered"}]} =
               TwilioChannel.parse_webhook(@account, request)

      assert {:error, :invalid_signature} =
               TwilioChannel.parse_webhook(@account, %{request | headers: [{"x-twilio-signature", "AAAA"}]})

      assert {:error, :invalid_signature} =
               TwilioChannel.parse_webhook(@account, %{request | params: Map.put(params, "MessageStatus", "delivered")})

      inbound = %{"From" => "+306912345678", "Body" => "STOP"}

      assert {:ok, [%{type: :inbound, text: "STOP"}]} =
               TwilioChannel.parse_webhook(@account, %{
                 request
                 | params: inbound,
                   headers: [{"x-twilio-signature", TwilioChannel.signature("tw-token", @callback, inbound)}]
               })
    end
  end

  describe "Vonage" do
    @account %{provider: "vonage", account_id: "vk1", secret: "vs-secret", sms_sender: "CFAthina"}

    test "sends Greek as unicode with the callback and client reference" do
      capture(&Req.Test.json(&1, %{"message-count" => "1", "messages" => [%{"status" => "0", "message-id" => "V1"}]}))

      assert {:ok, %{provider_message_id: "V1"}} = VonageChannel.send_message(@account, outgoing())
      assert_received {:request, "POST", "/sms/json", _query, _headers, body}
      form = URI.decode_query(body)
      assert form["to"] == "306912345678"
      assert form["type"] == "unicode"
      assert form["callback"] == @callback
      assert form["client-ref"] == @id

      VonageChannel.send_message(@account, outgoing(%{body: "Class cancelled"}))
      assert_received {:request, _, _, _, _, latin}
      assert URI.decode_query(latin)["type"] == "text"
    end

    test "a status per part maps onto the port without the secret" do
      for {code, kind} <- [{"1", :transient}, {"9", :transient}, {"4", :unauthorized}, {"15", :rejected}] do
        capture(&Req.Test.json(&1, %{"messages" => [%{"status" => code, "error-text" => "x"}]}))

        assert {:error, {^kind, detail}} =
                 @account |> VonageChannel.send_message(outgoing()) |> refute_secret(["vs-secret"])

        assert detail == "vonage_" <> code
      end
    end

    test "check reads the balance with basic auth" do
      capture(&Req.Test.json(&1, %{"value" => 10.28, "autoReload" => false}))
      assert {:ok, %{balance: 10.28}} = VonageChannel.check(@account)
      assert_received {:request, "GET", "/account/get-balance", "", headers, _body}
      assert {"authorization", "Basic " <> Base.encode64("vk1:vs-secret")} in headers

      capture(&status(&1, 401, %{}))
      assert {:error, {:unauthorized, "vonage_http_401"}} = VonageChannel.check(@account)
    end

    test "webhook: signed when the box saved the signature secret" do
      params = %{
        "messageId" => "V1",
        "status" => "delivered",
        "err-code" => "0",
        "msisdn" => "306912345678",
        "timestamp" => "1730628000"
      }

      data = VonageChannel.signed_data(params)
      assert data =~ ~r/^&err-code=0&messageId=V1&msisdn=/

      assert {:ok, [%{status: "delivered", error_code: nil, event_key: "vonage:V1:delivered"}]} =
               VonageChannel.parse_webhook(@account, %{params: params})

      signed = Map.put(@account, :webhook_secret, "sig-secret")

      for algorithm <- [:md5hash, :sha256, :sha512] do
        sig = VonageChannel.digest(algorithm, "sig-secret", data)
        assert {:ok, [_receipt]} = VonageChannel.parse_webhook(signed, %{params: Map.put(params, "sig", String.upcase(sig))})
      end

      assert {:error, :invalid_signature} = VonageChannel.parse_webhook(signed, %{params: params})

      assert {:error, :invalid_signature} =
               VonageChannel.parse_webhook(signed, %{params: Map.put(params, "sig", String.duplicate("0", 64))})

      assert {:ok, [%{status: "failed", error_code: "6"}]} =
               VonageChannel.parse_webhook(@account, %{params: %{params | "status" => "rejected", "err-code" => "6"}})
    end
  end

  describe "Infobip" do
    @account %{
      provider: "infobip",
      secret: "ib-key",
      base_url: "https://x1y2z3.api.infobip.com",
      sms_sender: "CFAthina"
    }

    test "sends through v3 with the delivery webhook" do
      capture(&Req.Test.json(&1, %{"bulkId" => "b", "messages" => [%{"messageId" => @id, "status" => %{"groupName" => "PENDING"}}]}))

      assert {:ok, %{provider_message_id: @id}} = InfobipChannel.send_message(@account, outgoing())
      assert_received {:request, "POST", "/sms/3/messages", _query, headers, body}
      assert {"authorization", "App ib-key"} in headers
      [message] = Jason.decode!(body)["messages"]
      assert message["destinations"] == [%{"to" => "306912345678", "messageId" => @id}]
      assert message["webhooks"]["delivery"]["url"] == @callback
      assert message["content"]["text"] =~ "ακυρώθηκε"
    end

    test "a rejected message, refused key and a base URL that is not Infobip's" do
      capture(&Req.Test.json(&1, %{"messages" => [%{"status" => %{"groupName" => "REJECTED", "name" => "REJECTED_DESTINATION"}}]}))
      assert {:error, {:rejected, "infobip_REJECTED_DESTINATION"}} = InfobipChannel.send_message(@account, outgoing())

      capture(&status(&1, 401, %{"requestError" => %{}}))

      assert {:error, {:unauthorized, "infobip_http_401"}} =
               @account |> InfobipChannel.send_message(outgoing()) |> refute_secret(["ib-key"])

      assert {:error, {:unauthorized, "infobip_base_url_invalid"}} =
               InfobipChannel.send_message(%{@account | base_url: "https://evil.example"}, outgoing())
    end

    test "check reads the balance" do
      capture(&Req.Test.json(&1, %{"balance" => 47.79, "currency" => "EUR"}))
      assert {:ok, %{balance: 47.79, currency: "EUR"}} = InfobipChannel.check(@account)
      assert_received {:request, "GET", "/account/1/balance", _, _, _}
    end

    test "webhook: reports with the price in euros" do
      report = %{
        "results" => [
          %{
            "messageId" => @id,
            "status" => %{"groupName" => "DELIVERED", "name" => "DELIVERED_TO_HANDSET"},
            "error" => %{"name" => "NO_ERROR"},
            "price" => %{"pricePerMessage" => 0.045, "currency" => "EUR"},
            "doneAt" => "2026-11-03T10:15:00.000+0000"
          },
          %{
            "messageId" => "other",
            "status" => %{"groupName" => "UNDELIVERABLE", "name" => "UNDELIVERABLE_NOT_DELIVERED"},
            "error" => %{"name" => "EC_ABSENT_SUBSCRIBER"},
            "price" => %{"pricePerMessage" => 0.05, "currency" => "USD"}
          }
        ]
      }

      assert {:ok, [delivered, failed]} = InfobipChannel.parse_webhook(@account, %{params: report})
      assert %{status: "delivered", cost_cents: 5, currency: "EUR", error_code: nil} = delivered
      assert delivered.occurred_at == ~U[2026-11-03 10:15:00.000000Z]
      assert %{status: "failed", cost_cents: nil, error_code: "EC_ABSENT_SUBSCRIBER"} = failed
    end
  end

  describe "Yuboto" do
    @account %{provider: "yuboto", secret: "WVVCT1RPLUtFWQ==", sms_sender: "CFAthina"}

    test "sends with the encoded key and asks for the delivery callback" do
      capture(&Req.Test.json(&1, %{"ErrorCode" => 0, "ErrorMessage" => "", "Message" => [%{"id" => "Y1", "status" => "Submitted", "errorCode" => 0}]}))

      assert {:ok, %{provider_message_id: "Y1"}} = YubotoChannel.send_message(@account, outgoing())
      assert_received {:request, "POST", "/omni/v1/Send", _query, headers, body}
      assert {"authorization", "Basic WVVCT1RPLUtFWQ=="} in headers
      payload = Jason.decode!(body)
      assert payload["contacts"] == [%{"phonenumber" => "306912345678"}]
      assert payload["dlr"] == true
      assert payload["callbackUrl"] == @callback
      assert payload["option1"] == @id
      assert payload["sms"]["typesms"] == "unicode"
    end

    test "a key that is not Base64 yet is encoded once" do
      assert YubotoChannel.authorization("54E3B5F5-2CF3-412E") == "Basic " <> Base.encode64("54E3B5F5-2CF3-412E")
      assert YubotoChannel.authorization("WVVCT1RPLUtFWQ==") == "Basic WVVCT1RPLUtFWQ=="
    end

    test "error codes map onto the port" do
      for {code, kind} <- [{2, :unauthorized}, {4, :transient}, {108, :rejected}, {12, :rejected}] do
        capture(&Req.Test.json(&1, %{"ErrorCode" => code, "ErrorMessage" => "x"}))

        assert {:error, {^kind, detail}} =
                 @account |> YubotoChannel.send_message(outgoing()) |> refute_secret(["WVVCT1RPLUtFWQ=="])

        assert detail == "yuboto_#{code}"
      end
    end

    test "check reads the balance" do
      capture(&Req.Test.json(&1, %{"ErrorCode" => 0, "currentBalance" => 112.8, "type" => "money"}))
      assert {:ok, %{balance: 112.8, balance_type: "money"}} = YubotoChannel.check(@account)
      assert_received {:request, "POST", "/omni/v1/UserBalance", _, _, _}
    end

    test "webhook: the GET callback's query" do
      assert {:ok, [%{status: "delivered", event_key: "yuboto:Y1:1"}]} =
               YubotoChannel.parse_webhook(@account, %{params: %{"smsid" => "Y1", "status" => "1", "statusDescription" => "Delivered"}})

      assert {:ok, [%{status: "failed", error_code: "yuboto_status_-6"}]} =
               YubotoChannel.parse_webhook(@account, %{params: %{"smsid" => "Y1", "status" => "-6"}})

      assert {:ok, []} = YubotoChannel.parse_webhook(@account, %{params: %{}})
    end
  end

  describe "Apifon" do
    @account %{provider: "apifon", account_id: "ap-token", secret: "ap-secret", sms_sender: "CFAthina"}

    test "signs every request and sends UCS-2 for Greek" do
      capture(&Req.Test.json(&1, %{
        "request_id" => "r1",
        "results" => %{"306912345678" => [%{"message_id" => "A1", "custom_id" => @id}]},
        "result_info" => %{"status_code" => 200, "description" => "OK"}
      }))

      assert {:ok, %{provider_message_id: "A1"}} = ApifonChannel.send_message(@account, outgoing())
      assert_received {:request, "POST", "/services/api/v1/sms/send", _query, headers, body}

      {_, date} = List.keyfind(headers, "x-apifonws-date", 0)
      {_, authorization} = List.keyfind(headers, "authorization", 0)
      expected = ApifonChannel.signature("ap-secret", "POST", "/services/api/v1/sms/send", body, date)
      assert authorization == "ApifonWS ap-token:" <> expected

      payload = Jason.decode!(body)
      assert payload["message"]["dc"] == 2
      assert payload["message"]["sender_id"] == "CFAthina"
      assert payload["callback_url"] == @callback
      assert payload["subscribers"] == [%{"number" => "306912345678", "custom_id" => @id}]
    end

    test "errors map onto the port without the secret" do
      capture(&status(&1, 401, %{"result_info" => %{"status_code" => 401}}))

      assert {:error, {:unauthorized, "apifon_401"}} =
               @account |> ApifonChannel.send_message(outgoing()) |> refute_secret(["ap-secret"])

      capture(&Req.Test.json(&1, %{"result_info" => %{"status_code" => 403, "description" => "Wrong parameters"}}))
      assert {:error, {:rejected, "apifon_403"}} = ApifonChannel.send_message(@account, outgoing())
    end

    test "check signs the empty balance request" do
      capture(&Req.Test.json(&1, %{"balance" => "9864.0"}))
      assert {:ok, %{balance: "9864.0"}} = ApifonChannel.check(@account)
      assert_received {:request, "POST", "/services/api/v1/balance", _, _, ""}
    end

    test "webhook: delivery callbacks and replies" do
      callback = %{
        "data" => [
          %{"message_id" => "A1", "status" => %{"code" => 7, "text" => "delivered"}, "error_code" => "000", "timestamp" => 1_730_628_000},
          %{"message_id" => "A2", "status" => %{"code" => 22, "text" => "unknown_sub"}, "error_code" => "001"}
        ],
        "type" => "SMS"
      }

      assert {:ok, [delivered, failed]} = ApifonChannel.parse_webhook(@account, %{params: callback})
      assert %{status: "delivered", error_code: nil, event_key: "apifon:A1:7"} = delivered
      assert delivered.occurred_at == ~U[2024-11-03 10:00:00.000000Z]
      assert %{status: "failed", error_code: "001"} = failed

      assert {:ok, [%{type: :inbound, from: "+306912345678", text: "STOP"}]} =
               ApifonChannel.parse_webhook(@account, %{params: %{"from" => "306912345678", "text" => "STOP"}})
    end
  end
end
