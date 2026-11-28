defmodule Palee.Finance.Domain.CleanupRecordFilter do
  @moduledoc """
  ADR-797: the filters and pages of «Εκκαθάριση συναλλαγών» as pure data.

  A filter is built once from the request (`new/1`) and read by the store:

    * `q`: free text. The store matches it against a document's number and
      the record id; the application adds `customer_ids`, the people whose
      name, @handle or email match it, so one field finds all three;
    * `user_id`: one customer (the «Πελάτης» filter);
    * `package_id`: records of one package, inactive packages included;
    * `from` / `to`: inclusive dates, on the issue date of a document or the
      paid date of a payment;
    * `kind`: `invoice`, `receipt` or `payment` (nil = all);
    * `cursor` / `limit`: keyset pages, newest first.

  The cursor is the opaque, URL-safe sort key `{inserted_at, id}` of the
  last record on a page. Ties on the same instant break on `id`, so a page
  never repeats or skips a record, also while records are added or purged.
  """

  @kinds ~w(invoice receipt payment)
  @default_limit 30
  @max_limit 100

  defstruct q: nil,
            customer_ids: [],
            user_id: nil,
            package_id: nil,
            from: nil,
            to: nil,
            kind: nil,
            cursor: nil,
            limit: @default_limit

  @type t :: %__MODULE__{}

  def kinds, do: @kinds

  @doc "A filter from request params (string or atom keys). Invalid values are dropped."
  def new(params) when is_map(params) do
    %__MODULE__{
      q: text(value(params, :q) || value(params, :search)),
      user_id: uuid(value(params, :user_id)),
      package_id: uuid(value(params, :package_id)),
      from: date(value(params, :from)),
      to: date(value(params, :to)),
      kind: kind(value(params, :kind)),
      cursor: decode_cursor(value(params, :cursor)),
      limit: limit(value(params, :limit))
    }
  end

  def new(_params), do: new(%{})

  @doc "The people the free text matched by name or email (resolved outside finance)."
  def with_customer_ids(%__MODULE__{} = filter, ids) when is_list(ids),
    do: %{filter | customer_ids: Enum.uniq(ids)}

  @doc "Whether the filter can only match payments, or only documents."
  def wants?(%__MODULE__{kind: nil}, _table), do: true
  def wants?(%__MODULE__{kind: "payment"}, table), do: table == :payment
  def wants?(%__MODULE__{kind: _document}, table), do: table == :document

  @doc """
  Merges the newest-first rows of both tables (each fetched with
  `limit + 1`) into one page: `%{records, next_cursor}`.
  """
  def page(%__MODULE__{limit: limit}, rows) do
    sorted = Enum.sort(rows, &newer?/2)
    {records, rest} = Enum.split(sorted, limit)

    next_cursor =
      case {rest, List.last(records)} do
        {[], _last} -> nil
        {_more, nil} -> nil
        {_more, last} -> encode_cursor(last.inserted_at, last.id)
      end

    %{records: records, next_cursor: next_cursor}
  end

  @doc "Newest first; on the same instant the larger id first (as in SQL)."
  def newer?(a, b) do
    case DateTime.compare(a.inserted_at, b.inserted_at) do
      :gt -> true
      :lt -> false
      :eq -> a.id >= b.id
    end
  end

  def encode_cursor(%DateTime{} = at, id) when is_binary(id) do
    Base.url_encode64("#{DateTime.to_iso8601(at)}|#{id}", padding: false)
  end

  def decode_cursor(value) when is_binary(value) and value != "" do
    with {:ok, raw} <- Base.url_decode64(value, padding: false),
         [at, id] <- String.split(raw, "|", parts: 2),
         {:ok, at, _offset} <- DateTime.from_iso8601(at),
         id when is_binary(id) <- uuid(id) do
      {at, id}
    else
      _invalid -> nil
    end
  end

  def decode_cursor(_value), do: nil

  defp value(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))

  defp text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> String.slice(trimmed, 0, 120)
    end
  end

  defp text(_value), do: nil

  defp uuid(value) when is_binary(value) do
    case Ecto.UUID.cast(String.trim(value)) do
      {:ok, id} -> id
      :error -> nil
    end
  end

  defp uuid(_value), do: nil

  defp date(%Date{} = date), do: date

  defp date(value) when is_binary(value) do
    case Date.from_iso8601(String.trim(value)) do
      {:ok, date} -> date
      _invalid -> nil
    end
  end

  defp date(_value), do: nil

  defp kind(value) when value in @kinds, do: value
  defp kind(_value), do: nil

  defp limit(value) when is_integer(value), do: value |> max(1) |> min(@max_limit)

  defp limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> limit(number)
      _invalid -> @default_limit
    end
  end

  defp limit(_value), do: @default_limit
end
