# Bao configuration

One state owns auth, policies and project mounts. Use the
[root workflow](../README.md#plan-and-apply) with `-chdir=terraform/bao-config`.
This root requires human authority and must not run under agent plan credentials.

## Project access

Add one entry to `projects` in [projects.tf](projects.tf). The
[child module](modules/project-layout) creates a protected KV v2 mount,
exact-path read policies for non-empty credential sets, and only explicitly
granted Amp roles. It does not create or read secret values.

- Project names are literal lower-case `owner/repository` pairs. Credential names
  use literal slash-separated segments. No wildcards, templates or normalization.
- Environments are `dev` and `prod`. Classes: `plan` (verified read-only
  provider credentials), `app` (application runtime secrets), `inference` and
  `admin`. Omitted or empty classes create no policy. Amp grants are only
  `dev/plan` or `prod/plan` (whole non-empty set), or `dev/app/<credential>`
  (one declared document, so dev runtime secrets stay out of orbs). Never
  `prod/app`: production app secrets reach their platform through sync only.
- Root preconditions reject mount/policy/role namespace collisions and duplicate
  Amp IDs, including ambiguous `--` joins even with different credential sets.
  Policies use `allow_overwrite = false`. Existing reserved names require review
  and explicit import, not automatic adoption. Mount renames require migration.
- Module outputs `mount`, `secret_keys`, `policy_names` and `role_names` contain
  only locations and names. Read exact data paths, not metadata or mount listings.

`auth/amp` roles require audience `bao`, the project-scope subject, matching
`project_id`, `token_use=exchanged` and a `thread_id`, which setup tokens lack.
Tokens get one policy, no default policy, and a five-minute lifetime. Every
orb of the Amp project can use each of its roles.

The `*.tftest.hcl` files mock the Vault provider. They cannot prove server-side
JWT login or ACL enforcement.
