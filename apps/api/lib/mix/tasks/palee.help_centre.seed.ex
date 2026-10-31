defmodule Mix.Tasks.Palee.HelpCentre.Seed do
  @shortdoc "Seeds the help centre's starting articles (ADR-362)"
  @moduledoc """
  Seeds `priv/help_centre/articles.json` into `help_articles` and rebuilds
  the search index. Idempotent; an article the Palee team has edited is
  never overwritten. Regenerate the file with `npm run help:seed` in
  apps/web.
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(_args) do
    case Palee.Application.HelpCentre.SeedHelpCentre.call() do
      {:ok, counts} -> Mix.shell().info("Help centre seeded: #{inspect(counts)}")
      {:error, reason} -> Mix.raise("Help centre seed failed: #{inspect(reason)}")
    end
  end
end
