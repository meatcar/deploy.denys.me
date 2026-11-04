# Bao configuration

One state owns auth, policies and project mounts. Use the
[root workflow](../README.md#plan-and-apply) with `-chdir=terraform/bao-config`.
This root requires human authority and must not run under agent plan credentials.

## Project access

This repository is public, so it names only itself in `projects`
([projects.tf](projects.tf)). Every other project is one record in the
`registry` KV v2 mount, read at plan time. A record holds the same fields as a
`projects` entry plus `project` (its name) and the
[bao-sync](../../packages/bao-sync) `destinations` and `syncs`. Write the record,
then plan and apply. First apply only: `-target=vault_kv_secret_v2.registry_keep`.

The `bao-sync` policy grants list on each synced folder's `detailed-metadata`
and read on each synced source and its destination credential. A sync grants
nothing unless both documents are declared and the credential is `prod/admin/`.
bao-sync reads the registry every run. A sync or destination change within
documents it can already read (keys, targets, `adopt`, Vercel IDs) applies on
its next run without a plan, so writing a record is the approval. New sources
or credentials need an apply for the policy first. Remove a record with
`kv metadata delete`; a soft-deleted record fails every plan.

The [child module](modules/project-layout) creates a protected KV v2 mount,
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
  Creating a policy overwrites a same-named live one (vault provider default
  until v6), so check new names first. Mount renames require migration.
- Module outputs `mount`, `secret_keys`, `policy_names`, `write_role_name` and `role_names` contain
  only locations and names. Read exact data paths, not metadata or mount listings.

`agent_writes` lists declared `app` or `inference` documents that local agents
may write, never `plan`, `admin` or a whole class. The project then gets policy
and token role `project--<owner>--<repo>--write`: create in prod, create or
patch in dev, no read or delete. Prod is create-only because bao-sync deploys
every new version unreviewed. Tokens are orphan, non-renewable, at most 15
minutes, without the default policy, and may revoke themselves. Only the
`bao-minter` userpass user can mint them. Create it with a 1Password password
before the first apply (userpass refuses a user without one); tofu then owns its
token settings:

```sh
op read --no-newline op://VAULT/ITEM/password | bao write auth/userpass/users/bao-minter password=-
```

Agents use the [orb-access write helper](../../templates/orb-access/.agents/README.md#local-bao-writes).

`auth/amp` roles require audience `bao`, the project-scope subject, matching
`project_id`, `token_use=exchanged` and a `thread_id`, which setup tokens lack.
Tokens get one policy, no default policy, and a five-minute lifetime. Every
orb of the Amp project can use each of its roles.

The `*.tftest.hcl` files mock the Vault provider. They cannot prove server-side
JWT login or ACL enforcement.
