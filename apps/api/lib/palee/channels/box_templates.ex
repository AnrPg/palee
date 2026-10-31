defmodule Palee.Channels.BoxTemplates do
  @moduledoc """
  The box's own wording of channel messages (ADR-350 §2): a row per key,
  language and channel (`any`, or `whatsapp` with the provider's template
  id and Meta's approval). Palee's wording stays the default; deleting a
  row goes back to it.
  """

  alias Palee.Channels.ChannelStore
  alias Palee.Channels.Contacts
  alias Palee.Channels.Domain.{MessageText, Templates}

  @approval ~w(none pending approved rejected)

  @doc "Palee's templates with the box's rows for each, plus the box's own keys."
  def list(context) do
    rows = ChannelStore.list_templates(context, nil)
    grouped = Enum.group_by(rows, & &1.key)

    builtin =
      Enum.map(Templates.all(), fn template ->
        %{
          key: template.key,
          purpose: template.purpose,
          variables: template.variables,
          defaults: template.bodies,
          custom: Enum.map(Map.get(grouped, template.key, []), &public/1),
          builtin: true
        }
      end)

    own =
      grouped
      |> Map.drop(Templates.keys())
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {key, rows} ->
        %{
          key: key,
          purpose: nil,
          variables: rows |> Enum.flat_map(&Templates.placeholders(&1.body)) |> Enum.uniq(),
          defaults: %{},
          custom: Enum.map(rows, &public/1),
          builtin: false
        }
      end)

    builtin ++ own
  end

  @doc """
  Saves one row. `params`: `locale`, `channel` (`any` or `whatsapp`),
  `body`, and for WhatsApp `provider_template_id`, `approval_status` and
  `variable_names` (the template's placeholders in the provider's order).
  """
  def save(context, key, params, actor_id) do
    locale = params[:locale]
    channel = params[:channel] || "any"
    body = params[:body]
    names = params[:variable_names] || (is_binary(body) && Templates.placeholders(body)) || []
    approval = params[:approval_status] || "none"
    provider_id = blank_to_nil(params[:provider_template_id])

    errors =
      %{}
      |> add(not valid_key?(key), :key, "invalid")
      |> add(locale not in Contacts.locales(), :locale, "invalid")
      |> add(channel not in ~w(any whatsapp), :channel, "invalid")
      |> add(not (is_binary(body) and String.trim(body) != ""), :body, "required")
      |> add(is_binary(body) and String.length(body) > MessageText.max_length(), :body, "too_long")
      |> add(approval not in @approval, :approval_status, "invalid")
      |> add(channel == "whatsapp" and approval == "approved" and is_nil(provider_id), :provider_template_id, "required")
      |> add(not (is_list(names) and Enum.all?(names, &(is_binary(&1) and &1 =~ ~r/^[a-z_]{1,40}$/))), :variable_names, "invalid")
      |> add(is_binary(provider_id) and String.length(provider_id) > 120, :provider_template_id, "too_long")

    if errors == %{} do
      with {:ok, row} <-
             ChannelStore.save_template(context, %{
               key: key,
               locale: locale,
               channel: channel,
               body: String.trim(body),
               provider_template_id: provider_id,
               variable_names: names,
               approval_status: if(channel == "whatsapp", do: approval, else: "none"),
               updated_by_id: actor_id
             }) do
        {:ok, public(row)}
      end
    else
      {:error, {:invalid_fields, errors}}
    end
  end

  def delete(context, key, locale, channel) do
    ChannelStore.delete_template(context, key, locale, channel || "any")
  end

  defp valid_key?(key) when is_binary(key), do: key =~ ~r/^[a-z][a-z0-9_]{2,59}$/
  defp valid_key?(_key), do: false

  defp public(row),
    do:
      Map.take(row, [
        :locale,
        :channel,
        :body,
        :provider_template_id,
        :variable_names,
        :approval_status,
        :updated_at
      ])

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_value), do: nil

  defp add(errors, true, field, code), do: Map.put_new(errors, field, code)
  defp add(errors, false, _field, _code), do: errors
end
