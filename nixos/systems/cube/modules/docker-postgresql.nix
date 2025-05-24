{
  config,
  pkgs,
  ...
}: let
  cfg = config.services.postgresql;
  port = toString cfg.settings.port;
  dataDir = "${config.mine.persistPath}/postgres";
  pgversion = "14";
in {
  config = {
    systemd.tmpfiles.rules = [
      "d ${dataDir} 0750 - - - -"
    ];
    systemd.services.init-docker-network-postgres = {
      description = "Create the docker network 'postgres' for postgres.";
      after = ["network.target"];
      wantedBy = ["docker-postgres.service"];

      serviceConfig.Type = "oneshot";
      script = let
        docker = "${config.virtualisation.docker.package}/bin/docker";
        network = "postgres";
      in ''
        check=$(${docker} network ls | grep "${network}" || true)
        if [ -z "$check" ]; then
          ${docker} network create "${network}"
        else
          echo "docker network '${network}' already exists"
        fi
      '';
    };

    systemd.services."init-postgres-user-db@" = {
      description = "Create the postgres database and user for %i";
      after = ["docker-postgres.service"];
      before = ["docker-%i.service"];
      wantedBy = ["docker-%i.service"];

      serviceConfig.Type = "oneshot";
      serviceConfig.LoadCredential = [
        "userPgPass:CHANGEME"
        "postgresPass:${config.age.secrets.postgresPass.path}"
      ];
      environment = {
        "POSTGRES_USER" = "postgres";
        DBUSER = "%i";
        DBNAME = "%i";
      };
      script = ''
        export PGPASSWORD=$(cat "$CREDENTIALS_DIRECTORY/postgresPass")
        USER_PASSWORD=$(cat "$CREDENTIALS_DIRECTORY/userPgPass")
        PSQL=${pkgs."postgresql_${pgversion}"}/bin/psql

        while ! (echo '\q' | $PSQL --host localhost --username "$POSTGRES_USER")
        do
          sleep 1 # spin until db is up
        done

        $PSQL -v ON_ERROR_STOP=1 --host localhost --username "$POSTGRES_USER" <<-EOSQL
          -- CREATE TABLE IF EXISTS
          DO
          \$do$
          BEGIN
             IF EXISTS ( SELECT FROM pg_catalog.pg_roles WHERE rolname = '$DBUSER') THEN
                RAISE NOTICE 'Role "$DBUSER" already exists. Skipping.';
             ELSE
                CREATE ROLE $DBUSER LOGIN PASSWORD '$USER_PASSWORD';
             END IF;
          END
          \$do$;

          -- CREATE DATABASE IF EXISTS
          SELECT 'CREATE DATABASE $DBNAME ENCODING "UNICODE"'
          WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DBNAME')\gexec

          ALTER DATABASE $DBNAME OWNER TO $DBUSER;
          GRANT ALL PRIVILEGES ON DATABASE $DBNAME TO $DBUSER;
        EOSQL
      '';
    };

    virtualisation.oci-containers.containers.postgres = {
      image = "postgres:${pgversion}";
      ports = ["${port}:5432"];
      volumes = [
        "${dataDir}:/var/lib/postgresql/data"
        "${config.age.secrets.postgresPass.path}:${config.age.secrets.postgresPass.path}"
      ];
      environment = {
        POSTGRES_PASSWORD_FILE = config.age.secrets.postgresPass.path;
      };
      extraOptions = ["--network=postgres"];
    };
  };
}
