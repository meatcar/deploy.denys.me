{ pkgs, src }:
pkgs.runCommand "orb-access"
  {
    nativeBuildInputs = with pkgs; [
      bash
      bubblewrap
      coreutils
      gnugrep
      go-task
      jq
      python3
      shellcheck
    ];
  }
  ''
    export PYTHONDONTWRITEBYTECODE=1
    cd ${src}
    shellcheck -x templates/orb-access/.agents/{setup,resume,access/*.sh,sandbox/*.sh}
    python -m unittest discover -s tests/orb-access -v
    mkdir -p "$TMPDIR/project"
    cp -R .agents templates "$TMPDIR/project/"
    export ORB_ACCESS_SOURCE="$TMPDIR/project"
    python -m unittest discover -s tests/orb-access -v
    touch "$out"
  ''
