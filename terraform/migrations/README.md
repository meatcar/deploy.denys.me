# Consolidate six states into two

**Do not apply the new root before migrating existing state.** This procedure
changes backend state, not cloud resources, and requires explicit approval.
Keep every operator, scheduled job, and old checkout from writing state for
the entire maintenance window. S3 locks protect individual writes, not this
multi-state transfer.

## Capture and prepare

1. In an initialized checkout of the pre-refactor configuration, select the
   default workspace in every root. Verify the bucket is
   `terraform-state-denys-me` and the keys below. Resolve drift first.
2. From that checkout's repository root, save private snapshots. Never print,
   commit, or upload their contents to an agent. Keep a separate backup of the
   snapshots throughout the migration.

   ```sh
   umask 077
   mkdir -m 700 -p output/state-consolidation/snapshots
   tofu -chdir=terraform state pull > output/state-consolidation/snapshots/main.tfstate
   for root in bao netbird railway ovh-vps; do
     tofu -chdir="terraform/$root" state pull > "output/state-consolidation/snapshots/$root.tfstate"
   done
   tofu -chdir=terraform/bao-config state pull > output/state-consolidation/snapshots/bao-config.tfstate
   ```

3. Make the snapshots available locally in the updated checkout. Prepare
   candidates using only local OpenTofu state commands:

   ```sh
   python3 terraform/migrations/prepare.py \
     output/state-consolidation/snapshots output/state-consolidation/candidate
   ```

   The helper preserves originals, rejects address collisions, and produces a
   combined `main.tfstate` plus emptied source states. It does not contact S3,
   run providers, or transfer source outputs. The main root declares the former
   Bao outputs, which OpenTofu recalculates when the reviewed plan is applied.
   Discard incomplete candidates after any error; restart from unchanged
   snapshots in a fresh destination.

| Old backend key | Candidate file | Destination address |
| --- | --- | --- |
| `state` | `main.tfstate` | Existing root addresses; `moved.tf` handles OCI and parked domains |
| `bao/state` | `bao.tfstate` | `module.bao_support.<old address>` |
| `netbird/state` | `netbird.tfstate` | `module.netbird_access.<old address>` |
| `railway/state` | `railway.tfstate` | `module.railway_services.<old address>` |
| `ovh-vps/state` | `ovh-vps.tfstate` | Same address in the main root |
| `bao-config/state` | Unchanged | Unchanged |

## Review before publishing

From the updated repository root, create a private review copy without cached
backend metadata, states, or tfvars. Supply the usual provider inputs through
the repository environment, then run these commands as a human operator:

```sh
umask 077
mkdir -m 700 output/state-consolidation/review
tar --exclude=.terraform --exclude=.terragrunt-cache --exclude=.env\* \
  --exclude=\*.tfstate\* --exclude=\*.tfplan --exclude=\*.tfvars\* \
  --exclude=output -cf - terraform |
  tar -xf - -C output/state-consolidation/review
cp terraform/migrations/local-backend_override.tf.example \
  output/state-consolidation/review/terraform/local-backend_override.tf
cp output/state-consolidation/candidate/main.tfstate \
  output/state-consolidation/review/terraform/candidate.tfstate
tofu -chdir=output/state-consolidation/review/terraform init -reconfigure -lockfile=readonly
jq -e '.backend.type == "local" and .backend.config.path == "candidate.tfstate"' \
  output/state-consolidation/review/terraform/.terraform/terraform.tfstate
```

Stop if the backend check fails. Only after it passes:

```sh
tofu -chdir=output/state-consolidation/review/terraform plan -out=review.tfplan
tofu -chdir=output/state-consolidation/review/terraform show review.tfplan
```

Keep plan output private. Do not apply from the review copy.

- Expect OCI and parked-domain address moves, not recreation. Verify every
  source resource is represented once in the destination.
- Require zero managed-resource creates, updates, or destroys for this refactor.
  Output changes and the existing non-destructive `removed` block are separate.
  Investigate drift or provider normalization instead of applying it incidentally.
- The main root now uses AWS 6.63, already used by Bao, instead of AWS 6.50.
  State-backend resources must stay in `us-east-1`; Bao resources must stay in
  `ca-central-1` through `aws.ca_central_1`.
- Check OVH's empty purchase plan, Railway volumes, DNS proxy flags, and NetBird
  complete administrator memberships. Provider mocks cannot prove these match
  live state.

## Publish only after approval

Re-pull all five affected remote states and compare lineage, serial, and
contents with the originals. Any difference invalidates the candidates; stop
and prepare again. Keep the maintenance window in force.

1. Initialize the updated main root against its unchanged S3 backend. Push the
   combined candidate with `tofu state push`, without `-force`.
2. Using the initialized pre-refactor roots, push each corresponding emptied
   candidate to `bao/state`, `netbird/state`, `railway/state`, and `ovh-vps/state`,
   again without `-force`. Never run plan/apply from those old roots afterward.
3. Re-plan the updated main root against S3. Review and apply only the expected
   address/provider bindings and output changes. Do not reuse the local-backend
   review plan. Re-plan Bao configuration separately; its backend is unchanged.
4. Retire old automation/checkouts before releasing the maintenance window.
   Retain snapshots and old S3 object versions under the existing private backup
   policy. Do not delete backend objects as part of this procedure.

There is a temporary duplicate-ownership window between destination and source
writes. If a write or review fails, freeze all applies and reconcile which
pushes succeeded before retrying or restoring. Never blindly restore only one
state or force-push an older snapshot over concurrent changes.
