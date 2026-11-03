defmodule Palee.Status.Domain.Components do
  @moduledoc """
  The components the public status page shows (ADR-364), in display order.

  Each component is fed by one probe of `Palee.Status.Ports.DependencyProbe`
  and has a public key the page and the API use. Probe reasons are internal
  (they can name hosts or errors) and never leave the platform console.

  * `app` – the Palee app and API itself: database, cache and background
    jobs, the parts without which nothing works.
  * `search` – search (Meilisearch).
  * `files` – photos, documents and receipts (object storage).
  * `email` – email delivery (the outbox, its daily budget and SMTP key).
  * `payments` – online payments (the providers' APIs).
  * `fiscal` – reporting receipts to the tax authority (myDATA).
  """

  @components ~w(app search files email payments fiscal)
  @statuses ~w(operational degraded down)

  @doc "Every component key, in display order."
  def all, do: @components

  @doc "Whether `key` names a component."
  def known?(key), do: key in @components

  @doc "The probe statuses, best first."
  def statuses, do: @statuses

  @doc """
  The worse of two statuses (`down` > `degraded` > `operational`), for
  folding several probes (database, cache, jobs) into one component.
  """
  def worst(a, b) do
    if rank(a) >= rank(b), do: a, else: b
  end

  @doc "Severity rank of a status (0 is best)."
  def rank("operational"), do: 0
  def rank("degraded"), do: 1
  def rank("down"), do: 2

  @doc "Keeps only known component keys, without repeats, in display order."
  def normalize(keys) when is_list(keys) do
    wanted = MapSet.new(keys, &to_string/1)
    Enum.filter(@components, &MapSet.member?(wanted, &1))
  end

  def normalize(_keys), do: []

  @doc "Whether every key in the list is a known component."
  def all_known?(keys) when is_list(keys), do: Enum.all?(keys, &known?(to_string(&1)))
  def all_known?(_keys), do: false
end
