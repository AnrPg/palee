defmodule Palee.Channels.Domain.Templates do
  @moduledoc """
  The wording of channel messages (ADR-350 §2). Each message names a
  template `key`; the text comes from the box's own wording for the
  person's language when it has one, else from Palee's wording below,
  else from English. Placeholders are `{{name}}`; a missing value is an
  error, never an empty gap in a sent text.

  `box_message` is the free text staff type (`{{text}}`). WhatsApp only
  sends a template the provider approved (`channel_templates` rows with
  channel `whatsapp`), so it needs one per key and language.

  Marketing texts end with how to stop them (ADR-350 §3).
  """

  @locales ~w(el en)

  # key => {purpose, variables, %{locale => body}}
  @templates %{
    "box_message" =>
      {"service", ~w(box text), %{"el" => "{{box}}: {{text}}", "en" => "{{box}}: {{text}}"}},
    "class_cancelled" =>
      {"service", ~w(box class when),
       %{
         "el" => "{{box}}: Το μάθημα {{class}} στις {{when}} ακυρώθηκε. Η κράτησή σου επιστράφηκε.",
         "en" => "{{box}}: The {{class}} class on {{when}} is cancelled. Your booking was refunded."
       }},
    "class_changed" =>
      {"service", ~w(box class when),
       %{
         "el" => "{{box}}: Το μάθημα {{class}} άλλαξε ώρα: {{when}}.",
         "en" => "{{box}}: The {{class}} class has a new time: {{when}}."
       }},
    "booking_reminder" =>
      {"service", ~w(box class when),
       %{
         "el" => "{{box}}: Σε περιμένουμε στο {{class}}, {{when}}.",
         "en" => "{{box}}: See you at {{class}}, {{when}}."
       }},
    "waitlist_spot" =>
      {"service", ~w(box class when),
       %{
         "el" => "{{box}}: Άνοιξε θέση στο {{class}}, {{when}}. Είσαι μέσα.",
         "en" => "{{box}}: A spot opened in {{class}}, {{when}}. You're in."
       }},
    "payment_due" =>
      {"service", ~w(box amount date),
       %{
         "el" => "{{box}}: Υπενθύμιση πληρωμής {{amount}} έως {{date}}.",
         "en" => "{{box}}: Reminder: {{amount}} is due by {{date}}."
       }},
    "package_expiring" =>
      {"service", ~w(box package date),
       %{
         "el" => "{{box}}: Το πακέτο {{package}} λήγει στις {{date}}.",
         "en" => "{{box}}: Your {{package}} package ends on {{date}}."
       }},
    "trial_reminder" =>
      {"service", ~w(box class when),
       %{
         "el" => "{{box}}: Η δοκιμαστική σου προπόνηση είναι {{when}} ({{class}}). Τα λέμε!",
         "en" => "{{box}}: Your trial session is {{when}} ({{class}}). See you!"
       }},
    "lead_follow_up" =>
      {"marketing", ~w(box text),
       %{"el" => "{{box}}: {{text}}", "en" => "{{box}}: {{text}}"}},
    "win_back" =>
      {"marketing", ~w(box text),
       %{"el" => "{{box}}: {{text}}", "en" => "{{box}}: {{text}}"}}
  }

  @opt_out %{
    "el" => " Για διακοπή απάντησε STOP.",
    "en" => " Reply STOP to opt out."
  }

  def keys, do: @templates |> Map.keys() |> Enum.sort()
  def locales, do: @locales
  def known?(key), do: Map.has_key?(@templates, key)

  @doc "`{:ok, %{purpose, variables, bodies}}` of a built-in key, or `:error`."
  def fetch(key) do
    case Map.fetch(@templates, key) do
      {:ok, {purpose, variables, bodies}} ->
        {:ok, %{key: key, purpose: purpose, variables: variables, bodies: bodies}}

      :error ->
        :error
    end
  end

  @doc "Every built-in template, for the templates screen."
  def all, do: Enum.map(keys(), fn key -> key |> fetch() |> elem(1) end)

  @doc """
  The body for `locale`: the box's own (`overrides`, `%{locale => body}`)
  first, then Palee's, then English. `{:ok, {body, locale}}` or
  `{:error, :channel_template_missing}`.
  """
  def body(key, locale, overrides) do
    builtin =
      case fetch(key) do
        {:ok, template} -> template.bodies
        :error -> %{}
      end

    [{overrides, locale}, {builtin, locale}, {overrides, "en"}, {builtin, "en"}]
    |> Enum.find_value(fn {bodies, lang} ->
      if body = Map.get(bodies, lang), do: {:ok, {body, lang}}
    end)
    |> case do
      nil -> {:error, :channel_template_missing}
      found -> found
    end
  end

  @doc """
  Fills `{{name}}` placeholders from `variables` (string keys).
  `{:ok, text}` or `{:error, {:invalid_fields, %{variables: [...]}}}`.
  """
  def render(body, variables) do
    names = placeholders(body)
    missing = Enum.reject(names, &filled?(variables, &1))

    if missing == [] do
      {:ok,
       Regex.replace(~r/\{\{\s*([a-z_]+)\s*\}\}/, body, fn _whole, name ->
         variables |> Map.fetch!(name) |> to_string() |> String.trim()
       end)}
    else
      {:error, {:invalid_fields, %{variables: "missing_" <> Enum.join(missing, ",")}}}
    end
  end

  defp filled?(variables, name) do
    case Map.get(variables, name) do
      nil -> false
      value -> String.trim(to_string(value)) != ""
    end
  end

  @doc "The placeholder names a body uses, in order."
  def placeholders(body) do
    ~r/\{\{\s*([a-z_]+)\s*\}\}/
    |> Regex.scan(body, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
  end

  @doc "The opt-out sentence added to marketing texts."
  def opt_out(locale), do: Map.get(@opt_out, locale, @opt_out["en"])
end
