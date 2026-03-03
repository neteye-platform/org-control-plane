locals {
  # Load all YAML files from repos directory
  yaml_files = fileset(var.repos_yaml_dir, "*.yaml")

  # Parse and merge with THREE-TIER hierarchy (org → category → repo)
  repos = {
    for f in local.yaml_files :
    yamldecode(file("${var.repos_yaml_dir}/${f}")).name => merge(
      var.org_defaults,
      var.category_defaults,
      yamldecode(file("${var.repos_yaml_dir}/${f}")),
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

  # Deduplicate team slugs for data source lookups (minimize API calls)
  unique_team_slugs = toset(flatten([
    for repo_name, repo in local.repos : [
      for team in try(repo.teams, []) : team.name
    ]
  ]))
}
