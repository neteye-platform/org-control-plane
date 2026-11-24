variable "settings" {
  description = <<-EOT
    Repository settings in three tiers, from the most generic to the most specific:
    `defaults.org`, `defaults.category` and `repositories.<name>`. Both `defaults`
    entries are optional. See the README for the merge rules of each field.
  EOT

  # The JSON Schemas in schemas/ are generated from this type: run
  # scripts/generate-schemas.py after a change. A comment line just before a
  # field becomes its description in the schema.
  type = map(map(object({
    # Repository name. Must match the file name.
    name = optional(string)
    # Short description of the repository.
    description = optional(string)
    # URL of the project homepage.
    homepage_url = optional(string)
    # Create the repository as a fork of `source_owner`/`source_repo`.
    fork = optional(bool)
    # Owner of the repository to fork.
    source_owner = optional(string)
    # Name of the repository to fork.
    source_repo = optional(string)
    # Repository visibility: public, private or internal.
    visibility = optional(string)
    # Enable GitHub Issues.
    has_issues = optional(bool)
    # Enable GitHub Discussions.
    has_discussions = optional(bool)
    # Enable GitHub Projects.
    has_projects = optional(bool)
    # Enable the GitHub wiki.
    has_wiki = optional(bool)
    # Mark the repository as a template repository.
    is_template = optional(bool)
    # Allow merge commits on pull requests.
    allow_merge_commit = optional(bool)
    # Allow squash merging on pull requests.
    allow_squash_merge = optional(bool)
    # Allow rebase merging on pull requests.
    allow_rebase_merge = optional(bool)
    # Allow auto-merge on pull requests.
    allow_auto_merge = optional(bool)
    # Allow private forks of the repository.
    allow_forking = optional(bool)
    # Title of merge commits: PR_TITLE or MERGE_MESSAGE.
    merge_commit_title = optional(string)
    # Message of merge commits: PR_BODY, PR_TITLE or BLANK.
    merge_commit_message = optional(string)
    # Title of squash commits: PR_TITLE or COMMIT_OR_PR_TITLE.
    squash_merge_commit_title = optional(string)
    # Message of squash commits: PR_BODY, COMMIT_MESSAGES or BLANK.
    squash_merge_commit_message = optional(string)
    # Delete the head branch after a pull request is merged.
    delete_branch_on_merge = optional(bool)
    # Create an initial commit when the repository is created.
    auto_init = optional(bool)
    # Name of the .gitignore template to apply on creation.
    gitignore_template = optional(string)
    # Name of the license template to apply on creation.
    license_template = optional(string)
    # Archive the repository.
    archived = optional(bool)
    # Archive the repository instead of deleting it on destroy. Default: false.
    archive_on_destroy = optional(bool)
    # Repository topics. Default: no topics.
    topics = optional(list(string))
    # Create the repository from a template repository.
    template = optional(object({
      # Owner of the template repository.
      owner = string
      # Name of the template repository.
      repository = string
      # Copy all branches of the template, not only the default branch.
      include_all_branches = optional(bool)
    }))
    # Always suggest to update pull request branches.
    allow_update_branch = optional(bool)

    # Team permissions. The most specific tier that sets this list replaces the inherited one.
    team_access = optional(list(object({
      # Team slug.
      team = string
      # One of: pull, triage, push, maintain, admin.
      permission = string
    })))
    # Team permissions added to the inherited `team_access`, keyed by team slug.
    extra_team_access = optional(list(object({
      # Team slug.
      team = string
      # One of: pull, triage, push, maintain, admin.
      permission = string
    })))
    # Collaborator permissions. The most specific tier that sets this list replaces the inherited one.
    user_access = optional(list(object({
      # GitHub username.
      username = string
      # One of: pull, triage, push, maintain, admin.
      permission = string
    })))
    # Collaborator permissions added to the inherited `user_access`, keyed by username.
    extra_user_access = optional(list(object({
      # GitHub username.
      username = string
      # One of: pull, triage, push, maintain, admin.
      permission = string
    })))
    # Issue labels. The most specific tier that sets this list replaces the inherited one. Labels not in the final list are deleted.
    labels = optional(list(object({
      # Label name.
      name = string
      # Label color as a hex code without the leading #.
      color = string
      # Label description.
      description = optional(string)
    })))
    # Labels added to the inherited `labels`. A name already in `labels` is not overridden.
    extra_labels = optional(list(object({
      # Label name.
      name = string
      # Label color as a hex code without the leading #.
      color = string
      # Label description.
      description = optional(string)
    })))

    # Repository rulesets keyed by ruleset name. The tiers are merged field by field.
    branch_rulesets = optional(map(object({
      # Ruleset target: branch, tag or push. Default: branch.
      target = optional(string)
      # Enforcement: active, evaluate or disabled. Default: active.
      enforcement = optional(string)
      # Actors that can bypass the ruleset. The most specific tier that sets this list replaces the inherited one.
      bypass_actors = optional(list(object({
        # Actor ID (team, integration or role ID).
        actor_id = number
        # One of: RepositoryRole, Team, Integration, OrganizationAdmin, DeployKey.
        actor_type = string
        # One of: always, pull_request, exempt.
        bypass_mode = string
      })))
      # Bypass actors added to `bypass_actors` from every tier.
      extra_bypass_actors = optional(list(object({
        # Actor ID (team, integration or role ID).
        actor_id = number
        # One of: RepositoryRole, Team, Integration, OrganizationAdmin, DeployKey.
        actor_type = string
        # One of: always, pull_request, exempt.
        bypass_mode = string
      })))
      # Refs the ruleset applies to.
      conditions = optional(object({
        ref_name = optional(object({
          # Ref patterns to include, added from every tier. Short names like main become refs/heads/main.
          include = optional(list(string))
          # Ref patterns that replace the inherited `include` list (repository or category tier only).
          include_override = optional(list(string))
          # Ref patterns to exclude, added from every tier.
          exclude = optional(list(string))
        }))
      }))
      # Ruleset rules. Each scalar comes from the most specific tier that sets it.
      rules = optional(object({
        # Only allow users with bypass permission to create matching refs.
        creation = optional(bool)
        # Only allow users with bypass permission to delete matching refs.
        deletion = optional(bool)
        # Only allow users with bypass permission to update matching refs.
        update = optional(bool)
        # Prevent force pushes.
        non_fast_forward = optional(bool)
        # Prevent merge commits.
        required_linear_history = optional(bool)
        # Require signed commits.
        required_signatures = optional(bool)
        # Require a pull request before merging.
        pull_request = optional(object({
          # Allowed merge methods: merge, squash, rebase.
          allowed_merge_methods = optional(list(string))
          # Number of approving reviews required.
          required_approving_review_count = optional(number)
          # Dismiss approvals when new commits are pushed.
          dismiss_stale_reviews_on_push = optional(bool)
          # Require approval of the most recent push by someone else.
          require_last_push_approval = optional(bool)
          # Require a review from code owners.
          require_code_owner_review = optional(bool)
          # Require all review threads to be resolved.
          required_review_thread_resolution = optional(bool)
        }))
        # Require status checks to pass before merging.
        required_status_checks = optional(object({
          # Require branches to be up to date before merging.
          strict_required_status_checks_policy = optional(bool)
          # Do not enforce the checks when a branch is created.
          do_not_enforce_on_create = optional(bool)
          # Required checks, added from every tier.
          required_check = optional(list(object({
            # Name of the status check.
            context = string
            # ID of the GitHub App that must report the check.
            integration_id = optional(number)
          })))
          # Required checks that replace the inherited list (repository or category tier only).
          required_check_override = optional(list(object({
            # Name of the status check.
            context = string
            # ID of the GitHub App that must report the check.
            integration_id = optional(number)
          })))
        }))
        # Require code scanning results. Tools are merged by name across tiers.
        required_code_scanning = optional(object({
          required_code_scanning_tool = optional(list(object({
            # Name of the code scanning tool.
            tool = string
            # Alert severity that blocks the merge. Default: none.
            alerts_threshold = optional(string)
            # Security alert severity that blocks the merge. Default: none.
            security_alerts_threshold = optional(string)
          })))
        }))
        # Merge queue settings. The most specific tier that sets this object replaces the inherited one.
        merge_queue = optional(object({
          # ALLGREEN or HEADGREEN. Default: ALLGREEN.
          grouping_strategy = optional(string)
          # MERGE, SQUASH or REBASE. Default: MERGE.
          merge_method = optional(string)
          # Minutes to wait for checks. Default: 60.
          check_response_timeout_minutes = optional(number)
          # Minimum entries in a merge group. Default: 1.
          min_entries_to_merge = optional(number)
          # Maximum entries in a merge group. Default: 5.
          max_entries_to_merge = optional(number)
          # Minutes to wait for the minimum group size. Default: 5.
          min_entries_to_merge_wait_minutes = optional(number)
          # Maximum entries to build at the same time. Default: 5.
          max_entries_to_build = optional(number)
        }))
        # Request a Copilot code review on pull requests.
        copilot_code_review = optional(object({
          # Review each new push.
          review_on_push = optional(bool)
          # Review draft pull requests.
          review_draft_pull_requests = optional(bool)
        }))
      }))
    })))
  })))

  validation {
    condition     = alltrue([for k in keys(var.settings) : contains(["defaults", "repositories"], k)])
    error_message = "The only allowed keys are \"defaults\" and \"repositories\"."
  }

  validation {
    condition     = alltrue([for k in keys(try(var.settings.defaults, {})) : contains(["org", "category"], k)])
    error_message = "The only allowed keys in \"defaults\" are \"org\" and \"category\"."
  }

  validation {
    condition = alltrue([
      for name, repo in try(var.settings.repositories, {}) : repo.name == null || repo.name == name
    ])
    error_message = "The \"name\" of a repository must match its key."
  }
}
