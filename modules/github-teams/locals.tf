locals {
  # Load all YAML files from the teams directory
  yaml_files = fileset(var.teams_yaml_dir, "*.yaml")

  # Parse YAML files into a map: team_name => team_config
  teams = {
    for f in local.yaml_files :
    yamldecode(file("${var.teams_yaml_dir}/${f}")).name => yamldecode(file("${var.teams_yaml_dir}/${f}"))
  }

  # Org role name => role ID, as defined in the GitHub organization
  org_role_ids = {
    for r in data.github_organization_roles.all.roles :
    r.name => r.role_id
  }

  # Flatten org role bindings (team x org_roles) for for_each
  org_role_bindings = flatten([
    for team_name, team in local.teams : [
      for role in try(team.org_roles, []) : {
        team = team.name
        role = role
      }
    ]
  ])

  # Flatten memberships for for_each
  memberships = flatten([
    for team_name, team in local.teams : [
      for member in try(team.members, []) : {
        team     = team.name
        username = member.username
        role     = member.role
      }
    ]
  ])
}
