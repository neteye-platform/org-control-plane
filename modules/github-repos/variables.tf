variable "org_defaults" {
  description = "Organization-wide default settings for repositories"
  type = object({
    description                 = optional(string)
    visibility                  = optional(string)
    auto_init                   = optional(bool)
    has_issues                  = optional(bool)
    has_wiki                    = optional(bool)
    has_projects                = optional(bool)
    has_discussions             = optional(bool)
    allow_merge_commit          = optional(bool)
    allow_squash_merge          = optional(bool)
    allow_rebase_merge          = optional(bool)
    delete_branch_on_merge      = optional(bool)
    archived                    = optional(bool)
    vulnerability_alerts        = optional(bool)
    topics                      = optional(list(string))
    squash_merge_commit_title   = optional(string)
    squash_merge_commit_message = optional(string)
    branch_protection = optional(object({
      enabled                    = optional(bool)
      pattern                    = optional(string)
      required_approvals         = optional(number)
      dismiss_stale_reviews      = optional(bool)
      require_code_owner_reviews = optional(bool)
      enforce_admins             = optional(bool)
      required_status_checks     = optional(list(string))
      strict_status_checks       = optional(bool)
    }))
  })
  default = {}
}

variable "product_defaults" {
  description = "Product-level default settings (overrides org defaults)"
  type = object({
    description                 = optional(string)
    visibility                  = optional(string)
    auto_init                   = optional(bool)
    has_issues                  = optional(bool)
    has_wiki                    = optional(bool)
    has_projects                = optional(bool)
    has_discussions             = optional(bool)
    allow_merge_commit          = optional(bool)
    allow_squash_merge          = optional(bool)
    allow_rebase_merge          = optional(bool)
    delete_branch_on_merge      = optional(bool)
    archived                    = optional(bool)
    vulnerability_alerts        = optional(bool)
    topics                      = optional(list(string))
    squash_merge_commit_title   = optional(string)
    squash_merge_commit_message = optional(string)
    branch_protection = optional(object({
      enabled                    = optional(bool)
      pattern                    = optional(string)
      required_approvals         = optional(number)
      dismiss_stale_reviews      = optional(bool)
      require_code_owner_reviews = optional(bool)
      enforce_admins             = optional(bool)
      required_status_checks     = optional(list(string))
      strict_status_checks       = optional(bool)
    }))
  })
  default = {}
}

variable "repos_yaml_dir" {
  type        = string
  description = "Absolute path to repo YAML directory"
}
