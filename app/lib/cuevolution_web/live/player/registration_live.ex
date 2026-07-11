defmodule CuevolutionWeb.RegistrationLive do
  use CuevolutionWeb, :live_view

  import Ecto.Query

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.Player
  alias Cuevolution.Accounts.ProfilePicture
  alias Cuevolution.Accounts.Region
  alias Cuevolution.Repo
  alias Cuevolution.Venues
  alias CuevolutionWeb.PlayerComponents

  @genders [{"Male", "male"}, {"Female", "female"}]
  @notification_defs [
    {"email", "Email", "Confirmations and draws by email."},
    {"sms", "SMS", "Text messages to your mobile."},
    {"both", "Both", "Email and SMS — never miss a draw."}
  ]

  @step_fields %{
    1 => [:first_name, :last_name, :date_of_birth, :location, :gender],
    2 => [:email, :mobile_number, :username, :password],
    3 => [:region_id, :preferred_venue_id, :other_venue_name],
    4 => [:notification_preference]
  }
  @last_step 4
  @all_step_fields Enum.flat_map(@step_fields, fn {_step, fields} -> fields end)

  def mount(_params, _session, socket) do
    regions = Repo.all(from r in Region, order_by: r.name)
    changeset = Player.registration_changeset(%Player{}, %{})

    {:ok,
     socket
     |> assign(
       page_title: "Register",
       step: 1,
       attrs: %{},
       regions: regions,
       venues: [],
       genders: @genders,
       notification_defs: @notification_defs,
       last_step: @last_step,
       registered: false,
       touched_fields: MapSet.new()
     )
     |> allow_upload(:photo,
       accept: ~w(.jpg .jpeg .png),
       max_entries: 1,
       max_file_size: 8_000_000
     )
     |> assign_form(changeset)}
  end

  embed_templates "registration_live/step_*"
  embed_templates "registration_live/field_error*"

  def handle_event("validate", %{"player" => params} = full_params, socket) do
    attrs = Map.merge(socket.assigns.attrs, params)
    changeset = Player.registration_changeset(%Player{}, attrs) |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:attrs, attrs)
     |> touch_target(full_params["_target"])
     |> assign_form(changeset)}
  end

  def handle_event("choose", %{"field" => field, "choice" => value}, socket) do
    attrs = Map.put(socket.assigns.attrs, field, value)

    attrs =
      if field == "venue_choice" and value == "other",
        do: Map.delete(attrs, "preferred_venue_id"),
        else: attrs

    attrs = if field == "preferred_venue_id", do: Map.delete(attrs, "venue_choice"), else: attrs

    changeset = Player.registration_changeset(%Player{}, attrs) |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:attrs, attrs)
     |> touch_fields([field])
     |> assign_form(changeset)}
  end

  def handle_event("choose_region", %{"id" => region_id}, socket) do
    attrs =
      socket.assigns.attrs
      |> Map.put("region_id", region_id)
      |> Map.delete("preferred_venue_id")
      |> Map.delete("venue_choice")
      |> Map.delete("other_venue_name")

    changeset = Player.registration_changeset(%Player{}, attrs) |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:attrs, attrs)
     |> assign(:venues, Venues.list_active_for_region(region_id))
     |> touch_fields(["region_id"])
     |> assign_form(changeset)}
  end

  def handle_event("next", _params, socket) do
    attrs = socket.assigns.attrs
    changeset = Player.registration_changeset(%Player{}, attrs) |> Map.put(:action, :validate)

    step_fields = Map.fetch!(@step_fields, socket.assigns.step)
    blocking? = Enum.any?(changeset.errors, fn {field, _} -> field in step_fields end)

    if blocking? do
      # Mark this step's fields as touched so their errors become visible, and
      # give the display changeset a blank default for any that were never
      # typed into at all — `PlayerComponents.input` independently gates on
      # `used_input?/1`, which needs the key present in params, not just a
      # touched-fields entry, or an untouched-but-blocking field would still
      # render with no visible error.
      display_changeset =
        attrs
        |> with_blank_defaults(step_fields)
        |> then(&Player.registration_changeset(%Player{}, &1))
        |> Map.put(:action, :validate)

      socket =
        socket
        |> touch_fields(Enum.map(step_fields, &Atom.to_string/1))
        |> assign_form(display_changeset)

      {:noreply, socket}
    else
      {:noreply, assign(socket, step: socket.assigns.step + 1)}
    end
  end

  def handle_event("back", _params, socket) do
    {:noreply, assign(socket, step: max(1, socket.assigns.step - 1))}
  end

  def handle_event("save", params, socket) do
    # Step 4 has no named form fields (notification preference is chosen via
    # phx-click), so a submit here can arrive as a bare %{} with no "player"
    # key at all — everything relevant already lives in socket.assigns.attrs.
    attrs = Map.merge(socket.assigns.attrs, Map.get(params, "player", %{}))

    with {:ok, attrs} <- put_uploaded_photo(socket, attrs),
         {:ok, player} <- Accounts.register_player(attrs) do
      {:noreply, assign(socket, attrs: attrs, registered: true, registered_player: player)}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        display_changeset =
          attrs
          |> with_blank_defaults(@all_step_fields)
          |> then(&Player.registration_changeset(%Player{}, &1))
          |> Map.put(:action, :validate)

        {:noreply,
         socket
         |> assign(:attrs, attrs)
         |> assign(:step, step_for_first_error(changeset))
         |> touch_fields(Enum.map(@all_step_fields, &Atom.to_string/1))
         |> assign_form(display_changeset)}

      {:error, :upload_failed} ->
        {:noreply,
         put_flash(socket, :error, "Could not process the profile picture — try again.")}

      {:error, :upload_in_progress} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Your photo is still uploading — give it a moment and try again."
         )}
    end
  end

  # `consume_uploaded_entries/3` raises if any entry isn't `done?` yet — guard
  # explicitly instead of crashing the LiveView process out from under the
  # user on a slow upload/connection.
  defp put_uploaded_photo(socket, attrs) do
    if Enum.all?(socket.assigns.uploads.photo.entries, & &1.done?) do
      consume_uploaded_photo(socket, attrs)
    else
      {:error, :upload_in_progress}
    end
  end

  defp consume_uploaded_photo(socket, attrs) do
    results =
      consume_uploaded_entries(socket, :photo, fn %{path: path}, entry ->
        case ProfilePicture.store(path, entry.uuid) do
          {:ok, public_path} -> {:ok, public_path}
          {:error, _reason} -> {:postpone, :error}
        end
      end)

    case results do
      [public_path] when is_binary(public_path) ->
        {:ok, Map.put(attrs, "profile_picture_path", public_path)}

      [] ->
        {:ok, attrs}

      _ ->
        {:error, :upload_failed}
    end
  end

  # `_target` is `["player", "first_name"]` for a native input change — the
  # last element is the field that actually changed. Pill/card clicks touch
  # their field directly via `touch_fields/2` instead, since they never fire
  # a "validate" event.
  defp touch_target(socket, target) when is_list(target) and target != [],
    do: touch_fields(socket, [List.last(target)])

  defp touch_target(socket, _target), do: socket

  defp touch_fields(socket, fields) do
    Phoenix.Component.update(socket, :touched_fields, &Enum.into(fields, &1))
  end

  # Ensures each field's key is present in `attrs` (blank if absent) so
  # `Phoenix.Component.used_input?/1` — which `PlayerComponents.input` checks
  # independently of our own touched-fields filtering — treats it as touched
  # too. Only used to build a display-only changeset, never written back into
  # `socket.assigns.attrs`.
  defp with_blank_defaults(attrs, fields) do
    Enum.reduce(fields, attrs, fn field, acc -> Map.put_new(acc, Atom.to_string(field), "") end)
  end

  defp step_for_first_error(changeset) do
    error_fields = Enum.map(changeset.errors, fn {field, _} -> field end)

    @step_fields
    |> Enum.sort_by(fn {step, _fields} -> step end)
    |> Enum.find_value(1, fn {step, fields} ->
      Enum.any?(fields, &(&1 in error_fields)) && step
    end)
  end

  defp region_name(assigns, region_id) do
    Enum.find_value(assigns.regions, "", fn r -> r.id == region_id && r.name end)
  end

  defp age_hint(nil), do: nil
  defp age_hint(""), do: nil

  defp age_hint(dob_string) do
    case Date.from_iso8601(dob_string) do
      {:ok, dob} -> format_age_hint(age_in_years(dob))
      _ -> nil
    end
  end

  defp age_in_years(dob) do
    today = Date.utc_today()
    age = today.year - dob.year
    if {today.month, today.day} < {dob.month, dob.day}, do: age - 1, else: age
  end

  defp format_age_hint(age) when age < 0, do: nil
  defp format_age_hint(age) when age < 18, do: "Age #{age} — must be 18+"
  defp format_age_hint(age), do: "Age #{age}"

  defp mobile_hint(form) do
    has_error? = Enum.any?(form.source.errors, fn {field, _} -> field == :mobile_number end)
    normalized = Ecto.Changeset.get_change(form.source, :mobile_number)

    cond do
      has_error? -> {"neutral", nil}
      is_nil(normalized) -> {"neutral", nil}
      Accounts.mobile_number_taken?(normalized) -> {"danger", "This number is already registered"}
      true -> {"neutral", "Will be saved as #{normalized}"}
    end
  end

  defp username_hint(nil, _form), do: {"neutral", nil}
  defp username_hint("", _form), do: {"neutral", nil}

  defp username_hint(username, form) do
    has_error? = Enum.any?(form.source.errors, fn {field, _} -> field == :username end)

    cond do
      has_error? -> {"neutral", nil}
      Accounts.username_taken?(username) -> {"danger", "#{username} is already taken"}
      true -> {"success", "✓ #{username} is available"}
    end
  end

  defp email_hint(nil, _form), do: {"neutral", nil}
  defp email_hint("", _form), do: {"neutral", nil}

  defp email_hint(email, form) do
    has_error? = Enum.any?(form.source.errors, fn {field, _} -> field == :email end)

    cond do
      has_error? -> {"neutral", nil}
      Accounts.email_taken?(email) -> {"danger", "An account with this email already exists"}
      true -> {"success", "✓ available"}
    end
  end

  defp upload_error_message(:too_large), do: "That photo is too large (max 8MB)."
  defp upload_error_message(:not_accepted), do: "Please upload a JPG or PNG."
  defp upload_error_message(:too_many_files), do: "Only one photo is allowed."
  defp upload_error_message(_), do: "Could not process that photo."

  defp assign_form(socket, changeset) do
    # `changeset` keeps every error for the blocking checks in "next"/"save"
    # to use — only the copy handed to the template gets pruned down to
    # touched fields, so a field the user hasn't reached yet stays quiet.
    display_changeset = filter_errors(changeset, socket.assigns.touched_fields)
    assign(socket, :form, to_form(display_changeset, as: :player))
  end

  defp filter_errors(changeset, touched_fields) do
    errors =
      Enum.filter(changeset.errors, fn {field, _} -> Atom.to_string(field) in touched_fields end)

    %{changeset | errors: errors}
  end
end
