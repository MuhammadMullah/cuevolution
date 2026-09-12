defmodule Cuevolution.AccountsTest do
  use Cuevolution.DataCase, async: true

  alias Cuevolution.Accounts
  alias Cuevolution.Accounts.Admin
  alias Cuevolution.Accounts.AdminActionLog
  alias Cuevolution.Accounts.AdminToken
  alias Cuevolution.Accounts.Player
  alias Cuevolution.Competitions
  alias Cuevolution.Teams

  describe "authenticate_admin/2" do
    test "returns the admin given correct email and password" do
      admin = insert(:admin, hashed_password: Bcrypt.hash_pwd_salt("correct_password"))

      assert {:ok, authenticated} = Accounts.authenticate_admin(admin.email, "correct_password")
      assert authenticated.id == admin.id
    end

    test "returns a generic error given an incorrect password" do
      admin = insert(:admin, hashed_password: Bcrypt.hash_pwd_salt("correct_password"))

      assert {:error, :invalid_credentials} =
               Accounts.authenticate_admin(admin.email, "wrong_password")
    end

    test "returns the same generic error given a non-existent email" do
      assert {:error, :invalid_credentials} =
               Accounts.authenticate_admin("nobody@cuevolution.test", "whatever")
    end

    test "does not leak whether the email or the password was wrong" do
      admin = insert(:admin, hashed_password: Bcrypt.hash_pwd_salt("correct_password"))

      assert Accounts.authenticate_admin(admin.email, "wrong_password") ==
               Accounts.authenticate_admin("nobody@cuevolution.test", "wrong_password")
    end

    test "spends comparable time on a non-existent email as on a wrong password (dummy-hash check)" do
      admin = insert(:admin, hashed_password: Bcrypt.hash_pwd_salt("correct_password"))

      {existing_time, _} =
        :timer.tc(fn -> Accounts.authenticate_admin(admin.email, "wrong_password") end)

      {missing_time, _} =
        :timer.tc(fn ->
          Accounts.authenticate_admin("nobody@cuevolution.test", "wrong_password")
        end)

      # Both paths run a real bcrypt comparison, so neither should be
      # dramatically (>10x) faster than the other — a cheap short-circuit on
      # "email not found" would leak account existence via timing.
      ratio = max(existing_time, missing_time) / max(min(existing_time, missing_time), 1)
      assert ratio < 10
    end

    test "rejects an invited admin who hasn't completed setup yet, same generic error" do
      admin = insert(:admin, hashed_password: nil, role: "tournament_manager")

      assert Accounts.authenticate_admin(admin.email, "whatever") ==
               {:error, :invalid_credentials}
    end
  end

  describe "invite_admin/3, get_admin_by_setup_token/1 and complete_admin_setup/2" do
    test "creates a pending admin with the given role and enqueues a setup email" do
      inviter = insert(:admin, role: "super_admin")

      assert {:ok, invited} =
               Accounts.invite_admin(
                 inviter,
                 %{"email" => "new-admin@cuevolution.test", "role" => "tournament_manager"},
                 &"https://cuevolution.test/admin/setup/#{&1}"
               )

      assert invited.role == "tournament_manager"
      assert invited.hashed_password == nil
      assert Admin.pending?(invited)

      assert_enqueued(
        worker: Cuevolution.Notifications.Workers.SendAdminInvitationEmailWorker,
        args: %{"admin_id" => invited.id}
      )

      [job] =
        all_enqueued(worker: Cuevolution.Notifications.Workers.SendAdminInvitationEmailWorker)

      "https://cuevolution.test/admin/setup/" <> token = job.args["setup_url"]

      assert Accounts.get_admin_by_setup_token(token).id == invited.id
    end

    test "rejects super_admin as an invitable role" do
      inviter = insert(:admin, role: "super_admin")

      assert {:error, changeset} =
               Accounts.invite_admin(
                 inviter,
                 %{"email" => "wannabe@cuevolution.test", "role" => "super_admin"},
                 &"https://cuevolution.test/admin/setup/#{&1}"
               )

      assert "is invalid" in errors_on(changeset).role
    end

    test "rejects a duplicate email" do
      existing = insert(:admin)
      inviter = insert(:admin, role: "super_admin")

      assert {:error, changeset} =
               Accounts.invite_admin(
                 inviter,
                 %{"email" => existing.email, "role" => "tournament_manager"},
                 &"https://cuevolution.test/admin/setup/#{&1}"
               )

      assert "has already been taken" in errors_on(changeset).email
    end

    test "logs the invite against the inviting admin" do
      inviter = insert(:admin, role: "super_admin")

      {:ok, invited} =
        Accounts.invite_admin(
          inviter,
          %{"email" => "logged@cuevolution.test", "role" => "regional_coordinator"},
          &"https://cuevolution.test/admin/setup/#{&1}"
        )

      log = Repo.get_by!(AdminActionLog, entity_id: invited.id)
      assert log.admin_id == inviter.id
      assert log.action_type == "invite_admin"
    end

    test "an unknown or garbage setup token resolves to nil" do
      assert Accounts.get_admin_by_setup_token("garbage") == nil
    end

    test "complete_admin_setup sets password and mobile number and clears pending status" do
      admin = insert(:admin, hashed_password: nil, role: "venue_representative")

      assert {:ok, updated} =
               Accounts.complete_admin_setup(admin, %{
                 "password" => "New-Pass1!",
                 "password_confirmation" => "New-Pass1!",
                 "mobile_number" => "0712345678"
               })

      assert Bcrypt.verify_pass("New-Pass1!", updated.hashed_password)
      assert updated.mobile_number == "+254712345678"
      refute Admin.pending?(updated)
    end

    test "complete_admin_setup invalidates the setup token that was used" do
      admin = insert(:admin, hashed_password: nil, role: "venue_representative")

      {encoded_token, token_struct} = AdminToken.build_admin_setup_token(admin)

      Repo.insert!(token_struct)

      {:ok, _updated} =
        Accounts.complete_admin_setup(admin, %{
          "password" => "New-Pass1!",
          "password_confirmation" => "New-Pass1!",
          "mobile_number" => "0712345678"
        })

      assert Accounts.get_admin_by_setup_token(encoded_token) == nil
    end
  end

  describe "generate_admin_session_token/1 and get_admin_by_session_token/1" do
    test "a generated token resolves back to the admin that generated it" do
      admin = insert(:admin)

      token = Accounts.generate_admin_session_token(admin)

      assert %Cuevolution.Accounts.Admin{id: id} = Accounts.get_admin_by_session_token(token)
      assert id == admin.id
    end

    test "an unknown token resolves to nil" do
      assert Accounts.get_admin_by_session_token("not_a_real_token") == nil
    end

    test "two admins get independent, non-colliding tokens" do
      admin_a = insert(:admin)
      admin_b = insert(:admin)

      token_a = Accounts.generate_admin_session_token(admin_a)
      token_b = Accounts.generate_admin_session_token(admin_b)

      assert Accounts.get_admin_by_session_token(token_a).id == admin_a.id
      assert Accounts.get_admin_by_session_token(token_b).id == admin_b.id
    end
  end

  describe "log_admin_action/4" do
    test "first-time entries store nil prior/new values" do
      admin = insert(:admin)
      player = insert(:player)

      assert {:ok, log} = Accounts.log_admin_action("result_entered", admin, player)

      assert log.admin_id == admin.id
      assert log.action_type == "result_entered"
      assert log.entity_type == "Cuevolution.Accounts.Player"
      assert log.entity_id == player.id
      assert log.prior_value == nil
      assert log.new_value == nil
    end

    test "corrections store both prior and new values" do
      admin = insert(:admin)
      player = insert(:player)

      assert {:ok, log} =
               Accounts.log_admin_action("result_corrected", admin, player,
                 prior_value: %{"score" => "3-2"},
                 new_value: %{"score" => "3-1"}
               )

      assert log.prior_value == %{"score" => "3-2"}
      assert log.new_value == %{"score" => "3-1"}
    end
  end

  describe "username_taken?/1" do
    test "returns true when the username is already registered, case-insensitively" do
      insert(:player, username: "TakenHandle")

      assert Accounts.username_taken?("takenhandle")
      assert Accounts.username_taken?("TakenHandle")
    end

    test "returns false for an unused username" do
      refute Accounts.username_taken?("totally_unused_handle")
    end

    test "returns false for a blank username" do
      refute Accounts.username_taken?("")
    end
  end

  describe "email_taken?/1" do
    test "returns true when the email is already registered, case-insensitively" do
      insert(:player, email: "Taken@Example.com")

      assert Accounts.email_taken?("taken@example.com")
      assert Accounts.email_taken?("Taken@Example.com")
    end

    test "returns false for an unused email" do
      refute Accounts.email_taken?("totally-unused@example.com")
    end

    test "returns false for a blank email" do
      refute Accounts.email_taken?("")
    end
  end

  describe "mobile_number_taken?/1" do
    test "returns true when the mobile number is already registered, regardless of format" do
      insert(:player, mobile_number: "+254712345678")

      assert Accounts.mobile_number_taken?("+254712345678")
      assert Accounts.mobile_number_taken?("0712345678")
    end

    test "returns false for an unused mobile number" do
      refute Accounts.mobile_number_taken?("0798765432")
    end

    test "returns false for a blank mobile number" do
      refute Accounts.mobile_number_taken?("")
    end

    test "returns false for a mobile number that fails to normalize" do
      refute Accounts.mobile_number_taken?("not-a-number")
    end
  end

  describe "register_player/1" do
    setup do
      %{attrs: player_registration_attrs()}
    end

    test "creates a player and dispatches a registration-confirmation notification", %{
      attrs: attrs
    } do
      assert {:ok, player} = Accounts.register_player(attrs)

      assert player.id
      assert player.username == attrs.username
      assert Bcrypt.verify_pass("Valid1!Pass", player.hashed_password)

      notification =
        Repo.get_by!(Cuevolution.Notifications.Notification,
          player_id: player.id,
          event_type: "registration_confirmation"
        )

      assert notification.channel == "email"
      assert notification.status == "pending"
    end

    test "rejects invalid attrs and creates no account", %{attrs: attrs} do
      invalid_attrs = %{attrs | date_of_birth: Date.add(Date.utc_today(), -365 * 10)}

      assert {:error, changeset} = Accounts.register_player(invalid_attrs)
      refute changeset.valid?
      refute Repo.get_by(Cuevolution.Accounts.Player, username: attrs.username)
    end

    test "rejects a mobile number that's already registered, regardless of format", %{
      attrs: attrs
    } do
      insert(:player, mobile_number: "+254712345678")
      dup_attrs = %{attrs | mobile_number: "0712345678"}

      assert {:error, changeset} = Accounts.register_player(dup_attrs)
      assert "has already been taken" in errors_on(changeset).mobile_number
      refute Repo.get_by(Cuevolution.Accounts.Player, username: attrs.username)
    end

    test "rejects an 'Other' venue name that already exists as a real venue in the region", %{
      attrs: attrs
    } do
      insert(:venue, region_id: attrs.region_id, name: "Cue Sports Pool")
      dup_attrs = %{attrs | other_venue_name: "cue sports pool"}

      assert {:error, changeset} = Accounts.register_player(dup_attrs)

      assert "is already a listed venue — please select it instead of entering it as \"Other\"" in errors_on(
               changeset
             ).other_venue_name

      refute Repo.get_by(Cuevolution.Accounts.Player, username: attrs.username)
    end

    test "allows an 'Other' venue name that matches a venue in a different region", %{
      attrs: attrs
    } do
      other_region = build(:region)
      insert(:venue, region_id: other_region.id, name: "Cue Sports Pool")
      dup_attrs = %{attrs | other_venue_name: "Cue Sports Pool"}

      assert {:ok, _player} = Accounts.register_player(dup_attrs)
    end

    test "allows an 'Other' venue name that only matches a deactivated venue", %{attrs: attrs} do
      insert(:venue, region_id: attrs.region_id, name: "Cue Sports Pool", active: false)
      dup_attrs = %{attrs | other_venue_name: "Cue Sports Pool"}

      assert {:ok, _player} = Accounts.register_player(dup_attrs)
    end
  end

  describe "update_notification_preference/2" do
    test "persists the new preference" do
      player = insert(:player, notification_preference: "email")

      assert {:ok, updated} = Accounts.update_notification_preference(player, "both")
      assert updated.notification_preference == "both"
      assert Repo.get!(Cuevolution.Accounts.Player, player.id).notification_preference == "both"
    end

    test "rejects an invalid preference value" do
      player = insert(:player, notification_preference: "email")

      assert {:error, changeset} =
               Accounts.update_notification_preference(player, "carrier_pigeon")

      refute changeset.valid?
      assert Repo.get!(Cuevolution.Accounts.Player, player.id).notification_preference == "email"
    end
  end

  describe "authenticate_player/2" do
    test "returns the player given correct email and password" do
      player = insert(:player, hashed_password: Bcrypt.hash_pwd_salt("correct_password"))

      assert {:ok, authenticated} = Accounts.authenticate_player(player.email, "correct_password")
      assert authenticated.id == player.id
    end

    test "returns a generic error given an incorrect password" do
      player = insert(:player, hashed_password: Bcrypt.hash_pwd_salt("correct_password"))

      assert {:error, :invalid_credentials} =
               Accounts.authenticate_player(player.email, "wrong_password")
    end

    test "returns the same generic error given a non-existent email" do
      assert {:error, :invalid_credentials} =
               Accounts.authenticate_player("nobody@cuevolution.test", "whatever")
    end

    test "authenticates by username as well as email" do
      player =
        insert(:player,
          username: "PlayerOne",
          hashed_password: Bcrypt.hash_pwd_salt("correct_password")
        )

      assert {:ok, authenticated} =
               Accounts.authenticate_player("PlayerOne", "correct_password")

      assert authenticated.id == player.id
    end

    test "authenticates by username case-insensitively" do
      player =
        insert(:player,
          username: "PlayerOne",
          hashed_password: Bcrypt.hash_pwd_salt("correct_password")
        )

      assert {:ok, authenticated} =
               Accounts.authenticate_player("playerone", "correct_password")

      assert authenticated.id == player.id
    end

    test "returns the generic error given a non-existent username" do
      assert {:error, :invalid_credentials} =
               Accounts.authenticate_player("nosuchuser", "whatever")
    end
  end

  describe "player session tokens" do
    test "generate_player_session_token/1 and get_player_by_session_token/1 round-trip" do
      player = insert(:player)

      token = Accounts.generate_player_session_token(player)

      assert %Cuevolution.Accounts.Player{id: id} = Accounts.get_player_by_session_token(token)
      assert id == player.id
    end

    test "an unknown token resolves to nil" do
      assert Accounts.get_player_by_session_token("not_a_real_token") == nil
    end

    test "player and admin session tokens share zero state" do
      player = insert(:player)
      admin = insert(:admin)

      player_token = Accounts.generate_player_session_token(player)
      admin_token = Accounts.generate_admin_session_token(admin)

      assert Accounts.get_admin_by_session_token(player_token) == nil
      assert Accounts.get_player_by_session_token(admin_token) == nil
    end
  end

  describe "get_player_by_login/1" do
    test "finds the player by email, case-insensitively" do
      player = insert(:player, email: "Findme@Example.com")
      assert Accounts.get_player_by_login("findme@example.com").id == player.id
    end

    test "finds the player by username, case-insensitively" do
      player = insert(:player, username: "FindMe")
      assert Accounts.get_player_by_login("findme").id == player.id
    end

    test "returns nil for a login matching no player" do
      assert Accounts.get_player_by_login("nobody-at-all") == nil
    end
  end

  describe "deliver_player_reset_password_instructions/2 and get_player_by_reset_password_token/1" do
    test "enqueues a reset email whose URL round-trips to the player" do
      player = insert(:player, notification_preference: "sms")

      assert {:ok, _job} =
               Accounts.deliver_player_reset_password_instructions(
                 player,
                 &"https://cuevolution.test/reset-password/#{&1}"
               )

      assert_enqueued(
        worker: Cuevolution.Notifications.Workers.SendPasswordResetEmailWorker,
        args: %{"player_id" => player.id}
      )

      [job] = all_enqueued(worker: Cuevolution.Notifications.Workers.SendPasswordResetEmailWorker)
      "https://cuevolution.test/reset-password/" <> token = job.args["reset_url"]

      assert Accounts.get_player_by_reset_password_token(token).id == player.id
    end

    test "requesting a second link invalidates the first" do
      player = insert(:player)

      Accounts.deliver_player_reset_password_instructions(
        player,
        &"https://cuevolution.test/reset-password/#{&1}"
      )

      [first_job] =
        all_enqueued(worker: Cuevolution.Notifications.Workers.SendPasswordResetEmailWorker)

      "https://cuevolution.test/reset-password/" <> first_token = first_job.args["reset_url"]

      Accounts.deliver_player_reset_password_instructions(
        player,
        &"https://cuevolution.test/reset-password/#{&1}"
      )

      assert Accounts.get_player_by_reset_password_token(first_token) == nil
    end

    test "an unknown or garbage token resolves to nil" do
      assert Accounts.get_player_by_reset_password_token("garbage") == nil
    end
  end

  describe "reset_player_password/2" do
    test "updates the password and invalidates every existing token" do
      player = insert(:player, hashed_password: Bcrypt.hash_pwd_salt("Old-Pass1!"))
      session_token = Accounts.generate_player_session_token(player)

      assert {:ok, updated} =
               Accounts.reset_player_password(player, %{
                 "password" => "New-Pass1!",
                 "password_confirmation" => "New-Pass1!"
               })

      assert Bcrypt.verify_pass("New-Pass1!", updated.hashed_password)
      assert Accounts.get_player_by_session_token(session_token) == nil
    end

    test "rejects a weak password without changing the stored hash" do
      player = insert(:player, hashed_password: Bcrypt.hash_pwd_salt("Old-Pass1!"))

      assert {:error, changeset} =
               Accounts.reset_player_password(player, %{
                 "password" => "short",
                 "password_confirmation" => "short"
               })

      refute changeset.valid?
      assert Bcrypt.verify_pass("Old-Pass1!", Repo.get!(Player, player.id).hashed_password)
    end

    test "rejects a mismatched confirmation" do
      player = insert(:player)

      assert {:error, changeset} =
               Accounts.reset_player_password(player, %{
                 "password" => "New-Pass1!",
                 "password_confirmation" => "Different1!"
               })

      assert "does not match" in errors_on(changeset).password_confirmation
    end
  end

  defp player_registration_attrs(overrides \\ %{}) do
    region = build(:region)

    Map.merge(
      %{
        first_name: "Jane",
        last_name: "Doe",
        date_of_birth: Date.add(Date.utc_today(), -365 * 20),
        gender: "female",
        email: "jane-#{System.unique_integer([:positive])}@example.com",
        mobile_number: "0712345678",
        location: "Nairobi",
        username: "janedoe#{System.unique_integer([:positive])}",
        notification_preference: "email",
        region_id: region.id,
        other_venue_name: "Test Venue",
        password: "Valid1!Pass"
      },
      overrides
    )
  end

  describe "region_locked?/1 and change_region/2" do
    test "unlocked for a player with no match result" do
      player = insert(:player)
      refute Accounts.region_locked?(player)
    end

    test "locked for a player with a recorded match result" do
      player = insert(:player)

      participation =
        insert(:stage_participation,
          player_id: player.id,
          region_id: player.region_id,
          category: player.gender
        )

      fixture = insert(:fixture, participant_a_id: participation.id)
      admin = insert(:admin)

      {:ok, _result} =
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => participation.id
        })

      assert Accounts.region_locked?(player)
    end

    test "change_region/2 updates the region when unlocked" do
      player = insert(:player)
      new_region = build(:region)

      assert {:ok, updated} = Accounts.change_region(player, new_region.id)
      assert updated.region_id == new_region.id
    end

    test "change_region/2 rejects the change when locked, even bypassing any UI check" do
      player = insert(:player)

      participation =
        insert(:stage_participation,
          player_id: player.id,
          region_id: player.region_id,
          category: player.gender
        )

      fixture = insert(:fixture, participant_a_id: participation.id)
      admin = insert(:admin)

      {:ok, _result} =
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => participation.id
        })

      new_region = build(:region)
      assert {:error, :region_locked} = Accounts.change_region(player, new_region.id)
    end
  end

  describe "update_personal_details/2" do
    test "updates username, date of birth, and town" do
      player = insert(:player, username: "oldname", location: "Mombasa")

      assert {:ok, updated} =
               Accounts.update_personal_details(player, %{
                 "username" => "newname",
                 "date_of_birth" => "1990-05-15",
                 "location" => "Kisumu"
               })

      assert updated.username == "newname"
      assert updated.date_of_birth == ~D[1990-05-15]
      assert updated.location == "Kisumu"
    end

    test "rejects a username already taken by another player" do
      insert(:player, username: "takenname")
      player = insert(:player, username: "myname")

      assert {:error, changeset} =
               Accounts.update_personal_details(player, %{"username" => "takenname"})

      assert "has already been taken" in errors_on(changeset).username
    end

    test "rejects a date of birth under the minimum age" do
      player = insert(:player)
      too_young = Date.utc_today() |> Date.add(-365 * 10)

      assert {:error, changeset} =
               Accounts.update_personal_details(player, %{
                 "date_of_birth" => Date.to_iso8601(too_young)
               })

      assert "must be at least 18 years old" in errors_on(changeset).date_of_birth
    end

    test "does not touch fields it doesn't manage" do
      player = insert(:player, email: "keep@example.com")

      assert {:ok, updated} =
               Accounts.update_personal_details(player, %{"location" => "Nakuru"})

      assert updated.email == "keep@example.com"
    end
  end

  describe "anonymize_warnings/1" do
    test "returns [] for a non-captain player with no pending fixtures" do
      player = insert(:player)
      assert Accounts.anonymize_warnings(player) == []
    end

    test "flags :captain for a team captain" do
      captain = insert(:player)
      {:ok, _team} = Teams.create_team(captain, %{"name" => "The Sharks"})

      assert :captain in Accounts.anonymize_warnings(captain)
    end

    test "flags :pending_fixtures for a player with an unplayed fixture" do
      player = insert(:player)

      participation =
        insert(:stage_participation,
          player_id: player.id,
          region_id: player.region_id,
          category: player.gender
        )

      insert(:fixture, participant_a_id: participation.id)

      assert :pending_fixtures in Accounts.anonymize_warnings(player)
    end

    test "flags both when the player is a captain with a pending fixture" do
      captain = insert(:player)
      {:ok, _team} = Teams.create_team(captain, %{"name" => "The Sharks"})

      participation =
        insert(:stage_participation,
          player_id: captain.id,
          region_id: captain.region_id,
          category: captain.gender
        )

      insert(:fixture, participant_a_id: participation.id)

      warnings = Accounts.anonymize_warnings(captain)
      assert :captain in warnings
      assert :pending_fixtures in warnings
    end
  end

  describe "anonymize_player/2" do
    test "clears PII, sets anonymized_at, and logs the admin action" do
      player = insert(:player)
      admin = insert(:admin)

      assert {:ok, anonymized} = Accounts.anonymize_player(player, admin)

      assert anonymized.first_name == "Former"
      assert anonymized.last_name == "Player"
      assert anonymized.email != player.email
      assert anonymized.mobile_number != player.mobile_number
      assert anonymized.username != player.username
      assert anonymized.anonymized_at

      log =
        Repo.get_by!(Cuevolution.Accounts.AdminActionLog,
          entity_id: player.id,
          action_type: "anonymize_player"
        )

      assert log.admin_id == admin.id
    end

    test "leaves historical match results untouched" do
      player = insert(:player)
      admin = insert(:admin)

      participation =
        insert(:stage_participation,
          player_id: player.id,
          region_id: player.region_id,
          category: player.gender
        )

      fixture = insert(:fixture, participant_a_id: participation.id)

      {:ok, result} =
        Competitions.record_result(fixture, admin, %{
          "winner_participation_id" => participation.id
        })

      {:ok, _anonymized} = Accounts.anonymize_player(player, admin)

      persisted = Repo.get!(Cuevolution.Competitions.MatchResult, result.id)
      assert persisted.winner_participation_id == participation.id
    end

    test "login is rejected after anonymization" do
      player = insert(:player, hashed_password: Bcrypt.hash_pwd_salt("Valid1!Pass"))
      admin = insert(:admin)

      original_username = player.username
      {:ok, _anonymized} = Accounts.anonymize_player(player, admin)

      assert {:error, :invalid_credentials} =
               Accounts.authenticate_player(original_username, "Valid1!Pass")
    end
  end

  describe "deactivate_player/1" do
    test "clears PII and sets anonymized_at, without an admin action log" do
      player = insert(:player)

      assert {:ok, deactivated} = Accounts.deactivate_player(player)

      assert deactivated.first_name == "Former"
      assert deactivated.last_name == "Player"
      assert deactivated.email != player.email
      assert deactivated.username != player.username
      assert deactivated.anonymized_at

      refute Repo.get_by(Cuevolution.Accounts.AdminActionLog, entity_id: player.id)
    end

    test "invalidates every session token for the player" do
      player = insert(:player)
      token = Accounts.generate_player_session_token(player)

      assert {:ok, _deactivated} = Accounts.deactivate_player(player)

      refute Accounts.get_player_by_session_token(token)
    end

    test "login is rejected after deactivation" do
      player = insert(:player, hashed_password: Bcrypt.hash_pwd_salt("Valid1!Pass"))
      original_username = player.username

      {:ok, _deactivated} = Accounts.deactivate_player(player)

      assert {:error, :invalid_credentials} =
               Accounts.authenticate_player(original_username, "Valid1!Pass")
    end
  end
end
