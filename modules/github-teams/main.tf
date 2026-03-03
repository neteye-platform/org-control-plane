# Terraform backend configuration for remote state
terraform {
  required_version = ">= 1.5"
  backend "s3" {}
}

resource "github_team" "teams" {
  for_each = local.teams

  name           = each.value.name
  description    = each.value.description
  privacy        = each.value.privacy
  parent_team_id = lookup(each.value, "parent_team_id", null)
}

resource "github_team_membership" "memberships" {
  for_each = {
    for item in local.memberships :
    "${item.team}-${item.username}" => item
  }

  team_id  = github_team.teams[each.value.team].id
  username = each.value.username
  role     = each.value.role
}
