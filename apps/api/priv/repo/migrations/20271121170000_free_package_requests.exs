defmodule Palee.Repo.Migrations.FreePackageRequests do
  use Ecto.Migration

  @moduledoc """
  ADR-681: a free package (price 0) can be asked for («Το θέλω») and is
  activated by the box without any payment. Notification type
  `package_request_activated` tells the person their package started. The
  type constraint is rewritten from what the database holds.
  """

  @types ~w(package_request_activated)

  def up do
    drop constraint(:finance_package_requests, :finance_package_requests_price_check)

    create constraint(:finance_package_requests, :finance_package_requests_price_check,
             check: "price_cents_snapshot >= 0"
           )

    rewrite_notification_types(&Enum.uniq(&1 ++ @types))
  end

  def down do
    execute(
      "DELETE FROM notifications WHERE type IN (#{Enum.map_join(@types, ", ", &"'#{&1}'")})"
    )

    rewrite_notification_types(&(&1 -- @types))
    execute("DELETE FROM finance_package_requests WHERE price_cents_snapshot = 0")
    drop constraint(:finance_package_requests, :finance_package_requests_price_check)

    create constraint(:finance_package_requests, :finance_package_requests_price_check,
             check: "price_cents_snapshot > 0"
           )
  end

  defp rewrite_notification_types(change) do
    flush()

    %{rows: [[definition]]} =
      repo().query!("""
      SELECT pg_get_constraintdef(oid) FROM pg_constraint
      WHERE conname = 'notifications_type_check' AND conrelid = 'notifications'::regclass
      """)

    current = Regex.scan(~r/'([a-z0-9_]+)'/, definition) |> Enum.map(&List.last/1)

    execute("ALTER TABLE notifications DROP CONSTRAINT notifications_type_check")

    execute(
      "ALTER TABLE notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (#{Enum.map_join(change.(current), ", ", &"'#{&1}'")}))"
    )
  end
end
