{ pkgs }:
let
  inherit ((builtins.fromTOML (builtins.readFile ./pyproject.toml))) project;
in
pkgs.python3Packages.buildPythonApplication {
  pname = project.name;
  inherit (project) version;
  pyproject = true;
  src = pkgs.lib.cleanSource ./.;
  build-system = [ pkgs.python3Packages.setuptools ];
  nativeCheckInputs = with pkgs; [
    python3Packages.pytestCheckHook
    openbao
  ];
  postFixup =
    pkgs.lib.optionalString pkgs.stdenv.isLinux ''
      wrapProgram $out/bin/cli-proxy-api-admin \
        --prefix PATH : ${
          pkgs.lib.makeBinPath [
            pkgs.curl
            pkgs.podman
            pkgs.systemd
          ]
        }
    ''
    + ''
      wrapProgram $out/bin/cli-proxy-api-rotate-admin \
        --prefix PATH : ${
          pkgs.lib.makeBinPath [
            pkgs.openbao
            pkgs.openssh
          ]
        }
      wrapProgram $out/bin/cli-proxy-api-deploy-key \
        --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.openssh ]}
    '';
}
