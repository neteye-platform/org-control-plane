# Merge of the repository settings, access and labels across the three tiers.
# The provider is mocked: `terraform init -backend=false && terraform test`.

mock_provider "github" {}

variables {
  settings = {
    defaults = {
      org = {
        visibility        = "public"
        has_issues        = true
        has_wiki          = false
        allow_auto_merge  = true
        team_access       = [{ team = "developers", permission = "push" }]
        user_access       = [{ username = "alice", permission = "pull" }]
        labels            = [{ name = "bug", color = "D73A4A", description = "Something is broken" }, { name = "docs", color = "0075CA" }]
        extra_team_access = [{ team = "ignored", permission = "admin" }]
        extra_user_access = [{ username = "ignored", permission = "admin" }]
        extra_labels      = [{ name = "ignored", color = "000000" }]
      }
      category = {
        has_wiki          = true
        extra_team_access = [{ team = "squad", permission = "admin" }, { team = "developers", permission = "maintain" }]
        extra_user_access = [{ username = "bob", permission = "push" }]
        extra_labels      = [{ name = "squad", color = "111111" }, { name = "bug", color = "222222" }]
      }
    }
    repositories = {
      inherits = {
        name        = "inherits"
        description = "Takes everything from the defaults"
      }
      overrides = {
        name               = "overrides"
        description        = "Overrides the defaults"
        visibility         = "private"
        has_issues         = false
        allow_auto_merge   = false
        topics             = ["terraform"]
        archive_on_destroy = true
        template           = { owner = "acme", repository = "template" }
        team_access        = [{ team = "owners", permission = "maintain" }]
        user_access        = []
        labels             = [{ name = "only", color = "FFFFFF" }]
        extra_labels       = [{ name = "only", color = "333333" }, { name = "extra", color = "444444" }]
      }
      extends = {
        name              = "extends"
        description       = "Adds to the defaults"
        extra_team_access = [{ team = "repo-team", permission = "triage" }, { team = "squad", permission = "push" }]
        extra_user_access = [{ username = "carol", permission = "admin" }]
        extra_labels      = [{ name = "repo-label", color = "555555" }, { name = "squad", color = "666666" }]
      }
    }
  }
}

run "scalars_come_from_the_most_specific_tier" {
  command = plan

  assert {
    condition     = github_repository.repos["inherits"].visibility == "public" && github_repository.repos["inherits"].has_issues == true
    error_message = "unset fields must come from the org defaults"
  }

  assert {
    condition     = github_repository.repos["inherits"].has_wiki == true
    error_message = "the category defaults must override the org defaults"
  }

  assert {
    condition = (
      github_repository.repos["overrides"].visibility == "private" &&
      github_repository.repos["overrides"].has_issues == false &&
      github_repository.repos["overrides"].allow_auto_merge == false
    )
    error_message = "repository values must override the defaults, also when they are false"
  }

  assert {
    condition     = github_repository.repos["inherits"].name == "inherits" && github_repository.repos["inherits"].description == "Takes everything from the defaults"
    error_message = "name and description must come from the repository"
  }
}

run "built_in_defaults" {
  command = plan

  assert {
    condition = (
      length(github_repository.repos["inherits"].topics) == 0 &&
      github_repository.repos["inherits"].archive_on_destroy == false &&
      length(github_repository.repos["inherits"].template) == 0
    )
    error_message = "without settings: no topics, no archive on destroy, no template"
  }

  assert {
    condition = (
      length(github_repository.repos["overrides"].topics) == 1 && contains(github_repository.repos["overrides"].topics, "terraform") &&
      github_repository.repos["overrides"].archive_on_destroy == true &&
      github_repository.repos["overrides"].template[0].owner == "acme" &&
      github_repository.repos["overrides"].template[0].repository == "template"
    )
    error_message = "topics, archive_on_destroy and template must come from the repository"
  }
}

