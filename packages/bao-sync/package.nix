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
  nativeCheckInputs = [
    pkgs.python3Packages.pytestCheckHook
    pkgs.openbao
  ];
}
