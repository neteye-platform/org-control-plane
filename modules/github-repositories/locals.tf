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

  # Build one team-access entry per (repo, team slug).
  # Merge strategy: union across tiers keyed by team slug; most specific tier wins (repo > category > org).
  team_access_configs = {
    for pair in flatten([
      for repo_name in keys(local.repos) : [
        for slug, entry in merge(
          { for t in try(var.org_defaults.team_access, []) : t.team => t },
          { for t in try(var.category_defaults.team_access, []) : t.team => t },
          { for t in try(local.repo_yamls[repo_name].team_access, []) : t.team => t }
        ) : {
          repo_name  = repo_name
          team       = slug
          permission = entry.permission
        }
      ]
    ]) : "${pair.repo_name}/${pair.team}" => pair
  }

  # Shorthand references to each tier's branch_rulesets map
  _org_rs_map  = try(var.org_defaults.branch_rulesets, {})
  _cat_rs_map  = try(var.category_defaults.branch_rulesets, {})
  _repo_rs_map = { for name, yaml in local.repo_yamls : name => try(yaml.branch_rulesets, {}) }

  # Build one ruleset config per (repo, ruleset_name) combination.
  # Ruleset names are collected across all three tiers so that a category
  # or repo can both override an org-level ruleset and define new ones.
  #
  # Merge strategy per field type:
  #   - Scalars:        repo > category > org  (coalesce)
  #   - Additive lists: concat all tiers, deduplicated  (conditions, required_check)
  #   - bypass_actors:  full replacement when set explicitly; otherwise additive via extra_bypass_actors
  #   - merge_queue:    highest-priority tier that defines it wins entirely
  ruleset_configs = {
    for pair in flatten([
      for repo_name in keys(local.repos) : [
        for rs_name in toset(concat(
          keys(local._org_rs_map),
          keys(local._cat_rs_map),
          keys(local._repo_rs_map[repo_name])
          )) : {
          repo_name    = repo_name
          ruleset_name = rs_name
          repo_rs      = try(local._repo_rs_map[repo_name][rs_name], {})
          cat_rs       = try(local._cat_rs_map[rs_name], {})
          org_rs       = try(local._org_rs_map[rs_name], {})
        }
      ]
      ]) : "${pair.repo_name}/${pair.ruleset_name}" => {
      repo_name   = pair.repo_name
      name        = pair.ruleset_name
      target      = try(coalesce(try(pair.repo_rs.target, null), try(pair.cat_rs.target, null), try(pair.org_rs.target, null)), "branch")
      enforcement = try(coalesce(try(pair.repo_rs.enforcement, null), try(pair.cat_rs.enforcement, null), try(pair.org_rs.enforcement, null)), "active")

      # bypass_actors: full override when set explicitly at repo or category level;
      # otherwise merge org list with extra_bypass_actors from lower tiers
      bypass_actors = (
        try(pair.repo_rs.bypass_actors, null) != null
        ? pair.repo_rs.bypass_actors
        : try(pair.cat_rs.bypass_actors, null) != null
        ? pair.cat_rs.bypass_actors
        : distinct(concat(
          try(pair.org_rs.bypass_actors, []),
          try(pair.cat_rs.extra_bypass_actors, []),
          try(pair.repo_rs.extra_bypass_actors, [])
        ))
      )

      # Ref conditions are additive: include/exclude lists are concatenated across tiers.
      # Short branch names (e.g. "main") are expanded to "refs/heads/main".
      conditions = {
        ref_name = {
          include = [
            for ref in distinct(concat(
              try(pair.org_rs.conditions.ref_name.include, []),
              try(pair.cat_rs.conditions.ref_name.include, []),
              try(pair.repo_rs.conditions.ref_name.include, [])
            )) : startswith(ref, "refs/") || startswith(ref, "~") ? ref : "refs/heads/${ref}"
          ]
          exclude = [
            for ref in distinct(concat(
              try(pair.org_rs.conditions.ref_name.exclude, []),
              try(pair.cat_rs.conditions.ref_name.exclude, []),
              try(pair.repo_rs.conditions.ref_name.exclude, [])
            )) : startswith(ref, "refs/") || startswith(ref, "~") ? ref : "refs/heads/${ref}"
          ]
        }
      }

      rules = {
        creation                = try(coalesce(try(pair.repo_rs.rules.creation, null), try(pair.cat_rs.rules.creation, null), try(pair.org_rs.rules.creation, null)), null)
        deletion                = try(coalesce(try(pair.repo_rs.rules.deletion, null), try(pair.cat_rs.rules.deletion, null), try(pair.org_rs.rules.deletion, null)), null)
        update                  = try(coalesce(try(pair.repo_rs.rules.update, null), try(pair.cat_rs.rules.update, null), try(pair.org_rs.rules.update, null)), null)
        non_fast_forward        = try(coalesce(try(pair.repo_rs.rules.non_fast_forward, null), try(pair.cat_rs.rules.non_fast_forward, null), try(pair.org_rs.rules.non_fast_forward, null)), null)
        required_linear_history = try(coalesce(try(pair.repo_rs.rules.required_linear_history, null), try(pair.cat_rs.rules.required_linear_history, null), try(pair.org_rs.rules.required_linear_history, null)), null)
        required_signatures     = try(coalesce(try(pair.repo_rs.rules.required_signatures, null), try(pair.cat_rs.rules.required_signatures, null), try(pair.org_rs.rules.required_signatures, null)), null)

        _has_pull_request   = try(pair.org_rs.rules.pull_request, null) != null || try(pair.cat_rs.rules.pull_request, null) != null || try(pair.repo_rs.rules.pull_request, null) != null
        _has_code_scanning  = try(pair.org_rs.rules.required_code_scanning, null) != null || try(pair.cat_rs.rules.required_code_scanning, null) != null || try(pair.repo_rs.rules.required_code_scanning, null) != null
        _has_copilot_review = try(pair.org_rs.rules.copilot_code_review, null) != null || try(pair.cat_rs.rules.copilot_code_review, null) != null || try(pair.repo_rs.rules.copilot_code_review, null) != null

        pull_request = {
          allowed_merge_methods             = try(coalesce(try(pair.repo_rs.rules.pull_request.allowed_merge_methods, null), try(pair.cat_rs.rules.pull_request.allowed_merge_methods, null), try(pair.org_rs.rules.pull_request.allowed_merge_methods, null)), null)
          required_approving_review_count   = try(coalesce(try(pair.repo_rs.rules.pull_request.required_approving_review_count, null), try(pair.cat_rs.rules.pull_request.required_approving_review_count, null), try(pair.org_rs.rules.pull_request.required_approving_review_count, null)), null)
          dismiss_stale_reviews_on_push     = try(coalesce(try(pair.repo_rs.rules.pull_request.dismiss_stale_reviews_on_push, null), try(pair.cat_rs.rules.pull_request.dismiss_stale_reviews_on_push, null), try(pair.org_rs.rules.pull_request.dismiss_stale_reviews_on_push, null)), null)
          require_last_push_approval        = try(coalesce(try(pair.repo_rs.rules.pull_request.require_last_push_approval, null), try(pair.cat_rs.rules.pull_request.require_last_push_approval, null), try(pair.org_rs.rules.pull_request.require_last_push_approval, null)), null)
          require_code_owner_review         = try(coalesce(try(pair.repo_rs.rules.pull_request.require_code_owner_review, null), try(pair.cat_rs.rules.pull_request.require_code_owner_review, null), try(pair.org_rs.rules.pull_request.require_code_owner_review, null)), null)
          required_review_thread_resolution = try(coalesce(try(pair.repo_rs.rules.pull_request.required_review_thread_resolution, null), try(pair.cat_rs.rules.pull_request.required_review_thread_resolution, null), try(pair.org_rs.rules.pull_request.required_review_thread_resolution, null)), null)
        }

        required_status_checks = {
          strict_required_status_checks_policy = try(coalesce(try(pair.repo_rs.rules.required_status_checks.strict_required_status_checks_policy, null), try(pair.cat_rs.rules.required_status_checks.strict_required_status_checks_policy, null), try(pair.org_rs.rules.required_status_checks.strict_required_status_checks_policy, null)), null)
          do_not_enforce_on_create             = try(coalesce(try(pair.repo_rs.rules.required_status_checks.do_not_enforce_on_create, null), try(pair.cat_rs.rules.required_status_checks.do_not_enforce_on_create, null), try(pair.org_rs.rules.required_status_checks.do_not_enforce_on_create, null)), null)
          required_check = distinct(concat(
            try(pair.org_rs.rules.required_status_checks.required_check, []),
            try(pair.cat_rs.rules.required_status_checks.required_check, []),
            try(pair.repo_rs.rules.required_status_checks.required_check, [])
          ))
        }

        required_code_scanning = {
          required_code_scanning_tool = values(merge(
            { for tool in try(pair.org_rs.rules.required_code_scanning.required_code_scanning_tool, []) : tool.tool => tool },
            { for tool in try(pair.cat_rs.rules.required_code_scanning.required_code_scanning_tool, []) : tool.tool => tool },
            { for tool in try(pair.repo_rs.rules.required_code_scanning.required_code_scanning_tool, []) : tool.tool => tool }
          ))
        }

        merge_queue = try(coalesce(
          try(pair.repo_rs.rules.merge_queue, null),
          try(pair.cat_rs.rules.merge_queue, null),
          try(pair.org_rs.rules.merge_queue, null)
        ), null)

        copilot_code_review = {
          review_on_push             = try(coalesce(try(pair.repo_rs.rules.copilot_code_review.review_on_push, null), try(pair.cat_rs.rules.copilot_code_review.review_on_push, null), try(pair.org_rs.rules.copilot_code_review.review_on_push, null)), null)
          review_draft_pull_requests = try(coalesce(try(pair.repo_rs.rules.copilot_code_review.review_draft_pull_requests, null), try(pair.cat_rs.rules.copilot_code_review.review_draft_pull_requests, null), try(pair.org_rs.rules.copilot_code_review.review_draft_pull_requests, null)), null)
        }
      }
    }
  }
}
