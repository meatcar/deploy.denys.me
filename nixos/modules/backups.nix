{ config, ... }:
{
  services.restic.backups.persist = {
    # repository set in secrets.nix
    passwordFile = config.age.secrets.restic-password.path;
    environmentFile = config.age.secrets.restic-env.path;
    paths = [ "/persist" ];
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 5"
      "--keep-monthly 12"
      "--keep-yearly 75"
    ];
  };
}
