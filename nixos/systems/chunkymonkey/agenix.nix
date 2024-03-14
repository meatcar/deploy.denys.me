{...}: {
  age.secrets = {
    hashedPassword.file = ../../../secrets/hashed-password.age;
    transitDashboardEnv.file = ../../../secrets/transitDashboardEnv.age;
  };
}
