# Merge of the repository rulesets across the three tiers.
# The provider is mocked: `terraform init -backend=false && terraform test`.

mock_provider "github" {}

variables {
  settings = {
    defaults = {
      org = {
        branch_rulesets = {
          main = {
            bypass_actors       = [{ actor_id = 5, actor_type = "RepositoryRole", bypass_mode = "pull_request" }]
            extra_bypass_actors = [{ actor_id = 1, actor_type = "Team", bypass_mode = "always" }]
            conditions = {
              ref_name = {
                include = ["~DEFAULT_BRANCH", "release/*", "refs/tags/v*"]
                exclude = ["tmp/*"]
              }
            }
            rules = {
              creation         = false
              deletion         = true
              non_fast_forward = true
              pull_request = {
                required_approving_review_count = 1
                dismiss_stale_reviews_on_push   = true
                allowed_merge_methods           = ["squash"]
              }
              required_status_checks = {
                strict_required_status_checks_policy = true
                do_not_enforce_on_create             = true
                required_check                       = [{ context = "org-check", integration_id = 15368 }]
              }
              required_code_scanning = {
                required_code_scanning_tool = [
                  { tool = "CodeQL", alerts_threshold = "errors", security_alerts_threshold = "high_or_higher" },
                  { tool = "Semgrep" },
                ]
              }
              merge_queue         = { merge_method = "SQUASH", max_entries_to_merge = 3 }
              copilot_code_review = { review_on_push = false, review_draft_pull_requests = false }
            }
          }
          tags = {
            target = "tag"
            rules  = { update = true }
          }
        }
      }
      category = {
        branch_rulesets = {
          main = {
            extra_bypass_actors = [{ actor_id = 0, actor_type = "DeployKey", bypass_mode = "always" }]
            conditions          = { ref_name = { include = ["maint-*"], exclude = ["wip/*"] } }
            rules = {
              required_status_checks = { required_check = [{ context = "category-check" }] }
              required_code_scanning = {
                required_code_scanning_tool = [{ tool = "CodeQL", alerts_threshold = "errors_and_warnings" }]
              }
              copilot_code_review = { review_on_push = true }
            }
          }
        }
      }
    }
    repositories = {
      inherits = { name = "inherits", description = "Inherits the rulesets" }
      changes = {
        name        = "changes"
        description = "Changes the rulesets"
        branch_rulesets = {
          main = {
            bypass_actors = []
            conditions    = { ref_name = { include_override = ["main"] } }
            rules = {
              deletion               = false
              pull_request           = { required_approving_review_count = 2 }
              required_status_checks = { required_check_override = [{ context = "repo-check" }], do_not_enforce_on_create = false }
              merge_queue            = { grouping_strategy = "HEADGREEN" }
            }
          }
          repo-only = {
            enforcement = "evaluate"
            rules       = { required_signatures = true }
          }
        }
      }
    }
  }
}

run "rulesets_are_collected_from_every_tier" {
  command = plan

  assert {
    condition     = keys(local.ruleset_configs) == ["changes/main", "changes/repo-only", "changes/tags", "inherits/main", "inherits/tags"]
    error_message = "every repository must get the inherited rulesets plus its own"
  }

  assert {
    condition = (
      github_repository_ruleset.rulesets["inherits/main"].target == "branch" &&
      github_repository_ruleset.rulesets["inherits/main"].enforcement == "active" &&
      github_repository_ruleset.rulesets["inherits/tags"].target == "tag" &&
      github_repository_ruleset.rulesets["changes/repo-only"].enforcement == "evaluate" &&
      github_repository_ruleset.rulesets["changes/repo-only"].name == "repo-only" &&
      github_repository_ruleset.rulesets["changes/repo-only"].repository == "changes"
    )
    error_message = "target must default to branch, enforcement to active"
  }
}

run "bypass_actors" {
  command = plan

  assert {
    condition = (
      [for a in local.ruleset_configs["inherits/main"].bypass_actors : a.actor_type] == ["RepositoryRole", "Team", "DeployKey"]
    )
    error_message = "inherited bypass_actors must be kept, and extra_bypass_actors added from the org and the category"
  }

  assert {
    condition     = [for a in local.ruleset_configs["changes/main"].bypass_actors : a.actor_type] == ["Team", "DeployKey"]
    error_message = "an empty bypass_actors must remove the inherited actors but keep extra_bypass_actors"
  }
}

