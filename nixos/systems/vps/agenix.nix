{...}: {
  age.secrets = {
    wg-priv-key.file = ../../../secrets/wg-server-priv-key.age;
    restic-password.file = ../../../secrets/restic-password.age;
    restic-env.file = ../../../secrets/restic-env.age;
    restic-repo.file = ../../../secrets/restic-repo.age;
    hashedPassword.file = ../../../secrets/hashed-password.age;
  };
}
