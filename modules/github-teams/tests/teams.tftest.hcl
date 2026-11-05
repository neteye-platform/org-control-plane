# Teams and organization roles.
# The provider is mocked: `terraform init -backend=false && terraform test`.

mock_provider "github" {
  mock_data "github_organization_roles" {
    defaults = {
      roles = [
        { role_id = 42, name = "security_manager", description = "", source = "Predefined", base_role = "", permissions = [] },
        { role_id = 43, name = "ci_cd_admin", description = "", source = "Predefined", base_role = "", permissions = [] },
      ]
    }
  }
}

variables {
  teams = {
    auditors = {
      name                 = "auditors"
      description          = "Security auditors"
      privacy              = "closed"
      notification_setting = "notifications_enabled"
      org_roles            = ["security_manager", "ci_cd_admin"]
    }
    developers = {
      name                 = "developers"
      description          = "Developers"
      privacy              = "secret"
      notification_setting = "notifications_disabled"
      parent_team_id       = "123"
    }
  }
}

run "teams" {
  command = plan

  assert {
    condition     = keys(github_team.teams) == ["auditors", "developers"]
    error_message = "one team per entry"
  }

  assert {
    condition = (
      github_team.teams["auditors"].name == "auditors" &&
      github_team.teams["auditors"].description == "Security auditors" &&
      github_team.teams["auditors"].privacy == "closed" &&
      github_team.teams["auditors"].notification_setting == "notifications_enabled" &&
      github_team.teams["auditors"].parent_team_id == null &&
      github_team.teams["developers"].privacy == "secret" &&
      github_team.teams["developers"].notification_setting == "notifications_disabled" &&
      github_team.teams["developers"].parent_team_id == "123"
    )
    error_message = "the team fields must be passed to the resource"
  }
}

run "organization_roles" {
  command = plan

  assert {
    condition = (
      keys(github_organization_role_team.role_bindings) == ["auditors-ci_cd_admin", "auditors-security_manager"] &&
      github_organization_role_team.role_bindings["auditors-security_manager"].role_id == 42 &&
      github_organization_role_team.role_bindings["auditors-ci_cd_admin"].role_id == 43
    )
    error_message = "org roles must be resolved by name, one binding per team and role"
  }
}

run "unknown_organization_role" {
  command = plan

  variables {
    teams = {
      auditors = {
        name                 = "auditors"
        description          = ""
        privacy              = "closed"
        notification_setting = "notifications_enabled"
        org_roles            = ["does_not_exist"]
      }
    }
  }

  expect_failures = [github_organization_role_team.role_bindings]
}

run "team_name_must_match_its_key" {
  command = plan

  variables {
    teams = {
      expected = { name = "other", description = "", privacy = "closed", notification_setting = "notifications_enabled" }
    }
  }

  expect_failures = [var.teams]
}
