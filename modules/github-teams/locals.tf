locals {
  # Org role name => role ID, as defined in the GitHub organization
  org_role_ids = {
    for r in data.github_organization_roles.all.roles :
    r.name => r.role_id
  }

  # Flatten org role bindings (team x org_roles) for for_each
  org_role_bindings = flatten([
    for team_name, team in var.teams : [
      for role in coalesce(team.org_roles, []) : {
        team = team.name
        role = role
      }
    ]
  ])
}
