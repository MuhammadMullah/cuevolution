defmodule Cuevolution.Accounts.AdminPermissionsTest do
  use ExUnit.Case, async: true

  alias Cuevolution.Accounts.Admin

  test "role labels match the admin product language" do
    assert Admin.role_label("super_admin") == "Super Admin"
    assert Admin.role_label("tournament_director") == "Tournament Director"
    assert Admin.role_label("regional_coordinator") == "Regional Coordinator"
    assert Admin.role_label("venue_representative") == "Venue Representative"
  end

  test "permissions match the four admin roles" do
    super_admin = %Admin{role: "super_admin"}
    director = %Admin{role: "tournament_director"}
    coordinator = %Admin{role: "regional_coordinator"}
    venue_rep = %Admin{role: "venue_representative"}

    assert Admin.can?(super_admin, :manage_admins)
    assert Admin.can?(director, :manage_admins)
    refute Admin.can?(coordinator, :manage_admins)
    refute Admin.can?(venue_rep, :manage_venues)

    assert Admin.can?(coordinator, :approve_results)
    refute Admin.can?(coordinator, :anonymize_users)
    refute Admin.can?(venue_rep, :approve_results)
    assert Admin.can?(venue_rep, :manage_fixtures)
    assert Admin.can?(venue_rep, :record_results)
    refute Admin.can?(director, :manage_fixtures)
    refute Admin.can?(director, :record_results)
    refute Admin.can?(director, :approve_results)
  end

  test "tournament directors cannot manage super admins" do
    director = %Admin{role: "tournament_director"}
    super_admin = %Admin{role: "super_admin"}
    coordinator = %Admin{role: "regional_coordinator"}

    refute Admin.manageable_by?(director, super_admin)
    assert Admin.manageable_by?(director, coordinator)
    assert Admin.manageable_by?(super_admin, director)
  end

  test "suspended and removed admins lose permissions" do
    assert Admin.can?(%Admin{role: "super_admin"}, :manage_admins)

    refute Admin.can?(
             %Admin{role: "super_admin", suspended_at: DateTime.utc_now()},
             :manage_admins
           )

    refute Admin.can?(%Admin{role: "super_admin", removed_at: DateTime.utc_now()}, :manage_admins)
  end
end
