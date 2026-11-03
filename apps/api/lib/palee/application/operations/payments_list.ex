defmodule Palee.Application.Operations.PaymentsList do
  @moduledoc """
  ADR-378 `payments.list`: online payments, read-only. Money moves only
  through Palee's checkout and the desk (ADR-246); no operation writes one.
  Desk payments arrive as `payment.recorded` webhooks.
  """

  @behaviour Palee.Operations.Operation

  alias Palee.Application.Operations.Views
  alias Palee.Application.Payments.OnlinePayments

  @statuses ~w(scheduled awaiting_payer processing succeeded failed cancelled expired)

  @impl true
  def spec do
    %{
      name: "payments.list",
      kind: :query,
      summary: "List online payments",
      description:
        "Online payments (card, wallet) newest first, with refunds in refunded_cents. " <>
          "Filter by status or member. Read-only: nothing here changes money.",
      capability: [:manage_billing, :view_finance_reports],
      scope: "payments:read",
      risk: :read,
      data_classes: [:financial],
      http: %{method: :get, path: "/payments"},
      input:
        Views.page_input(%{
          "status" => %{"type" => "string", "enum" => @statuses},
          "member_id" => Views.uuid()
        }),
      output: Views.page(Views.payment_schema()),
      examples: [%{input: %{"status" => "succeeded"}, output: %{}}]
    }
  end

  @impl true
  def execute(context, input) do
    with {:ok, offset} <- Views.decode_cursor(input["cursor"]) do
      filters =
        %{
          status: input["status"],
          user_id: input["member_id"],
          limit: input["limit"],
          offset: offset
        }
        |> Map.reject(fn {_key, value} -> is_nil(value) end)

      %{payments: payments, total: total} = OnlinePayments.list(context, filters)

      {:ok,
       %{
         "data" => Enum.map(payments, &Views.payment/1),
         "next_cursor" => Views.next_cursor(offset, input["limit"], total)
       }}
    end
  end
end
