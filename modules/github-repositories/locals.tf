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
  _org_rs  = var.org_defaults.branch_ruleset
  _cat_rs  = try(var.category_defaults.branch_ruleset, {})
  _repo_rs = { for name, yaml in local.repo_yamls : name => try(yaml.branch_ruleset, {}) }

  # One ruleset per repo.
  # - Scalar fields:  repo > category > org    (coalesce)
  # - Additive lists: concat all three tiers   (conditions include/exclude, required_check)
  # - bypass_actors:  additive by default; full override when bypass_actors is set explicitly at repo or category level
  # - merge_queue:    highest priority tier wins entirely; omitted when not set anywhere
  ruleset_configs = {
    for repo_name in keys(local.repos) :
    repo_name => {
      name        = coalesce(try(local._repo_rs[repo_name].name, null), try(local._cat_rs.name, null), local._org_rs.name)
      target      = coalesce(try(local._repo_rs[repo_name].target, null), try(local._cat_rs.target, null), local._org_rs.target)
      enforcement = coalesce(try(local._repo_rs[repo_name].enforcement, null), try(local._cat_rs.enforcement, null), local._org_rs.enforcement)

      bypass_actors = (
        try(local._repo_rs[repo_name].bypass_actors, null) != null
        ? local._repo_rs[repo_name].bypass_actors
        : try(local._cat_rs.bypass_actors, null) != null
          ? local._cat_rs.bypass_actors
          : distinct(concat(
              local._org_rs.bypass_actors,
              try(local._cat_rs.extra_bypass_actors, []),
              try(local._repo_rs[repo_name].extra_bypass_actors, [])
            ))
      )

      conditions = {
        ref_name = {
          include = [
            for ref in distinct(concat(
              local._org_rs.conditions.ref_name.include,
              try(local._cat_rs.conditions.ref_name.include, []),
              try(local._repo_rs[repo_name].conditions.ref_name.include, [])
            )) : startswith(ref, "refs/") || startswith(ref, "~") ? ref : "refs/heads/${ref}"
          ]
          exclude = [
            for ref in distinct(concat(
              try(local._org_rs.conditions.ref_name.exclude, []),
              try(local._cat_rs.conditions.ref_name.exclude, []),
              try(local._repo_rs[repo_name].conditions.ref_name.exclude, [])
            )) : startswith(ref, "refs/") || startswith(ref, "~") ? ref : "refs/heads/${ref}"
          ]
        }
      }

      rules = {
        deletion                = try(coalesce(try(local._repo_rs[repo_name].rules.deletion, null), try(local._cat_rs.rules.deletion, null), try(local._org_rs.rules.deletion, null)), null)
        non_fast_forward        = try(coalesce(try(local._repo_rs[repo_name].rules.non_fast_forward, null), try(local._cat_rs.rules.non_fast_forward, null), try(local._org_rs.rules.non_fast_forward, null)), null)
        required_signatures     = try(coalesce(try(local._repo_rs[repo_name].rules.required_signatures, null), try(local._cat_rs.rules.required_signatures, null), try(local._org_rs.rules.required_signatures, null)), null)
        required_linear_history = try(coalesce(try(local._repo_rs[repo_name].rules.required_linear_history, null), try(local._cat_rs.rules.required_linear_history, null), try(local._org_rs.rules.required_linear_history, null)), null)

        pull_request = {
          required_approving_review_count   = coalesce(try(local._repo_rs[repo_name].rules.pull_request.required_approving_review_count, null), try(local._cat_rs.rules.pull_request.required_approving_review_count, null), local._org_rs.rules.pull_request.required_approving_review_count)
          dismiss_stale_reviews_on_push     = coalesce(try(local._repo_rs[repo_name].rules.pull_request.dismiss_stale_reviews_on_push, null), try(local._cat_rs.rules.pull_request.dismiss_stale_reviews_on_push, null), local._org_rs.rules.pull_request.dismiss_stale_reviews_on_push)
          require_last_push_approval        = coalesce(try(local._repo_rs[repo_name].rules.pull_request.require_last_push_approval, null), try(local._cat_rs.rules.pull_request.require_last_push_approval, null), local._org_rs.rules.pull_request.require_last_push_approval)
          require_code_owner_review         = coalesce(try(local._repo_rs[repo_name].rules.pull_request.require_code_owner_review, null), try(local._cat_rs.rules.pull_request.require_code_owner_review, null), local._org_rs.rules.pull_request.require_code_owner_review)
          required_review_thread_resolution = coalesce(try(local._repo_rs[repo_name].rules.pull_request.required_review_thread_resolution, null), try(local._cat_rs.rules.pull_request.required_review_thread_resolution, null), local._org_rs.rules.pull_request.required_review_thread_resolution)
        }

        required_status_checks = {
          strict_required_status_checks_policy = coalesce(try(local._repo_rs[repo_name].rules.required_status_checks.strict_required_status_checks_policy, null), try(local._cat_rs.rules.required_status_checks.strict_required_status_checks_policy, null), local._org_rs.rules.required_status_checks.strict_required_status_checks_policy)
          do_not_enforce_on_create             = try(coalesce(try(local._repo_rs[repo_name].rules.required_status_checks.do_not_enforce_on_create, null), try(local._cat_rs.rules.required_status_checks.do_not_enforce_on_create, null), try(local._org_rs.rules.required_status_checks.do_not_enforce_on_create, null)), null)
          required_check = distinct(concat(
            local._org_rs.rules.required_status_checks.required_check,
            try(local._cat_rs.rules.required_status_checks.required_check, []),
            try(local._repo_rs[repo_name].rules.required_status_checks.required_check, [])
          ))
        }

        copilot_code_review = {
          review_on_push             = coalesce(try(local._repo_rs[repo_name].rules.copilot_code_review.review_on_push, null), try(local._cat_rs.rules.copilot_code_review.review_on_push, null), local._org_rs.rules.copilot_code_review.review_on_push)
          review_draft_pull_requests = coalesce(try(local._repo_rs[repo_name].rules.copilot_code_review.review_draft_pull_requests, null), try(local._cat_rs.rules.copilot_code_review.review_draft_pull_requests, null), local._org_rs.rules.copilot_code_review.review_draft_pull_requests)
        }

        merge_queue = try(coalesce(
          try(local._repo_rs[repo_name].rules.merge_queue, null),
          try(local._cat_rs.rules.merge_queue, null),
          try(local._org_rs.rules.merge_queue, null)
        ), null)
      }
    }
  }
}
