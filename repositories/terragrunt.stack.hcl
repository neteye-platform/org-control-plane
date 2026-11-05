# One unit, and one state, per category: every directory under repositories/,
# except the hidden ones. Terragrunt generates the units in .terragrunt-stack/
# from catalog/units/repository-category.

locals {
  # fileset() lists files only: a directory is found by its files. Git does not
  # keep empty directories, and every category has a _defaults.yaml file.
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
