locals {
  # Load all YAML files from repos directory
  yaml_files = fileset(var.repos_yaml_dir, "*.yaml")

  # Parse and merge with THREE-TIER hierarchy (org → category → repo)
  repos = {
    for f in local.yaml_files :
    yamldecode(file("${var.repos_yaml_dir}/${f}")).name => merge(
      var.org_defaults,
      var.category_defaults,
      yamldecode(file("${var.repos_yaml_dir}/${f}")),
    )
  }
}
