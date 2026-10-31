defmodule Palee.Access.Domain.ProviderSettings do
  @moduledoc """
  What each door controller needs (ADR-381), checked before anything is
  saved. Settings are plain values shown back to staff; credentials are
  secrets, encrypted at rest and never returned.

    * `sandbox` – no hardware (development, tests, demos);
    * `shelly` – a Shelly relay (Plus 1, Pro 1, Gen2+) on the door strike or
      the turnstile's dry contact, through the Shelly Cloud Control API v2:
      `server` (the account's cloud host, e.g. `shelly-77-eu.shelly.cloud`),
      `device_id`, `channel` (0 by default); credential `auth_key`;
    * `kisi` – a Kisi controller: `lock_id`; credential `api_key` (a Kisi
      login of the box with access to that lock).
  """

  @providers ~w(sandbox shelly kisi)
  @host ~r/\A[a-z0-9-]+(\.[a-z0-9-]+)*\.shelly\.cloud\z/
  @device ~r/\A[a-zA-Z0-9]{6,32}\z/

  def providers, do: @providers

  @doc "`{:ok, settings, credentials}` or `{:error, :invalid_door_settings}`."
  def validate(provider, settings, credentials, previous_credentials \\ nil)

  def validate("sandbox", _settings, _credentials, _previous), do: {:ok, %{}, %{}}

  def validate("shelly", settings, credentials, previous) do
    settings = stringify(settings)
    credentials = merge_credentials(credentials, previous)
    channel = Map.get(settings, "channel", 0)

    with server when is_binary(server) <- settings["server"],
         server = server |> String.trim() |> String.downcase() |> strip_scheme(),
         true <- Regex.match?(@host, server),
         device when is_binary(device) <- settings["device_id"],
         true <- Regex.match?(@device, device),
         true <- is_integer(channel) and channel in 0..3,
         key when is_binary(key) and byte_size(key) in 20..200 <- credentials["auth_key"] do
      {:ok, %{"server" => server, "device_id" => device, "channel" => channel},
       %{"auth_key" => key}}
    else
      _invalid -> {:error, :invalid_door_settings}
    end
  end

  def validate("kisi", settings, credentials, previous) do
    settings = stringify(settings)
    credentials = merge_credentials(credentials, previous)

    with lock_id when is_integer(lock_id) and lock_id > 0 <- integer(settings["lock_id"]),
         key when is_binary(key) and byte_size(key) in 16..200 <- credentials["api_key"] do
      {:ok, %{"lock_id" => lock_id}, %{"api_key" => key}}
    else
      _invalid -> {:error, :invalid_door_settings}
    end
  end

  def validate(_provider, _settings, _credentials, _previous),
    do: {:error, :invalid_door_settings}

  defp merge_credentials(credentials, previous) do
    given =
      credentials
      |> stringify()
      |> Map.reject(fn {_key, value} -> value in [nil, ""] end)

    Map.merge(stringify(previous), given)
  end

  defp stringify(nil), do: %{}
  defp stringify(map) when is_map(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)
  defp stringify(_other), do: %{}

  defp strip_scheme("https://" <> host), do: String.trim_trailing(host, "/")
  defp strip_scheme(host), do: String.trim_trailing(host, "/")

  defp integer(value) when is_integer(value), do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _other -> nil
    end
  end

  defp integer(_value), do: nil
end
