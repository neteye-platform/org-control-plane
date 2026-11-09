# One unit, and one state, per directory except the hidden ones.

locals {
  # fileset() lists files only: a category is found by its files.
  categories = toset([
    for f in fileset(get_terragrunt_dir(), "*/*") : dirname(f)
    if !startswith(f, ".")
  ])
}

unit "category" {
  expansion {
    for_each = local.categories
  }

  source = "${get_repo_root()}/catalog/units/repository-category"
  path   = each.key

  values = {
    category = each.key
  }
}
