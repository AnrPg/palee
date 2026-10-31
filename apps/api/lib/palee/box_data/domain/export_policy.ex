defmodule Palee.BoxData.Domain.ExportPolicy do
  @moduledoc """
  ADR-365 (CP-G5): when an owner may ask for a copy of the box's data, and
  how long the file is kept.

    * One export at a time: a pending one answers `:export_in_progress`.
    * One a day: a request less than `cooldown_hours/0` after the last one
      that did not fail answers `:box_export_too_soon`.
    * The file is kept `keep_days/0` days; download links are short-lived
      and made afresh each time the list is read.
  """

  @statuses ~w(pending ready failed)
  @keep_days 7
  @cooldown_hours 24

  def statuses, do: @statuses
  def keep_days, do: @keep_days
  def cooldown_hours, do: @cooldown_hours

  @doc "`:ok`, or why a new request must wait. `exports` are the box's, any order."
  def can_request?(exports, %DateTime{} = now) when is_list(exports) do
    cond do
      Enum.any?(exports, &(&1.status == "pending")) -> {:error, :export_in_progress}
      Enum.any?(exports, &recent?(&1, now)) -> {:error, :box_export_too_soon}
      true -> :ok
    end
  end

  defp recent?(%{status: "failed"}, _now), do: false

  defp recent?(%{requested_at: requested_at}, now),
    do: DateTime.diff(now, requested_at) < @cooldown_hours * 3_600

  @doc "When a file finished at `now` stops being offered."
  def expires_at(%DateTime{} = now), do: DateTime.add(now, @keep_days * 86_400, :second)

  @doc "A ready file past its time is `expired`."
  def visible_status(%{status: "ready", expires_at: %DateTime{} = expires_at}, %DateTime{} = now) do
    if DateTime.compare(expires_at, now) == :gt, do: "ready", else: "expired"
  end

  def visible_status(%{status: status}, _now), do: status

  def downloadable?(export, now), do: visible_status(export, now) == "ready"

  @doc "The file name, with the box's slug and the UTC date."
  def file_name(slug, %DateTime{} = now),
    do: "palee-#{slug}-data-#{Calendar.strftime(now, "%Y-%m-%d")}.zip"

  @doc "The tenant-relative folder an export's file lives in."
  def object_folder(export_id), do: "exports/box-data/#{export_id}/"
end
