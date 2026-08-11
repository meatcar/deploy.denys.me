_: {
  age.secrets = {
    hashedPassword.file = ../../../secrets/hashed-password.age;
    transitDashboardEnv.file = ../../../secrets/transitDashboardEnv.age;
    postgresPass = {
      file = ../../../secrets/chunkymonkey-postgres-pass.age;
      owner = "pod"; # rootless postgres + initdb containers read this
    };
    larapaperPgPass = {
      file = ../../../secrets/larapaperPgPass.age;
      owner = "pod"; # initdb container reads this to create the larapaper role
    };
    larapaperEnv = {
      file = ../../../secrets/larapaperEnv.age;
      owner = "pod"; # larapaper container reads APP_KEY, DB_PASSWORD
    };
    mysqlRootPass = {
      file = ../../../secrets/chunkymonkey-mysql-root-pass.age;
      owner = "pod"; # invoiceninja-mysql, its initdb container, mysql-dump@
    };
    invoiceninjaEnv = {
      file = ../../../secrets/invoiceninjaEnv.age;
      # Read by the app and the host init service, which provisions the DB user
      # from this same DB_PASSWORD line — one source of truth.
      owner = "pod";
    };
    invoiceninjaSesEnv = {
      file = ../../../secrets/invoiceninjaSesEnv.age;
      owner = "pod"; # SES API credentials rotate without touching APP_KEY
    };
    sesSmtpUser.file = ../../../secrets/chunkymonkey-ses-smtp-user.age;
    sesSmtpPass.file = ../../../secrets/chunkymonkey-ses-smtp-pass.age;
    cloudflareToken = {
      file = ../../../secrets/chunkymonkey-cloudflare-token.age;
      owner = "pod"; # traefik reads it via CF_DNS_API_TOKEN_FILE for DNS-01
    };
    restic-password.file = ../../../secrets/restic-password.age;
    restic-env.file = ../../../secrets/restic-env.age;
    restic-repo.file = ../../../secrets/restic-repo.age;
  };
}
