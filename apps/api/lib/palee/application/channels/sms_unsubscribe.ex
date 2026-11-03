defmodule Palee.Application.Channels.SmsUnsubscribe do
  @moduledoc """
  The public page behind the short link of a marketing SMS (ADR-390). No
  sign-in: the signed token names the contact. Opening the page changes
  nothing (a phone's link preview opens links too); the person's tap on
  «Διακοπή» withdraws their marketing SMS consent at that box.

  Answers only what the page needs: the box's name, the person's message
  language and whether offers by SMS are already off. Never the number.
  """

  alias Palee.Channels
  alias Palee.Organizations

  @doc "`{:ok, view}` or `{:error, :not_found}`."
  def show(token), do: token |> Channels.find_unsubscribe() |> view()

  @doc "Withdraws the consent: `{:ok, view}` or `{:error, :not_found}`."
  def withdraw(token, now \\ DateTime.utc_now()),
    do: token |> Channels.unsubscribe(now) |> view()

  defp view({:ok, %{context: context, contact: contact, withdrawn: withdrawn}}) do
    organization = Organizations.get_by_id(context.organization_id)

    {:ok,
     %{
       box_name: (organization && organization.name) || "Palee",
       locale: contact.locale,
       withdrawn: withdrawn
     }}
  end

  defp view(_error), do: {:error, :not_found}
end
