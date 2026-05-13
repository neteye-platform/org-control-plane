locals {
  yaml_files     = fileset(var.repos_yaml_dir, "*.yaml")
  _decoded_yamls = [for f in local.yaml_files : yamldecode(file("${var.repos_yaml_dir}/${f}"))]
  repo_yamls     = { for y in local._decoded_yamls : y.name => y }

  # Three-tier merge for repository settings (org → category → repo)
  repos = {
    for name, yaml in local.repo_yamls :
    name => merge(
      var.org_defaults,
      var.category_defaults,
      yaml,
    )
  }

  # Shorthand references to each tier's branch_ruleset (avoids deep-path repetition)
  _org_rs = var.org_defaults.branch_ruleset
  _cat_rs = try(var.category_defaults.branch_ruleset, {})

  # One ruleset per repo — scalar fields: repo > category > org; additive fields: concat + deduplicate
  ruleset_configs = {
    for repo_name in keys(local.repos) :
    repo_name => {
      name        = coalesce(try(local.repo_yamls[repo_name].branch_ruleset.name, null), try(local._cat_rs.name, null), local._org_rs.name)
      enforcement = coalesce(try(local.repo_yamls[repo_name].branch_ruleset.enforcement, null), try(local._cat_rs.enforcement, null), local._org_rs.enforcement)

      targets = distinct(concat(
        local._org_rs.targets,
        try(local._cat_rs.targets, []),
        try(local.repo_yamls[repo_name].branch_ruleset.targets, [])
      ))

      restrict_deletions     = coalesce(try(local.repo_yamls[repo_name].branch_ruleset.restrict_deletions, null), try(local._cat_rs.restrict_deletions, null), local._org_rs.restrict_deletions)
      require_signed_commits = coalesce(try(local.repo_yamls[repo_name].branch_ruleset.require_signed_commits, null), try(local._cat_rs.require_signed_commits, null), local._org_rs.require_signed_commits)
      block_force_pushes     = coalesce(try(local.repo_yamls[repo_name].branch_ruleset.block_force_pushes, null), try(local._cat_rs.block_force_pushes, null), local._org_rs.block_force_pushes)

      copilot_review_on_push   = coalesce(try(local.repo_yamls[repo_name].branch_ruleset.copilot_review_on_push, null), try(local._cat_rs.copilot_review_on_push, null), local._org_rs.copilot_review_on_push)
      copilot_review_draft_prs = coalesce(try(local.repo_yamls[repo_name].branch_ruleset.copilot_review_draft_pull_requests, null), try(local._cat_rs.copilot_review_draft_pull_requests, null), local._org_rs.copilot_review_draft_pull_requests)

      strict_status_checks = coalesce(try(local.repo_yamls[repo_name].branch_ruleset.require_status_checks.strict, null), try(local._cat_rs.require_status_checks.strict, null), local._org_rs.require_status_checks.strict)

      checks = distinct(concat(
        local._org_rs.require_status_checks.checks,
        try(local._cat_rs.require_status_checks.extra_checks, []),
        try(local.repo_yamls[repo_name].branch_ruleset.require_status_checks.extra_checks, [])
      ))

      bypass_actors = distinct(concat(
        local._org_rs.bypass_actors,
        try(local._cat_rs.extra_bypass_actors, []),
        try(local.repo_yamls[repo_name].branch_ruleset.extra_bypass_actors, [])
      ))

      pr_required_approving_review_count   = coalesce(try(local.repo_yamls[repo_name].branch_ruleset.pull_request.required_approving_review_count, null), try(local._cat_rs.pull_request.required_approving_review_count, null), local._org_rs.pull_request.required_approving_review_count)
      pr_dismiss_stale_reviews_on_push     = coalesce(try(local.repo_yamls[repo_name].branch_ruleset.pull_request.dismiss_stale_reviews_on_push, null), try(local._cat_rs.pull_request.dismiss_stale_reviews_on_push, null), local._org_rs.pull_request.dismiss_stale_reviews_on_push)
      pr_require_last_push_approval        = coalesce(try(local.repo_yamls[repo_name].branch_ruleset.pull_request.require_last_push_approval, null), try(local._cat_rs.pull_request.require_last_push_approval, null), local._org_rs.pull_request.require_last_push_approval)
      pr_require_code_owner_review         = coalesce(try(local.repo_yamls[repo_name].branch_ruleset.pull_request.require_code_owner_review, null), try(local._cat_rs.pull_request.require_code_owner_review, null), local._org_rs.pull_request.require_code_owner_review)
      pr_required_review_thread_resolution = coalesce(try(local.repo_yamls[repo_name].branch_ruleset.pull_request.required_review_thread_resolution, null), try(local._cat_rs.pull_request.required_review_thread_resolution, null), local._org_rs.pull_request.required_review_thread_resolution)
    }
  }
}
