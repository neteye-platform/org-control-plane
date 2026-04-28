variable "repos_yaml_dir" {
  type        = string
  description = "Absolute path to repo YAML directory"
}

variable "org_defaults" {
  description = "Organization-wide default settings for repositories"
  type        = any
}

variable "category_defaults" {
  description = "Category-level default settings (overrides org defaults)"
  type        = any
}
