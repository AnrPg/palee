defmodule Palee.Workers.RecordExerciseNamesJob do
  @moduledoc """
  ADR-461: remembers the exercise names of a saved training-log entry, PR or
  published WOD for suggestions, off the save path. A `user` job carries its
  owner (`owner_user_id`), an `org` job its organization.
  """

  use Oban.Worker, queue: :default, max_attempts: 5

  alias Palee.Application.{OwnershipKeys, RememberExerciseNames}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"scope" => "user", "names" => names} = args}) do
    with {:ok, %{"owner_user_id" => user_id}} <- OwnershipKeys.require_user_args(args) do
      RememberExerciseNames.call(%{scope: :user, user_id: user_id}, names, increment(args))
    end
  end

  def perform(%Oban.Job{args: %{"scope" => "org", "names" => names} = args}) do
    with {:ok, %{"organization_id" => organization_id}} <-
           OwnershipKeys.require_tenant_args(args) do
      RememberExerciseNames.call(
        %{scope: :org, organization_id: organization_id},
        names,
        increment(args)
      )
    end
  end

  def perform(%Oban.Job{}), do: {:error, :invalid_args}

  @doc "The job's args for an owner and its names."
  def args(%{scope: :user, user_id: user_id}, rows, increment),
    do: %{
      "scope" => "user",
      "owner_user_id" => user_id,
      "names" => rows,
      "increment" => increment
    }

  def args(%{scope: :org, organization_id: organization_id}, rows, increment),
    do: %{
      "scope" => "org",
      "organization_id" => organization_id,
      "names" => rows,
      "increment" => increment
    }

  defp increment(%{"increment" => n}) when is_integer(n) and n >= 0, do: n
  defp increment(_args), do: 1
end
