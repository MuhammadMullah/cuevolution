defmodule CuevolutionWeb.AdminComponents do
  @moduledoc """
  UI primitives for the admin console, built directly from the shipped
  design mockup (`project-scope/Quevolution/Cuevolution Admin.dc.html`).

  Kept entirely separate from `CuevolutionWeb.PlayerComponents` (and
  `CoreComponents`) — the admin console has its own dark sidebar shell and
  visual language, distinct from the player app's light guest/app shells,
  even though both draw from the same `ink-*`/`red-*` design tokens.
  """

  use Phoenix.Component
  use CuevolutionWeb, :verified_routes

  alias Phoenix.LiveView.JS

  @doc "The small uppercase mono label used above page/section titles."
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def eyebrow(assigns) do
    ~H"""
    <div class={[
      "font-mono text-[11px] font-medium uppercase tracking-[0.14em] text-red-600",
      @class
    ]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  The dark, centered card shell used by the admin sign-in page — visually
  distinct from the authenticated `app_shell/1` on purpose (mirrors the
  mockup's "restricted access, separate from player accounts" framing).
  """
  attr :flash, :map, required: true
  slot :inner_block, required: true

  def guest_shell(assigns) do
    ~H"""
    <div class="flex min-h-screen items-center justify-center bg-ink-950 p-6 font-sans antialiased">
      <.admin_flash_group flash={@flash} />
      <div class="w-full max-w-[400px]">
        <div class="mb-7 text-center">
          <img
            src={~p"/images/cuevolution-logo-white.png"}
            class="mx-auto mb-3.5 h-7 w-auto"
            alt="Cuevolution"
          />
          <div class="font-mono text-xs font-medium tracking-[0.12em] text-ink-400">
            admin.sportpesapool.ke
          </div>
        </div>
        <div class="rounded-[20px] border border-[#2a2942] bg-ink-900 p-6 shadow-[0_20px_60px_rgba(0,0,0,0.35)] sm:p-9">
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  @nav_items [
    {"Dashboard", "▦", "/admin/dashboard"},
    {"Stages", "◆", "/admin/stages"},
    {"Groups", "▤", "/admin/groups"},
    {"Draws", "⚏", "/admin/draws"},
    {"Results & Points", "◔", "/admin/results"},
    {"Directory", "☰", "/admin/players"},
    {"Venues", "⚑", "/admin/venues"}
  ]

  @doc """
  The admin app shell: dark sidebar (nav + admin identity/logout) plus a
  light main content area, wrapping page content. Mirrors the mockup's
  "ADMIN APP SHELL" section, including its mobile topbar + drawer.
  """
  attr :current_admin, :map, required: true

  attr :active, :atom,
    required: true,
    doc:
      "one of :dashboard, :stages, :groups, :draws, :results, :directory, :venues, :notifications, :admins"

  attr :flash, :map, required: true
  slot :inner_block, required: true

  def app_shell(assigns) do
    assigns = assign(assigns, :nav_items, nav_items_for(assigns.current_admin))

    ~H"""
    <div class="flex min-h-screen flex-col bg-ink-25 font-sans antialiased lg:flex-row">
      <.admin_flash_group flash={@flash} />

      <div class="sticky top-0 z-30 flex h-14 w-full items-center justify-between bg-ink-950 px-4 lg:hidden">
        <div class="flex items-center gap-2.5">
          <button
            type="button"
            phx-click={JS.toggle(to: "#admin-drawer-backdrop") |> JS.toggle(to: "#admin-sidebar")}
            class="flex size-[34px] cursor-pointer items-center justify-center rounded-[9px] bg-white/10 text-white"
          >
            ☰
          </button>
          <img src={~p"/images/cuevolution-logo-white.png"} class="h-[18px] w-auto" alt="Cuevolution" />
        </div>
        <div class="flex size-8 items-center justify-center rounded-full bg-red-500 text-xs font-semibold text-white">
          {admin_initials(@current_admin)}
        </div>
      </div>

      <div
        id="admin-drawer-backdrop"
        phx-click={JS.hide(to: "#admin-drawer-backdrop") |> JS.hide(to: "#admin-sidebar")}
        class="fixed inset-0 z-[39] hidden bg-ink-950/50 lg:hidden"
      >
      </div>

      <aside
        id="admin-sidebar"
        class="fixed inset-y-0 left-0 z-40 hidden w-[260px] flex-col bg-ink-950 lg:sticky lg:top-0 lg:flex lg:h-screen"
      >
        <div class="hidden items-center gap-2.5 px-[22px] pb-[26px] pt-[22px] lg:flex">
          <img src={~p"/images/cuevolution-logo-white.png"} class="h-[22px] w-auto" alt="Cuevolution" />
        </div>
        <div class="px-3.5 pb-3.5 font-mono text-[10.5px] font-medium uppercase tracking-[0.12em] text-ink-500">
          Admin console
        </div>
        <nav class="flex flex-1 flex-col gap-0.5 px-2.5">
          <.nav_item
            :for={{label, icon, path} <- @nav_items}
            label={label}
            icon={icon}
            path={path}
            active={nav_active?(@active, path)}
          />
        </nav>
        <div class="border-t border-[#221f3b] p-3.5">
          <div class="flex items-center gap-2.5 px-2.5 py-2">
            <div class="flex size-8 shrink-0 items-center justify-center rounded-full bg-red-500 text-xs font-semibold text-white">
              {admin_initials(@current_admin)}
            </div>
            <div class="min-w-0 flex-1">
              <div class="truncate text-[13.5px] font-semibold text-ink-25">
                {@current_admin.email}
              </div>
              <div class="text-xs text-ink-500">Circuit Admin</div>
            </div>
          </div>
          <.link
            href={~p"/admin/logout"}
            method="delete"
            class="flex items-center gap-2 rounded-[9px] px-2.5 py-2.5 text-[13.5px] font-semibold text-red-300 hover:bg-red-500/15"
          >
            <span>⏻</span>Log out
          </.link>
        </div>
      </aside>

      <main class="min-w-0 flex-1 p-[18px] sm:p-6 lg:p-9">
        {render_slot(@inner_block)}
      </main>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :icon, :string, required: true
  attr :path, :string, required: true
  attr :active, :boolean, required: true

  defp nav_item(assigns) do
    ~H"""
    <.link
      navigate={@path}
      class={[
        "flex items-center gap-2.5 rounded-[10px] px-3 py-2.5 text-sm font-semibold",
        @active && "bg-red-500/15 text-red-300",
        !@active && "text-ink-400 hover:bg-white/5 hover:text-ink-25"
      ]}
    >
      <span class="w-[18px] flex-none text-center">{@icon}</span>{@label}
    </.link>
    """
  end

  defp nav_active?(active, "/admin/dashboard"), do: active == :dashboard
  defp nav_active?(active, "/admin/stages"), do: active == :stages
  defp nav_active?(active, "/admin/groups"), do: active == :groups
  defp nav_active?(active, "/admin/draws"), do: active == :draws
  defp nav_active?(active, "/admin/results"), do: active == :results
  defp nav_active?(active, "/admin/players"), do: active == :directory
  defp nav_active?(active, "/admin/venues"), do: active == :venues
  defp nav_active?(active, "/admin/admins"), do: active == :admins

  defp nav_items_for(%{role: "super_admin"}), do: @nav_items ++ [{"Admins", "☺", "/admin/admins"}]
  defp nav_items_for(_current_admin), do: @nav_items

  defp admin_initials(%{email: email}) do
    email
    |> String.split(["@", "."])
    |> List.first("")
    |> String.slice(0, 2)
    |> String.upcase()
  end

  @doc "A single dashboard stat tile."
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :delta, :string, default: nil
  attr :delta_class, :string, default: "text-ink-500"

  def stat_tile(assigns) do
    ~H"""
    <div class="rounded-2xl border border-ink-200 bg-white px-5 py-[18px] shadow-[0_1px_2px_rgba(13,12,34,0.05)]">
      <div class="mb-2 text-[12.5px] text-ink-500">{@label}</div>
      <div class="font-mono text-[26px] font-semibold text-ink-950">{@value}</div>
      <div :if={@delta} class={["mt-1 text-[12.5px]", @delta_class]}>{@delta}</div>
    </div>
    """
  end

  @doc "The card wrapper used throughout the admin console (dashboard panels, tables, forms)."
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <div class={[
      "rounded-2xl border border-ink-200 bg-white p-5 shadow-[0_1px_2px_rgba(13,12,34,0.05)] sm:p-[22px]",
      @class
    ]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  A live-search text field for the Draws page's participant/venue pickers —
  typing filters `suggestions` (server-computed) into a dropdown; clicking
  one fires `select_field`, pressing Enter accepts the top one. Both typing
  and Enter go through a single `phx-keyup` binding (deliberately no
  `phx-keydown`/`phx-key` pair here — LiveView's key-match filter and its
  per-element debounce cycle are both scoped to the *element*, not the
  binding, so a second keyed binding on the same input silently starves
  whichever one fires first; see the "Enter never fired" bug this replaced).
  Purely a UI primitive: the owning LiveView computes suggestions and
  interprets the resulting `*_id`/`*_kind`.

  The dropdown is `position: fixed`, positioned by JS off the input's own
  `getBoundingClientRect()` (see `.AdminFieldSuggestionsPosition` below) —
  it lives inside a fixture-entry table row wrapped in an
  `overflow-x-auto` scroller (needed for the table's horizontal scroll on
  narrow screens), and a plain `position: absolute` dropdown gets clipped
  by that scroller's implied `overflow-y: auto` (CSS's overflow-x/-y are
  coupled: setting one axis to a non-`visible` value forces the other away
  from `visible` too) instead of floating over the rest of the page.
  """
  attr :row_id, :integer, required: true
  attr :field, :string, required: true, doc: "one of \"a\", \"b\", \"venue\""
  attr :value, :string, required: true
  attr :placeholder, :string, required: true
  attr :confirmed, :boolean, default: false, doc: "true once a suggestion has been accepted"
  attr :suggestions, :list, required: true

  def field_search(assigns) do
    ~H"""
    <div>
      <input
        id={"draw-row-#{@row_id}-#{@field}"}
        type="text"
        value={@value}
        placeholder={@placeholder}
        autocomplete="off"
        phx-keyup="field_keyup"
        phx-value-row={@row_id}
        phx-value-field={@field}
        class={[
          "w-full rounded-lg border bg-white px-2.5 py-2 text-[13.5px] text-ink-950 focus:outline-none",
          @confirmed && "border-green-300 focus:border-green-500",
          !@confirmed && "border-ink-300 focus:border-red-500"
        ]}
      />
      <div
        :if={@suggestions != []}
        id={"draw-row-#{@row_id}-#{@field}-suggestions"}
        phx-hook=".AdminFieldSuggestionsPosition"
        class="fixed z-30 max-h-56 overflow-y-auto rounded-lg border border-ink-200 bg-white shadow-lg"
      >
        <button
          :for={s <- @suggestions}
          type="button"
          phx-click="select_field"
          phx-value-row={@row_id}
          phx-value-field={@field}
          phx-value-id={s.id}
          phx-value-name={s.name}
          phx-value-kind={s.kind}
          class="block w-full px-2.5 py-1.5 text-left text-[13px] hover:bg-ink-50"
        >
          <span class="font-medium text-ink-950">{s.name}</span>
          <span class="ml-1 text-ink-400">{s.sub}</span>
        </button>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".AdminFieldSuggestionsPosition">
        export default {
          mounted() {
            this.reposition = () => {
              const input = this.el.previousElementSibling
              if (!input) return
              const rect = input.getBoundingClientRect()
              this.el.style.left = `${rect.left}px`
              this.el.style.top = `${rect.bottom + 4}px`
              this.el.style.width = `${rect.width}px`
            }
            this.reposition()
            window.addEventListener("scroll", this.reposition, true)
            window.addEventListener("resize", this.reposition)
          },
          updated() {
            this.reposition()
          },
          destroyed() {
            window.removeEventListener("scroll", this.reposition, true)
            window.removeEventListener("resize", this.reposition)
          }
        }
      </script>
    </div>
    """
  end

  @doc """
  A date input styled to match the design. Relies on the browser's own
  calendar glyph (rendered by every evergreen browser for `type="date"`,
  so there's no need to fake one with an overlay — a hidden-native +
  custom-SVG overlay was tried and dropped because hiding
  `::-webkit-calendar-picker-indicator` behaves inconsistently across
  Chrome builds and risked showing both icons at once). The `showPicker()`
  hook widens the click target to the whole field, not just the icon.
  """
  attr :name, :string, required: true
  attr :id, :string, required: true
  attr :value, :string, default: ""
  attr :class, :string, default: nil

  def date_field(assigns) do
    ~H"""
    <input
      type="date"
      id={@id}
      name={@name}
      value={@value}
      phx-hook=".AdminDatePicker"
      class={[
        "w-full cursor-pointer rounded-lg border border-ink-300 bg-white px-2.5 py-2 text-[13px] text-ink-950",
        @class
      ]}
    />
    <script :type={Phoenix.LiveView.ColocatedHook} name=".AdminDatePicker">
      export default {
        mounted() {
          this.onClick = () => {
            if (typeof this.el.showPicker === "function") {
              try {
                this.el.showPicker()
              } catch (_error) {
                // no-op — e.g. picker already open, or unsupported in this state
              }
            }
          }
          this.el.addEventListener("click", this.onClick)
        },
        destroyed() {
          this.el.removeEventListener("click", this.onClick)
        }
      }
    </script>
    """
  end

  @doc "A 30-minute-interval time picker (design calls for fixed slots, not a free-text native time input)."
  attr :name, :string, required: true
  attr :id, :string, required: true
  attr :value, :string, default: ""
  attr :class, :string, default: nil

  def time_select(assigns) do
    assigns = assign(assigns, :options, time_options())

    ~H"""
    <div class="relative">
      <svg
        class="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-ink-400"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      >
        <circle cx="12" cy="12" r="9" />
        <path d="M12 7v5l3 3" />
      </svg>
      <select
        id={@id}
        name={@name}
        class={[
          "w-full cursor-pointer rounded-lg border border-ink-300 bg-white py-2 pl-8 pr-2.5 text-[13px] text-ink-950",
          @class
        ]}
      >
        <option value="" selected={@value in [nil, ""]}>--:--</option>
        <option :for={t <- @options} value={t} selected={t == @value}>{t}</option>
      </select>
    </div>
    """
  end

  defp time_options do
    for h <- 0..23, m <- [0, 30] do
      hh = String.pad_leading(Integer.to_string(h), 2, "0")
      mm = String.pad_leading(Integer.to_string(m), 2, "0")
      "#{hh}:#{mm}"
    end
  end

  attr :id, :string, default: "admin-flash-group"
  attr :flash, :map, required: true

  defp admin_flash_group(assigns) do
    ~H"""
    <div
      id={@id}
      aria-live="polite"
      class="fixed inset-x-0 top-0 z-50 flex flex-col items-center gap-2 p-4 sm:items-end"
    >
      <.admin_flash kind={:info} flash={@flash} />
      <.admin_flash kind={:error} flash={@flash} />
    </div>
    """
  end

  attr :id, :string, doc: "the optional id of the flash container"
  attr :flash, :map, required: true
  attr :kind, :atom, values: [:info, :error], required: true

  defp admin_flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "admin-flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-hook=".AdminAutoDismissFlash"
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> fade_out("##{@id}")}
      role="alert"
      class={[
        "w-full max-w-sm rounded-2xl border px-4 py-3 text-sm font-medium shadow-md sm:w-96",
        @kind == :info && "border-green-100 bg-green-50 text-green-700",
        @kind == :error && "border-red-100 bg-red-50 text-red-700"
      ]}
    >
      {msg}
      <script :type={Phoenix.LiveView.ColocatedHook} name=".AdminAutoDismissFlash">
        export default {
          mounted() {
            this.timer = setTimeout(() => this.el.click(), 4000)
          },
          destroyed() {
            clearTimeout(this.timer)
          }
        }
      </script>
    </div>
    """
  end

  @doc "Fades an element out over 1s, then hides it — used to auto-dismiss flashes."
  def fade_out(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 1000,
      transition: {"transition-opacity ease-out duration-1000", "opacity-100", "opacity-0"}
    )
  end
end
