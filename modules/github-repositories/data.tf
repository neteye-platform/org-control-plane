# Deduplicated team lookups to minimize GitHub API calls
# Each team slug is looked up once and reused across all repo-team associations
data "github_team" "teams" {
  for_each = local.unique_team_slugs
  slug     = each.value
}
