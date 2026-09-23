fqdn:
[ fqdn ]
++ map (name: "${name}.${fqdn}") [
  "organizr"
  "sonarr"
  "radarr"
  "bazarr"
  "transmission"
  "jackett"
  "tautulli"
  "scrutiny"
  "books"
  "rss"
]
