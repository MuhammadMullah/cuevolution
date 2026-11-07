defmodule CuevolutionWeb.BracketStylesTest do
  @moduledoc """
  The bracket charts moved from inline utility classes to component classes in
  app.css. Nothing in the compiler ties a class name in a template to a rule in
  the stylesheet, so a typo would render an unstyled card and no other test
  would notice. This closes that gap.
  """
  use ExUnit.Case, async: true

  @templates [
    "lib/cuevolution_web/live/public_fixtures_live.html.heex",
    "lib/cuevolution_web/live/admin/group_management_live.html.heex"
  ]

  @stylesheet "assets/css/app.css"

  # Built by interpolation (`bracket-lane--#{lane.side}`), so the scan below
  # cannot see them.
  @interpolated ~w(bracket-lane--winners bracket-lane--losers bracket-lane--knockout)

  defp defined_classes do
    @stylesheet
    |> File.read!()
    |> then(&Regex.scan(~r/^\.(bracket-[A-Za-z0-9_\-]*)\s*\{/m, &1))
    |> Enum.map(fn [_, class] -> class end)
    |> MapSet.new()
  end

  defp classes_used(path) do
    path
    |> File.read!()
    |> then(&Regex.scan(~r/\b(bracket-[A-Za-z0-9_\-]+)\b/, &1))
    |> Enum.map(fn [_, class] -> class end)
    |> Enum.reject(&String.ends_with?(&1, "-"))
    |> MapSet.new()
  end

  test "every bracket class a template names has a rule in app.css" do
    defined = defined_classes()

    for path <- @templates do
      missing = path |> classes_used() |> MapSet.difference(defined) |> Enum.sort()
      assert missing == [], "#{path} uses undefined bracket classes: #{inspect(missing)}"
    end
  end

  test "the interpolated lane classes are defined too" do
    defined = defined_classes()
    missing = Enum.reject(@interpolated, &MapSet.member?(defined, &1))
    assert missing == [], "app.css is missing: #{inspect(missing)}"
  end
end
