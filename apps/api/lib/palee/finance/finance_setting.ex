defmodule Palee.Finance.FinanceSetting do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "finance_settings" do
    field :organization_id, :binary_id, read_after_writes: true
    field :payment_reminder_interval_days, :integer, default: 7
    # Days before a subscription ends to remind the member (0 = no reminder).
    field :subscription_expiry_reminder_days, :integer, default: 5
    # ADR-500: also remind on the day it ends and on the day after; then every
    # `payment_reminder_interval_days` until the member renews or leaves.
    field :subscription_end_day_reminder, :boolean, default: true
    field :subscription_day_after_reminder, :boolean, default: true
    # Slack after a subscription ends or an invoice falls overdue during which
    # the member keeps access (entitlement "grace"); 0 = cut off immediately.
    field :subscription_grace_days, :integer, default: 3
    field :entitlement_enforcement_mode, :string, default: "observe"
    field :entitlement_timezone, :string, default: "Europe/Athens"
    field :document_mode, :string, default: "invoice"
    field :package_modules, {:array, :string}, default: ["group_classes", "online_coaching"]
    # ADR-553: who sees the subscription packages (all, own, none).
    field :package_audience, :string, default: "all"
    # ADR-596: the one package the public page and website feature (nil: none).
    field :featured_package_id, :binary_id
    # ADR-633: since when clients book only with a package (nil: the box
    # sells no package). Set and cleared by the daily run, never by a form.
    field :package_rule_since, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(settings \\ %__MODULE__{}, params) do
    settings
    |> cast(params, [
      :payment_reminder_interval_days,
      :subscription_expiry_reminder_days,
      :subscription_end_day_reminder,
      :subscription_day_after_reminder,
      :subscription_grace_days,
      :entitlement_enforcement_mode,
      :entitlement_timezone,
      :document_mode,
      :package_modules,
      :package_audience,
      :featured_package_id
    ])
    |> validate_required([
      :payment_reminder_interval_days,
      :entitlement_enforcement_mode,
      :entitlement_timezone,
      :document_mode
    ])
    |> validate_number(:payment_reminder_interval_days, greater_than: 0)
    |> validate_number(:subscription_expiry_reminder_days,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 60
    )
    |> validate_number(:subscription_grace_days,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 60
    )
    |> validate_inclusion(:entitlement_enforcement_mode, [
      "observe",
      "enforce_managed",
      "enforce_all"
    ])
    |> validate_length(:entitlement_timezone, min: 1, max: 100)
    |> validate_inclusion(:document_mode, ["invoice", "receipt"])
    |> validate_package_modules()
    |> validate_inclusion(:package_audience, Palee.Finance.Domain.PackageAudience.audiences())
    |> foreign_key_constraint(:featured_package_id)
  end

  defp validate_package_modules(changeset) do
    alias Palee.Finance.Domain.PackageType

    validate_change(changeset, :package_modules, fn :package_modules, modules ->
      if Enum.all?(modules, &PackageType.module_available?/1),
        do: [],
        else: [package_modules: "contains an unknown or unavailable module"]
    end)
  end
end
