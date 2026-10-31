defmodule Palee.Application.HelpCentre.SeedHelpCentre do
  @moduledoc """
  Loads `priv/help_centre/articles.json` (ADR-362) and seeds it as the
  system. Used by `mix palee.help_centre.seed` and
  `Palee.Release.seed_help_centre/0`.
  """

  alias Palee.Application.HelpCentre.PlatformHelpArticles

  def call(path \\ default_path()) do
    with {:ok, contents} <- File.read(path),
         {:ok, file} <- Jason.decode(contents) do
      PlatformHelpArticles.seed(:system, file)
    end
  end

  def default_path, do: Application.app_dir(:palee, "priv/help_centre/articles.json")
end
