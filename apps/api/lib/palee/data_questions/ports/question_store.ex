defmodule Palee.DataQuestions.Ports.QuestionStore do
  @moduledoc "The audit log of data questions (ADR-361). Tenant context first."

  @callback insert(context :: map(), attrs :: map()) :: {:ok, map()} | {:error, term()}
  @callback get(context :: map(), id :: Ecto.UUID.t()) :: map() | nil
  @doc "Newest first; `user_id` narrows to one asker; `before` pages by insertion time."
  @callback list(context :: map(), filters :: map()) :: [map()]
  @doc "How many questions this person asked since `since`."
  @callback count_since(context :: map(), user_id :: Ecto.UUID.t(), since :: DateTime.t()) ::
              non_neg_integer()
end
