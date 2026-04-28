terraform {
  required_version = ">= 1.5"
  backend "s3" {}
}

# Create GitHub repositories with full configuration
resource "github_repository" "repos" {
  for_each = local.repos

  name                        = each.key
  description                 = each.value.description
  homepage_url                = try(each.value.homepage_url, null)
  fork                        = try(each.value.fork, null)
  source_owner                = try(each.value.source_owner, null)
  source_repo                 = try(each.value.source_repo, null)
  visibility                  = each.value.visibility
  has_issues                  = each.value.has_issues
  has_discussions             = each.value.has_discussions
  has_projects                = each.value.has_projects
  has_wiki                    = each.value.has_wiki
  is_template                 = each.value.is_template
  allow_merge_commit          = each.value.allow_merge_commit
  allow_squash_merge          = each.value.allow_squash_merge
  allow_rebase_merge          = each.value.allow_rebase_merge
  allow_auto_merge            = each.value.allow_auto_merge
  allow_forking               = try(each.value.allow_forking, null)
  squash_merge_commit_title   = each.value.squash_merge_commit_title
  squash_merge_commit_message = each.value.squash_merge_commit_message
  delete_branch_on_merge      = each.value.delete_branch_on_merge
  auto_init                   = each.value.auto_init
  gitignore_template          = try(each.value.gitignore_template, null)
  license_template            = try(each.value.license_template, null)
  archived                    = each.value.archived
  archive_on_destroy          = try(each.value.archive_on_destroy, false)
  topics                      = try(each.value.topics, [])
  template {
    owner                = try(each.value.template.owner, null)
    repository           = try(each.value.template.repository, null)
    include_all_branches = try(each.value.template.include_all_branches, null)
  }
  vulnerability_alerts = each.value.vulnerability_alerts
  allow_update_branch  = each.value.allow_update_branch

  # Prevent recreation on taint or destroy to avoid accidental deletion of repositories
  lifecycle {
    prevent_destroy = true
  }
}
