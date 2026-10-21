# deploy.denys.me orbs

Uses the [orb access template](../templates/orb-access/.agents/README.md) through
local symlinks. This repository's [Taskfile](Taskfile.yml) selects the approved
`prod/plan` Bao role and caches main-root providers at setup without backend
access. Resume only restores network access.

Run the on-demand [agent plan task](../terraform/README.md#agent-plans) after
enrollment. Credentials are scoped to child processes, not lifecycle hooks.
`task --taskfile .agents/Taskfile.yml doctl -- compute droplet list` runs doctl
with the same read-only DigitalOcean token: Droplets, images, snapshots,
regions, sizes, and actions only.
