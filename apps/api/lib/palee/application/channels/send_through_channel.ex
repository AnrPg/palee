defmodule Palee.Application.Channels.SendThroughChannel do
  @moduledoc """
  The narrow «send through channel» API (ADR-351) for automations
  (CP-C2), staff messages and system notices: one SMS, Viber or WhatsApp
  message to a member or lead of the box, through the first channel the
  person agreed to, within the box's budget and quiet hours.

      SendThroughChannel.call(context, %{
        user_id: member_id,                 # or lead_id: lead_id
        template_key: "class_cancelled",    # Palee's keys or the box's own
        variables: %{"class" => "WOD", "when" => "Τρι 18:00"},
        purpose: "service",                 # or "marketing" (fixed by built-in keys)
        channels: ["viber", "sms"],         # optional order of preference
        urgent: true,                       # optional: ignores quiet hours (service only)
        idempotency_key: "automation:42:run:7",
        source: "automation",               # "staff" | "automation" | "system"
        source_ref: "automation:42"         # optional, for lists and reports
      })

  Answers `{:ok, %{id, channel, status, release_at, estimated_cost_cents}}`
  or `{:error, reason}` with the reasons of `Channels.Sending.send/3`.
  Callers decide what to do on `:channel_consent_missing` and the rest:
  push first, these channels only as a fallback (CP-C3).

  `context` is a tenant context or `%{organization_id: id}` (a job). The
  box name (`{{box}}`) and its time zone are filled in here.
  """

  alias Palee.Channels
  alias Palee.Channels.Domain.{ChannelPolicy, Templates}
  alias Palee.Organizations
  alias Palee.Workers.DeliverChannelMessagesJob

  @doc "See the module doc."
  def call(context, params, now \\ DateTime.utc_now()) do
    with {:ok, request} <- request(context, params),
         {:ok, message} <- Channels.send(context, request, env(context, now)) do
      schedule(context, message)
      {:ok, view(message)}
    end
  end

  @doc "The same checks without queuing: the channel, text, cost and budget."
  def preview(context, params, now \\ DateTime.utc_now()) do
    with {:ok, request} <- request(context, Map.put_new(params, :idempotency_key, "preview")),
         {:ok, plan} <- Channels.preview(context, request, env(context, now)) do
      {:ok,
       plan
       |> Map.take([
         :channel,
         :purpose,
         :template_key,
         :locale,
         :body,
         :segments,
         :encoding,
         :estimated_cost_cents,
         :currency,
         :urgent,
         :release_at,
         :held_for_quiet_hours,
         :budget,
         :replies_possible
       ])
       |> Map.put(:contact, Channels.public_contact(plan.contact))}
    end
  end

  @doc false
  def request(context, params) do
    key = param(params, :idempotency_key)
    source = param(params, :source) || "staff"
    channels = param(params, :channels)

    errors =
      %{}
      |> add(not (is_binary(key) and byte_size(key) in 1..120), :idempotency_key, "required")
      |> add(source not in ChannelPolicy.sources(), :source, "invalid")
      |> add(not is_binary(param(params, :template_key)), :template_key, "required")
      |> add(
        not (is_nil(channels) or (is_list(channels) and channels != [])),
        :channels,
        "invalid"
      )
      |> add(not is_map(param(params, :variables) || %{}), :variables, "invalid")

    with :ok <- no_errors(errors),
         {:ok, person} <- Channels.person(person_params(params)) do
      {:ok,
       %{
         person: person,
         template_key: param(params, :template_key),
         variables: stringify(param(params, :variables) || %{}),
         purpose: param(params, :purpose),
         channels: channels,
         urgent: param(params, :urgent) == true,
         idempotency_key: key,
         source: source,
         source_ref: param(params, :source_ref),
         actor_id: if(source == "staff", do: Map.get(context, :user_id))
       }}
    end
  end

  defp person_params(params),
    do:
      %{user_id: param(params, :user_id), lead_id: param(params, :lead_id)}
      |> Map.reject(&is_nil(elem(&1, 1)))

  defp stringify(variables),
    do: Map.new(variables, fn {key, value} -> {to_string(key), value} end)

  defp no_errors(errors) when errors == %{}, do: :ok
  defp no_errors(errors), do: {:error, {:invalid_fields, errors}}

  @doc "What other contexts need from the box: `now`, its time zone and name."
  def env(%{organization_id: organization_id} = context, now) do
    organization =
      case Map.get(context, :organization) do
        %{name: name, activation: _} = organization when is_binary(name) -> organization
        _missing -> Organizations.get_by_id(organization_id)
      end

    %{
      now: now,
      time_zone: Organizations.organization_timezone(organization_id),
      box_name: (organization && organization.name) || "Palee",
      # A box in demo mode sends no SMS (product owner, 2026-11-02).
      demo: match?(%{activation: "demo"}, organization)
    }
  end

  @doc "Template keys Palee writes, with their purpose and placeholders."
  def template_keys,
    do: Enum.map(Templates.all(), &Map.take(&1, [:key, :purpose, :variables]))

  @doc """
  Delivers the box's due messages soon: a job when background jobs run,
  inline otherwise (tests, one-off tasks). Held messages wait for the
  sweep (every minute).
  """
  def schedule(%{organization_id: organization_id}, message \\ nil) do
    due? = is_nil(message) or DateTime.compare(message.next_attempt_at, DateTime.utc_now()) != :gt

    cond do
      not due? ->
        :ok

      Application.get_env(:palee, :start_oban, true) ->
        %{"organization_id" => organization_id, "message_id" => message && message.id}
        |> DeliverChannelMessagesJob.new()
        |> Oban.insert()

        :ok

      true ->
        {:ok, _counts} =
          Channels.deliver(
            %{organization_id: organization_id},
            (message && message.id) || :due,
            DateTime.utc_now()
          )

        :ok
    end
  end

  @public ~w(id channel purpose template_key status hold_reason next_attempt_at segments
             estimated_cost_cents currency source source_ref)a

  defp view(message),
    do: message |> Map.take(@public) |> Map.put(:release_at, message.next_attempt_at)

  defp param(params, key) when is_map(params),
    do: Map.get(params, key, Map.get(params, Atom.to_string(key)))

  defp add(errors, true, field, code), do: Map.put_new(errors, field, code)
  defp add(errors, false, _field, _code), do: errors
end
