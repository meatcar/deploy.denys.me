{ pkgs }:
let
  routes = import ./routes.nix {
    publicHost = "cpa.pvlv.ca";
    managementHost = "cpa.vpn.denys.me";
  };
  directory = pkgs.writeTextDir "cli-proxy-api.yml" (
    builtins.toJSON (
      routes
      // {
        http = routes.http // {
          routers = builtins.mapAttrs (_: router: router // { tls = { }; }) routes.http.routers;
        };
      }
    )
  );
in
pkgs.testers.runNixOSTest {
  name = "cli-proxy-isolation";
  nodes.server = {
    imports = [ ./firewall.nix ];
    networking.firewall.allowedTCPPorts = [ 8443 ];
    networking.firewall.extraCommands = ''
      for tool in iptables ip6tables; do
        $tool -t nat -A PREROUTING -m addrtype --dst-type LOCAL -p tcp --dport 443 -j REDIRECT --to-ports 8443
      done
    '';
    networking.dhcpcd.denyInterfaces = [
      "wt0"
      "pub0"
      "tailscale0"
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
      staticConfigFile = pkgs.writeText "traefik-test.yml" (
        builtins.toJSON {
          entryPoints = {
            websecure.address = ":8443";
            netbird.address = ":9443";
          };
          providers.file.directory = toString directory;
        }
      );
    };
    systemd.services.backend = {
      wantedBy = [ "multi-user.target" ];
      script = ''
        mkdir -p /tmp/backend/v1 /tmp/backend/v0/management
        mkdir -p /tmp/backend/v0/resource/plugins/pi-bridge
        echo bridge > /tmp/backend/v0/resource/plugins/pi-bridge/capabilities
        echo inference > /tmp/backend/v1/models
        echo wrong-backend > /tmp/backend/v0/management/config
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
    for name, interface, subnet in [("private", "wt0", 1), ("public", "pub0", 2), ("tailscale", "tailscale0", 3)]:
        server.succeed(f"ip netns add {name}")
        server.succeed(f"ip link add {interface} type veth peer name peer netns {name}")
        server.succeed(f"ip addr add 192.0.{subnet}.1/24 dev {interface}")
        server.succeed(f"ip -6 addr add fd00:{subnet}::1/64 dev {interface} nodad")
        server.succeed(f"ip link set {interface} up")
        server.succeed(f"ip -n {name} addr add 192.0.{subnet}.2/24 dev peer")
        server.succeed(f"ip -n {name} -6 addr add fd00:{subnet}::2/64 dev peer nodad")
        server.succeed(f"ip -n {name} link set peer up")

    def request(namespace, address, port, host, path):
        return f"ip netns exec {namespace} curl --noproxy '*' --path-as-is -gksS --max-time 2 -H 'Host: {host}' -w '\n%{{http_code}}' 'https://{address}:{port}{path}'"

    public_host = "cpa.pvlv.ca"
    private_host = "cpa.vpn.denys.me"
    assert server.succeed(request("public", "192.0.2.1", 443, public_host, "/v1/models")).strip() == "inference\n\n200"
    assert server.succeed(request("public", "192.0.2.1", 443, public_host, "/v0/resource/plugins/pi-bridge/capabilities")).strip() == "bridge\n\n200"
    for host in [public_host, private_host]:
        for path in ["/", "/v0/management/config", "/management.html", "/usage-service/info", "/v0/resource/plugins/pi-bridge/panel", "/v0/resource/plugins/pi-bridge/dev/usage", "/codex/callback", "/v1/../v0/management/config", "/v1/%2e%2e/v0/management/config"]:
            response = server.succeed(request("public", "192.0.2.1", 443, host, path))
            assert response.strip().endswith("404"), (host, path, response)
            assert "management\n" not in response
    for address in ["192.0.1.1", "[fd00:1::1]"]:
        assert server.succeed(request("private", address, 443, private_host, "/v0/management/config")).strip() == "management\n\n200"
    for tool in ["iptables", "ip6tables"]:
        server.succeed(f"{tool} -I INPUT -p tcp --dport 9443 -j ACCEPT")
    for action in ["", "stop", "restart"]:
        if action:
            server.succeed(f"systemctl {action} firewall")
        for namespace, subnet in [("public", 2), ("tailscale", 3)]:
            for address in [f"192.0.{subnet}.1", f"[fd00:{subnet}::1]"]:
                server.fail(request(namespace, address, 9443, private_host, "/v0/management/config"))
    assert "management" in server.succeed(request("private", "192.0.1.1", 443, private_host, "/v0/management/config"))
  '';
}
