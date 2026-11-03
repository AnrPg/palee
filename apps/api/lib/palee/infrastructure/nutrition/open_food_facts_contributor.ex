defmodule Palee.Infrastructure.Nutrition.OpenFoodFactsContributor do
  @moduledoc """
  Sends a product members shared to Open Food Facts (ADR-421 addendum),
  through its product write API (`POST /cgi/product_jqm2.pl`, read
  2026-11-03 at openfoodfacts.github.io/openfoodfacts-server/api/ and
  .../Product-Opener/v2/products/post-cgi-product_jqm2.pl/).

    * Auth: Palee's own Open Food Facts account (`OFF_USER_ID`, the user
      name, not the email; `OFF_PASSWORD`), as form fields of the POST, as
      Open Food Facts allows for a global app account. OAuth is not offered
      yet. Without both the contributor is off and shares wait in the outbox.
    * Every write names the app: `app_name`, `app_version` and `app_uuid`
      (a salted pseudonym per member, so Open Food Facts moderators can stop
      one contributor without blocking Palee; it cannot be turned back into
      the member), the same User-Agent as reads, and a `comment`.
    * Only data: barcode, name in the member's language, brand, serving size
      and the six nutrients per 100 g (`nutrition_data_per=100g`). No photo
      (Palee never keeps the label photos; Open Food Facts does not require
      one), no energy (Palee never holds it).
    * Never overwrites: the product is read first (`GET /api/v2/product/…`,
      one read, within the 15 reads/min/IP limit at the outbox's pace) and
      an existing one ends the share as `exists`. Writes have no published
      rate limit; failures (network, 429, 5xx) back off in the outbox, other
      4xx answers and `status: 0` are final.
    * Contributed data is under ODbL 1.0 / DbCL like the rest of Open Food
      Facts; the members agreed to share it with everyone.

  Config (`:open_food_facts_contributions`): `base_url` (staging
  `https://world.openfoodfacts.net` takes HTTP basic auth `off:off`),
  `user_id`, `password`, `app_name`, `app_version`, `uuid_salt`,
  `user_agent`, `receive_timeout`, `req_options` (tests pass a `Req.Test`
  plug).
  """

  @behaviour Palee.Nutrition.Ports.FoodContributor

  @nutrients ~w(proteins carbohydrates fat fiber sugars salt)

  @impl true
  def configured? do
    config = config()
    present?(config[:user_id]) and present?(config[:password])
  end

  @impl true
  def contribute(share) do
    if configured?() do
      config = config()

      with :absent <- existing(share.barcode, config) do
        share |> form(config) |> write(config)
      end
    else
      {:error, :not_configured}
    end
  end

  defp existing(barcode, config) do
    [
      method: :get,
      url: "#{config[:base_url]}/api/v2/product/#{barcode}.json",
      params: [fields: "code"]
    ]
    |> request(config)
    |> case do
      {:ok, %Req.Response{status: 200, body: body}} ->
        case decode(body) do
          %{"status" => 1} -> {:error, :exists}
          %{"status" => 0} -> :absent
          _other -> {:error, {:transient, :unexpected_body}}
        end

      {:ok, %Req.Response{status: 404}} ->
        :absent

      other ->
        failure(other)
    end
  end

  defp write(form, config) do
    [method: :post, url: "#{config[:base_url]}/cgi/product_jqm2.pl", form: form]
    |> request(config)
    |> case do
      {:ok, %Req.Response{status: 200, body: body}} ->
        case decode(body) do
          %{"status" => 1} -> :ok
          %{"status_verbose" => verbose} -> {:error, {:rejected, verbose}}
          _other -> {:error, {:transient, :unexpected_body}}
        end

      other ->
        failure(other)
    end
  end

  defp failure({:ok, %Req.Response{status: status}}) when status == 429 or status >= 500,
    do: {:error, {:transient, {:http, status}}}

  defp failure({:ok, %Req.Response{status: status}}), do: {:error, {:rejected, {:http, status}}}
  defp failure({:error, exception}), do: {:error, {:transient, Exception.message(exception)}}

  @doc false
  def form(share, config) do
    language = share.language || "el"

    given = share.nutrients || %{}

    nutrients =
      @nutrients
      |> Enum.filter(&is_number(Map.get(given, &1)))
      |> Enum.flat_map(&[{"nutriment_#{&1}", Map.get(given, &1)}, {"nutriment_#{&1}_unit", "g"}])

    [
      {"code", share.barcode},
      {"user_id", config[:user_id]},
      {"password", config[:password]},
      {"app_name", config[:app_name]},
      {"app_version", config[:app_version]},
      {"app_uuid", app_uuid(share.user_id, config)},
      {"comment", "Shared by a Palee member (checked against the pack)"},
      {"lang", language},
      {"product_name_#{language}", share.name},
      {"brands", share.brand},
      {"serving_size", share.serving_size}
    ]
    |> Kernel.++(if nutrients == [], do: [], else: [{"nutrition_data_per", "100g"} | nutrients])
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Enum.map(fn {key, value} -> {key, to_string(value)} end)
  end

  # A salted pseudonym per member (Open Food Facts asks for one per user);
  # none once the account is gone.
  defp app_uuid(nil, _config), do: nil

  defp app_uuid(user_id, config) do
    salt = config[:uuid_salt] || endpoint_secret()
    <<bytes::binary-size(16), _rest::binary>> = :crypto.mac(:hmac, :sha256, salt, user_id)
    Ecto.UUID.cast!(bytes)
  end

  defp endpoint_secret do
    Application.get_env(:palee, PaleeWeb.Endpoint, [])[:secret_key_base] || "palee"
  end

  defp request(options, config) do
    options
    |> Keyword.merge(
      headers: [{"user-agent", config[:user_agent]}],
      receive_timeout: config[:receive_timeout] || 10_000,
      retry: false,
      decode_body: false
    )
    |> then(fn options ->
      if String.contains?(config[:base_url] || "", "openfoodfacts.net"),
        do: Keyword.put(options, :auth, {:basic, "off:off"}),
        else: options
    end)
    |> Keyword.merge(config[:req_options] || [])
    |> Req.request()
  end

  defp decode(body) when is_map(body), do: body

  defp decode(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _error -> %{}
    end
  end

  defp decode(_body), do: %{}

  defp present?(value), do: is_binary(value) and value != ""

  defp config, do: Application.get_env(:palee, :open_food_facts_contributions, [])
end
