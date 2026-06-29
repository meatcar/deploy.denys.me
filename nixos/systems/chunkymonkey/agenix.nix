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
    restic-password.file = ../../../secrets/restic-password.age;
    restic-env.file = ../../../secrets/restic-env.age;
    restic-repo.file = ../../../secrets/restic-repo.age;
  };
}
