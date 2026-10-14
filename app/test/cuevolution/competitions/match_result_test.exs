defmodule Cuevolution.Competitions.MatchResultTest do
  use Cuevolution.DataCase, async: true

  alias Cuevolution.Competitions.MatchResult

  describe "create_changeset/2 — winner required unless tied" do
    test "requires winner_participation_id when the score isn't tied" do
      fixture = insert(:fixture)

      changeset =
        MatchResult.create_changeset(%MatchResult{}, %{
          fixture_id: fixture.id,
          score: %{"participant_a_frames" => 3, "participant_b_frames" => 1},
          recorded_by_admin_id: insert(:admin).id
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).winner_participation_id
    end

    test "accepts a nil winner_participation_id when the score is tied" do
      fixture = insert(:fixture)

      changeset =
        MatchResult.create_changeset(%MatchResult{}, %{
          fixture_id: fixture.id,
          score: %{"participant_a_frames" => 2, "participant_b_frames" => 2},
          recorded_by_admin_id: insert(:admin).id
        })

      assert changeset.valid?
    end

    test "accepts a nil winner_participation_id for a 0-0 tie too" do
      fixture = insert(:fixture)

      changeset =
        MatchResult.create_changeset(%MatchResult{}, %{
          fixture_id: fixture.id,
          score: %{"participant_a_frames" => 0, "participant_b_frames" => 0},
          recorded_by_admin_id: insert(:admin).id
        })

      assert changeset.valid?
    end

    test "still requires a winner when there is no score at all" do
      fixture = insert(:fixture)

      changeset =
        MatchResult.create_changeset(%MatchResult{}, %{
          fixture_id: fixture.id,
          recorded_by_admin_id: insert(:admin).id
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).winner_participation_id
    end
  end

  describe "correction_changeset/2 — winner required unless tied" do
    test "rejects a nil winner_participation_id for a non-tied score" do
      result = insert(:match_result)

      changeset =
        MatchResult.correction_changeset(result, %{
          winner_participation_id: nil,
          score: %{"participant_a_frames" => 3, "participant_b_frames" => 1}
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).winner_participation_id
    end

    test "accepts a nil winner_participation_id for a tied score" do
      result = insert(:match_result)

      changeset =
        MatchResult.correction_changeset(result, %{
          winner_participation_id: nil,
          score: %{"participant_a_frames" => 2, "participant_b_frames" => 2}
        })

      assert changeset.valid?
    end
  end
end
