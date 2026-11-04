defmodule Palee.Infrastructure.Integrations.SandboxAudience do
  @moduledoc """
  The email list of development, tests and demos (ADR-380): nothing leaves
  the machine. `list_id` = `fail` answers as a refused key.
  """

  @behaviour Palee.Integrations.Ports.AudienceProvider

  @impl true
  def check(%{list_id: "fail"}), do: {:error, {:unauthorized, :sandbox}}
  def check(_connection), do: :ok

  @impl true
  def subscribe(%{list_id: "fail"}, _contact), do: {:error, {:unauthorized, :sandbox}}
  def subscribe(_connection, %{email: email}) when is_binary(email), do: :ok

  @impl true
  def unsubscribe(%{list_id: "fail"}, _email), do: {:error, {:unauthorized, :sandbox}}
  def unsubscribe(_connection, email) when is_binary(email), do: :ok
end
