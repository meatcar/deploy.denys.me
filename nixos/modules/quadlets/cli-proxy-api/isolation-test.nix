{ pkgs }:
let
  routes = import ./routes.nix {
    publicHost = "cpa.pvlv.ca";
    managementHost = "cpa.vpn.denys.me";
  };
  application = import ../routing-test.nix { inherit pkgs; };
  publicFirewall =
    (import ../default.nix {
      inherit pkgs;
      inherit (pkgs) lib;
      config = { };
      inputs = { };
    }).networking.firewall;
  directory =
    pkgs.runCommand "isolation-routes"
      {
        nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.pyyaml ])) ];
      }
      ''
        python ${./prepare-isolation.py} "$out" \
          ${application.staticConfig} ${application.dynamicConfig} \
          ${pkgs.writeText "cpa-routes.json" (builtins.toJSON routes)}
      '';
in
pkgs.testers.runNixOSTest {
  name = "cli-proxy-isolation";
  nodes.server = {
    imports = [ ./firewall.nix ];
    networking.firewall = {
      inherit (publicFirewall) extraCommands extraStopCommands;
    };
    networking.dhcpcd.denyInterfaces = [
      "wt0"
      "pub0"
      "tailscale0"
      "direct0"
    ];
    networking.hosts."127.0.0.1" = [
      "cli-proxy-api"
      "cpa-manager-plus"
    ];
    environment.systemPackages = with pkgs; [
      curl
      iproute2
      iptables
    ];
    services.traefik = {
      enable = true;
      staticConfigFile = "${directory}/static.json";
    };
    systemd.services.backend = {
      wantedBy = [ "multi-user.target" ];
      script = ''
        mkdir -p /tmp/backend/v1 /tmp/backend/v0/management
        mkdir -p /tmp/backend/v0/resource/plugins/pi-bridge
        echo bridge > /tmp/backend/v0/resource/plugins/pi-bridge/capabilities
        echo inference > /tmp/backend/v1/models
        echo wrong-backend > /tmp/backend/v0/management/config
        mkdir -p /tmp/backend/api
        echo device > /tmp/backend/api/display
        echo portal > /tmp/backend/client
        echo admin > /tmp/backend/login
        echo admin > /tmp/backend/dashboard
        exec ${pkgs.python3}/bin/python3 -m http.server 8317 --bind 127.0.0.1 --directory /tmp/backend
      '';
    };
    systemd.services.manager = {
      wantedBy = [ "multi-user.target" ];
      script = ''
        mkdir -p /tmp/manager/v0/management
        echo management > /tmp/manager/v0/management/config
        exec ${pkgs.python3}/bin/python3 -m http.server 18317 --bind 127.0.0.1 --directory /tmp/manager
      '';
    };
  };
  testScript = ''
    server.start()
    server.wait_for_unit("traefik.service")
    server.wait_for_unit("backend.service")
    server.wait_for_unit("manager.service")
    server.wait_for_open_port(8443)
    for name, interface, subnet in [("private", "wt0", 1), ("public", "pub0", 2), ("tailscale", "tailscale0", 3), ("direct", "direct0", 4)]:
        server.succeed(f"ip netns add {name}")
        server.succeed(f"ip link add {interface} type veth peer name peer netns {name}")
        server.succeed(f"ip addr add 192.0.{subnet}.1/24 dev {interface}")
        server.succeed(f"ip -6 addr add fd00:{subnet}::1/64 dev {interface} nodad")
        server.succeed(f"ip link set {interface} up")
        server.succeed(f"ip -n {name} addr add 192.0.{subnet}.2/24 dev peer")
        server.succeed(f"ip -n {name} -6 addr add fd00:{subnet}::2/64 dev peer nodad")
        server.succeed(f"ip -n {name} link set peer up")
    # Emulate the real Cloudflare source boundary; the direct namespace has no
    # trusted source address and cannot enter via either the low or high ports.
    server.succeed("ip addr add 173.245.48.1/24 dev pub0")
    server.succeed("ip -n public addr add 173.245.48.2/24 dev peer")

    def request(namespace, address, port, host, path):
        return f"ip netns exec {namespace} curl --noproxy '*' --path-as-is -gksS --max-time 2 -H 'Host: {host}' -w '\n%{{http_code}}' 'https://{address}:{port}{path}'"

    public_host = "cpa.pvlv.ca"
    private_host = "cpa.vpn.denys.me"
    for path, body in [("/v1/models", "inference"), ("/v0/resource/plugins/pi-bridge/capabilities", "bridge")]:
        response = server.succeed(request("public", "173.245.48.1", 443, public_host, path)).strip()
        assert response == f"{body}\n\n200", (path, response)
    for host in [public_host, private_host]:
        for path in ["/", "/v0/management/config", "/management.html", "/usage-service/info", "/v0/resource/plugins/pi-bridge/panel", "/v0/resource/plugins/pi-bridge/dev/usage", "/codex/callback", "/v1/../v0/management/config", "/v1/%2e%2e/v0/management/config"]:
            response = server.succeed(request("public", "173.245.48.1", 443, host, path))
            assert response.strip().endswith("404"), (host, path, response)
            assert "management\n" not in response
    for host, path, marker in [("billing.denys.me", "/client", "portal"), ("trmnl.denys.me", "/api/display", "device")]:
        assert marker in server.succeed(request("public", "173.245.48.1", 443, host, path))
    for public, private, path in [("billing.denys.me", "billing.vpn.denys.me", "/login"), ("trmnl.denys.me", "trmnl.vpn.denys.me", "/dashboard")]:
        for host in [public, private]:
            for port in [443, 8443]:
                assert server.succeed(request("public", "173.245.48.1", port, host, path)).strip().endswith("404")
        for address in ["192.0.1.1", "[fd00:1::1]"]:
            for port in [443, 9443]:
                assert "admin" in server.succeed(request("private", address, port, private, path))
    for address in ["192.0.4.1", "[fd00:4::1]"]:
        for port in [443, 8443, 9443, 8317, 18317, 9000, 3306, 5432]:
            server.fail(request("direct", address, port, "billing.vpn.denys.me", "/login"))
    for address in ["192.0.1.1", "[fd00:1::1]"]:
        assert server.succeed(request("private", address, 443, private_host, "/v0/management/config")).strip() == "management\n\n200"
    for tool in ["iptables", "ip6tables"]:
        server.succeed(f"{tool} -I INPUT -p tcp --dport 9443 -j ACCEPT")
    for action in ["", "stop", "restart"]:
        if action:
            server.succeed(f"systemctl {action} firewall")
        for namespace, subnet in [("public", 2), ("tailscale", 3)]:
            for address in [f"192.0.{subnet}.1", f"[fd00:{subnet}::1]"]:
                for host, path in [(private_host, "/v0/management/config"), ("billing.vpn.denys.me", "/login"), ("trmnl.vpn.denys.me", "/dashboard")]:
                    server.fail(request(namespace, address, 9443, host, path))
    assert "management" in server.succeed(request("private", "192.0.1.1", 443, private_host, "/v0/management/config"))
  '';
}
