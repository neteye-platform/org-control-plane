terraform {
  required_version = ">= 1.5"
  backend "s3" {}
}

# Create GitHub repositories with full configuration
resource "github_repository" "repos" {
  for_each = local.repos

  name                        = each.key
  description                 = each.value.description
  homepage_url                = try(each.value.homepage_url, null)
  fork                        = try(each.value.fork, null)
  source_owner                = try(each.value.source_owner, null)
  source_repo                 = try(each.value.source_repo, null)
  visibility                  = each.value.visibility
  has_issues                  = each.value.has_issues
  has_discussions             = each.value.has_discussions
  has_projects                = each.value.has_projects
  has_wiki                    = each.value.has_wiki
  is_template                 = each.value.is_template
  allow_merge_commit          = each.value.allow_merge_commit
  allow_squash_merge          = each.value.allow_squash_merge
  allow_rebase_merge          = each.value.allow_rebase_merge
  allow_auto_merge            = each.value.allow_auto_merge
  allow_forking               = try(each.value.allow_forking, null)
  squash_merge_commit_title   = each.value.squash_merge_commit_title
  squash_merge_commit_message = each.value.squash_merge_commit_message
  delete_branch_on_merge      = each.value.delete_branch_on_merge
  auto_init                   = each.value.auto_init
  gitignore_template          = try(each.value.gitignore_template, null)
  license_template            = try(each.value.license_template, null)
  archived                    = each.value.archived
  archive_on_destroy          = try(each.value.archive_on_destroy, false)
  topics                      = try(each.value.topics, [])
  dynamic "template" {
    for_each = try([each.value.template], [])

    content {
      owner                = template.value.owner
      repository           = template.value.repository
      include_all_branches = template.value.include_all_branches
    }
  }
  allow_update_branch = each.value.allow_update_branch

  # Prevent recreation on taint or destroy to avoid accidental deletion of repositories
  lifecycle {
    prevent_destroy = true
  }
}

# One ruleset resource per (repo, ruleset_name) pair; keyed as "repo/ruleset"
resource "github_repository_ruleset" "rulesets" {
  for_each    = local.ruleset_configs
  name        = each.value.name
  repository  = github_repository.repos[each.value.repo_name].name
  target      = each.value.target
  enforcement = each.value.enforcement

  dynamic "bypass_actors" {
    for_each = each.value.bypass_actors
    content {
      actor_id    = bypass_actors.value.actor_id
      actor_type  = bypass_actors.value.actor_type
      bypass_mode = bypass_actors.value.bypass_mode
    }
  }

  conditions {
    ref_name {
      include = each.value.conditions.ref_name.include
      exclude = each.value.conditions.ref_name.exclude
    }
  }

  rules {
    deletion                = each.value.rules.deletion
    non_fast_forward        = each.value.rules.non_fast_forward
    required_signatures     = each.value.rules.required_signatures
    required_linear_history = each.value.rules.required_linear_history

    # Optional rule blocks: only emitted when the ruleset actually configures them
    dynamic "pull_request" {
      for_each = each.value.rules._has_pull_request ? [each.value.rules.pull_request] : []
      content {
        allowed_merge_methods             = pull_request.value.allowed_merge_methods
        required_approving_review_count   = pull_request.value.required_approving_review_count
        dismiss_stale_reviews_on_push     = pull_request.value.dismiss_stale_reviews_on_push
        require_last_push_approval        = pull_request.value.require_last_push_approval
        require_code_owner_review         = pull_request.value.require_code_owner_review
        required_review_thread_resolution = pull_request.value.required_review_thread_resolution
      }
    }

    dynamic "required_status_checks" {
      for_each = length(each.value.rules.required_status_checks.required_check) > 0 ? [each.value.rules.required_status_checks] : []
      content {
        strict_required_status_checks_policy = required_status_checks.value.strict_required_status_checks_policy
        do_not_enforce_on_create             = required_status_checks.value.do_not_enforce_on_create

        dynamic "required_check" {
          for_each = required_status_checks.value.required_check
          content {
            context        = required_check.value.context
            integration_id = try(required_check.value.integration_id, null)
          }
        }
      }
    }

    dynamic "copilot_code_review" {
      for_each = each.value.rules._has_copilot_review ? [each.value.rules.copilot_code_review] : []
      content {
        review_on_push             = copilot_code_review.value.review_on_push
        review_draft_pull_requests = copilot_code_review.value.review_draft_pull_requests
      }
    }

    dynamic "merge_queue" {
      for_each = each.value.rules.merge_queue != null ? [each.value.rules.merge_queue] : []
      content {
        grouping_strategy                 = try(merge_queue.value.grouping_strategy, "ALLGREEN")
        merge_method                      = try(merge_queue.value.merge_method, "MERGE")
        check_response_timeout_minutes    = try(merge_queue.value.check_response_timeout_minutes, 60)
        min_entries_to_merge              = try(merge_queue.value.min_entries_to_merge, 1)
        max_entries_to_merge              = try(merge_queue.value.max_entries_to_merge, 5)
        min_entries_to_merge_wait_minutes = try(merge_queue.value.min_entries_to_merge_wait_minutes, 5)
        max_entries_to_build              = try(merge_queue.value.max_entries_to_build, 5)
      }
    }
  }

  # Prevent ruleset deletion to avoid accidental loss of branch protection settings
  lifecycle {
    prevent_destroy = true
  }
}
