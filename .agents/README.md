# deploy.denys.me orbs

Uses the [orb access template](../templates/orb-access/.agents/README.md) through
local symlinks. This repository's [Taskfile](Taskfile.yml) selects the approved
`prod/plan` Bao role and caches only main-root providers without backend access.

The plan task is not part of this lifecycle. Network and Bao provisioning,
read-only credentials, and real orb verification remain prerequisites.
