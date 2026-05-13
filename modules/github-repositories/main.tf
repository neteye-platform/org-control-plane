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

resource "github_repository_ruleset" "main_protection" {
  for_each    = local.ruleset_configs
  name        = each.value.name
  repository  = github_repository.repos[each.key].name
  target      = "branch"
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
      include = [for t in each.value.targets : "refs/heads/${t}"]
      exclude = []
    }
  }

  rules {
    deletion            = each.value.restrict_deletions
    non_fast_forward    = each.value.block_force_pushes
    required_signatures = each.value.require_signed_commits

    required_status_checks {
      strict_required_status_checks_policy = each.value.strict_status_checks

      dynamic "required_check" {
        for_each = each.value.checks
        content {
          context = required_check.value
        }
      }
    }

    pull_request {
      required_approving_review_count   = each.value.pr_required_approving_review_count
      dismiss_stale_reviews_on_push     = each.value.pr_dismiss_stale_reviews_on_push
      require_last_push_approval        = each.value.pr_require_last_push_approval
      require_code_owner_review         = each.value.pr_require_code_owner_review
      required_review_thread_resolution = each.value.pr_required_review_thread_resolution
    }

    copilot_code_review {
      review_on_push             = each.value.copilot_review_on_push
      review_draft_pull_requests = each.value.copilot_review_draft_prs
    }
  }
}
