defmodule CuevolutionWeb.BracketComponents do
  @moduledoc """
  The Circuit bracket chart, shared by the public fixtures page
  (`PublicFixturesLive`) and the tournament director's chart
  (`Admin.GroupManagementLive`) so the two views of one bracket look like the
  same bracket.

  Each page builds its lanes with `build_lane/4` and renders them with
  `bracket_lane/1`, supplying only the card it wants for a match — a link for
  spectators, a button that opens score entry for the director. Everything
  about where the cards sit and how they connect lives here.

  Two layouts:

    * **One direction** — rounds left to right. The winners' and losers'
      sides, and a knockout that cannot be folded.
    * **Two-sided** — the knockout folded in half like a World Cup wall
      chart: the top half of the draw runs in from the left, the bottom half
      from the right, and they meet in the final in the middle. Scaled to fit
      the width it is given, so the whole knockout is always on screen.
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  # A card is ~92px tall; the rest is the breathing room the connectors run
  # through.
  @slot_height 112

  # ------------------------------------------------------------------ layout

  @doc """
  A lane with its geometry worked out, so templates only read:
  `%{title, side, rounds, height, links, split}`.

  `key` names the field holding each round's matches (`:matches` on the
  public page, `:fixtures` on the director's). `split` is the two-sided
  layout, or `nil` when the lane is not a knockout that folds.
  """
  def build_lane(title, side, rounds, key) do
    height = lane_height(rounds, key)

    %{
      title: title,
      side: side,
      rounds: rounds,
      height: height,
      links: lane_links(rounds, height, key),
      split: split_knockout(side, rounds, key)
    }
  end

  defp lane_height(rounds, key) do
    widest = rounds |> Enum.map(&length(Map.fetch!(&1, key))) |> Enum.max(fn -> 1 end)
    max(widest * @slot_height, @slot_height)
  end

  @doc """
  The connector run between each round and the next, as lists of
  `%{height:, merge?:}`.

  Two shapes only: a **merge**, where two cards feed one and the elbow
  brackets them together, and a **carry**, where a round feeds the next one
  for one. With `justify-around` over a fixed lane height, a link of height
  `H/n` centred in its own band lands exactly between the two cards it joins.
  """
  def lane_links(rounds, height, key) do
    rounds
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [round, next] ->
      count = length(Map.fetch!(round, key))
      next_count = length(Map.fetch!(next, key))

      cond do
        count == 0 or next_count == 0 ->
          []

        next_count * 2 == count ->
          List.duplicate(%{height: div(height, count), merge?: true}, next_count)

        true ->
          List.duplicate(%{height: 2, merge?: false}, count)
      end
    end)
  end

  # Every single-elimination round halves cleanly — R64 1-16 feed R32 1-8 and
  # on to SF 1, R64 17-32 feed SF 2 — so cutting each round down the middle
  # keeps every feed on its own side. The right-hand rounds are listed
  # final-side first, the order they are drawn in, and so are their links.
  defp split_knockout("knockout", [_, _ | _] = rounds, key) do
    {earlier, [final]} = Enum.split(rounds, -1)

    if splittable?(earlier, final, key) do
      left = Enum.map(earlier, &half(&1, :top, key))
      right = Enum.map(earlier, &half(&1, :bottom, key))
      height = lane_height(left, key)

      %{
        left: left,
        right: Enum.reverse(right),
        final: final,
        height: height,
        left_links: lane_links(left, height, key),
        right_links: right |> lane_links(height, key) |> Enum.reverse()
      }
    end
  end

  defp split_knockout(_side, _rounds, _key), do: nil

  defp splittable?(earlier, final, key) do
    length(Map.fetch!(final, key)) == 1 and
      Enum.all?(earlier, fn round ->
        count = length(Map.fetch!(round, key))
        count > 0 and rem(count, 2) == 0
      end)
  end

  defp half(round, which, key) do
    matches = Map.fetch!(round, key)
    count = div(length(matches), 2)

    Map.put(
      round,
      key,
      if(which == :top, do: Enum.take(matches, count), else: Enum.drop(matches, count))
    )
  end

  # -------------------------------------------------------------- components

  attr :lane, :map, required: true
  attr :key, :atom, required: true
  attr :id, :string, required: true

  attr :fit, :boolean,
    default: true,
    doc: "scale the two-sided knockout to the width available"

  slot :card,
    required: true,
    doc: "one match card; receives `{match, round}`"

  @doc "A lane's rounds and connectors, two-sided when the lane folds."
  def bracket_lane(%{lane: %{split: nil}} = assigns) do
    ~H"""
    <div class="flex overflow-x-auto pb-1">
      <div :for={{round, index} <- Enum.with_index(@lane.rounds)} class="flex">
        <.bracket_column round={round} key={@key} height={@lane.height}>
          <:card :let={item}>{render_slot(@card, item)}</:card>
        </.bracket_column>
        <.bracket_links
          :if={index < length(@lane.rounds) - 1}
          links={Enum.at(@lane.links, index, [])}
          height={@lane.height}
        />
      </div>
    </div>
    """
  end

  def bracket_lane(assigns) do
    ~H"""
    <%!-- The frame is measured and the board inside it scaled to fit by the
          BracketFit hook. The scale lives in a CSS variable on the frame's
          own style, which LiveView is told to leave alone, so a score update
          re-renders the cards without the chart jumping back to full size. --%>
    <div
      id={@id}
      class="bracket-fit pb-1"
      phx-hook="BracketFit"
      phx-mounted={JS.ignore_attributes(["style"])}
      data-fit={to_string(@fit)}
    >
      <div class="bracket-split" data-layout="two-sided">
        <div class="flex" data-half="top">
          <div :for={{round, index} <- Enum.with_index(@lane.split.left)} class="flex">
            <.bracket_column round={round} key={@key} height={@lane.split.height} compact>
              <:card :let={item}>{render_slot(@card, item)}</:card>
            </.bracket_column>
            <.bracket_links
              :if={index < length(@lane.split.left) - 1}
              links={Enum.at(@lane.split.left_links, index, [])}
              height={@lane.split.height}
              tight
            />
          </div>
        </div>

        <.bracket_links links={[%{height: 2, merge?: false}]} height={@lane.split.height} tight />

        <div class="flex" data-half="final">
          <.bracket_column round={@lane.split.final} key={@key} height={@lane.split.height} compact>
            <:card :let={item}>{render_slot(@card, item)}</:card>
          </.bracket_column>
        </div>

        <.bracket_links links={[%{height: 2, merge?: false}]} height={@lane.split.height} tight />

        <div class="flex" data-half="bottom">
          <div :for={{round, index} <- Enum.with_index(@lane.split.right)} class="flex">
            <.bracket_links
              :if={index > 0}
              links={Enum.at(@lane.split.right_links, index - 1, [])}
              height={@lane.split.height}
              mirrored
              tight
            />
            <.bracket_column round={round} key={@key} height={@lane.split.height} compact>
              <:card :let={item}>{render_slot(@card, item)}</:card>
            </.bracket_column>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :round, :map, required: true
  attr :key, :atom, required: true
  attr :height, :integer, required: true
  attr :compact, :boolean, default: false
  slot :card, required: true

  # One round: its heading and its cards, spaced over `height` so each card
  # sits level with the two it is fed by.
  defp bracket_column(assigns) do
    ~H"""
    <div class={[
      "flex flex-col gap-2",
      if(@compact, do: "w-[160px]", else: "min-w-[210px]")
    ]}>
      <div class="flex items-baseline justify-between gap-2">
        <span class="text-[11px] font-semibold uppercase tracking-[0.06em] text-ink-500">
          {@round.name}
        </span>
        <span :if={@round.race_to} class="text-[10px] text-ink-400">
          race to {@round.race_to}
        </span>
      </div>

      <div class="flex flex-col justify-around" style={"height:#{@height}px"}>
        <%= for item <- Map.fetch!(@round, @key) do %>
          {render_slot(@card, {item, @round})}
        <% end %>
      </div>
    </div>
    """
  end

  attr :links, :list, required: true
  attr :height, :integer, required: true
  attr :mirrored, :boolean, default: false
  attr :tight, :boolean, default: false

  # The elbows that say which two cards feed the next one. `mirrored` turns
  # them to face left, for the half of a two-sided chart that runs in from the
  # right; `tight` narrows them, since every pixel saved across the eleven
  # columns of a two-sided chart is a bigger card once it is fitted.
  defp bracket_links(assigns) do
    ~H"""
    <div
      aria-hidden="true"
      class={[
        "bracket-links",
        @mirrored && "bracket-links--mirrored",
        @tight && "bracket-links--tight"
      ]}
    >
      <div class="h-[14px]"></div>
      <div class="flex flex-col justify-around" style={"height:#{@height}px"}>
        <div :for={link <- @links} class="bracket-link" style={"height:#{link.height}px"}>
          <div :if={link.merge?} class="bracket-link__elbow"></div>
          <div :if={link.merge?} class="bracket-link__stem"></div>
          <div :if={!link.merge?} class="bracket-link__carry"></div>
        </div>
      </div>
    </div>
    """
  end

  attr :a, :map, required: true, doc: "`%{name:, score:, won?:}` for slot A"
  attr :b, :map, required: true, doc: "`%{name:, score:, won?:}` for slot B"
  attr :decided, :boolean, default: false
  attr :shade_a, :boolean, default: false, doc: "slot A came down from the winners' side"

  @doc """
  The two player lines of a card.

  Once a match is decided its winner moves to the top line, on a coloured
  background. Until then the card keeps the drawn order, and slot A is shaded
  when it holds whoever came down from the winners' side.
  """
  def bracket_slots(assigns) do
    winner_first? = assigns.decided and assigns.b.won? and not assigns.a.won?

    assigns =
      assign(assigns,
        lines:
          if(winner_first?,
            do: [{assigns.b, false}, {assigns.a, false}],
            else: [{assigns.a, assigns.shade_a and not assigns.decided}, {assigns.b, false}]
          )
      )

    ~H"""
    <%= for {{player, shaded?}, index} <- Enum.with_index(@lines) do %>
      <span :if={index == 1} class="bracket-card__rule"></span>
      <span class={[
        "bracket-card__slot",
        @decided && player.won? && "bracket-card__slot--winner",
        shaded? && "bracket-card__slot--dropped"
      ]}>
        <span class={[
          "bracket-card__name",
          player.won? && "bracket-card__name--won",
          @decided && !player.won? && "bracket-card__name--beaten"
        ]}>
          {player.name || "—"}
        </span>
        <span class="bracket-card__score">{player.score}</span>
      </span>
    <% end %>
    """
  end
end
