defmodule Cuevolution.Names do
  @moduledoc """
  Display formatting for player and team names.

  Names are stored exactly as they were typed — "john", "OTIENO", "kpb
  warriors" — and are normalised to title case only on the way out, so
  nothing the player or captain entered is ever lost. Every surface that
  shows a name goes through here, which is what keeps the casing uniform
  across screens, emails, the fixture PDF and the directory exports.

  Words break on whitespace and hyphens, never on apostrophes: Kenyan names
  like Ng'ang'a and Wang'ombe have to come back as "Ng'ang'a", not
  "Ng'Ang'A". Separators are preserved exactly as given, so double spaces
  and hyphens survive the round trip.
  """

  @word ~r/[^\s\-]+/u

  @doc """
  Title-cases a name for display. `nil` passes through.

      iex> Cuevolution.Names.title_case("john OTIENO")
      "John Otieno"

      iex> Cuevolution.Names.title_case("NG'ANG'A")
      "Ng'ang'a"

      iex> Cuevolution.Names.title_case("mary-jane wanjiru")
      "Mary-Jane Wanjiru"

      iex> Cuevolution.Names.title_case("kpb warriors")
      "Kpb Warriors"

      iex> Cuevolution.Names.title_case(nil)
      nil
  """
  def title_case(nil), do: nil

  def title_case(name) when is_binary(name) do
    Regex.replace(@word, name, &String.capitalize/1)
  end

  @doc """
  A player's full name, title-cased.

      iex> Cuevolution.Names.player_name(%{first_name: "john", last_name: "OTIENO"})
      "John Otieno"
  """
  def player_name(%{first_name: first, last_name: last}), do: full_name(first, last)

  @doc """
  Joins a first and last name, title-cased, skipping either if it is missing.

      iex> Cuevolution.Names.full_name("mary", nil)
      "Mary"
  """
  def full_name(first, last) do
    [title_case(first), title_case(last)]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  @doc """
  A case-insensitive sort key, so names order alphabetically regardless of
  how they were typed.

      iex> Cuevolution.Names.sort_key("otieno")
      "otieno"

      iex> Cuevolution.Names.sort_key(nil)
      ""
  """
  def sort_key(nil), do: ""
  def sort_key(name) when is_binary(name), do: String.downcase(name)
end
