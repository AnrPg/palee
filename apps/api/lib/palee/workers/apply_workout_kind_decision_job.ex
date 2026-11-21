defmodule Palee.Workers.ApplyWorkoutKindDecisionJob do
  @moduledoc """
  ADR-690: one box's part of a Palee team decision on a workout type name.
  Its types with that name merge into the decided kind (its WODs move with
  them) in the box's own tenant context, and its owners are told.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [period: 3_600, keys: [:organization_id, :folded, :target]]

  alias Palee.Application.{ResolveJobTenantContext, WorkoutKinds}

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "organization_id" => organization_id,
          "folded" => folded,
          "target" => target,
          "decision" => decision
        }
      }) do
    case ResolveJobTenantContext.call(organization_id, "ApplyWorkoutKindDecisionJob") do
      {:ok, context} ->
        WorkoutKinds.apply_to_box(context, folded, target, decision)
        :ok

      # The box is gone: nothing of it to rewrite.
      {:error, :organization_not_found} ->
        :ok
    end
  end
end
