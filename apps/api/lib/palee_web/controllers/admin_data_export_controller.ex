defmodule PaleeWeb.AdminDataExportController do
  @moduledoc """
  ADR-365 (CP-G5): an owner downloads a copy of all the box's data (ZIP of
  CSV files), at any time, one a day. ADR-367: plus ZIP parts with the box's
  photos and PDFs.
  """

  use PaleeWeb, :controller
  use PaleeWeb.ControllerSpecs

  alias Palee.Application.BoxDataExports
  alias OpenApiSpex.Schema

  action_fallback PaleeWeb.FallbackController

  tags(["Admin data export"])
  security([%{"bearerAuth" => []}])

  @export %Schema{
    title: "BoxDataExport",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      status: %Schema{type: :string, enum: ["pending", "ready", "failed", "expired"]},
      record_count: %Schema{type: :integer, nullable: true},
      table_count: %Schema{type: :integer, nullable: true},
      requested_at: %Schema{type: :string, format: :"date-time"},
      completed_at: %Schema{type: :string, format: :"date-time", nullable: true},
      expires_at: %Schema{type: :string, format: :"date-time", nullable: true},
      file: %Schema{
        type: :object,
        nullable: true,
        properties: %{
          name: %Schema{type: :string},
          bytes: %Schema{type: :integer},
          sha256: %Schema{type: :string},
          download_url: %Schema{type: :string, nullable: true}
        },
        required: [:bytes, :download_url, :name, :sha256]
      },
      parts: %Schema{
        type: :array,
        description: "ADR-367: ZIP parts with the box's stored files (photos, PDFs)",
        items: %Schema{
          title: "BoxDataExportPart",
          type: :object,
          properties: %{
            name: %Schema{type: :string},
            bytes: %Schema{type: :integer},
            sha256: %Schema{type: :string},
            files: %Schema{type: :integer},
            download_url: %Schema{type: :string, nullable: true}
          },
          required: [:bytes, :download_url, :files, :name, :sha256]
        }
      }
    },
    required: [
      :completed_at,
      :expires_at,
      :file,
      :id,
      :parts,
      :record_count,
      :requested_at,
      :status,
      :table_count
    ]
  }

  operation(:index,
    summary: "The box's data exports, with download links for ready files (owners)",
    responses: [
      ok:
        {"Exports", "application/json",
         %Schema{
           title: "BoxDataExports",
           type: :object,
           properties: %{exports: %Schema{type: :array, items: @export}},
           required: [:exports]
         }}
    ]
  )

  def index(conn, _params) do
    with {:ok, exports} <- BoxDataExports.list(conn.assigns.tenant_context) do
      json(conn, %{exports: exports})
    end
  end

  operation(:create,
    summary: "Ask for a copy of all the box's data (owners; one a day)",
    responses: [accepted: {"Export", "application/json", @export}]
  )

  def create(conn, _params) do
    with {:ok, export} <- BoxDataExports.request(conn.assigns.tenant_context) do
      conn |> put_status(:accepted) |> json(export)
    end
  end
end
