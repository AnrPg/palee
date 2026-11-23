defmodule PaleeWeb.RouteActivityTest do
  use ExUnit.Case, async: true

  alias Palee.ActivityLog.Domain.Actions
  alias PaleeWeb.RouteActivity

  @staff_prefixes ["/api/org/:organization_slug/admin", "/api/org/:organization_slug/staff"]
  @changes [:post, :put, :patch, :delete]

  defp changing_staff_routes do
    PaleeWeb.Router.__routes__()
    |> Enum.filter(&(&1.verb in @changes))
    |> Enum.filter(fn route ->
      Enum.any?(@staff_prefixes, &String.starts_with?(route.path, &1))
    end)
  end

  test "every staff route that changes something says what it records (ADR-760)" do
    routes = changing_staff_routes()
    assert routes != []

    for route <- routes do
      entry = RouteActivity.for_action(route.plug, route.plug_opts)
      assert entry, "#{route.verb} #{route.path} has no activity log entry"

      case entry do
        :skip -> :ok
        key when is_binary(key) -> assert Actions.known?(key), "unknown key #{key}"
        {:by_param, _name, keys} -> for key <- Map.values(keys), do: assert(Actions.known?(key))
      end
    end
  end

  test "every action key is recorded by some route or by the system" do
    assert Enum.sort(RouteActivity.keys()) == Actions.keys()
  end

  test "every area has its capability and the owner holds them all" do
    owner = Palee.Organizations.Domain.AccessPolicy.capabilities([:owner])

    for capability <-
          Palee.ActivityLog.Domain.Visibility.capabilities() ++ [:export_activity_log] do
      assert Map.get(owner, capability) == :all, inspect(capability)
    end
  end
end