run "ref_conditions" {
  command = plan

  assert {
    condition = (
      local.ruleset_configs["inherits/main"].conditions.ref_name.include == ["~DEFAULT_BRANCH", "refs/heads/release/*", "refs/tags/v*", "refs/heads/maint-*"]
    )
    error_message = "include must be additive, short names must become refs/heads/ and refs/ or ~ patterns must stay as they are"
  }

  assert {
    condition     = local.ruleset_configs["changes/main"].conditions.ref_name.include == ["refs/heads/main"]
    error_message = "a repository include_override must replace the inherited include list"
  }

  assert {
    condition = (
      local.ruleset_configs["inherits/main"].conditions.ref_name.exclude == ["refs/heads/tmp/*", "refs/heads/wip/*"] &&
      local.ruleset_configs["changes/main"].conditions.ref_name.exclude == ["refs/heads/tmp/*", "refs/heads/wip/*"]
    )
    error_message = "exclude must be additive"
  }
}

run "rule_scalars_and_pull_request" {
  command = plan

  assert {
    condition = (
      local.ruleset_configs["inherits/main"].rules.deletion == true &&
      local.ruleset_configs["inherits/main"].rules.creation == false &&
      local.ruleset_configs["changes/main"].rules.deletion == false &&
      local.ruleset_configs["changes/main"].rules.non_fast_forward == true &&
      local.ruleset_configs["inherits/main"].rules.update == null
    )
    error_message = "each rule flag must come from the most specific tier that sets it, also when it is false"
  }

  assert {
    condition = (
      github_repository_ruleset.rulesets["inherits/main"].rules[0].pull_request[0].required_approving_review_count == 1 &&
      github_repository_ruleset.rulesets["changes/main"].rules[0].pull_request[0].required_approving_review_count == 2 &&
      github_repository_ruleset.rulesets["changes/main"].rules[0].pull_request[0].dismiss_stale_reviews_on_push == true &&
      length(github_repository_ruleset.rulesets["changes/main"].rules[0].pull_request[0].allowed_merge_methods) == 1 &&
      contains(github_repository_ruleset.rulesets["changes/main"].rules[0].pull_request[0].allowed_merge_methods, "squash")
    )
    error_message = "pull_request fields must merge one by one"
  }

  assert {
    condition = (
      length(github_repository_ruleset.rulesets["changes/repo-only"].rules[0].pull_request) == 0 &&
      length(github_repository_ruleset.rulesets["changes/repo-only"].rules[0].required_status_checks) == 0 &&
      length(github_repository_ruleset.rulesets["changes/repo-only"].rules[0].required_code_scanning) == 0 &&
      length(github_repository_ruleset.rulesets["changes/repo-only"].rules[0].copilot_code_review) == 0 &&
      github_repository_ruleset.rulesets["changes/repo-only"].rules[0].required_signatures == true
    )
    error_message = "optional rule blocks must exist only when a tier sets them"
  }
}

run "required_status_checks" {
  command = plan

  assert {
    condition = (
      [for c in local.ruleset_configs["inherits/main"].rules.required_status_checks.required_check : c.context] == ["org-check", "category-check"] &&
      local.ruleset_configs["inherits/main"].rules.required_status_checks.required_check[0].integration_id == 15368 &&
      local.ruleset_configs["inherits/main"].rules.required_status_checks.required_check[1].integration_id == null
    )
    error_message = "required_check must be additive, with an optional integration_id"
  }

  assert {
    condition = (
      [for c in local.ruleset_configs["changes/main"].rules.required_status_checks.required_check : c.context] == ["repo-check"] &&
      github_repository_ruleset.rulesets["changes/main"].rules[0].required_status_checks[0].strict_required_status_checks_policy == true &&
      github_repository_ruleset.rulesets["inherits/main"].rules[0].required_status_checks[0].do_not_enforce_on_create == true &&
      github_repository_ruleset.rulesets["changes/main"].rules[0].required_status_checks[0].do_not_enforce_on_create == false
    )
    error_message = "a repository required_check_override must replace the inherited checks, the other fields stay inherited"
  }
}

run "code_scanning" {
  command = plan

  assert {
    condition = (
      { for t in github_repository_ruleset.rulesets["inherits/main"].rules[0].required_code_scanning[0].required_code_scanning_tool :
      t.tool => [t.alerts_threshold, t.security_alerts_threshold] } ==
      { CodeQL = ["errors_and_warnings", "none"], Semgrep = ["none", "none"] }
    )
    error_message = "tools must merge by name, the most specific tier wins, and thresholds must default to none"
  }
}

