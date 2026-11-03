defmodule Palee.Application.ServiceStatusLinks do
  @moduledoc """
  ADR-364: links in status emails. The page lives at
  `config :palee, :status_page_url` (default `<public base URL>/status`),
  so it can move to a host outside the cluster without code changes.
  """

  alias Palee.Application.{PublicURL, SignedToken}

  @unsubscribe_salt "status-unsubscribe"

  def unsubscribe_salt, do: @unsubscribe_salt

  def page_url,
    do: Application.get_env(:palee, :status_page_url) || PublicURL.base_url() <> "/status"

  def confirm_url(token), do: page_url() <> "?confirm=" <> URI.encode_www_form(token)

  def unsubscribe_url(subscriber_id) do
    token = SignedToken.sign(@unsubscribe_salt, subscriber_id)
    page_url() <> "?unsubscribe=" <> URI.encode_www_form(token)
  end
end
