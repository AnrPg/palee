defmodule Palee.Workouts.Domain.FreeTextDocument do
  @moduledoc """
  ADR-570: reads a free-text workout's editor document (TipTap JSON,
  `free_text_document`) as lines with the exercise links the coach made.

  Every text block (paragraph, heading, list item paragraph, code block) is
  one line, in document order; a hard break counts as one `\\n`. Offsets are
  counted in characters, as the editor counts them for Greek and Latin text.

  An `exerciseLink` mark ties a run of text to a catalog exercise (`ref`),
  either because the coach picked it from the suggestions or confirmed a
  match before publishing. A link with `ref: null` records a match the coach
  rejected: that text stays plain and is never asked about again in this
  workout. `checked` is the folded text a coach last confirmed for a link
  whose words no longer name its exercise, so it is asked about only once.
  """

  @mark "exerciseLink"

  @type link :: %{
          from: non_neg_integer(),
          to: non_neg_integer(),
          text: String.t(),
          ref: String.t() | nil,
          checked: String.t() | nil
        }
  @type line :: %{index: non_neg_integer(), text: String.t(), links: [link()]}

  def mark_name, do: @mark

  @doc "The document's lines (`[]` for anything that is not a document)."
  @spec lines(map() | nil) :: [line()]
  def lines(%{} = document) do
    document
    |> blocks()
    |> Enum.with_index()
    |> Enum.map(fn {inline, index} -> line(inline, index) end)
  end

  def lines(_document), do: []

  @doc "Whether a document holds any exercise link."
  def links?(document), do: document |> lines() |> Enum.any?(&(&1.links != []))

  @textblocks ["paragraph", "heading", "codeBlock"]

  defp blocks(%{"type" => type} = node) when type in @textblocks,
    do: [Enum.filter(List.wrap(node["content"]), &inline?/1)]

  defp blocks(%{"content" => content}) when is_list(content),
    do: Enum.flat_map(content, &blocks/1)

  defp blocks(_node), do: []

  defp inline?(%{"type" => type}), do: type in ["text", "hardBreak"]
  defp inline?(_node), do: false

  defp line(inline, index) do
    {pieces, _offset} =
      Enum.map_reduce(inline, 0, fn node, offset ->
        text = inline_text(node)
        length = String.length(text)

        {%{text: text, from: offset, to: offset + length, link: link_attrs(node)},
         offset + length}
      end)

    %{index: index, text: Enum.map_join(pieces, & &1.text), links: merge_links(pieces)}
  end

  defp inline_text(%{"type" => "text", "text" => text}) when is_binary(text), do: text
  defp inline_text(%{"type" => "hardBreak"}), do: "\n"
  defp inline_text(_node), do: ""

  defp link_attrs(%{"marks" => marks}) when is_list(marks) do
    Enum.find_value(marks, fn
      %{"type" => @mark} = mark ->
        attrs = Map.get(mark, "attrs") || %{}
        %{ref: blank(attrs["ref"]), checked: blank(attrs["checked"])}

      _other ->
        nil
    end)
  end

  defp link_attrs(_node), do: nil

  # Neighbouring text nodes with the same link (other marks split them) are one link.
  defp merge_links(pieces) do
    pieces
    |> Enum.reduce([], fn
      %{link: nil}, acc ->
        [:gap | acc]

      %{link: attrs} = piece, [%{} = last | rest]
      when last.ref == attrs.ref and last.to == piece.from ->
        [%{last | to: piece.to, text: last.text <> piece.text} | rest]

      %{link: attrs} = piece, acc ->
        [
          %{
            from: piece.from,
            to: piece.to,
            text: piece.text,
            ref: attrs.ref,
            checked: attrs.checked
          }
          | acc
        ]
    end)
    |> Enum.reject(&(&1 == :gap))
    |> Enum.reverse()
  end

  defp blank(value) when is_binary(value) and value != "", do: value
  defp blank(_value), do: nil
end
