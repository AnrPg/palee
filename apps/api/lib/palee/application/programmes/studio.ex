defmodule Palee.Application.Programmes.Studio do
  @moduledoc """
  ADR-370/371 use cases for the seller's staff: write a programme from the
  business's own WODs, publish it as a version, archive it, follow its
  sales, refund a buyer and moderate reviews.

  Publishing freezes each WOD of the draft as a hidden library copy
  (`library_visibility: personal`, published), so a later edit of the
  original never changes what buyers paid for.
  """

  require Logger

  alias Palee.Application.Programmes.{Covers, Facts, Presenter}
  alias Palee.{Identity, Organizations, Payments, Programmes, Workouts}

  # ── Programmes ──────────────────────────────────────────────────────────

  def list(context, filters \\ %{}) do
    programmes = Programmes.list_programmes(context, filters)
    ids = Enum.map(programmes, & &1.id)
    sales = Programmes.sales(context, ids)
    reviews = Programmes.review_summaries(context, ids)
    covers = Covers.urls(context, programmes)

    Enum.map(programmes, fn programme ->
      Presenter.staff(programme, %{
        sales: Map.get(sales, programme.id, %{buyers: 0, active: 0}),
        reviews: Map.get(reviews, programme.id, %{average: nil, count: 0}),
        cover_url: get_in(covers, [programme.id, :url])
      })
    end)
  end

  def show(context, id) do
    with {:ok, programme} <- fetch(context, id) do
      versions = Programmes.list_versions(context, programme.id)

      {:ok,
       present(context, programme, %{
         versions: Enum.map(versions, &Presenter.version/1),
         sales:
           Map.get(Programmes.sales(context, [programme.id]), programme.id, %{
             buyers: 0,
             active: 0
           }),
         reviews:
           Map.get(Programmes.review_summaries(context, [programme.id]), programme.id, %{
             average: nil,
             count: 0
           }),
         online_payments: Payments.available?(context, "programmes")
       })}
    end
  end

  def create(context, params) do
    with :ok <- check_equipment(params),
         {:ok, params} <- check_draft(context, params, nil),
         {:ok, programme} <-
           Programmes.create_programme(
             context,
             Map.merge(params, %{author_id: context.user_id, updated_by_id: context.user_id})
           ) do
      telemetry(:created, context, programme)
      {:ok, present(context, programme)}
    end
  end

  def update(context, id, params) do
    with {:ok, programme} <- fetch(context, id),
         true <- programme.status != "archived" || {:error, :programme_archived},
         :ok <- check_equipment(params),
         {:ok, params} <- check_draft(context, params, programme),
         {:ok, programme} <-
           Programmes.update_programme(
             context,
             programme,
             Map.put(params, :updated_by_id, context.user_id)
           ) do
      {:ok, present(context, programme)}
    end
  end

  # ADR-542: the author's equipment lists are vocabulary keys.
  defp check_equipment(params),
    do:
      Programmes.check_equipment(
        params[:equipment],
        params[:equipment_removed],
        Workouts.equipment_keys()
      )

  # One programme for the editor: its cover (ADR-541) and the facts its
  # draft's WODs give (ADR-542), with what the page shows.
  defp present(context, programme, extra \\ %{}) do
    urls = Covers.urls(context, [programme])[programme.id]
    facts = Facts.derive(context, programme.draft_days || [])

    Presenter.staff(
      programme,
      Map.merge(
        %{
          cover: Covers.staff(programme, urls),
          cover_url: urls && urls.url,
          facts: %{
            equipment: facts["equipment"],
            minutes_per_session: facts["minutes_per_session"]
          }
        },
        Map.merge(Facts.shown(programme, facts), extra)
      )
    )
  end

  # The draft's days must use published WODs of this business.
  defp check_draft(context, params, programme) do
    weeks = Map.get(params, :draft_weeks) || (programme && programme.draft_weeks) || 4

    case Map.fetch(params, :draft_days) do
      :error ->
        {:ok, params}

      {:ok, []} ->
        {:ok, Map.put(params, :draft_days, [])}

      {:ok, days} ->
        with {:ok, days} <- Programmes.normalize_days(days, weeks),
             :ok <- check_workouts(context, Programmes.workout_ids(days)) do
          {:ok, Map.put(params, :draft_days, days)}
        end
    end
  end

  defp check_workouts(context, ids) do
    if Enum.all?(ids, &published?(Workouts.get_workout(context, &1))),
      do: :ok,
      else: {:error, :programme_workout_unavailable}
  end

  defp published?(%{status: status}), do: to_string(status) == "published"
  defp published?(_workout), do: false

  @doc """
  Publishes the draft as the next version (`changelog` optional). The
  first publication puts the programme on sale.
  """
  def publish(context, id, params) do
    now = DateTime.utc_now()

    with {:ok, programme} <- fetch(context, id),
         {:ok, days} <- Programmes.normalize_days(programme.draft_days, programme.draft_weeks),
         :ok <- Programmes.publishable(programme, days),
         :ok <- check_workouts(context, Programmes.workout_ids(days)),
         {:ok, frozen} <- freeze(context, programme, days),
         facts = Facts.derive(context, frozen),
         {:ok, %{programme: programme, version: version}} <-
           Programmes.publish_version(
             context,
             programme.id,
             %{
               weeks: programme.draft_weeks,
               days: frozen,
               changelog: params[:changelog],
               published_at: now,
               published_by_id: context.user_id,
               facts: facts
             },
             %{
               status: "published",
               published_at: programme.published_at || now,
               archived_at: nil,
               updated_by_id: context.user_id
             }
           ) do
      telemetry(:published, context, programme, %{version: version.number})
      {:ok, present(context, programme, %{version: Presenter.version(version)})}
    end
  end

  # One frozen copy per distinct WOD, shared by the days that use it.
  defp freeze(context, programme, days) do
    days
    |> Programmes.workout_ids()
    |> Enum.reduce_while({:ok, %{}}, fn workout_id, {:ok, copies} ->
      case freeze_workout(context, programme, workout_id) do
        {:ok, copy} -> {:cont, {:ok, Map.put(copies, workout_id, copy)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, copies} ->
        {:ok,
         Enum.map(days, fn row ->
           copy = Map.fetch!(copies, row["workout_id"])

           %{
             "day" => row["day"],
             "workout_id" => copy.id,
             "source_workout_id" => row["workout_id"],
             "title" => copy.title,
             "summary" => copy.summary
           }
         end)}

      error ->
        error
    end
  end

  defp freeze_workout(context, programme, workout_id) do
    source = Workouts.get_workout(context, workout_id)

    with {:ok, draft} <-
           Workouts.duplicate_workout(context, workout_id, "· #{programme.title}", %{
             copy_goals: false
           }),
         {:ok, _hidden} <- publish_hidden(context, draft) do
      {:ok, %{id: draft.id, title: source[:title] || draft.title, summary: summary(source)}}
    else
      {:error, reason} ->
        Logger.warning(
          "programme #{programme.id}: freezing WOD #{workout_id} failed: #{inspect(reason)}"
        )

        {:error, :programme_workout_unavailable}
    end
  end

  # A copy that cannot be published is deleted, so a failed publish never
  # leaves a stray draft in the coach's library.
  defp publish_hidden(context, draft) do
    revision = %{expected_source_revision: Map.get(draft, :dsl_source_revision) || 0}

    with {:ok, _published} <- Workouts.publish_workout(context, draft.id, revision),
         {:ok, hidden} <-
           Workouts.update_library_metadata(context, draft.id, %{library_visibility: "personal"}) do
      {:ok, hidden}
    else
      error ->
        _deleted = Workouts.delete_workout(context, draft.id)
        error
    end
  end

  defp summary(%{} = workout) do
    text = workout[:subtitle] || workout[:description]
    if is_binary(text), do: String.slice(text, 0, 200), else: nil
  end

  defp summary(_workout), do: nil

  # ── Cover (ADR-541) ─────────────────────────────────────────────────────

  @doc "Sets the cover (`Covers.set/3`); an archived programme keeps its own."
  def set_cover(context, id, params) do
    with {:ok, programme} <- fetch(context, id),
         true <- programme.status != "archived" || {:error, :programme_archived},
         {:ok, programme} <- Covers.set(context, programme, params) do
      {:ok, present(context, programme)}
    end
  end

  def remove_cover(context, id) do
    with {:ok, programme} <- fetch(context, id),
         {:ok, programme} <- Covers.remove(context, programme) do
      {:ok, present(context, programme)}
    end
  end

  def archive(context, id), do: step(context, id, :archive)
  def restore(context, id), do: step(context, id, :restore)

  defp step(context, id, step) do
    with {:ok, programme} <- fetch(context, id),
         {:ok, programme} <- Programmes.transition(context, programme, step, DateTime.utc_now()) do
      telemetry(step, context, programme)
      {:ok, present(context, programme)}
    end
  end

  # ── Sales ───────────────────────────────────────────────────────────────

  def purchases(context, id) do
    with {:ok, programme} <- fetch(context, id) do
      purchases = Programmes.list_purchases(context, %{programme_id: programme.id})
      names = names(purchases)

      {:ok,
       Enum.map(purchases, fn purchase ->
         Presenter.purchase(purchase, %{buyer: Map.get(names, purchase.user_id)})
       end)}
    end
  end

  @doc """
  Staff refund a buyer (goodwill or a dispute): up to what is left of the
  price, through the seller's provider. A full refund ends the purchase
  and removes its future WODs.
  """
  def refund(context, purchase_id, params) do
    now = DateTime.utc_now()

    with %{} = purchase <- Programmes.get_purchase(context, purchase_id) || {:error, :not_found},
         :ok <- Programmes.check_staff_refund(purchase, params[:amount_cents]),
         true <-
           is_binary(purchase.payment_intent_id) || {:error, :programme_refund_not_available},
         {:ok, refund} <-
           Payments.refund(
             context,
             purchase.payment_intent_id,
             %{
               amount_cents: params[:amount_cents],
               reason: params[:reason] || "programme refund",
               idempotency_key:
                 params[:idempotency_key] ||
                   "programme-refund:#{purchase.id}:#{purchase.refunded_cents}"
             },
             context.user_id,
             now
           ),
         {:ok, purchase} <-
           Programmes.step_purchase(
             context,
             purchase.id,
             {:refunded, params[:amount_cents], :staff},
             now
           ) do
      unless Programmes.delivering?(purchase), do: remove_future(context, purchase, now)
      telemetry(:refunded, context, purchase, %{amount_cents: params[:amount_cents]})
      {:ok, %{purchase: Presenter.purchase(purchase), refund: refund}}
    end
  end

  @doc false
  def remove_future(context, purchase, now) do
    today = Organizations.local_today(context.organization_id, now)

    ids =
      context |> Programmes.deliveries(purchase.id, today) |> Enum.map(& &1.assigned_workout_id)

    with {:ok, _removed} <-
           Workouts.remove_athlete_from_assignments(
             context,
             Enum.uniq(ids),
             purchase.user_id,
             today
           ) do
      Programmes.delete_deliveries(context, purchase.id, today)
      :ok
    end
  end

  # ── Reviews ─────────────────────────────────────────────────────────────

  def reviews(context, id) do
    with {:ok, programme} <- fetch(context, id) do
      reviews = Programmes.list_reviews(context, programme.id)
      names = names(reviews)
      {:ok, Enum.map(reviews, &Presenter.review(&1, Map.get(names, &1.user_id)))}
    end
  end

  def moderate_review(context, review_id, reason) do
    with %{} = review <- Programmes.get_review(context, review_id) || {:error, :not_found},
         {:ok, review} <- Programmes.moderate_review(context, review, reason) do
      {:ok, Presenter.review(review)}
    end
  end

  # ── helpers ─────────────────────────────────────────────────────────────

  defp fetch(context, id) do
    case Programmes.get_programme(context, id) do
      nil -> {:error, :not_found}
      programme -> {:ok, programme}
    end
  end

  defp names(rows) do
    rows
    |> Enum.map(& &1.user_id)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Identity.list_by_ids()
    |> Map.new(&{&1.id, %{id: &1.id, nickname: &1.nickname}})
  end

  defp telemetry(event, context, row, extra \\ %{}) do
    :telemetry.execute(
      [:palee, :programmes, event],
      %{count: 1},
      Map.merge(%{organization_id: context.organization_id, id: row.id}, extra)
    )
  end
end
