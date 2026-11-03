defmodule PaleeWeb.CoachPayFiles do
  @moduledoc "Sends a coach pay statement PDF as a download (ADR-382)."

  import Phoenix.Controller, only: [send_download: 3]

  def send_pdf(conn, %{content: content, content_type: content_type, filename: filename}),
    do:
      send_download(conn, {:binary, content},
        filename: filename,
        content_type: content_type,
        disposition: :attachment
      )
end
