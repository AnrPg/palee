defmodule Palee.Infrastructure.Fiscal.SandboxAuthorityGateway do
  @moduledoc """
  An authority that is not there (ADR-243): accepts every well-formed
  document with a made-up MARK, without the network. Used by the
  `sandbox` environment (pilots before a gym has myDATA credentials,
  demos, development) and by tests.

  Sandbox MARKs start with `9000` so they can never be mistaken for real
  ones, and the same document always gets the same MARK.
  """

  @behaviour Palee.Fiscal.Ports.AuthorityGateway

  alias Palee.Infrastructure.Fiscal.MyData.XmlCodec

  @doc "ADR-273: the sandbox is always reachable and needs no credentials."
  @impl true
  def check(_connection), do: {:ok, %{}}

  @doc "ADR-451: the sandbox keeps nothing, so a lost answer is never found."
  @impl true
  def find(_connection, _key), do: :not_found

  @impl true
  def submit(_connection, invoices) when is_list(invoices) do
    body = XmlCodec.invoices_doc(invoices)

    {Enum.map(invoices, &result/1),
     %{
       request_body: body,
       request_bodies: Enum.map(invoices, &XmlCodec.invoices_doc([&1])),
       response_status: nil,
       response_body: nil
     }}
  end

  defp result(invoice) do
    digest = :crypto.hash(:sha, XmlCodec.invoices_doc([invoice]))

    if Enum.any?(invoice, &match?({"invoiceDetails", _}, &1)) do
      <<number::unsigned-integer-size(40), _rest::binary>> = digest

      {:ok,
       %{
         mark:
           "9000" <>
             (number
              |> rem(100_000_000_000)
              |> Integer.to_string()
              |> String.pad_leading(11, "0")),
         uid: Base.encode16(digest),
         authentication_code: nil,
         qr_url: nil
       }}
    else
      {:error, {:rejected, [%{code: "sandbox", message: "Document without lines"}]}}
    end
  end
end
