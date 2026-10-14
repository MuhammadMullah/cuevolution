defmodule Cuevolution.Competitions.StageTest do
  use Cuevolution.DataCase, async: true

  alias Cuevolution.Competitions.Stage

  describe "seeded pipeline order" do
    test "all six stages are seeded in the correct order" do
      stages =
        Stage
        |> Cuevolution.Repo.all()
        |> Enum.sort_by(& &1.order)
        |> Enum.map(&{&1.name, &1.order})

      assert stages == [
               {"Grassroots", 1},
               {"Grassroots Round 2", 2},
               {"Regional", 3},
               {"Regional Round 2", 4},
               {"Circuit", 5},
               {"Finals", 6}
             ]
    end
  end

  describe "grassroots?/1 and round_robin?/1" do
    test "Regional Round 2 is neither a Grassroots round nor round-robin" do
      regional_round_2 = Cuevolution.Repo.get_by!(Stage, name: "Regional Round 2")

      refute Stage.grassroots?(regional_round_2)
      refute Stage.round_robin?(regional_round_2)
    end

    test "Regional is round-robin but not a Grassroots round" do
      regional = Cuevolution.Repo.get_by!(Stage, name: "Regional")

      refute Stage.grassroots?(regional)
      assert Stage.round_robin?(regional)
    end

    test "both Grassroots rounds are Grassroots and round-robin" do
      for name <- ["Grassroots", "Grassroots Round 2"] do
        stage = Cuevolution.Repo.get_by!(Stage, name: name)
        assert Stage.grassroots?(stage)
        assert Stage.round_robin?(stage)
      end
    end

    test "Circuit and Finals are neither" do
      for name <- ["Circuit", "Finals"] do
        stage = Cuevolution.Repo.get_by!(Stage, name: name)
        refute Stage.grassroots?(stage)
        refute Stage.round_robin?(stage)
      end
    end
  end
end
