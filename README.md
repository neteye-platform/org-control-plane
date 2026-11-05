# GitHub Organization Control Plane

Infrastructure as code for the
[neteye-platform](https://github.com/neteye-platform) GitHub organization.
The organization settings, the teams and the repositories are YAML files.
Terraform and Terragrunt apply them with a GitHub App. A pull request shows the
plan of each unit in a comment, and a merge to `main` applies it. A unit
without changes gets no comment. When no unit has changes, a single comment
says so.

> **Production impact:** every change merged to `main` changes the live
> GitHub organization. Read the plan before you approve.

## Layout

```text
org-settings/settings.yaml          organization settings
teams/teams/<team>.yaml             one file per team
repositories/_defaults.yaml         defaults of all repositories
repositories/<category>/_defaults.yaml   defaults of a category (`{}` if none)
repositories/<category>/<repo>.yaml one file per repository
modules/                            Terraform modules
schemas/                            JSON Schemas of the YAML files (generated)
```

Every unit has its own Terraform state: `org-settings`, `teams` and each
repository category. A new category is a new directory under `repositories/`
with a `_defaults.yaml` file, which holds `{}` if the category has no
defaults.

CI runs all units with `terragrunt run --all`: the categories run in parallel,
after `teams`, because repositories grant access to teams. On a pull request,
each unit with changes gets its own comment. On merge, the units apply in the
same order.

## Editing the YAML files

Each YAML file starts with a `yaml-language-server` comment that points to its
JSON Schema, so the editor completes and documents every field. The pre-commit
hooks validate the files against the schemas. The schemas are generated from
the types of the module variables: after a change to a `variables.tf`, run
`python3 scripts/generate-schemas.py` (the pre-commit hook does it for you).

## Organization settings

`org-settings/settings.yaml` holds the profile (name, description, blog,
location, ...), the base permission of the members, what members can create,
and the security features enabled on new repositories. All fields are
required, except `twitter_username`. The billing email comes from SSM
Parameter Store, see [Credentials](#credentials).

## Teams

One file per team in `teams/teams/`. The file name must match `name`.

| Field | Description |
| --- | --- |
| `name`, `description` | Team name and description (required). |
| `privacy` | `secret` or `closed` (required). |
| `notification_setting` | `notifications_enabled` or `notifications_disabled` (required). |
| `parent_team_id` | ID of the parent team (optional). |
| `org_roles` | Organization roles assigned to the team, by name (optional). |

## Repositories

One file per repository in `repositories/<category>/`. The file name must match
`name`, and a repository name must be unique across all categories. The schema
of this repository also requires `description` and at least one topic.

Settings merge in three tiers. The most specific tier wins:

1. `repositories/_defaults.yaml`: all repositories.
2. `repositories/<category>/_defaults.yaml`: the repositories of the category.
   Every category has this file, with `{}` when it has no defaults.
3. `repositories/<category>/<repo>.yaml`: one repository.

### General settings

Every field of the
[`github_repository`](https://registry.terraform.io/providers/integrations/github/latest/docs/resources/repository)
resource that the schema lists: visibility, features (issues, wiki, ...),
merge options, `topics`, `template`, `archived` and more. A scalar field comes
from the most specific tier that sets it.

### Access

| Field | Merge rule |
| --- | --- |
| `team_access` | List of `team` (slug) and `permission`. The most specific tier that sets it replaces the inherited list. |
| `extra_team_access` | Category or repository tier: adds to the inherited `team_access`, or overrides the permission of a team. |
| `user_access` | Same as `team_access`, for collaborators (`username`). An added user gets an invitation. |
| `extra_user_access` | Same as `extra_team_access`, for collaborators. |

The permission is `pull`, `triage`, `push`, `maintain` or `admin`. The
"category or repository tier" fields have no effect in the org defaults, and
their schema rejects them.

### Labels

| Field | Merge rule |
| --- | --- |
| `labels` | List of `name`, `color` and `description`. The most specific tier that sets it replaces the inherited list. |
| `extra_labels` | Category or repository tier: adds labels. A name already in `labels` is not overridden. |

The final list is authoritative: the control plane deletes every other label,
GitHub defaults included.

### Rulesets

`branch_rulesets` maps a ruleset name to its settings. A tier can change an
inherited ruleset or add a new one. Ruleset fields merge one by one:

| Field | Merge rule |
| --- | --- |
| `target`, `enforcement`, rule flags, `pull_request`, `copilot_code_review` and `required_status_checks` flags | The most specific tier that sets the field wins. |
| `conditions.ref_name.include`, `exclude` | Added from every tier. A short name like `main` becomes `refs/heads/main`, or `refs/tags/main` in a tag ruleset. |
| `conditions.ref_name.include_override` | Category or repository tier: replaces the inherited `include`. |
| `bypass_actors` | The most specific tier that sets it replaces the inherited list. `[]` removes all actors. |
| `extra_bypass_actors` | Added from every tier. |
| `rules.required_status_checks.required_check` | Added from every tier. |
| `rules.required_status_checks.required_check_override` | Category or repository tier: replaces the inherited checks. |
| `rules.required_code_scanning.required_code_scanning_tool` | Merged by tool name, the most specific tier wins. |
| `rules.merge_queue` | The most specific tier that sets it replaces the inherited object. |

Repositories and rulesets have `prevent_destroy`: to remove one, first remove
it from the state.

## Running locally

Install the pinned tools with [mise](https://mise.jdx.dev), then log in to
AWS with the [AWS CLI](https://aws.amazon.com/cli/), which Terragrunt also
uses to read the credentials:

```bash
mise install
aws sso login   # or any other way to get AWS credentials
```

Then run Terragrunt from the repository root:

```bash
terragrunt run --all plan                                     # all units
terragrunt plan --working-dir teams                           # one unit
terragrunt stack generate --working-dir repositories          # one category:
terragrunt plan --working-dir repositories/.terragrunt-stack/ai
```

## Credentials

Terragrunt reads the credentials from AWS. No other environment variable is
needed, locally or in CI.

- The state is in the S3 bucket set in `root.hcl`.
- The parameters below are in SSM Parameter Store, in the region set in
  `root.hcl`, under the prefix `/org-control-plane`:

| Parameter | Type | Value |
| --- | --- | --- |
| `github-app/app-id` | String | ID of the GitHub App that Terraform uses |
| `github-app/installation-id` | String | ID of the App installation on the organization |
| `github-app/private-key` | SecureString | Private key (PEM) of the App |
| `org-settings/billing-email` | SecureString | Billing email of the organization |

The AWS identity needs read and write access to the state bucket, and
`ssm:GetParametersByPath` on the prefix, and `kms:Decrypt` on the key of the
SecureString parameters. CI uses the
`AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` repository secrets. The
region and the prefix are also set in `plan.yaml` and `apply.yaml`.

CI treats every value under the prefix as a secret: it masks the values in the
logs and removes them from the plan comments.

A second GitHub App writes the plan comments, so it needs "Pull requests:
write" on this repository. Only CI uses it, with the `NETEYE_APP_ID`
repository variable and the `NETEYE_APP_PRIVATE_KEY` repository secret.

## Tests

- `terraform test` in each module directory tests the merge rules and the
  resources, with a mocked provider (run `terraform init -backend=false`
  first).
- `python3 -m unittest discover -s tests` tests the schema generator and the
  scripts of the workflows. It needs `node`, `bash` and `jq`.

CI runs both: the first in the plan workflow, the second with the pre-commit
hooks.

## Versions

Terraform and Terragrunt are pinned in `mise.toml` with checksums in
`mise.lock`. The GitHub provider is pinned in the modules, and the single
`.terraform.lock.hcl` at the root pins its checksums for every unit. Renovate
updates all of them.

## Reusing the modules

The modules in `modules/` do not depend on this repository. Another repository
can use them as a Terragrunt or Terraform source pinned to a commit, for
example
`git::https://github.com/neteye-platform/org-control-plane.git//modules/github-repositories?ref=<commit>`.
The module variables document the inputs, and the tests in `modules/*/tests`
show examples.

## Security

See [SECURITY.md](SECURITY.md) for the vulnerability disclosure policy.

## License

Dual-licensed under [Apache 2.0](LICENSE-APACHE) and [MIT](LICENSE-MIT).
