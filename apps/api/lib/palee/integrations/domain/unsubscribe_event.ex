defmodule Palee.Integrations.Domain.UnsubscribeEvent do
  @moduledoc """
  What Mailchimp or Brevo tells Palee when someone unsubscribes on their
  side (ADR-380, 2026-11-03): the addresses that said no, for the box's own
  list only.

    * **Mailchimp** posts a form (`type=unsubscribe`, `data[email]`,
      `data[list_id]`) and checks the address with a `GET` first. Only
      `unsubscribe` counts: `cleaned` (a bouncing address) is the provider's
      decision, not the member's.
    * **Brevo** posts JSON (`event: "unsubscribed"`, `email`, `list_id` as a
      list of numbers, or none for a global unsubscribe).
    * **sandbox** (dev and test) accepts either shape.

  Anything else is ignored (`[]`), so a provider's other events never touch
  consent.
  """

  @max_addresses 100

  @doc "The unsubscribed addresses in `params` for `list_id`, at most #{@max_addresses}."
  def emails(provider, list_id, params) when is_map(params) do
    provider
    |> parse(to_string(list_id), params)
    |> Enum.filter(&valid_email?/1)
    |> Enum.uniq()
    |> Enum.take(@max_addresses)
  end

  def emails(_provider, _list_id, _params), do: []

  defp parse("mailchimp", list_id, params), do: mailchimp(list_id, params)
  defp parse("brevo", list_id, params), do: brevo(list_id, params)
  defp parse("sandbox", list_id, params), do: mailchimp(list_id, params) ++ brevo(list_id, params)
  defp parse(_provider, _list_id, _params), do: []

  defp mailchimp(list_id, %{"type" => "unsubscribe", "data" => %{"email" => email} = data}) do
    if Map.get(data, "list_id") in [nil, list_id], do: [email], else: []
  end

  defp mailchimp(_list_id, _params), do: []

  defp brevo(list_id, %{"event" => event, "email" => email} = params)
       when event in ["unsubscribed", "unsubscribe"] do
    if for_list?(Map.get(params, "list_id"), list_id), do: [email], else: []
  end

  defp brevo(_list_id, _params), do: []

  # No list named: Brevo's unsubscribe from every list, which includes ours.
  defp for_list?(nil, _list_id), do: true
  defp for_list?(ids, list_id) when is_list(ids), do: Enum.any?(ids, &(to_string(&1) == list_id))
  defp for_list?(id, list_id), do: to_string(id) == list_id

  defp valid_email?(email) when is_binary(email),
    do: byte_size(email) <= 254 and String.contains?(email, "@")

  defp valid_email?(_email), do: false
end
