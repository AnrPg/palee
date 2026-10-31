defmodule PaleeWeb.Schemas.CoachNotes do
  @moduledoc "OpenAPI schemas for private coach notes (ADR-101)."

  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  @uuid %Schema{type: :string, format: :uuid}

  def uuid, do: @uuid

  def note do
    %Schema{
      title: "CoachNote",
      type: :object,
      properties: %{
        id: @uuid,
        coach_user_id: @uuid,
        coach_nickname: %Schema{type: :string, nullable: true},
        client_user_id: @uuid,
        body: %Schema{type: :string},
        subject_kind: %Schema{type: :string, enum: subject_kinds(), nullable: true},
        subject_id: %Schema{type: :string, format: :uuid, nullable: true},
        audience: %Schema{
          type: :string,
          enum: ~w(private staff),
          description: "ADR-359: private coach note (ADR-101) or a note every staff member reads"
        },
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :coach_user_id, :client_user_id, :body]
    }
  end

  def read do
    %Schema{
      title: "CoachNoteRead",
      type: :object,
      properties: %{
        id: @uuid,
        note_id: @uuid,
        client_user_id: @uuid,
        client_nickname: %Schema{type: :string, nullable: true},
        reader_user_id: @uuid,
        reader_nickname: %Schema{type: :string, nullable: true},
        read_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :note_id, :reader_user_id, :read_at]
    }
  end

  defp subject_kinds, do: Palee.Coaching.note_subject_kinds()

  @doc "A new note: its body and, optionally, what it is about."
  def create_schema do
    %Schema{
      type: :object,
      properties: %{
        body: %Schema{type: :string, minLength: 1, maxLength: 5000},
        subject_kind: %Schema{type: :string, enum: subject_kinds()},
        subject_id: @uuid,
        audience: %Schema{type: :string, enum: ~w(private staff), default: "private"}
      },
      required: [:body]
    }
  end

  def body_schema do
    %Schema{
      type: :object,
      properties: %{body: %Schema{type: :string, minLength: 1, maxLength: 5000}},
      required: [:body]
    }
  end

  def body(schema),
    do: %RequestBody{required: true, content: %{"application/json" => %MediaType{schema: schema}}}

  def one(key, schema), do: %Schema{type: :object, properties: %{key => schema}, required: [key]}
  def many(key, schema), do: one(key, %Schema{type: :array, items: schema})
end