run "team_access" {
  command = plan

  assert {
    condition = (
      keys(local.team_access_configs) == [
        "extends/developers", "extends/repo-team", "extends/squad",
        "inherits/developers", "inherits/squad",
        "overrides/owners",
      ]
    )
    error_message = "team_access must be replaced by the most specific tier, extra_team_access must be ignored in the org defaults and when the repository sets team_access"
  }

  assert {
    condition = (
      github_team_repository.access["inherits/developers"].permission == "maintain" &&
      github_team_repository.access["inherits/squad"].permission == "admin" &&
      github_team_repository.access["extends/squad"].permission == "push" &&
      github_team_repository.access["extends/repo-team"].permission == "triage" &&
      github_team_repository.access["overrides/owners"].permission == "maintain"
    )
    error_message = "extra_team_access must add teams and override the permission of a team, the repository tier last"
  }

  assert {
    condition     = github_team_repository.access["inherits/developers"].team_id == "developers" && github_team_repository.access["inherits/developers"].repository == "inherits"
    error_message = "the team slug and the repository must be passed to the resource"
  }
}

run "user_access" {
  command = plan

  assert {
    condition = (
      keys(local.user_access_configs) == ["extends/alice", "extends/bob", "extends/carol", "inherits/alice", "inherits/bob"]
    )
    error_message = "user_access must be replaced by the most specific tier, and an empty list must remove every collaborator"
  }

  assert {
    condition = (
      github_repository_collaborator.access["inherits/alice"].permission == "pull" &&
      github_repository_collaborator.access["inherits/bob"].permission == "push" &&
      github_repository_collaborator.access["extends/carol"].permission == "admin" &&
      github_repository_collaborator.access["extends/carol"].username == "carol"
    )
    error_message = "extra_user_access must add collaborators from the category and the repository"
  }
}

run "labels" {
  command = plan

  assert {
    condition = (
      { for l in local.labels_by_repo["inherits"] : l.name => l.color } ==
      { bug = "D73A4A", docs = "0075CA", squad = "111111" }
    )
    error_message = "inherited labels must keep the org labels, add the category extra_labels and never override a base label"
  }

  assert {
    condition = (
      { for l in local.labels_by_repo["overrides"] : l.name => l.color } ==
      { only = "FFFFFF", extra = "444444" }
    )
    error_message = "repository labels must replace the inherited list, drop the category extras and win over extra_labels"
  }

  assert {
    condition = (
      { for l in local.labels_by_repo["extends"] : l.name => l.color } ==
      { bug = "D73A4A", docs = "0075CA", squad = "666666", repo-label = "555555" }
    )
    error_message = "repository extra_labels must add labels and override category extra_labels with the same name"
  }

  assert {
    condition = (
      one([for l in github_issue_labels.labels["inherits"].label : l.description if l.name == "bug"]) == "Something is broken" &&
      one([for l in github_issue_labels.labels["inherits"].label : l.description if l.name == "docs"]) == null
    )
    error_message = "label descriptions must be passed to the resource, and be optional"
  }
}

run "category_lists_replace_the_org_lists" {
  command = plan

  variables {
    settings = {
      defaults = {
        org = {
          team_access = [{ team = "developers", permission = "push" }]
          user_access = [{ username = "alice", permission = "pull" }]
          labels      = [{ name = "bug", color = "D73A4A" }]
        }
        category = {
          team_access       = [{ team = "squad", permission = "admin" }]
          extra_team_access = [{ team = "helpers", permission = "triage" }]
          user_access       = [{ username = "bob", permission = "push" }]
          labels            = [{ name = "squad", color = "111111" }]
          extra_labels      = [{ name = "extra", color = "222222" }]
        }
      }
      repositories = {
        inherits = { name = "inherits", description = "Inherits the category lists" }
      }
    }
  }

  assert {
    condition     = keys(local.team_access_configs) == ["inherits/helpers", "inherits/squad"]
    error_message = "a category team_access must replace the org list, and its extra_team_access must still apply"
  }

  assert {
    condition     = keys(local.user_access_configs) == ["inherits/bob"]
    error_message = "a category user_access must replace the org list"
  }

  assert {
    condition     = toset([for l in local.labels_by_repo["inherits"] : l.name]) == toset(["squad", "extra"])
    error_message = "category labels must replace the org labels, and its extra_labels must still apply"
  }
}
