locals {
  # Load all YAML files from repos directory
  yaml_files = fileset(var.repos_yaml_dir, "*.yaml")

  # Parse and merge with THREE-TIER hierarchy (org → product → repo)
  # CRITICAL: Deep merge for branch_protection to preserve inherited fields
  repos = {
    for f in local.yaml_files :
    trimsuffix(basename(f), ".yaml") => merge(
      var.org_defaults,
      var.product_defaults,
      yamldecode(file("${var.repos_yaml_dir}/${f}")),
      # DEEP merge for branch_protection explicitly to avoid shallow replacement
      {
        branch_protection = merge(
          lookup(var.org_defaults, "branch_protection", {}),
          lookup(var.product_defaults, "branch_protection", {}),
          try(yamldecode(file("${var.repos_yaml_dir}/${f}")).branch_protection, {})
        )
      }
    )
  }

  # Flatten teams for for_each (convert nested per-repo lists to flat map)
  team_access = flatten([
    for repo_name, repo in local.repos : [
      for team in try(repo.teams, []) : {
        key        = "${repo_name}-${team.name}"
        repo       = repo_name
        team_slug  = team.name
        permission = team.permission
      }
    ]
  ])

  # Flatten webhooks for for_each
  webhooks = flatten([
    for repo_name, repo in local.repos : [
      for idx, webhook in try(repo.webhooks, []) : {
        key    = "${repo_name}-webhook-${idx}"
        repo   = repo_name
        config = webhook
      }
    ]
  ])

  # Flatten autolinks for for_each
  autolinks = flatten([
    for repo_name, repo in local.repos : [
      for idx, autolink in try(repo.autolinks, []) : {
        key    = "${repo_name}-autolink-${idx}"
        repo   = repo_name
        config = autolink
      }
    ]
  ])

  # Deduplicate team slugs for data source lookups (minimize API calls)
  unique_team_slugs = toset(flatten([
    for repo_name, repo in local.repos : [
      for team in try(repo.teams, []) : team.name
    ]
  ]))
}
