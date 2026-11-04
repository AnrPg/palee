defmodule Palee.Infrastructure.Analytics.DimensionSnapshot do
  @moduledoc """
  ADR-462 §2: the filter dimensions of a fact, read once when the fact is
  written so later changes to the class or the package never rewrite
  history. Used by every write path of `analytics_events`,
  `class_attendance_records` and `attendance_records`, inside the writer's
  tenant session (the reads go through the same RLS).

  Dimensions: `location_id`, `class_type_id`, `level` (class type
  difficulty), `coach_user_id`, `class_starts_at` (attendance only) and
  `package_family` (the person's base package on the day); the rest goes in
  `dimensions`.
  """

  import Ecto.Query

  alias Palee.Repo

  @uuid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

  @doc "Snapshot columns for an attendance row of `scheduled_class_id` and `user_id`."
  def attendance(scheduled_class_id, user_id, %Date{} = on) do
    class = scheduled_class_id |> List.wrap() |> classes() |> Map.get(scheduled_class_id)
    family = user_id |> List.wrap() |> package_families(on) |> Map.get(user_id)

    class_columns(class)
    |> Map.put("class_starts_at", class && class.scheduled_at)
    |> Map.put("package_family", family)
  end

  @doc """
  Adds snapshot columns to analytics event rows (atom-keyed maps, as
  `insert_all` takes them). The class comes from the subject
  (`scheduled_class`) or the metadata's `scheduled_class_id`; the branch
  from the class or the metadata's `location_id`.
  """
  def put_event_dimensions([]), do: []

  def put_event_dimensions(rows) when is_list(rows) do
    classes = rows |> Enum.map(&event_class_id/1) |> Enum.reject(&is_nil/1) |> classes()

    families =
      rows
      |> Enum.filter(&is_binary(&1[:user_id]))
      |> Enum.group_by(&event_date/1, & &1.user_id)
      |> Enum.flat_map(fn {on, users} ->
        users |> Enum.uniq() |> package_families(on) |> Enum.map(fn {u, f} -> {{u, on}, f} end)
      end)
      |> Map.new()

    Enum.map(rows, fn row ->
      class = Map.get(classes, event_class_id(row))
      columns = class_columns(class)
      metadata = row[:metadata] || %{}

      row
      |> Map.put(:location_id, columns["location_id"] || uuid(metadata["location_id"]))
      |> Map.put(:class_type_id, columns["class_type_id"] || uuid(metadata["class_type_id"]))
      |> Map.put(:level, columns["level"])
      |> Map.put(:coach_user_id, columns["coach_user_id"])
      |> Map.put(:package_family, Map.get(families, {row[:user_id], event_date(row)}))
      |> Map.put(:dimensions, event_dimensions(class))
    end)
  end

  defp event_dimensions(nil), do: %{}

  defp event_dimensions(class) do
    %{"class_starts_at" => class.scheduled_at && DateTime.to_iso8601(class.scheduled_at)}
    |> Map.merge(class_columns(class)["dimensions"])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp class_columns(nil),
    do: %{
      "location_id" => nil,
      "class_type_id" => nil,
      "level" => nil,
      "coach_user_id" => nil,
      "dimensions" => %{}
    }

  defp class_columns(class) do
    %{
      "location_id" => class.location_id,
      "class_type_id" => class.class_type_id,
      "level" => class.level,
      "coach_user_id" => class.coach_user_id,
      "dimensions" =>
        %{
          "space_id" => class.space_id,
          "class_series_id" => class.class_series_id,
          "class_kind" => class.kind
        }
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()
    }
  end

  defp event_class_id(%{context_type: "scheduled_class", context_id: id}) when is_binary(id),
    do: id

  defp event_class_id(row), do: uuid((row[:metadata] || %{})["scheduled_class_id"])

  defp event_date(row) do
    case row[:occurred_at] do
      %DateTime{} = at -> DateTime.to_date(at)
      _other -> Date.utc_today()
    end
  end

  defp uuid(value) when is_binary(value), do: if(value =~ @uuid, do: value)
  defp uuid(_value), do: nil

  defp classes([]), do: %{}

  defp classes(ids) do
    ids = ids |> Enum.uniq() |> Enum.map(&Ecto.UUID.dump!/1)

    from(class in "scheduled_classes",
      left_join: type in "class_types",
      on: type.id == class.class_type_id,
      where: class.id in ^ids,
      select: %{
        id: class.id,
        location_id: class.location_id,
        class_type_id: class.class_type_id,
        coach_user_id: class.coach_user_id,
        space_id: class.space_id,
        class_series_id: class.class_series_id,
        scheduled_at: class.scheduled_at,
        level: type.level,
        kind: type.kind
      }
    )
    |> Repo.all()
    |> Map.new(fn class ->
      class = %{
        class
        | id: load(class.id),
          location_id: load(class.location_id),
          class_type_id: load(class.class_type_id),
          coach_user_id: load(class.coach_user_id),
          space_id: load(class.space_id),
          class_series_id: load(class.class_series_id),
          scheduled_at: utc(class.scheduled_at)
      }

      {class.id, class}
    end)
  end

  @doc "The base package family each person held on `on` (`%{user_id => family}`)."
  def package_families([], _on), do: %{}

  def package_families(user_ids, %Date{} = on) do
    users = user_ids |> Enum.uniq() |> Enum.map(&Ecto.UUID.dump!/1)

    from(subscription in "membership_package_subscriptions",
      join: membership in "memberships",
      on: membership.id == subscription.membership_id,
      where:
        membership.user_id in ^users and is_nil(subscription.base_subscription_id) and
          subscription.starts_on <= ^on and
          (is_nil(subscription.ends_on) or subscription.ends_on >= ^on),
      order_by: [asc: subscription.starts_on],
      select: {membership.user_id, subscription.package_family_snapshot}
    )
    |> Repo.all()
    |> Enum.reject(fn {_user, family} -> is_nil(family) end)
    # The latest started wins: later rows overwrite earlier ones.
    |> Map.new(fn {user, family} -> {load(user), family} end)
  end

  defp load(nil), do: nil
  defp load(<<_::128>> = raw), do: Ecto.UUID.load!(raw)
  defp load(value), do: value

  defp utc(%NaiveDateTime{} = at), do: DateTime.from_naive!(at, "Etc/UTC")
  defp utc(%DateTime{} = at), do: at
  defp utc(_at), do: nil
end
