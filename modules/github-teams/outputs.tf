output "team_ids" {
  description = "Map of team name to team ID"
  value = {
    for name, team in github_team.teams :
    name => team.id
  }
}

output "team_slugs" {
  description = "Map of team name to team slug"
  value = {
    for name, team in github_team.teams :
    name => team.slug
  }
}
