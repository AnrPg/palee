defmodule Palee.Application.PublicServiceStatus do
  @moduledoc """
  ADR-364: the public status page data and its email subscriptions, for
  its public controller. No session: anyone may read the page,
  from the Palee web app or from a host outside the cluster.

  Sign-ups are double opt-in: `subscribe/1` always answers the same
  (accepted) for a valid address, and the confirmation email carries a
  one-time token the page posts back to `confirm/1`. Status emails carry an
  unsubscribe link with a signed token over the subscriber id
  (`unsubscribe/1` deletes the row).
  """

  require Logger

  alias Palee.{Email, Status}
  alias Palee.Application.{ServiceStatusLinks, SignedToken}

  @doc "The page now."
  def overview, do: {:ok, Status.overview(clock().now())}

  @doc "Uptime per component and day (1..90 days, default 90) and the incidents in that window."
  def history(days), do: {:ok, Status.history(days, clock().now())}

  @doc "Asks for status emails. `:ok` for any valid address (no enumeration)."
  def subscribe(params) do
    now = clock().now()
    token = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

    case Status.request_subscription(get(params, :email), get(params, :locale), token, now) do
      {:ok, {:confirm, subscriber}} ->
        send_confirmation(subscriber, token, now)

      {:ok, :already_confirmed} ->
        :ok

      {:error, :invalid_email} ->
        {:error, :invalid_status_email}

      {:error, reason} ->
        # A race on the unique address: someone signed up the same address
        # at the same moment. Answer the same as for a new sign-up.
        Logger.info("status subscription not stored: #{inspect(reason)}")
        :ok
    end
  end

  @doc "Confirms a sign-up from the token in the confirmation email."
  def confirm(params) do
    with {:ok, _subscriber} <- Status.confirm_subscription(get(params, :token), clock().now()) do
      :ok
    end
  end

  @doc "Removes a subscriber from the signed token in a status email."
  def unsubscribe(params) do
    with token when is_binary(token) <- get(params, :token),
         {:ok, subscriber_id} when is_binary(subscriber_id) <-
           SignedToken.verify(ServiceStatusLinks.unsubscribe_salt(), token, max_age: :infinity) do
      Status.unsubscribe(subscriber_id)
    else
      _invalid -> {:error, :status_subscription_not_found}
    end
  end

  defp send_confirmation(subscriber, token, now) do
    result =
      Email.enqueue(
        :status_subscription_confirm,
        subscriber.email,
        %{url: ServiceStatusLinks.confirm_url(token)},
        locale: subscriber.locale,
        idempotency_key: "status_subscription:#{subscriber.id}:#{token_tag(token)}",
        now: now
      )

    case result do
      {:ok, _message} ->
        :ok

      {:error, reason} ->
        Logger.info("status subscription confirmation not queued: #{inspect(reason)}")
        :ok
    end
  end

  defp token_tag(token), do: binary_part(token, 0, 8)

  defp get(params, key), do: Map.get(params, key, Map.get(params, to_string(key)))

  defp clock, do: Application.fetch_env!(:palee, :status_clock)
end
