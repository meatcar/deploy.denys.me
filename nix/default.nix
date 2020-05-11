{sources ? import ./sources.nix}:
import sources.nixpkgs {
    overlays = [
        (_: pkgs: {inherit sources;})
        # (_: pkgs: {niv = import sources.niv {inherit pkgs;};})
        (_: pkgs: {nixos-generators = import sources.nixos-generators {};})
    ];
    config = {};
}