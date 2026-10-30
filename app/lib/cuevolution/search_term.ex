defmodule Cuevolution.SearchTerm do
  @moduledoc """
  Normalizes the free-text terms admins type into the console's participant
  search boxes (Directory, Stages, Groups) into `ILIKE` patterns.

  Centralized because every one of those boxes is fed by hand — pasted out
  of a spreadsheet, or copied straight off a row on the page — so they all
  have to survive the same input noise:

    * surrounding and doubled-up whitespace from a paste;
    * the `@` the UI prints in front of a username, which is *display*
      sugar and not part of the stored handle. A term is
      therefore matched both as typed and with its leading `@`s removed,
      rather than one or the other — usernames may legitimately contain
      `@` themselves (`Bk@123`, `@Vans01`), so stripping cannot be
      unconditional;
    * `%`, `_` and `\\`, which are `LIKE` metacharacters and have to be
      escaped to be matched literally.

  Case needs no handling here: callers use `ilike/2`.
  """

  @doc """
  The `ILIKE` patterns to match `term` against, most specific first.

  Returns `[]` when the term is blank, meaning "no search filter" — callers
  pattern-match on that to leave their query untouched.

      iex> Cuevolution.SearchTerm.patterns("  MAS ")
      ["%MAS%"]

      iex> Cuevolution.SearchTerm.patterns("@MAS")
      ["%@MAS%", "%MAS%"]

      iex> Cuevolution.SearchTerm.patterns("100%")
      ["%100\\\\%%"]

      iex> Cuevolution.SearchTerm.patterns("   ")
      []
  """
  def patterns(nil), do: []

  def patterns(term) when is_binary(term) do
    term = squish(term)

    [term, String.trim_leading(term, "@")]
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.map(&like_pattern/1)
  end

  defp squish(term) do
    term
    |> String.trim()
    |> String.replace(~r/\s+/u, " ")
  end

  # Backslash is escaped alongside `%`/`_` because it is itself `LIKE`'s
  # default escape character — left raw, a term containing one would emit a
  # dangling escape sequence rather than matching literally.
  defp like_pattern(term) do
    "%" <> String.replace(term, ["\\", "%", "_"], &("\\" <> &1)) <> "%"
  end
end
