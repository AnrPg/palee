defmodule Palee.Leads.Ports.LeadStore do
  @moduledoc """
  ADR-344: where leads, their tasks and their history are kept. Every call
  runs in the box's `RepoContext` (the facade sets it); rows of other boxes
  are never visible. `transaction/2` groups several calls so a lead and its
  history line are written together.
  """

  alias Palee.Leads.{Lead, LeadEvent, LeadTask}

  @type context :: map()
  @type id :: Ecto.UUID.t()

  @callback transaction(context(), (-> result)) :: {:ok, result} | {:error, term()}
            when result: term()

  @callback insert(context(), map()) :: {:ok, Lead.t()} | {:error, Ecto.Changeset.t()}
  @callback update(context(), Lead.t(), map()) :: {:ok, Lead.t()} | {:error, Ecto.Changeset.t()}
  @callback get(context(), id()) :: Lead.t() | nil
  @callback get_for_update(context(), id()) :: Lead.t() | nil
  @callback get_by_source_ref(context(), String.t(), String.t()) :: Lead.t() | nil

  @doc "The open lead with this email, else the newest lost one; converted leads are never matched."
  @callback find_by_email(context(), String.t()) :: Lead.t() | nil

  @doc "Open leads that are this person: linked to the profile, or with the profile's email."
  @callback open_for_person(context(), id(), String.t() | nil) :: [Lead.t()]

  @doc """
  The box's leads, newest first. Filters: `stages`, `owner_id`, `source`,
  `q` (name, email or phone contains), `limit` (default 50, at most 200),
  `offset`.
  """
  @callback list(context(), map()) :: [Lead.t()]

  @doc "How many leads are in each stage."
  @callback stage_counts(context()) :: %{String.t() => non_neg_integer()}

  @callback delete(context(), id()) :: :ok | {:error, :not_found}

  @callback add_event(context(), map()) :: {:ok, LeadEvent.t()} | {:error, Ecto.Changeset.t()}
  @callback events(context(), id()) :: [LeadEvent.t()]

  @callback insert_task(context(), map()) :: {:ok, LeadTask.t()} | {:error, Ecto.Changeset.t()}
  @callback get_task(context(), id()) :: LeadTask.t() | nil
  @callback complete_task(context(), LeadTask.t(), map()) ::
              {:ok, LeadTask.t()} | {:error, Ecto.Changeset.t()}

  @doc "Tasks of one lead, open first by due date, then done ones."
  @callback tasks(context(), id()) :: [LeadTask.t()]

  @doc "Open tasks of open leads, due first. Filters: `assignee_id`, `due_before`, `limit`."
  @callback open_tasks(context(), map()) :: [LeadTask.t()]

  @doc "The earliest open task of each lead (its «επόμενη ενέργεια»)."
  @callback next_tasks(context(), [id()]) :: %{id() => LeadTask.t()}

  @doc """
  ADR-345 retention: deletes lost leads that never became anyone's profile
  and have not moved since `cutoff`. Answers how many.
  """
  @callback purge_stale(context(), DateTime.t()) :: non_neg_integer()
end
