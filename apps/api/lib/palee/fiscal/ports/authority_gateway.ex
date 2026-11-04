defmodule Palee.Fiscal.Ports.AuthorityGateway do
  @moduledoc """
  Reports fiscal documents to a tax authority (ADR-243). One adapter per
  channel: `Sandbox` (no network, for pilots and tests), `MyData` (AADE's
  REST API as an ERP), later a certified provider.

  `connection` is the organization's authority connection with its
  decrypted credentials (`%{environment, user_id, subscription_key}`).
  `invoices` are element trees of `Fiscal.Domain.MyDataInvoice.build/2`,
  sent together (ADR-530); the results come back in the same order.

  Errors:
    * `{:rejected, [%{code, message}]}` – the authority refused the content;
    * `{:duplicate, [%{code, message}]}` – the authority already has this
      document (a lost answer to an earlier attempt): look it up with
      `find/2` (ADR-530);
    * `{:unauthorized, reason}` – the credentials were refused;
    * anything else is transient (network, timeout, 5xx, technical error).

  A document is never cancelled at the authority: it is corrected with a
  credit note, which is reported like any other document (ADR-241).

  Every call also returns what went over the wire, for the attempt log:
  `%{request_body, request_bodies, response_status, response_body}`, where
  `request_bodies` holds each invoice's own `InvoicesDoc` in order.
  """

  @type connection :: %{
          required(:environment) => String.t(),
          optional(:user_id) => String.t() | nil,
          optional(:subscription_key) => String.t() | nil
        }
  @type receipt :: %{
          mark: String.t(),
          uid: String.t() | nil,
          authentication_code: String.t() | nil,
          qr_url: String.t() | nil
        }
  @type wire :: %{
          optional(:request_bodies) => [String.t()],
          request_body: String.t() | nil,
          response_status: non_neg_integer() | nil,
          response_body: String.t() | nil
        }

  @type result :: {:ok, receipt()} | {:error, term()}

  @type document_key :: %{
          issuer_vat: String.t(),
          series: String.t(),
          aa: String.t(),
          issue_date: Date.t(),
          invoice_type: String.t()
        }

  @callback submit(connection(), invoices :: [list()]) :: {[result()], wire()}

  @doc """
  ADR-530: the receipt of a document the authority already registered,
  found by its keys. `:not_found` when it has none; errors as `check/1`.
  Used before resending after an attempt whose answer was lost, and when
  the authority answers "duplicate".
  """
  @callback find(connection(), document_key()) :: {:ok, receipt()} | :not_found | {:error, term()}

  @doc """
  «Δοκιμή σύνδεσης» (ADR-273): asks the authority something harmless with
  the connection's credentials (nothing is reported). `{:ok, %{}}`, or the
  same errors as `submit/2` (`{:unauthorized, _}` for refused
  credentials, anything else transient).
  """
  @callback check(connection()) :: {:ok, map()} | {:error, term()}
end
