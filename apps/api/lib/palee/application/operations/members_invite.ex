defmodule Palee.Application.Operations.MembersInvite do
  @moduledoc """
  ADR-378 `members.invite`: emails a person the box's invitation to join as
  a member (wraps `InvitationEmails.send`, ADR-209). Palee never creates an
  account for someone: the person accepts the link themselves.
  """

  @behaviour Palee.Operations.Operation

  alias Palee.Application.InvitationEmails
  alias Palee.Application.Operations.Views

  @impl true
  def spec do
    %{
      name: "members.invite",
      kind: :command,
      summary: "Invite a person to join as a member",
      description:
        "Emails a one-time invitation to the address; the person joins the box by accepting " <>
          "it. Use it when a lead converts in another system (a CRM, a form). It sends an " <>
          "email, so send an Idempotency-Key: a retry with the same key never emails twice.",
      capability: [:invite_clients],
      scope: "members:write",
      risk: :outward,
      data_classes: [:personal],
      http: %{method: :post, path: "/members/invitations", status: 201},
      input: %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{
          "email" => %{"type" => "string", "format" => "email", "maxLength" => 254},
          "locale" => %{
            "type" => "string",
            "enum" => ["el", "en"],
            "description" => "The email's language; the box's own by default."
          }
        },
        "required" => ["email"]
      },
      output: %{
        "type" => "object",
        "properties" => %{
          "invitation_id" => Views.uuid(),
          "email" => %{"type" => "string"},
          "expires_at" => Views.date_time()
        },
        "required" => ["email", "expires_at", "invitation_id"]
      },
      examples: [%{input: %{"email" => "maria@example.com"}, output: %{}}]
    }
  end

  @impl true
  def preview(_context, input),
    do: {:ok, %{"would" => "email an invitation", "email" => input["email"], "role" => "member"}}

  @impl true
  def execute(context, input) do
    params =
      %{"intended_email" => input["email"], "role" => "member"}
      |> then(&if(input["locale"], do: Map.put(&1, "email_locale", input["locale"]), else: &1))

    with {:ok, %{invitation: invitation, address: address}} <- InvitationEmails.send(context, params) do
      {:ok,
       %{
         "invitation_id" => invitation.id,
         "email" => address,
         "expires_at" => Views.iso(invitation.expires_at)
       }}
    end
  end
end
