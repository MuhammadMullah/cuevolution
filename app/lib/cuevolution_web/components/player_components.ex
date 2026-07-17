defmodule CuevolutionWeb.PlayerComponents do
  @moduledoc """
  UI primitives for the player-facing app, built directly from the shipped
  design mockup (`project-scope/Quevolution/Cuevolution Design System.dc.html`
  and `Cuevolution Player App - standalone-src.dc.html`) — not from
  `project-scope/design/tokens.css`, which is an earlier draft superseded by
  the "Kenya Red / Kenya Green" direction (see assets/css/app.css for the
  full explanation).

  Kept entirely separate from `CuevolutionWeb.CoreComponents` so the admin
  console (out of scope for this pass) is untouched.
  """

  use Phoenix.Component
  use CuevolutionWeb, :verified_routes

  alias Cuevolution.Accounts.ProfilePicture
  alias Phoenix.HTML.Form
  alias Phoenix.HTML.FormField
  alias Phoenix.LiveView.JS

  import CuevolutionWeb.CoreComponents, only: [icon: 1]

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
  Renders a pill-shaped button, matching the mockup's CTA style.

  ## Examples

      <.button variant="primary">Sign in</.button>
      <.button variant="secondary" navigate={~p"/"}>Back</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled form)
  attr :class, :any, default: nil
  attr :variant, :string, values: ~w(primary secondary ghost cta cta-outline), default: "primary"
  attr :full_width, :boolean, default: false
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{
      "primary" => "bg-ink-950 text-ink-25 hover:bg-ink-900",
      "secondary" => "bg-white text-ink-950 border border-ink-300 hover:bg-ink-100",
      "ghost" => "bg-transparent text-ink-500 hover:text-red-700 hover:bg-red-50",
      "cta" => "bg-red-500 text-white hover:bg-red-600",
      "cta-outline" => "bg-transparent text-white border border-white/30 hover:bg-white/10"
    }

    assigns =
      assign(assigns, :class, [
        "inline-flex items-center justify-center gap-2 rounded-full px-6 py-3 font-sans text-sm font-semibold",
        "transition-all duration-150 ease-out cursor-pointer",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-red-500 focus-visible:ring-offset-2",
        "disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none",
        Map.fetch!(variants, assigns.variant),
        assigns.full_width && "w-full",
        assigns.class
      ])

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders a form input styled per the design mockup — mirrors
  `CuevolutionWeb.CoreComponents.input/1`'s API (field/name/label/type/
  errors/options/prompt) so it's a drop-in replacement inside player forms.
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(color date datetime-local email month number password
               search select tel text textarea time url week)

  attr :field, FormField, doc: "a form field struct retrieved from the form, e.g. @form[:email]"
  attr :errors, :list, default: []
  attr :prompt, :string, default: nil
  attr :options, :list, doc: "options for a select input"
  attr :multiple, :boolean, default: false
  attr :hint, :string, default: nil, doc: "small helper text shown below the input"

  attr :hint_variant, :string,
    default: "neutral",
    values: ~w(neutral success danger),
    doc: "color of the hint text — e.g. green for \"available\", red for \"already taken\""

  attr :class, :any, default: nil

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %FormField{} = field} = assigns) do
    # `used_input?/1` alone is unreliable here: in real browser testing it can
    # stay false for a field that was clearly typed into (e.g. password),
    # silently hiding a validation error the server has already computed.
    # Callers like RegistrationLive already scope `field.errors` down to
    # touched fields before building the form, so trust a non-empty error
    # list on its own rather than gating everything on `used_input?/1`.
    errors =
      if field.errors != [] or Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &CuevolutionWeb.CoreComponents.translate_error/1))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="mb-4">
      <label :if={@label} for={@id} class="mb-1.5 block text-sm font-semibold text-ink-700">
        {@label}
      </label>
      <select
        id={@id}
        name={@name}
        class={[
          "w-full cursor-pointer rounded-md border bg-white px-3.5 py-2.5 font-sans text-[15px] text-ink-950",
          "focus:border-red-500 focus:outline-none focus:ring-4 focus:ring-red-500/15",
          @errors == [] && "border-ink-300",
          @errors != [] && "border-danger",
          @class
        ]}
        multiple={@multiple}
        {@rest}
      >
        <option :if={@prompt} value="">{@prompt}</option>
        {Form.options_for_select(@options, @value)}
      </select>
      <.field_error :for={msg <- @errors}>{msg}</.field_error>
      <p
        :if={@hint && @errors == []}
        class={["mt-1.5 font-mono text-[12.5px]", hint_class(@hint_variant)]}
      >
        {@hint}
      </p>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="mb-4">
      <label :if={@label} for={@id} class="mb-1.5 block text-sm font-semibold text-ink-700">
        {@label}
      </label>
      <textarea
        id={@id}
        name={@name}
        class={[
          "w-full rounded-md border bg-white px-3.5 py-2.5 font-sans text-[15px] text-ink-950",
          "focus:border-red-500 focus:outline-none focus:ring-4 focus:ring-red-500/15",
          @errors == [] && "border-ink-300",
          @errors != [] && "border-danger",
          @class
        ]}
        {@rest}
      >{Form.normalize_value("textarea", @value)}</textarea>
      <.field_error :for={msg <- @errors}>{msg}</.field_error>
      <p
        :if={@hint && @errors == []}
        class={["mt-1.5 font-mono text-[12.5px]", hint_class(@hint_variant)]}
      >
        {@hint}
      </p>
    </div>
    """
  end

  def input(%{type: "password"} = assigns) do
    ~H"""
    <div class="mb-4">
      <label :if={@label} for={@id} class="mb-1.5 block text-sm font-semibold text-ink-700">
        {@label}
      </label>
      <div class="relative" phx-hook=".PasswordToggle" id={"#{@id}-toggle"}>
        <input
          type="password"
          name={@name}
          id={@id}
          value={Form.normalize_value(@type, @value)}
          class={[
            "w-full rounded-md border bg-white px-3.5 py-2.5 pr-11 font-sans text-[15px] text-ink-950 placeholder:text-ink-500",
            "focus:border-red-500 focus:outline-none focus:ring-4 focus:ring-red-500/15",
            @errors == [] && "border-ink-300",
            @errors != [] && "border-danger",
            @class
          ]}
          {@rest}
        />
        <button
          type="button"
          class="absolute inset-y-0 right-0 flex w-10 items-center justify-center text-ink-400 hover:text-ink-600 cursor-pointer"
          aria-label="Show password"
        >
          <.icon name="hero-eye" class="password-toggle-show size-5" />
          <.icon name="hero-eye-slash" class="password-toggle-hide hidden size-5" />
        </button>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".PasswordToggle">
          export default {
            mounted() {
              const input = this.el.querySelector("input")
              const button = this.el.querySelector("button")
              const showIcon = this.el.querySelector(".password-toggle-show")
              const hideIcon = this.el.querySelector(".password-toggle-hide")
              this.onClick = () => {
                const revealing = input.type === "password"
                input.type = revealing ? "text" : "password"
                showIcon.classList.toggle("hidden", revealing)
                hideIcon.classList.toggle("hidden", !revealing)
                button.setAttribute("aria-label", revealing ? "Hide password" : "Show password")
              }
              button.addEventListener("click", this.onClick)
            },
            destroyed() {
              this.el.querySelector("button").removeEventListener("click", this.onClick)
            }
          }
        </script>
      </div>
      <.field_error :for={msg <- @errors}>{msg}</.field_error>
      <p
        :if={@hint && @errors == []}
        class={["mt-1.5 font-mono text-[12.5px]", hint_class(@hint_variant)]}
      >
        {@hint}
      </p>
    </div>
    """
  end

  def input(%{type: "date"} = assigns) do
    ~H"""
    <div class="mb-4">
      <label :if={@label} for={@id} class="mb-1.5 block text-sm font-semibold text-ink-700">
        {@label}
      </label>
      <input
        type="date"
        name={@name}
        id={@id}
        value={Form.normalize_value(@type, @value)}
        phx-hook=".DateInputPicker"
        class={[
          "w-full cursor-pointer rounded-md border bg-white px-3.5 py-2.5 font-sans text-[15px] text-ink-950 placeholder:text-ink-500",
          "focus:border-red-500 focus:outline-none focus:ring-4 focus:ring-red-500/15",
          @errors == [] && "border-ink-300",
          @errors != [] && "border-danger",
          @class
        ]}
        {@rest}
      />
      <script :type={Phoenix.LiveView.ColocatedHook} name=".DateInputPicker">
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
      <.field_error :for={msg <- @errors}>{msg}</.field_error>
      <p
        :if={@hint && @errors == []}
        class={["mt-1.5 font-mono text-[12.5px]", hint_class(@hint_variant)]}
      >
        {@hint}
      </p>
    </div>
    """
  end

  def input(assigns) do
    ~H"""
    <div class="mb-4">
      <label :if={@label} for={@id} class="mb-1.5 block text-sm font-semibold text-ink-700">
        {@label}
      </label>
      <input
        type={@type}
        name={@name}
        id={@id}
        value={Form.normalize_value(@type, @value)}
        class={[
          "w-full rounded-md border bg-white px-3.5 py-2.5 font-sans text-[15px] text-ink-950 placeholder:text-ink-500",
          "focus:border-red-500 focus:outline-none focus:ring-4 focus:ring-red-500/15",
          @errors == [] && "border-ink-300",
          @errors != [] && "border-danger",
          @class
        ]}
        {@rest}
      />
      <.field_error :for={msg <- @errors}>{msg}</.field_error>
      <p
        :if={@hint && @errors == []}
        class={["mt-1.5 font-mono text-[12.5px]", hint_class(@hint_variant)]}
      >
        {@hint}
      </p>
    </div>
    """
  end

  defp field_error(assigns) do
    ~H"""
    <p class="mt-1.5 text-[12.5px] font-medium text-danger">{render_slot(@inner_block)}</p>
    """
  end

  defp hint_class("success"), do: "text-green-600"
  defp hint_class("danger"), do: "text-danger"
  defp hint_class("neutral"), do: "text-ink-500"

  @doc """
  A tappable pill option — used for gender/region/venue/notification choices.

  ⚠️ Never bind `phx-value-value` on this (or any `<button>`-based) component.
  Phoenix's client-side `extractMeta` reads `phx-value-*` attrs first, then
  unconditionally overwrites `meta.value` with the element's native DOM
  `.value` property — empty string for a plain `<button>` — clobbering
  whatever `phx-value-value` set. This only breaks in a real browser;
  `Phoenix.LiveViewTest` reads the rendered attribute directly and never
  exercises the client JS, so it won't catch the regression. Use any other
  key name (`phx-value-choice`, `phx-value-option`, etc.) instead.
  """
  attr :selected, :boolean, default: false
  attr :rest, :global
  slot :inner_block, required: true

  def option_pill(assigns) do
    ~H"""
    <button
      type="button"
      class={[
        "cursor-pointer rounded-full border px-4 py-2.5 font-sans text-sm font-semibold transition-colors",
        @selected && "border-red-500 bg-red-50 text-red-700",
        !@selected && "border-ink-300 bg-white text-ink-700 hover:bg-ink-50"
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  A larger tappable option card with a title and description — used for
  notification preference choices.

  ⚠️ Same `phx-value-value` landmine as `option_pill/1` above — see its docs.
  """
  attr :selected, :boolean, default: false
  attr :rest, :global
  slot :inner_block, required: true

  def option_card(assigns) do
    ~H"""
    <button
      type="button"
      class={[
        "w-full cursor-pointer rounded-2xl border p-4 text-left font-sans transition-colors",
        @selected && "border-red-500 bg-red-50",
        !@selected && "border-ink-300 bg-white hover:bg-ink-50"
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc "White rounded card container used throughout the app."
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <div
      class={["rounded-2xl border border-ink-200 bg-white p-5 shadow-sm sm:p-6", @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc "Semantic pill badge — pair color with a label, never color alone."
  attr :variant, :string, values: ~w(success danger neutral), default: "neutral"
  slot :inner_block, required: true

  def badge(assigns) do
    variants = %{
      "success" => "bg-green-100 text-green-700",
      "danger" => "bg-red-50 text-red-700",
      "neutral" => "bg-ink-100 text-ink-600"
    }

    assigns = assign(assigns, :classes, Map.fetch!(variants, assigns.variant))

    ~H"""
    <span class={[
      "inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-semibold",
      @classes
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  @stage_styles %{
    "grassroots" => {"bg-ink-100", "text-ink-700", "bg-ink-500"},
    "regional" => {"bg-green-100", "text-green-700", "bg-green-500"},
    "circuit" => {"bg-red-50", "text-red-700", "bg-red-500"},
    "finals" => {"bg-ink-950", "text-ink-25", "bg-ink-25"}
  }

  @doc "The colored dot + label badge for a qualification pipeline stage."
  attr :stage, :string, required: true, doc: "one of: grassroots, regional, circuit, finals"

  def stage_badge(assigns) do
    {bg, text, dot} =
      Map.get(@stage_styles, String.downcase(assigns.stage), @stage_styles["grassroots"])

    assigns = assign(assigns, bg: bg, text: text, dot: dot)

    ~H"""
    <span class={[
      "inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-semibold",
      @bg,
      @text
    ]}>
      <span class={["size-1.5 rounded-full", @dot]}></span> {String.capitalize(@stage)}
    </span>
    """
  end

  @doc "An initials avatar circle, or the player's photo if they have one."
  attr :name, :string, required: true
  attr :src, :string, default: nil
  attr :size, :string, default: "size-10"
  attr :class, :any, default: nil

  def avatar(assigns) do
    ~H"""
    <img
      :if={@src}
      src={@src}
      loading="lazy"
      class={["shrink-0 rounded-full object-cover", @size, @class]}
    />
    <div
      :if={!@src}
      class={[
        "flex shrink-0 items-center justify-center rounded-full bg-ink-950 font-semibold text-ink-25",
        @size,
        @class
      ]}
    >
      {initials(@name)}
    </div>
    """
  end

  defp initials(name) do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&String.first/1)
    |> Enum.take(2)
    |> Enum.join()
    |> String.upcase()
  end

  @doc """
  A centered empty state: icon, heading, message, and an optional action
  slot — per design-system.md §6.9, never a bare empty list/table.
  """
  attr :icon, :string, default: "hero-inbox"
  attr :title, :string, required: true
  slot :inner_block, doc: "the message body"
  slot :action

  def empty_state(assigns) do
    ~H"""
    <div class="rounded-2xl border border-ink-200 bg-white px-6 py-14 text-center shadow-sm sm:py-16">
      <div class="mx-auto mb-4 flex size-14 items-center justify-center rounded-2xl bg-ink-100 text-ink-400">
        <.icon name={@icon} class="size-6" />
      </div>
      <h3 class="mb-1.5 text-lg font-bold text-ink-950">{@title}</h3>
      <p class="mx-auto max-w-sm text-sm leading-relaxed text-ink-500">
        {render_slot(@inner_block)}
      </p>
      <div :if={@action != []} class="mt-5">{render_slot(@action)}</div>
    </div>
    """
  end

  @doc """
  The player app shell: sticky top nav (Fixtures / Standings / My Team) plus
  an account dropdown (Profile, Log out), wrapping page content. Mirrors
  design-system.md §6.6's "Player app nav" spec.
  """
  attr :current_player, :map, required: true
  attr :active, :atom, required: true, doc: "one of :fixtures, :standings, :team, :profile"
  attr :flash, :map, required: true
  slot :inner_block, required: true

  def app_shell(assigns) do
    ~H"""
    <div class="flex min-h-screen flex-col bg-ink-25 font-sans text-ink-700 antialiased">
      <header class="sticky top-0 z-20 border-b border-ink-200 bg-ink-25/90 backdrop-blur">
        <div class="mx-auto flex h-[62px] max-w-5xl items-center gap-5 px-4 sm:px-7">
          <img
            src={~p"/images/cuevolution-logo.png"}
            class="h-8 w-auto shrink-0"
            alt="Cuevolution"
          />

          <nav class="ml-2 flex flex-1 items-stretch gap-5 overflow-x-auto sm:gap-7">
            <.nav_link navigate={~p"/fixtures"} active={@active == :fixtures}>Fixtures</.nav_link>
            <.nav_link navigate={~p"/standings"} active={@active == :standings}>Standings</.nav_link>
            <.nav_link navigate={~p"/team"} active={@active == :team}>My Team</.nav_link>
          </nav>

          <div
            class="relative shrink-0"
            id="account-menu"
            phx-click-away={JS.hide(to: "#account-menu-dropdown")}
          >
            <button
              type="button"
              phx-click={JS.toggle(to: "#account-menu-dropdown")}
              class="cursor-pointer rounded-full"
              title="Account"
            >
              <.avatar
                name={"#{@current_player.first_name} #{@current_player.last_name}"}
                src={ProfilePicture.url(@current_player.profile_picture_path)}
                size="size-9"
                class="text-[13px]"
              />
            </button>
            <div
              id="account-menu-dropdown"
              class="absolute right-0 top-[46px] z-50 hidden w-56 overflow-hidden rounded-2xl border border-ink-200 bg-white shadow-lg"
            >
              <div class="border-b border-ink-100 px-4 py-3">
                <div class="text-sm font-semibold text-ink-950">
                  {@current_player.first_name} {@current_player.last_name}
                </div>
                <div class="font-mono text-[12.5px] text-ink-400">@{@current_player.username}</div>
              </div>
              <.link
                navigate={~p"/profile"}
                class="block px-4 py-2.5 text-sm font-medium text-ink-700 hover:bg-ink-100"
              >
                Profile
              </.link>
              <.link
                href={~p"/logout"}
                method="delete"
                class="block border-t border-ink-100 px-4 py-2.5 text-sm font-semibold text-red-600 hover:bg-red-50"
              >
                Log out
              </.link>
            </div>
          </div>
        </div>
      </header>

      <.flash_group flash={@flash} />

      <main class="mx-auto w-full max-w-5xl flex-1 px-4 py-6 sm:px-7 sm:py-10">
        {render_slot(@inner_block)}
      </main>
    </div>
    """
  end

  attr :active, :boolean, default: false
  attr :rest, :global, include: ~w(href navigate patch)
  slot :inner_block, required: true

  defp nav_link(assigns) do
    ~H"""
    <.link
      class={[
        "flex items-center whitespace-nowrap border-b-2 px-0.5 text-[15px] font-semibold",
        @active && "border-red-500 text-ink-950",
        !@active && "border-transparent text-ink-500 hover:text-ink-950"
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  @doc "The centered card shell used by sign-in/registration."
  attr :max_width, :string, default: "max-w-[420px]"
  attr :flash, :map, required: true
  slot :inner_block, required: true

  def guest_shell(assigns) do
    ~H"""
    <div class="bg-auth-pattern flex min-h-screen flex-col items-center px-5 py-12 font-sans text-ink-700 antialiased sm:py-16">
      <.flash_group flash={@flash} />
      <img src={~p"/images/cuevolution-logo.png"} class="mb-7 h-10 w-auto" alt="Cuevolution" />
      <div class={[
        "w-full rounded-2xl border border-ink-200 bg-white p-6 shadow-md sm:p-9",
        @max_width
      ]}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc "Flash messages styled per design-system.md §6.7."
  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div
      id={@id}
      aria-live="polite"
      class="fixed inset-x-0 top-0 z-50 flex flex-col items-center gap-2 p-4 sm:items-end"
    >
      <.player_flash kind={:info} flash={@flash} />
      <.player_flash kind={:error} flash={@flash} />
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

  attr :id, :string, doc: "the optional id of the flash container"
  attr :flash, :map, required: true
  attr :kind, :atom, values: [:info, :error], required: true

  defp player_flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-hook=".AutoDismissFlash"
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> fade_out("##{@id}")}
      role="alert"
      class={[
        "w-full max-w-sm rounded-2xl border px-4 py-3 text-sm font-medium shadow-md sm:w-96",
        @kind == :info && "border-green-100 bg-green-50 text-green-700",
        @kind == :error && "border-red-100 bg-red-50 text-red-700"
      ]}
    >
      {msg}
      <script :type={Phoenix.LiveView.ColocatedHook} name=".AutoDismissFlash">
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
end
