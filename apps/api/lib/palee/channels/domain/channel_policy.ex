defmodule Palee.Channels.Domain.ChannelPolicy do
  @moduledoc """
  Which channel a message may go through (ADR-348 §3, ADR-350).

  A message is sent only through a channel that:

    * the box has connected and switched on (`connection.channels`);
    * the person has agreed to for this purpose: `service` (about their
      bookings, classes and payments) or `marketing` (offers, win-back,
      lead follow-ups). Marketing consent never implies service consent
      and the other way round;
    * the person has not stopped (a STOP reply stops every channel);
    * for WhatsApp, has a template the provider approved for the message
      in the person's language (Meta only lets a business start a
      conversation with an approved template).

  Channels are tried in the caller's order, else the box's
  `channel_order`. Push stays first everywhere (CP-C3): callers send SMS,
  Viber or WhatsApp only when push is not enough.
  """

  @channels ~w(sms viber whatsapp)
  @purposes ~w(service marketing)
  @sources ~w(staff automation system)
  @consent_sources ~w(person staff form import stop_keyword)

  def channels, do: @channels
  def purposes, do: @purposes
  def sources, do: @sources
  def consent_sources, do: @consent_sources

  @doc """
  The first channel the message may go through: `{:ok, channel}` or
  `{:error, reason}` with the reason of the last refused channel:
  `:channel_not_enabled`, `:channel_opted_out`, `:channel_consent_missing`
  or `:whatsapp_template_missing`.

  `facts`: `connection` (`channels`, `channel_order`), `contact`
  (`opted_out_at`), `consents` (`[%{channel, purpose, granted_at,
  withdrawn_at}]`), `purpose`, `preferred` (a list or nil) and
  `whatsapp_template?` (whether an approved template exists).
  """
  def choose(facts) do
    order = facts.preferred || facts.connection.channel_order || @channels

    order
    |> Enum.filter(&(&1 in @channels))
    |> Enum.uniq()
    |> Enum.reduce_while({:error, :channel_not_enabled}, fn channel, last ->
      case allowed(channel, facts) do
        :ok -> {:halt, {:ok, channel}}
        {:error, reason} -> {:cont, worst(last, {:error, reason})}
      end
    end)
  end

  # The most telling reason wins: consent problems before "not switched on".
  @rank %{
    channel_not_enabled: 0,
    whatsapp_template_missing: 1,
    channel_consent_missing: 2,
    channel_opted_out: 3
  }

  defp worst({:error, a}, {:error, b}),
    do: if(Map.fetch!(@rank, b) >= Map.fetch!(@rank, a), do: {:error, b}, else: {:error, a})

  @doc "`:ok` or `{:error, reason}` for one channel (see `choose/1`)."
  def allowed(channel, facts) do
    cond do
      channel not in (facts.connection.channels || []) ->
        {:error, :channel_not_enabled}

      not is_nil(facts.contact.opted_out_at) ->
        {:error, :channel_opted_out}

      not consented?(facts.consents, channel, facts.purpose) ->
        {:error, :channel_consent_missing}

      channel == "whatsapp" and not facts.whatsapp_template? ->
        {:error, :whatsapp_template_missing}

      true ->
        :ok
    end
  end

  @doc "Whether the consents hold a current one for `channel` and `purpose`."
  def consented?(consents, channel, purpose) do
    Enum.any?(consents, fn consent ->
      consent.channel == channel and consent.purpose == purpose and
        granted?(consent)
    end)
  end

  @doc "A consent is current when granted after its last withdrawal."
  def granted?(%{granted_at: nil}), do: false
  def granted?(%{withdrawn_at: nil}), do: true

  def granted?(%{granted_at: granted, withdrawn_at: withdrawn}),
    do: DateTime.compare(granted, withdrawn) == :gt

  # STOP words in the languages of Palee's boxes, compared without accents
  # and case. A reply that is only one of these words stops every channel.
  @stop_words ~w(STOP STOPALL UNSUBSCRIBE CANCEL END QUIT ARRET ARRÊT ALTO BASTA
                 ΣΤΟΠ ΣΤΑΜΑΤΑ ΔΙΑΚΟΠΗ ΑΠΕΓΓΡΑΦΗ ΑΚΥΡΩΣΗ)

  @doc "Whether an inbound text asks to stop messages."
  def stop_keyword?(text) when is_binary(text) do
    folded = fold(text)
    folded = String.replace(folded, ~r/[^\p{L}]/u, "")
    Enum.any?(@stop_words, &(fold(&1) == folded))
  end

  def stop_keyword?(_text), do: false

  @doc false
  def fold(text) do
    text
    |> String.trim()
    |> String.upcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
  end
end
