defmodule Palee.Gamification.Ports.GamificationStore do
  @callback get_user_stats(Ecto.UUID.t()) :: map() | nil
  @callback lock_user_stats(Ecto.UUID.t()) :: map() | nil
  @callback get_settings() :: map()
  @callback update_settings(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback upsert_user_stats(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback increment_advancement(Ecto.UUID.t(), DateTime.t()) :: {:ok, map()} | {:error, term()}
  @callback create_achievement(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback list_user_achievements(Ecto.UUID.t()) :: [map()]
  @callback count_achievements_by_prefix(Ecto.UUID.t(), String.t()) :: non_neg_integer()
  @callback create_challenge(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback create_challenge_with_limit(map(), pos_integer()) ::
              {:ok, map()}
              | {:error, Ecto.Changeset.t()}
              | {:error, :active_challenge_limit_reached | term()}
  @callback get_challenge(Ecto.UUID.t()) :: map() | nil
  @callback update_challenge(Ecto.UUID.t(), map()) ::
              {:ok, map()} | {:error, Ecto.Changeset.t()} | {:error, :not_found}
  @callback delete_challenge(Ecto.UUID.t()) :: :ok | {:error, :not_found}
  @callback list_challenges() :: [map()]
  @callback list_active_challenges(Date.t()) :: [map()]
  @callback get_user_challenge_progress(Ecto.UUID.t(), Ecto.UUID.t()) :: map() | nil
  @callback lock_challenge(Ecto.UUID.t()) :: :ok | {:error, :not_found}
  @callback list_challenge_progress(Ecto.UUID.t()) :: [map()]
  @callback upsert_user_challenge_progress(map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  @callback set_leaderboard_opt_in(Ecto.UUID.t(), boolean()) ::
              {:ok, boolean()} | {:error, Ecto.Changeset.t() | term()}
  @callback leaderboard_opted_in?(Ecto.UUID.t()) :: boolean()
  @callback get_leaderboard(String.t(), non_neg_integer()) :: [map()]
  @callback refresh_leaderboard() :: :ok | {:error, term()}
  @callback transaction((-> {:ok, term()} | {:error, term()})) :: {:ok, term()} | {:error, term()}
  @callback opt_in_challenge_leaderboard(user_id :: Ecto.UUID.t(), challenge_id :: Ecto.UUID.t()) ::
              {:ok, any()} | {:error, any()}
  @callback opt_out_challenge_leaderboard(user_id :: Ecto.UUID.t(), challenge_id :: Ecto.UUID.t()) ::
              :ok
  @callback challenge_leaderboard_opted_in?(
              user_id :: Ecto.UUID.t(),
              challenge_id :: Ecto.UUID.t()
            ) :: boolean()
  @callback list_challenge_leaderboard_participants(challenge_id :: Ecto.UUID.t()) :: [map()]
  @callback get_user_preferences(user_id :: Ecto.UUID.t()) :: map() | nil
  @callback upsert_user_preferences(user_id :: Ecto.UUID.t(), params :: map()) ::
              {:ok, map()} | {:error, Ecto.Changeset.t()}

  @callback leaderboard_opted_in_user_ids([Ecto.UUID.t()]) :: [Ecto.UUID.t()]
  @doc "ADR-356: the opted-in people of `user_ids` with their division and birth year."
  @callback leaderboard_profiles([Ecto.UUID.t()]) :: %{
              Ecto.UUID.t() => %{division: String.t() | nil, birth_year: integer() | nil}
            }
  @doc "ADR-356: sets the division and birth year of an opted-in person."
  @callback put_leaderboard_profile(Ecto.UUID.t(), map()) ::
              {:ok, map()} | {:error, :not_opted_in | Ecto.Changeset.t()}
  @doc "ADR-394: the person's Palee-wide answer (`share`, `see_only`) or nil."
  @callback get_palee_leaderboard_consent(Ecto.UUID.t()) :: String.t() | nil
  @callback put_palee_leaderboard_consent(Ecto.UUID.t(), String.t()) ::
              {:ok, String.t()} | {:error, Ecto.Changeset.t()}
  @callback delete_palee_leaderboard_consent(Ecto.UUID.t()) :: :ok
  @doc """
  ADR-394: the results of one benchmark across every box, through the
  `palee_benchmark_results` SECURITY DEFINER function: only people who
  chose `share`, plus the caller's own.
  """
  @callback palee_benchmark_results(String.t(), DateTime.t(), DateTime.t(), integer()) :: [
              map()
            ]
  @doc "ADR-394: the scored sections of those benchmark WODs, by WOD id."
  @callback palee_benchmark_workout_sections(String.t(), [Ecto.UUID.t()]) :: %{
              Ecto.UUID.t() => map()
            }
  @callback get_training_goal(user_id :: Ecto.UUID.t(), kind :: String.t()) :: map() | nil
  @callback put_training_goal(params :: map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
end
