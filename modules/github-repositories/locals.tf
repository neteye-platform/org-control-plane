locals {
  # The three tiers, from the most generic to the most specific. A tier that is
  # not set, or null (an empty YAML file), gives null with
  # `try(local.<tier>.<field>, null)`, like a field the tier does not set.
  org      = try(var.settings.defaults.org, {})
  category = try(var.settings.defaults.category, {})
  repo     = coalesce(try(var.settings.repositories, null), {})

  # Fields each defaults tier sets. Unset fields are null and must not
  # override a value from a more generic tier.
  _org_set      = try({ for k, v in local.org : k => v if v != null }, {})
  _category_set = try({ for k, v in local.category : k => v if v != null }, {})

  # Three-tier merge for repository settings (org → category → repo). The repo
  # object comes first so that every field exists, null when no tier sets it.
  repos = {
    for name, repo in local.repo :
    name => merge(
      repo,
      local._org_set,
      local._category_set,
      { for k, v in repo : k => v if v != null },
      { name = name },
    )
  }

  # Build one team-access entry per (repo, team slug).
  # Override strategy: the most specific tier that defines `team_access` wins
  # entirely (repo > category > org). Lower tiers are NOT merged in.
  # Use `extra_team_access` at the category or repo tier to keep the inherited
  # list and add/override individual entries by team slug.
  team_access_configs = {
    for pair in flatten([
      for repo_name, repo in local.repo : [
        for slug, entry in merge(
          # Base list: highest tier that explicitly sets team_access wins.
          {
            for t in(
              repo.team_access != null ? repo.team_access
              : try(local.category.team_access, null) != null ? local.category.team_access
              : coalesce(try(local.org.team_access, null), [])
            ) : t.team => t
          },
          # Additive overrides keyed by team slug (category then repo).
          {
            for t in(
              repo.team_access == null ? coalesce(try(local.category.extra_team_access, null), []) : []
            ) : t.team => t
          },
          { for t in coalesce(repo.extra_team_access, []) : t.team => t }
          ) : {
          repo_name  = repo_name
          team       = slug
          permission = entry.permission
        }
      ]
    ]) : "${pair.repo_name}/${pair.team}" => pair
  }

  # Build one user-access entry per (repo, username).
  # Override strategy: the most specific tier that defines `user_access` wins
  # entirely (repo > category > org). Lower tiers are NOT merged in.
  # Use `extra_user_access` at the category or repo tier to keep the inherited
  # list and add/override individual entries by username.
  user_access_configs = {
    for pair in flatten([
      for repo_name, repo in local.repo : [
        for username, entry in merge(
          # Base list: highest tier that explicitly sets user_access wins.
          {
            for u in(
              repo.user_access != null ? repo.user_access
              : try(local.category.user_access, null) != null ? local.category.user_access
              : coalesce(try(local.org.user_access, null), [])
            ) : u.username => u
          },
          # Additive overrides keyed by username (category then repo).
          {
            for u in(
              repo.user_access == null ? coalesce(try(local.category.extra_user_access, null), []) : []
            ) : u.username => u
          },
          { for u in coalesce(repo.extra_user_access, []) : u.username => u }
          ) : {
          repo_name  = repo_name
          username   = username
          permission = entry.permission
        }
      ]
    ]) : "${pair.repo_name}/${pair.username}" => pair
  }

  # Build the full label list per repository, consumed by the authoritative
  # github_issue_labels resource (one resource per repo, not per label).
  # Override strategy:
  #   - `labels:` follows highest-tier-wins: a category or repo `labels:`
  #     replaces the inherited list entirely (repo > category > org).
  #   - `extra_labels:` is purely additive and NEVER overrides a name already
  #     present in the base `labels:` set; use it to add labels alongside the
  #     inherited defaults. Within extra_labels, repo overrides category by
  #     name (most-specific wins).
  labels_by_repo = {
    for repo_name, repo in local.repo : repo_name => values(merge(
      # extra_labels from category then repo (additive, lowest priority).
      # Listed first so the base-labels block below can shadow them by name.
      {
        for l in(repo.labels == null ? coalesce(try(local.category.extra_labels, null), []) : []) : l.name => l
      },
      { for l in coalesce(repo.extra_labels, []) : l.name => l },
      # Base labels: highest tier that explicitly sets `labels:` wins.
      # Listed last so base names always win over extra_labels on collision.
      {
        for l in(
          repo.labels != null ? repo.labels
          : try(local.category.labels, null) != null ? local.category.labels
          : coalesce(try(local.org.labels, null), [])
        ) : l.name => l
      },
    ))
  }

  # Shorthand references to each tier's branch_rulesets map
  _org_rs_map  = coalesce(try(local.org.branch_rulesets, null), {})
  _cat_rs_map  = coalesce(try(local.category.branch_rulesets, null), {})
  _repo_rs_map = { for name, repo in local.repo : name => coalesce(repo.branch_rulesets, {}) }

  # Build one ruleset config per (repo, ruleset_name) combination.
  # Ruleset names are collected across all three tiers so that a category
  # or repo can both override an org-level ruleset and define new ones.
  #
  # Merge strategy per field type:
  #   - Scalars:        repo > category > org  (coalesce)
  #   - Additive lists: concat all tiers, deduplicated  (conditions, required_check)
  #   - include_override:        full replacement when set at repo or category level
  #   - required_check_override: full replacement when set at repo or category level
  #   - bypass_actors:  full replacement when set explicitly; otherwise additive via extra_bypass_actors
  #   - merge_queue:    highest-priority tier that defines it wins entirely
  ruleset_configs = {
    for pair in flatten([
      for repo_name in keys(local.repo) : [
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
          target = try(coalesce(
            try(local._repo_rs_map[repo_name][rs_name].target, null),
            try(local._cat_rs_map[rs_name].target, null),
            try(local._org_rs_map[rs_name].target, null),
          ), "branch")
        }
      ]
      ]) : "${pair.repo_name}/${pair.ruleset_name}" => {
      repo_name   = pair.repo_name
      name        = pair.ruleset_name
      target      = pair.target
      enforcement = try(coalesce(try(pair.repo_rs.enforcement, null), try(pair.cat_rs.enforcement, null), try(pair.org_rs.enforcement, null)), "active")

      # bypass_actors: first available from repo > category > org; then
      # concat ALL extra_bypass_actors from all tiers (org, category, repo).
      bypass_actors = distinct(concat(
        try(pair.repo_rs.bypass_actors, null) != null ? pair.repo_rs.bypass_actors
        : try(pair.cat_rs.bypass_actors, null) != null ? pair.cat_rs.bypass_actors
        : coalesce(try(pair.org_rs.bypass_actors, null), []),
        coalesce(try(pair.org_rs.extra_bypass_actors, null), []),
        coalesce(try(pair.cat_rs.extra_bypass_actors, null), []),
        coalesce(try(pair.repo_rs.extra_bypass_actors, null), [])
      ))

      # Ref conditions are additive: include/exclude lists are concatenated across tiers.
      # `include_override` at the repo or category tier replaces the inherited
      # include list entirely, so a repo can drop patterns it inherits.
      # Short names are expanded: "main" to "refs/heads/main", or to
      # "refs/tags/main" in a tag ruleset.
      conditions = {
        ref_name = {
          include = [
            for ref in(
              try(pair.repo_rs.conditions.ref_name.include_override, null) != null
              ? pair.repo_rs.conditions.ref_name.include_override
              : try(pair.cat_rs.conditions.ref_name.include_override, null) != null
              ? pair.cat_rs.conditions.ref_name.include_override
              : distinct(concat(
                coalesce(try(pair.org_rs.conditions.ref_name.include, null), []),
                coalesce(try(pair.cat_rs.conditions.ref_name.include, null), []),
                coalesce(try(pair.repo_rs.conditions.ref_name.include, null), [])
              ))
            ) : startswith(ref, "refs/") || startswith(ref, "~") ? ref : "${pair.target == "tag" ? "refs/tags" : "refs/heads"}/${ref}"
          ]
          exclude = [
            for ref in distinct(concat(
              coalesce(try(pair.org_rs.conditions.ref_name.exclude, null), []),
              coalesce(try(pair.cat_rs.conditions.ref_name.exclude, null), []),
              coalesce(try(pair.repo_rs.conditions.ref_name.exclude, null), [])
            )) : startswith(ref, "refs/") || startswith(ref, "~") ? ref : "${pair.target == "tag" ? "refs/tags" : "refs/heads"}/${ref}"
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
          required_check = (
            try(pair.repo_rs.rules.required_status_checks.required_check_override, null) != null
            ? pair.repo_rs.rules.required_status_checks.required_check_override
            : try(pair.cat_rs.rules.required_status_checks.required_check_override, null) != null
            ? pair.cat_rs.rules.required_status_checks.required_check_override
            : distinct(concat(
              coalesce(try(pair.org_rs.rules.required_status_checks.required_check, null), []),
              coalesce(try(pair.cat_rs.rules.required_status_checks.required_check, null), []),
              coalesce(try(pair.repo_rs.rules.required_status_checks.required_check, null), [])
            ))
          )
        }

        required_code_scanning = {
          required_code_scanning_tool = values(merge(
            { for tool in coalesce(try(pair.org_rs.rules.required_code_scanning.required_code_scanning_tool, null), []) : tool.tool => tool },
            { for tool in coalesce(try(pair.cat_rs.rules.required_code_scanning.required_code_scanning_tool, null), []) : tool.tool => tool },
            { for tool in coalesce(try(pair.repo_rs.rules.required_code_scanning.required_code_scanning_tool, null), []) : tool.tool => tool }
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
