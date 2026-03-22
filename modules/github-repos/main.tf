# Terraform backend configuration for remote state
terraform {
  required_version = ">= 1.5"
  backend "s3" {}
}

# Create GitHub repositories with full configuration
resource "github_repository" "repos" {
  for_each = local.repos

  name        = each.key
  description = each.value.description
  visibility  = each.value.visibility
  auto_init   = each.value.auto_init

  has_issues      = each.value.has_issues
  has_wiki        = each.value.has_wiki
  has_projects    = each.value.has_projects
  has_discussions = each.value.has_discussions

  allow_merge_commit = each.value.allow_merge_commit
  allow_squash_merge = each.value.allow_squash_merge
  allow_rebase_merge = each.value.allow_rebase_merge

  squash_merge_commit_title   = try(each.value.squash_merge_commit_title, null)
  squash_merge_commit_message = try(each.value.squash_merge_commit_message, null)
  delete_branch_on_merge      = each.value.delete_branch_on_merge

  archived             = each.value.archived
  vulnerability_alerts = each.value.vulnerability_alerts
  topics               = try(each.value.topics, [])

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [pages, template]
  }
}

# Branch protection rules with deep-merged configuration
resource "github_branch_protection" "main" {
  for_each = {
    for name, repo in local.repos :
    name => repo
    if try(repo.branch_protection.enabled, true) != false
  }

  repository_id = github_repository.repos[each.key].node_id
  pattern       = each.value.branch_protection.pattern

  required_pull_request_reviews {
    required_approving_review_count = each.value.branch_protection.required_approvals
    dismiss_stale_reviews           = each.value.branch_protection.dismiss_stale_reviews
    require_code_owner_reviews      = each.value.branch_protection.require_code_owner_reviews
  }

  required_status_checks {
    strict   = each.value.branch_protection.strict_status_checks
    contexts = each.value.branch_protection.required_status_checks
  }

  enforce_admins = each.value.branch_protection.enforce_admins
}

# Team repository access (uses deduplicated team data sources)
resource "github_team_repository" "access" {
  for_each = {
    for item in local.team_access :
    item.key => item
  }

  team_id    = data.github_team.teams[each.value.team_slug].id
  repository = github_repository.repos[each.value.repo].name
  permission = each.value.permission
}

# Repository webhooks
resource "github_repository_webhook" "webhooks" {
  for_each = {
    for item in local.webhooks :
    item.key => item
  }

  repository = github_repository.repos[each.value.repo].name
  events     = each.value.config.events

  configuration {
    url          = each.value.config.url
    content_type = try(each.value.config.content_type, "form")
    secret       = try(each.value.config.secret, null)
    insecure_ssl = try(each.value.config.insecure_ssl, false)
  }

  active = try(each.value.config.active, true)
}

# Repository autolink references (e.g., JIRA-123 → https://jira.example.com/JIRA-123)
resource "github_repository_autolink_reference" "autolinks" {
  for_each = {
    for item in local.autolinks :
    item.key => item
  }

  repository          = github_repository.repos[each.value.repo].name
  key_prefix          = each.value.config.key_prefix
  target_url_template = each.value.config.target_url_template
  is_alphanumeric     = try(each.value.config.is_alphanumeric, false)
}
