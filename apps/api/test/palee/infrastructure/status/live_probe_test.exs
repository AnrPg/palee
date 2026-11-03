defmodule Palee.Infrastructure.Status.LiveProbeTest do
  use Palee.DataCase, async: false

  alias Palee.Infrastructure.Status.LiveProbe

  setup do
    previous = Application.get_env(:palee, :readiness_checker)

    on_exit(fn ->
      Application.put_env(:palee, :readiness_checker, previous)
      Application.delete_env(:palee, :status_probe_targets)
    end)

    Application.put_env(:palee, :status_probe_targets, [
      %{component: "payments", name: "stripe", url: "https://api.stripe.test/v1"},
      %{component: "payments", name: "viva", url: "https://api.viva.test"},
      %{component: "fiscal", name: "mydata", url: "https://mydata.test/myDATA"}
    ])

    :ok
  end

  defp by_key(results), do: Map.new(results, &{&1.component, &1})

  test "readiness feeds app, search and files; reachable providers are operational" do
    Application.put_env(:palee, :readiness_checker, Palee.TestSupport.FakeReadinessOk)

    Req.Test.stub(Palee.StatusHttp, fn conn ->
      # No credentials are sent: a 401 still means the API answers.
      Plug.Conn.send_resp(conn, 401, "unauthorized")
    end)

    results = by_key(LiveProbe.check())

    for key <- ~w(app search files email payments fiscal) do
      assert results[key].status == "operational", "#{key}: #{inspect(results[key])}"
    end
  end

  test "a failing dependency is down with an internal reason; 5xx is degraded" do
    Application.put_env(:palee, :readiness_checker, Palee.TestSupport.FakeReadinessError)

    Req.Test.stub(Palee.StatusHttp, fn conn ->
      if conn.host == "api.viva.test",
        do: Plug.Conn.send_resp(conn, 503, "busy"),
        else: Req.Test.transport_error(conn, :econnrefused)
    end)

    results = by_key(LiveProbe.check())

    assert results["app"].status == "down"
    assert results["payments"].status == "degraded"
    assert results["payments"].reason =~ "stripe"
    assert results["payments"].reason =~ "viva: HTTP 503"
    assert results["fiscal"].status == "down"
  end
end
