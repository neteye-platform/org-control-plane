# Input validation and missing tiers.

mock_provider "github" {}

run "missing_and_null_defaults_are_ignored" {
  command = plan

  variables {
    settings = {
      defaults = { org = null, category = null }
      repositories = {
        alone = { name = "alone", description = "No defaults", topics = ["x"] }
      }
    }
  }

  assert {
    condition = (
      github_repository.repos["alone"].description == "No defaults" &&
      length(local.ruleset_configs) == 0 &&
      length(local.team_access_configs) == 0 &&
      length(local.labels_by_repo["alone"]) == 0
    )
    error_message = "null defaults tiers must behave like missing ones"
  }
}

run "no_defaults_key" {
  command = plan

  variables {
    settings = {
      repositories = {
        alone = { name = "alone", description = "No defaults" }
      }
    }
  }

  assert {
    condition     = keys(github_repository.repos) == ["alone"]
    error_message = "the defaults key must be optional"
  }
}

run "no_repositories" {
  command = plan

  variables {
    settings = {
      defaults = { org = { visibility = "private" } }
    }
  }

  assert {
    condition     = length(github_repository.repos) == 0
    error_message = "a category without repositories must plan no resources"
  }
}

run "repository_name_must_match_its_key" {
  command = plan

  variables {
    settings = {
      repositories = {
        expected = { name = "other", description = "Wrong name" }
      }
    }
  }

  expect_failures = [var.settings]
}

run "unknown_top_level_key" {
  command = plan

  variables {
    settings = {
      repos = {
        any = { name = "any", description = "Wrong key" }
      }
    }
  }

  expect_failures = [var.settings]
}

run "unknown_defaults_tier" {
  command = plan

  variables {
    settings = {
      defaults = { team = { visibility = "private" } }
    }
  }

  expect_failures = [var.settings]
}
