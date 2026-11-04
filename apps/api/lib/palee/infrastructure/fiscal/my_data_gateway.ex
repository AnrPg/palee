defmodule Palee.Infrastructure.Fiscal.MyDataGateway do
  @moduledoc """
  AADE myDATA REST API, ERP channel (ADR-243): `POST /SendInvoices` with
  the business's own myDATA user and subscription key.

  Environments: `test` → AADE's development API, `production` → the live
  API. Base URLs come from config (`:palee, :mydata`) so a proxy or a
  test plug can stand in; requests honour the outbound proxy like the
  other adapters (`req_options`).

  Results (see `Fiscal.Ports.AuthorityGateway`), one per invoice of the
  `InvoicesDoc` (ADR-451: several per call, matched by `index`): a
  `Success` response with an `invoiceMark` is accepted;
  `ValidationError`/`XMLSyntaxError` are rejections, except AADE's
  "already sent" codes, which are `{:duplicate, errors}` so the caller can
  look the MARK up (`find/2`); HTTP 401/403 means the credentials were
  refused; everything else (timeouts, 5xx, 429, `TechnicalError`) is
  transient and retried.
  """

  @behaviour Palee.Fiscal.Ports.AuthorityGateway

  alias Palee.Infrastructure.Fiscal.MyData.XmlCodec

  @base_urls %{
    "test" => "https://mydataapidev.aade.gr",
    "production" => "https://mydatapi.aade.gr/myDATA"
  }
  @max_logged_body 65_536

  # AADE's validation code for a document that is already registered
  # (same UID: issuer, date, branch, type, series and number), per the
  # v1.0.12 API documentation: 233 "UID has already been sent". AADE lists
  # it for providers; on the ERP channel a document with the same UID
  # replaces the earlier one instead (error 259 names that case). ADR-451.
  @duplicate_codes ~w(233)
  # Pages of `RequestTransmittedDocs` read while looking a document up.
  @max_lookup_pages 20

  def duplicate_codes, do: @duplicate_codes
  def max_lookup_pages, do: @max_lookup_pages

  @impl true
  def submit(connection, invoices) when is_list(invoices) do
    {results, wire} = send_invoices(connection, invoices)
    {results, Map.put(wire, :request_bodies, Enum.map(invoices, &XmlCodec.invoices_doc([&1])))}
  end

  defp send_invoices(connection, invoices) do
    body = XmlCodec.invoices_doc(invoices)

    with {:ok, base_url} <- base_url(connection.environment),
         :ok <- credentials(connection) do
      config = Application.get_env(:palee, :mydata, [])

      [
        url: base_url <> "/SendInvoices",
        body: body,
        headers: [
          {"aade-user-id", connection.user_id},
          {"ocp-apim-subscription-key", connection.subscription_key},
          {"content-type", "application/xml; charset=utf-8"}
        ],
        receive_timeout: Keyword.get(config, :receive_timeout, 30_000),
        retry: false,
        decode_body: false
      ]
      |> Keyword.merge(Keyword.get(config, :req_options, []))
      |> Req.post()
      |> interpret(body, length(invoices))
    else
      {:error, reason} ->
        {List.duplicate({:error, reason}, length(invoices)), wire(body, nil, nil)}
    end
  end

  # A MARK no document will reach for years: the answer lists nothing.
  @check_mark "999999999999999"

  @doc """
  «Δοκιμή σύνδεσης» (ADR-273): `GET /RequestTransmittedDocs` for documents
  after a MARK no document has, with the business's user and key. Nothing
  is reported; a 200 means AADE took the credentials, 401/403 that it
  refused them. The key never leaves the headers.
  """
  @impl true
  def check(connection) do
    with {:ok, base_url} <- base_url(connection.environment),
         :ok <- credentials(connection) do
      config = Application.get_env(:palee, :mydata, [])

      [
        url: base_url <> "/RequestTransmittedDocs",
        params: [mark: @check_mark],
        headers: [
          {"aade-user-id", connection.user_id},
          {"ocp-apim-subscription-key", connection.subscription_key}
        ],
        receive_timeout: Keyword.get(config, :check_timeout, 15_000),
        retry: false,
        decode_body: false
      ]
      |> Keyword.merge(Keyword.get(config, :req_options, []))
      |> Req.get()
      |> case do
        {:ok, %Req.Response{status: 200}} ->
          {:ok, %{}}

        {:ok, %Req.Response{status: status}} when status in [401, 403] ->
          {:error, {:unauthorized, {:http, status}}}

        {:ok, %Req.Response{status: status}} ->
          {:error, {:http, status}}

        {:error, exception} ->
          {:error, {:network, Exception.message(exception)}}
      end
    end
  end

  defp base_url(environment) do
    urls =
      Map.merge(
        @base_urls,
        :palee |> Application.get_env(:mydata, []) |> Keyword.get(:base_urls, %{})
      )

    case Map.fetch(urls, environment) do
      {:ok, url} -> {:ok, String.trim_trailing(url, "/")}
      :error -> {:error, {:unauthorized, :unknown_environment}}
    end
  end

  defp credentials(%{user_id: user, subscription_key: key})
       when is_binary(user) and user != "" and is_binary(key) and key != "",
       do: :ok

  defp credentials(_connection), do: {:error, {:unauthorized, :credentials_missing}}

  defp interpret({:ok, %Req.Response{status: status, body: response}}, body, count)
       when status in [401, 403] do
    {List.duplicate({:error, {:unauthorized, {:http, status}}}, count),
     wire(body, status, response)}
  end

  defp interpret({:ok, %Req.Response{status: status, body: response}}, body, count)
       when status in [200, 400] do
    results =
      case XmlCodec.parse_response(to_string(response)) do
        {:ok, entries} ->
          by_index = index_entries(entries)
          Enum.map(1..count//1, &entry_result(Map.get(by_index, &1)))

        {:error, reason} ->
          List.duplicate({:error, reason}, count)
      end

    {results, wire(body, status, response)}
  end

  defp interpret({:ok, %Req.Response{status: status, body: response}}, body, count),
    do: {List.duplicate({:error, {:http, status}}, count), wire(body, status, response)}

  defp interpret({:error, exception}, body, count),
    do:
      {List.duplicate({:error, {:network, Exception.message(exception)}}, count),
       wire(body, nil, nil)}

  # `index` is 1-based in the order of the InvoicesDoc; a single answer
  # without one belongs to the only invoice.
  defp index_entries([%{index: nil} = only]), do: %{1 => only}

  defp index_entries(entries) do
    Map.new(entries, fn entry ->
      case Integer.parse(to_string(entry.index)) do
        {index, ""} -> {index, entry}
        _other -> {nil, entry}
      end
    end)
  end

  defp entry_result(nil), do: {:error, :empty_response}

  defp entry_result(%{status: "Success", mark: mark} = entry) when is_binary(mark),
    do: {:ok, Map.take(entry, [:mark, :uid, :authentication_code, :qr_url])}

  defp entry_result(%{status: code, errors: errors})
       when code in ["ValidationError", "XMLSyntaxError"] do
    if Enum.any?(errors, &(to_string(&1.code) in @duplicate_codes)),
      do: {:error, {:duplicate, errors}},
      else: {:error, {:rejected, errors}}
  end

  defp entry_result(%{status: other, errors: errors}), do: {:error, {:technical, other, errors}}

  @doc """
  ADR-451: the receipt of a document AADE already has, found by its keys
  (`issuer_vat`, `series`, `aa`, `issue_date`, `invoice_type`) among the
  documents the connection's user transmitted that day
  (`GET /RequestTransmittedDocs`). `{:ok, receipt}`, `:not_found`, or the
  same errors as `check/1`.
  """
  @impl true
  def find(connection, key) do
    with {:ok, base_url} <- base_url(connection.environment),
         :ok <- credentials(connection) do
      day = Calendar.strftime(key.issue_date, "%d/%m/%Y")

      params = [
        mark: "0",
        dateFrom: day,
        dateTo: day,
        invType: key.invoice_type
      ]

      case find_page(connection, base_url, params, key, nil, @max_lookup_pages, []) do
        {:ok, []} -> :not_found
        {:ok, found} -> {:ok, first_registration(found)}
        error -> error
      end
    end
  end

  # On the ERP channel a resend of the same document is registered again with a
  # new MARK (ADR-451), so every match is collected and the first registration
  # (the lowest MARK) wins, whatever order the pages come in.
  defp first_registration(found) do
    found
    |> Enum.min_by(&mark_number/1)
    |> Map.take([:mark, :uid, :authentication_code, :qr_url])
  end

  defp mark_number(%{mark: mark}) do
    case Integer.parse(mark) do
      {number, ""} -> number
      _other -> :infinity
    end
  end

  defp find_page(_connection, _base_url, _params, _key, _token, 0, found), do: {:ok, found}

  defp find_page(connection, base_url, params, key, token, pages_left, found) do
    config = Application.get_env(:palee, :mydata, [])

    page_params =
      case token do
        nil -> params
        %{partition_key: pk, row_key: rk} -> params ++ [nextPartitionKey: pk, nextRowKey: rk]
      end

    [
      url: base_url <> "/RequestTransmittedDocs",
      params: page_params,
      headers: [
        {"aade-user-id", connection.user_id},
        {"ocp-apim-subscription-key", connection.subscription_key}
      ],
      receive_timeout: Keyword.get(config, :check_timeout, 15_000),
      retry: false,
      decode_body: false
    ]
    |> Keyword.merge(Keyword.get(config, :req_options, []))
    |> Req.get()
    |> case do
      {:ok, %Req.Response{status: 200, body: body}} ->
        with {:ok, %{invoices: invoices, next: next}} <-
               XmlCodec.parse_transmitted(to_string(body)) do
          found =
            found ++
              Enum.filter(invoices, &(is_binary(&1[:mark]) and same_document?(&1, key)))

          case next do
            nil -> {:ok, found}
            next -> find_page(connection, base_url, params, key, next, pages_left - 1, found)
          end
        end

      {:ok, %Req.Response{status: status}} when status in [401, 403] ->
        {:error, {:unauthorized, {:http, status}}}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http, status}}

      {:error, exception} ->
        {:error, {:network, Exception.message(exception)}}
    end
  end

  # A cancelled or replaced document (`cancelledByMark`) is not the live one.
  defp same_document?(%{cancelled_by_mark: cancelled}, _key) when is_binary(cancelled), do: false

  defp same_document?(invoice, key) do
    invoice.series == key.series and invoice.aa == key.aa and
      invoice.invoice_type == key.invoice_type and
      invoice.issue_date == Date.to_iso8601(key.issue_date) and
      (is_nil(invoice.issuer_vat) or invoice.issuer_vat == key.issuer_vat)
  end

  defp wire(request, status, response) do
    %{
      request_body: request,
      response_status: status,
      response_body: response && response |> to_string() |> binary_part_safe(@max_logged_body)
    }
  end

  defp binary_part_safe(text, max) when byte_size(text) <= max, do: text
  defp binary_part_safe(text, max), do: String.slice(text, 0, max)
end
