defmodule Palee.Application.Leads.CaptureLead do
  @moduledoc """
  ADR-344/345: the one way a lead enters a box, whatever brought it: the
  box's public form (`Palee.Application.Leads.PublicIntake`), the box
  website's forms (W4, through the box site intake adapter), the
  prospect assistant (W8), a join link, staff typing it in, or a CSV row.

  `call(context, attrs, opts)` with the box's `context`
  (`%{organization_id: ...}`, a staff `user_id` when someone acted) and
  `attrs` (atom or string keys):

    * `name` and `email` and/or `phone` (required), `message`, `locale`,
      `interests` (e.g. `["trial"]`), `campaign`;
    * `source` (one of `Palee.Leads.sources/0`) and `source_ref` (the
      caller's id for this capture: a submission, a conversation);
    * `consent` - `%{contact, marketing, text_version, text_hash, given_at}`,
      required with contact consent for inbound sources;
    * `details` - extra facts for the first history line (preferred time,
      class type, attribution), stored as given.

  Idempotent: the same `source` + `source_ref` returns the first lead. A
  new enquiry from an address that already has an open (or lost) lead
  joins it: one history line, newer consent kept, a lost lead reopened.
  Converted leads are never reopened; a new one is made instead.

  Returns `{:ok, %{lead_id, created, lead}}` or `{:error, reason}`
  (`{:invalid_fields, map}` for bad input).
  """

  alias Palee.DomainEvents
  alias Palee.Leads
  alias Palee.Leads.Lead

  @spec call(map(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def call(%{organization_id: organization_id} = context, attrs, opts \\ [])
      when is_binary(organization_id) and is_map(attrs) do
    now = Keyword.get_lazy(opts, :now, &Leads.now/0)
    source = to_string(get(attrs, :source) || "manual")
    actor_id = Map.get(context, :user_id)

    with :ok <- known_source(source),
         {:ok, fields} <- Leads.normalize(attrs),
         {:ok, consent} <- Leads.consent(get(attrs, :consent), source, now),
         {:ok, {lead, how}} <-
           Leads.transaction(context, fn ->
             capture(context, Map.merge(fields, consent), source, actor_id, attrs, now)
           end) do
      if how == :created do
        DomainEvents.publish(:lead_captured, %{
          organization_id: organization_id,
          lead_id: lead.id,
          source: lead.source,
          at: now
        })
      end

      {:ok, %{lead_id: lead.id, created: how == :created, lead: lead}}
    end
  end

  defp known_source(source) do
    if source in Leads.sources(),
      do: :ok,
      else: {:error, {:invalid_fields, %{"source" => "invalid"}}}
  end

  defp capture(context, fields, source, actor_id, attrs, now) do
    case existing(context, source, fields) do
      {:same_capture, lead} -> {:ok, {lead, :existing}}
      {:same_person, lead} -> join(context, lead, fields, source, actor_id, now)
      nil -> create(context, fields, source, actor_id, attrs, now)
    end
  end

  defp existing(context, source, %{source_ref: ref, email: email}) do
    same_capture = is_binary(ref) && Leads.get_by_source_ref(context, source, ref)
    same_person = !same_capture && is_binary(email) && Leads.find_by_email(context, email)

    cond do
      same_capture -> {:same_capture, same_capture}
      same_person -> {:same_person, same_person}
      true -> nil
    end
  end

  defp create(context, fields, source, actor_id, attrs, now) do
    insert =
      fields
      |> Map.merge(%{
        source: source,
        stage: "new",
        stage_changed_at: now,
        created_by_id: actor_id
      })

    with {:ok, lead} <- Leads.insert(context, insert),
         {:ok, _event} <-
           Leads.add_event(context, %{
             lead_id: lead.id,
             kind: "created",
             actor_id: actor_id,
             at: now,
             data:
               details(attrs)
               |> Map.merge(%{"source" => source, "campaign" => fields.campaign})
               |> Map.merge(message(fields))
           }) do
      {:ok, {lead, :created}}
    else
      {:error, %Ecto.Changeset{} = changeset} -> {:error, conflict_or(changeset)}
      error -> error
    end
  end

  # The same person asked again: one history line, the newest contact
  # details and consent kept, a lost lead reopened.
  defp join(context, %Lead{} = lead, fields, source, actor_id, now) do
    changes =
      lead
      |> Leads.reenquiry(now)
      |> Map.merge(fill(lead, fields))
      |> Map.merge(newer_consent(lead, fields))

    with {:ok, lead} <- Leads.update(context, lead, changes),
         {:ok, _event} <-
           Leads.add_event(context, %{
             lead_id: lead.id,
             kind: "enquired_again",
             actor_id: actor_id,
             at: now,
             data: Map.merge(%{"source" => source}, message(fields))
           }) do
      {:ok, {lead, :existing}}
    end
  end

  defp fill(lead, fields) do
    %{
      phone: lead.phone || fields.phone,
      locale: lead.locale || fields.locale,
      interests: Enum.uniq(lead.interests ++ fields.interests)
    }
  end

  defp newer_consent(lead, fields) do
    marketing =
      if fields.consent_marketing_at,
        do: %{consent_marketing_at: fields.consent_marketing_at, marketing_opted_out_at: nil},
        else: %{}

    contact =
      if is_nil(lead.consent_contact_at) and fields.consent_contact_at,
        do: %{consent_contact_at: fields.consent_contact_at},
        else: %{}

    text =
      if fields.consent_text_version,
        do: %{
          consent_text_version: fields.consent_text_version,
          consent_text_hash: fields.consent_text_hash
        },
        else: %{}

    marketing |> Map.merge(contact) |> Map.merge(text)
  end

  defp message(%{message: message}) when is_binary(message), do: %{"message" => message}
  defp message(_fields), do: %{}

  defp details(attrs) do
    case get(attrs, :details) do
      %{} = details ->
        details
        |> Map.new(fn {key, value} -> {to_string(key), value} end)
        |> Map.take(~w(kind preferred_time class_type_id attribution submitted_at language))

      _none ->
        %{}
    end
  end

  # Two captures of the same address at once: the unique index refuses
  # the second insert; the caller retries and joins the first.
  defp conflict_or(%Ecto.Changeset{errors: errors} = changeset) do
    cond do
      Keyword.has_key?(errors, :source_ref) -> :lead_capture_conflict
      Keyword.has_key?(errors, :email) -> :lead_capture_conflict
      true -> changeset
    end
  end

  defp get(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
