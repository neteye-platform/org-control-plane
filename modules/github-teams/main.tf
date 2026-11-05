resource "github_team" "teams" {
  for_each = var.teams

  name                 = each.value.name
  description          = each.value.description
  privacy              = each.value.privacy
  parent_team_id       = each.value.parent_team_id
  notification_setting = each.value.notification_setting
}

data "github_organization_roles" "all" {}

resource "github_organization_role_team" "role_bindings" {
  for_each = {
    for item in local.org_role_bindings :
    "${item.team}-${item.role}" => item
  }

  role_id   = lookup(local.org_role_ids, each.value.role, null)
  team_slug = github_team.teams[each.value.team].slug

  lifecycle {
    precondition {
      condition     = contains(keys(local.org_role_ids), each.value.role)
      error_message = "The organization has no role named \"${each.value.role}\" (team \"${each.value.team}\")."
    }
  }
}
