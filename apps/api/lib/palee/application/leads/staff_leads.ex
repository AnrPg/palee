defmodule Palee.Application.Leads.StaffLeads do
  @moduledoc """
  ADR-344: the staff's «Ενδιαφερόμενοι» (`PaleeWeb.AdminLeadController`).
  One list with stages, source, owner and the next action; a lead's page
  with its tasks and history; moving a lead, notes, «Μίλησα», tasks,
  conversion to a box member, CSV import and erasure.

  Every write leaves a line in the lead's history with who did it.
  """

  alias Palee.Application.Leads.{CaptureLead, LeadReactions}
  alias Palee.{Automations, DomainEvents, Identity, Leads, Organizations}
  alias Palee.Leads.{Lead, LeadEvent, LeadTask}

  # Sources staff may choose when typing a lead in; the others come in by
  # themselves.
  @staff_sources ~w(manual walk_in referral event)
  @contact_channels ~w(phone email message in_person)

  def staff_sources, do: @staff_sources
  def contact_channels, do: @contact_channels

  # ── Reading ─────────────────────────────────────────────────────────────

  @doc "The list, newest first, with each lead's next task and the count per stage."
  def list(context, params) do
    filters = %{
      stages: stages(params["stage"]),
      owner_id: owner_filter(context, params["owner"]),
      source: params["source"],
      q: params["q"],
      limit: integer(params["limit"], 50),
      offset: integer(params["offset"], 0)
    }

    leads = Leads.list(context, filters)
    next = Leads.next_tasks(context, Enum.map(leads, & &1.id))
    owners = people(Enum.map(leads, & &1.owner_id))

    counts = Leads.stage_counts(context)

    %{
      leads: Enum.map(leads, &present(&1, Map.get(next, &1.id), owners)),
      counts: Map.new(Leads.stages(), &{&1, Map.get(counts, &1, 0)})
    }
  end

  defp stages(nil), do: nil
  defp stages("open"), do: Leads.open_stages()
  defp stages(stage) when is_binary(stage), do: String.split(stage, ",", trim: true)
  defp stages(_stage), do: nil

  defp owner_filter(%{user_id: user_id}, "me"), do: user_id
  defp owner_filter(_context, owner) when is_binary(owner), do: owner
  defp owner_filter(_context, _owner), do: nil

  @doc "One lead with its tasks and history."
  def show(context, id) do
    with %Lead{} = lead <- Leads.get(context, id) || {:error, :not_found} do
      {:ok, detail(context, lead)}
    end
  end

  defp detail(context, lead) do
    tasks = Leads.tasks(context, lead.id)
    events = Leads.events(context, lead.id)
    next = Enum.find(tasks, &is_nil(&1.done_at))

    people =
      people(
        [lead.owner_id, lead.user_id] ++
          Enum.map(tasks, & &1.assignee_id) ++ Enum.map(events, & &1.actor_id)
      )

    %{
      lead: present(lead, next, people),
      tasks: Enum.map(tasks, &present_task(&1, people)),
      events: Enum.map(events, &present_event(&1, people))
    }
  end

  @doc "Open tasks of open leads, due first (`mine=true` for the caller's own)."
  def tasks(context, params) do
    filters = %{
      assignee_id: if(params["mine"] in [true, "true"], do: Map.get(context, :user_id)),
      limit: integer(params["limit"], 50)
    }

    tasks = Leads.open_tasks(context, filters)
    leads = Map.new(tasks, &{&1.lead_id, Leads.get(context, &1.lead_id)})
    people = people(Enum.map(tasks, & &1.assignee_id))

    Enum.map(tasks, fn task ->
      task
      |> present_task(people)
      |> Map.put(:lead_name, leads[task.lead_id] && leads[task.lead_id].name)
    end)
  end

  # ── Writing ─────────────────────────────────────────────────────────────

  @doc "A lead typed in by staff (they spoke to the person, so contact consent is implied)."
  def create(context, params) do
    source = params["source"] || "manual"

    with :ok <- staff_source(source),
         :ok <- valid_owner(context, params["owner_id"]),
         {:ok, %{lead: lead}} <-
           CaptureLead.call(
             context,
             params
             |> Map.take(~w(name email phone message interests campaign locale))
             |> Map.put("source", source)
             |> Map.put("consent", consent(params)),
             now: Leads.now()
           ),
         {:ok, lead} <- maybe_assign(context, lead, params["owner_id"]) do
      {:ok, detail(context, lead)}
    end
  end

  defp staff_source(source) when source in @staff_sources, do: :ok
  defp staff_source(_source), do: {:error, {:invalid_fields, %{"source" => "invalid"}}}

  # Marketing consent typed in by staff must be the person's own yes; the
  # form says so next to the switch.
  defp consent(params),
    do: %{contact: true, marketing: params["marketing_consent"] in [true, "true"]}

  defp maybe_assign(_context, lead, nil), do: {:ok, lead}
  defp maybe_assign(context, lead, owner_id), do: change_owner(context, lead, owner_id)

  @doc "Changes a lead's details or owner."
  def update(context, id, params) do
    now = Leads.now()

    in_lock(context, id, fn lead ->
      with {:ok, details} <- details(lead, params),
           :ok <- valid_owner(context, params["owner_id"]),
           {:ok, updated} <- Leads.update(context, lead, details),
           {:ok, updated} <- owner_change(context, updated, params, now),
           :ok <- details_event(context, lead, details, now) do
        {:ok, updated}
      end
    end)
  end

  defp details(lead, params) do
    allowed = Map.take(params, ~w(name email phone message interests))

    case allowed do
      empty when map_size(empty) == 0 ->
        {:ok, %{}}

      fields ->
        merged = %{
          "name" => Map.get(fields, "name", lead.name),
          "email" => Map.get(fields, "email", lead.email),
          "phone" => Map.get(fields, "phone", lead.phone),
          "message" => Map.get(fields, "message", lead.message),
          "interests" => Map.get(fields, "interests", lead.interests)
        }

        case Leads.normalize(merged) do
          {:ok, normalized} ->
            {:ok, Map.take(normalized, [:name, :email, :phone, :message, :interests])}

          {:error, _invalid} = error ->
            error
        end
    end
  end

  defp owner_change(context, lead, %{"owner_id" => owner_id}, _now)
       when owner_id != lead.owner_id,
       do: change_owner(context, lead, owner_id)

  defp owner_change(_context, lead, _params, _now), do: {:ok, lead}

  defp details_event(_context, _lead, details, _now) when map_size(details) == 0, do: :ok

  defp details_event(context, lead, details, now) do
    changed = for {key, value} <- details, Map.get(lead, key) != value, do: to_string(key)

    if changed == [] do
      :ok
    else
      event(context, lead.id, "details_changed", %{"fields" => Enum.sort(changed)}, now)
    end
  end

  defp change_owner(context, lead, owner_id) do
    now = Leads.now()

    with {:ok, updated} <- Leads.update(context, lead, %{owner_id: owner_id}),
         :ok <-
           event(context, lead.id, "owner_changed", %{"from" => lead.owner_id, "to" => owner_id}, now) do
      {:ok, updated}
    end
  end

  defp valid_owner(_context, nil), do: :ok

  defp valid_owner(context, owner_id) when is_binary(owner_id) do
    if Organizations.staff_member?(context, owner_id),
      do: :ok,
      else: {:error, {:invalid_fields, %{"owner_id" => "not_staff"}}}
  end

  defp valid_owner(_context, _owner_id), do: {:error, {:invalid_fields, %{"owner_id" => "invalid"}}}

  @doc """
  Moves a lead to another stage (`lost` needs a `lost_reason`). Announces
  `:lead_moved`, so a lead moved to `trial` can get the trial follow-up.
  """
  def move(context, id, params) do
    now = Leads.now()

    context
    |> in_lock(id, fn lead ->
      with {:ok, changes} <-
             Leads.move(lead, params["stage"], now, lost_reason: params["lost_reason"]),
           {:ok, moved} <- Leads.update(context, lead, changes),
           :ok <-
             event(
               context,
               lead.id,
               "stage_changed",
               %{"from" => lead.stage, "to" => moved.stage, "lost_reason" => moved.lost_reason},
               now
             ) do
        {:ok, moved}
      end
    end)
    |> announce_move(context, now)
  end

  defp announce_move({:ok, %{lead: %{id: id, stage: stage}}} = ok, context, now) do
    DomainEvents.publish(:lead_moved, %{
      organization_id: context.organization_id,
      lead_id: id,
      to: stage,
      at: now
    })

    ok
  end

  defp announce_move(other, _context, _now), do: other

  @doc """
  The person asked for no more marketing messages: recorded on the lead,
  and any automatic marketing message waiting for them is cancelled.
  """
  def opt_out(context, id) do
    now = Leads.now()

    context
    |> in_lock(id, fn lead ->
      with {:ok, updated} <- Leads.update(context, lead, %{marketing_opted_out_at: now}),
           :ok <- event(context, lead.id, "marketing_opted_out", %{}, now) do
        {:ok, updated}
      end
    end)
    |> tap(fn
      {:ok, _detail} ->
        Automations.cancel_pending(context, %{lead_id: id, reason: "opted_out"})

      _error ->
        :ok
    end)
  end

  @doc "A note in the lead's history."
  def note(context, id, params) do
    text = params["text"] |> to_string() |> String.trim() |> String.slice(0, 2_000)

    if text == "" do
      {:error, {:invalid_fields, %{"text" => "required"}}}
    else
      in_lock(context, id, fn lead ->
        with :ok <- event(context, lead.id, "note", %{"text" => text}, Leads.now()),
             do: {:ok, lead}
      end)
    end
  end

  @doc "«Μίλησα»: staff reached the person (`channel`: phone, email, message, in_person)."
  def contacted(context, id, params) do
    now = Leads.now()
    channel = params["channel"] || "phone"

    if channel in @contact_channels do
      in_lock(context, id, fn lead ->
        with {:ok, updated} <- Leads.update(context, lead, %{last_contacted_at: now}),
             :ok <- event(context, lead.id, "contacted", %{"channel" => channel}, now) do
          {:ok, updated}
        end
      end)
    else
      {:error, {:invalid_fields, %{"channel" => "invalid"}}}
    end
  end

  @doc "A task on the lead: `title`, `due_at`, optional `assignee_id` (staff)."
  def add_task(context, id, params) do
    now = Leads.now()

    with :ok <- valid_owner(context, params["assignee_id"]),
         {:ok, due_at} <- due_at(params["due_at"]) do
      in_lock(context, id, fn lead ->
        with {:ok, task} <-
               Leads.insert_task(context, %{
                 lead_id: lead.id,
                 title: params["title"],
                 due_at: due_at,
                 assignee_id: params["assignee_id"] || lead.owner_id,
                 created_by_id: Map.get(context, :user_id)
               }),
             :ok <-
               event(
                 context,
                 lead.id,
                 "task_added",
                 %{"task_id" => task.id, "title" => task.title, "due_at" => task.due_at},
                 now
               ) do
          {:ok, lead}
        end
      end)
    end
  end

  defp due_at(%DateTime{} = at), do: {:ok, at}

  defp due_at(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> {:ok, at}
      _error -> {:error, {:invalid_fields, %{"due_at" => "invalid"}}}
    end
  end

  defp due_at(_value), do: {:error, {:invalid_fields, %{"due_at" => "required"}}}

  @doc "Marks a task done."
  def complete_task(context, task_id) do
    now = Leads.now()

    with %LeadTask{} = task <- Leads.get_task(context, task_id) || {:error, :not_found},
         true <- is_nil(task.done_at) || {:error, :lead_task_done} do
      in_lock(context, task.lead_id, fn lead ->
        with {:ok, done} <-
               Leads.complete_task(context, task, %{
                 done_at: now,
                 done_by_id: Map.get(context, :user_id)
               }),
             :ok <-
               event(context, lead.id, "task_done", %{"task_id" => done.id, "title" => done.title}, now) do
          {:ok, lead}
        end
      end)
    end
  end

  @doc """
  «Έγινε μέλος»: links the lead to the box member `user_id` (an active
  member of this box) and closes it, keeping its history.
  """
  def convert(context, id, params) do
    user_id = params["user_id"]

    with true <- is_binary(user_id) || {:error, {:invalid_fields, %{"user_id" => "required"}}},
         true <-
           Organizations.member_roles(context.organization_id, user_id) != [] ||
             {:error, :lead_person_not_in_box},
         %Lead{} = lead <- Leads.get(context, id) || {:error, :not_found},
         {:ok, converted} <-
           LeadReactions.convert(
             context,
             lead,
             user_id,
             Leads.now(),
             "staff",
             Map.get(context, :user_id)
           ) do
      {:ok, detail(context, converted)}
    end
  end

  @doc """
  Leads from CSV text. `dry_run: true` reports what would happen per row
  without writing. Rows that join an existing lead count as `existing`.
  """
  def import_csv(context, params) do
    dry_run? = params["dry_run"] in [true, "true"]

    with {:ok, rows} <- Leads.parse_csv(to_string(params["csv"])) do
      results = Enum.map(rows, &import_row(context, &1, dry_run?))

      {:ok,
       %{
         dry_run: dry_run?,
         created: Enum.count(results, &(&1.result == "created")),
         existing: Enum.count(results, &(&1.result == "existing")),
         invalid: Enum.count(results, &(&1.result == "invalid")),
         rows: results
       }}
    end
  end

  defp import_row(_context, %{row: row, errors: errors}, _dry_run?),
    do: %{row: row, result: "invalid", errors: errors}

  defp import_row(_context, %{row: row}, true), do: %{row: row, result: "valid", errors: %{}}

  defp import_row(context, %{row: row, attrs: attrs}, false) do
    attrs =
      attrs
      |> Map.put(:source, "csv")
      |> Map.put(:consent, %{contact: true})

    case CaptureLead.call(context, attrs) do
      {:ok, %{created: true}} -> %{row: row, result: "created", errors: %{}}
      {:ok, %{created: false}} -> %{row: row, result: "existing", errors: %{}}
      {:error, {:invalid_fields, errors}} -> %{row: row, result: "invalid", errors: errors}
      {:error, _reason} -> %{row: row, result: "invalid", errors: %{"row" => "not_saved"}}
    end
  end

  @doc "Deletes a lead with its tasks and history (an erasure request, ADR-345)."
  def erase(context, id), do: Leads.delete(context, id)

  # ── Helpers ─────────────────────────────────────────────────────────────

  defp in_lock(context, id, fun) do
    Leads.transaction(context, fn ->
      case Leads.get_for_update(context, id) do
        %Lead{} = lead -> fun.(lead)
        nil -> {:error, :not_found}
      end
    end)
    |> case do
      {:ok, %Lead{} = lead} -> {:ok, detail(context, lead)}
      other -> other
    end
  end

  defp event(context, lead_id, kind, data, now) do
    case Leads.add_event(context, %{
           lead_id: lead_id,
           kind: kind,
           data: data,
           at: now,
           actor_id: Map.get(context, :user_id)
         }) do
      {:ok, _event} -> :ok
      error -> error
    end
  end

  defp people(ids) do
    ids
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [] -> %{}
      ids -> ids |> Identity.list_by_ids() |> Map.new(&{&1.id, person(&1)})
    end
  end

  defp person(account),
    do: %{
      user_id: account.id,
      display_name: account.nickname,
      handle: account.handle,
      avatar_url: account.avatar_url
    }

  @doc "A lead as the API shows it."
  def present(%Lead{} = lead, next_task, people) do
    %{
      id: lead.id,
      name: lead.name,
      email: lead.email,
      phone: lead.phone,
      message: lead.message,
      locale: lead.locale,
      stage: lead.stage,
      source: lead.source,
      campaign: lead.campaign,
      interests: lead.interests,
      owner: Map.get(people, lead.owner_id),
      person: Map.get(people, lead.user_id),
      lost_reason: lead.lost_reason,
      stage_changed_at: lead.stage_changed_at,
      converted_at: lead.converted_at,
      last_contacted_at: lead.last_contacted_at,
      created_at: lead.inserted_at,
      consent: %{
        contact_at: lead.consent_contact_at,
        marketing_at: lead.consent_marketing_at,
        marketing_opted_out_at: lead.marketing_opted_out_at,
        text_version: lead.consent_text_version
      },
      next_task: next_task && present_task(next_task, people)
    }
  end

  defp present_task(%LeadTask{} = task, people),
    do: %{
      id: task.id,
      lead_id: task.lead_id,
      title: task.title,
      due_at: task.due_at,
      done_at: task.done_at,
      assignee: Map.get(people, task.assignee_id)
    }

  defp present_event(%LeadEvent{} = event, people),
    do: %{
      id: event.id,
      kind: event.kind,
      data: event.data,
      at: event.at,
      actor: Map.get(people, event.actor_id)
    }

  defp integer(value, _default) when is_integer(value), do: value

  defp integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> n
      _other -> default
    end
  end

  defp integer(_value, default), do: default
end
