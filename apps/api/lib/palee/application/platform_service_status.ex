defmodule Palee.Application.PlatformServiceStatus do
  @moduledoc """
  ADR-364: the status page in the platform console (vendors), for
  its platform controller: the live probe of every component
  with its internal reason, incidents and maintenance with their timeline,
  and the number of subscribers. A new incident or update with `notify`
  queues the email to confirmed subscribers.

  ADR-366: any Palee team member publishes, in any language. `translate/2`
  gives the English preview the console shows (a machine translation the
  person may correct); when it fails the incident is published without
  English. Every incident and step shows who published it.
  """

  alias Palee.{Identity, Status}
  alias Palee.Workers.StatusNotifyJob

  def console(context) do
    with {:ok, view} <- Status.console(context, clock().now()) do
      {:ok, Map.put(view, :publishers, publishers(view.incidents))}
    end
  end

  def create_incident(context, params) do
    with {:ok, incident, update} <- Status.create_incident(context, params, clock().now()) do
      :ok = maybe_notify(update)
      {:ok, incident, publishers([incident])}
    end
  end

  def add_update(context, id, params) do
    with {:ok, incident, update} <- Status.add_incident_update(context, id, params, clock().now()) do
      :ok = maybe_notify(update)
      {:ok, incident, publishers([incident])}
    end
  end

  def edit_incident(context, id, params) do
    with {:ok, incident} <- Status.edit_incident(context, id, params) do
      {:ok, incident, publishers([incident])}
    end
  end

  @doc """
  The English preview of a title and note: `{:ok, %{locale, title, body}}`,
  or `{:error, :status_translation_unavailable}` when the translator does
  not answer (the console then publishes the original only).
  """
  def translate(context, params) do
    with :ok <- Status.authorize_vendor(context),
         {:ok, text} <- Status.translation_request(params) do
      metering = %{feature: "status_translation", user_id: context.user_id}

      case translator().to_english(text, metering) do
        {:ok, answer} -> Status.translation_result(answer)
        {:error, _reason} -> {:error, :status_translation_unavailable}
      end
    end
  end

  defp publishers(incidents) do
    ids =
      incidents
      |> Enum.flat_map(fn incident ->
        [incident.created_by_id | Enum.map(List.wrap(incident.updates), & &1.created_by_id)]
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if ids == [],
      do: %{},
      else: ids |> Identity.list_by_ids() |> Map.new(&{&1.id, &1.nickname})
  end

  defp maybe_notify(%{notify: true, id: id}) do
    if Application.get_env(:palee, :start_oban, true) do
      {:ok, _job} = %{"update_id" => id} |> StatusNotifyJob.new() |> Oban.insert()
    end

    :ok
  end

  defp maybe_notify(_update), do: :ok

  defp clock, do: Application.fetch_env!(:palee, :status_clock)
  defp translator, do: Application.fetch_env!(:palee, :status_translator)
end
