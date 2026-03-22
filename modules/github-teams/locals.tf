locals {
  # Load all YAML files from the teams directory
  yaml_files = fileset(var.teams_yaml_dir, "*.yaml")

  # Parse YAML files into a map: team_name => team_config
  teams = {
    for f in local.yaml_files :
    yamldecode(file("${var.teams_yaml_dir}/${f}")).name => yamldecode(file("${var.teams_yaml_dir}/${f}"))
  }

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