run "merge_queue" {
  command = plan

  assert {
    condition = (
      github_repository_ruleset.rulesets["inherits/main"].rules[0].merge_queue[0].merge_method == "SQUASH" &&
      github_repository_ruleset.rulesets["inherits/main"].rules[0].merge_queue[0].max_entries_to_merge == 3 &&
      github_repository_ruleset.rulesets["inherits/main"].rules[0].merge_queue[0].grouping_strategy == "ALLGREEN" &&
      github_repository_ruleset.rulesets["inherits/main"].rules[0].merge_queue[0].check_response_timeout_minutes == 60 &&
      github_repository_ruleset.rulesets["inherits/main"].rules[0].merge_queue[0].min_entries_to_merge == 1 &&
      github_repository_ruleset.rulesets["inherits/main"].rules[0].merge_queue[0].min_entries_to_merge_wait_minutes == 5 &&
      github_repository_ruleset.rulesets["inherits/main"].rules[0].merge_queue[0].max_entries_to_build == 5
    )
    error_message = "an inherited merge_queue must keep its fields and get the built-in defaults"
  }

  assert {
    condition = (
      github_repository_ruleset.rulesets["changes/main"].rules[0].merge_queue[0].grouping_strategy == "HEADGREEN" &&
      github_repository_ruleset.rulesets["changes/main"].rules[0].merge_queue[0].merge_method == "MERGE" &&
      github_repository_ruleset.rulesets["changes/main"].rules[0].merge_queue[0].max_entries_to_merge == 5 &&
      length(github_repository_ruleset.rulesets["changes/repo-only"].rules[0].merge_queue) == 0
    )
    error_message = "a repository merge_queue must replace the inherited object entirely"
  }
}

run "copilot_code_review" {
  command = plan

  assert {
    condition = (
      github_repository_ruleset.rulesets["inherits/main"].rules[0].copilot_code_review[0].review_on_push == true &&
      github_repository_ruleset.rulesets["inherits/main"].rules[0].copilot_code_review[0].review_draft_pull_requests == false
    )
    error_message = "copilot_code_review fields must merge one by one"
  }
}

run "category_overrides" {
  command = plan

  variables {
    settings = {
      defaults = {
        org = {
          branch_rulesets = {
            main = {
              conditions = { ref_name = { include = ["main"] } }
              rules      = { required_status_checks = { required_check = [{ context = "org-check" }] } }
            }
          }
        }
        category = {
          branch_rulesets = {
            main = {
              conditions = { ref_name = { include_override = ["develop"] } }
              rules      = { required_status_checks = { required_check_override = [{ context = "category-check" }] } }
            }
          }
        }
      }
      repositories = {
        inherits = { name = "inherits", description = "Inherits the category overrides" }
        adds = {
          name        = "adds"
          description = "Adds to the overridden lists"
          branch_rulesets = {
            main = {
              conditions = { ref_name = { include = ["feature/*"] } }
              rules      = { required_status_checks = { required_check = [{ context = "repo-check" }] } }
            }
          }
        }
      }
    }
  }

  assert {
    condition = (
      local.ruleset_configs["inherits/main"].conditions.ref_name.include == ["refs/heads/develop"] &&
      [for c in local.ruleset_configs["inherits/main"].rules.required_status_checks.required_check : c.context] == ["category-check"]
    )
    error_message = "a category override must replace the org list"
  }

  assert {
    condition = (
      local.ruleset_configs["adds/main"].conditions.ref_name.include == ["refs/heads/develop"] &&
      [for c in local.ruleset_configs["adds/main"].rules.required_status_checks.required_check : c.context] == ["category-check"]
    )
    error_message = "a category override must also replace what the repository adds"
  }
}

run "tag_rulesets_expand_short_names_to_tags" {
  command = plan

  variables {
    settings = {
      defaults = {
        org = {
          branch_rulesets = {
            releases = {
              conditions = { ref_name = { include = ["v*", "refs/heads/keep"], exclude = ["v0*"] } }
            }
          }
        }
        # The target comes from another tier than the patterns.
        category = {
          branch_rulesets = {
            releases = { target = "tag" }
          }
        }
      }
      repositories = {
        repo = { name = "repo", description = "Repository" }
      }
    }
  }

  assert {
    condition = (
      github_repository_ruleset.rulesets["repo/releases"].target == "tag" &&
      local.ruleset_configs["repo/releases"].conditions.ref_name.include == ["refs/tags/v*", "refs/heads/keep"] &&
      local.ruleset_configs["repo/releases"].conditions.ref_name.exclude == ["refs/tags/v0*"]
    )
    error_message = "short names of a tag ruleset must become refs/tags/..."
  }
}
