{ ... }:
{
  services.restic.backups.persist = {
    repository = builtins.readFile "/var/secrets/restic_repository";
    passwordFile = "/var/secrets/restic_password";
    s3CredentialsFile = "/var/secrets/restic_environment";
    paths = [ "/persist" ];
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 5"
      "--keep-monthly 12"
      "--keep-yearly 75"
    ];
  };
}
