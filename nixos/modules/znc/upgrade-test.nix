{ pkgs }:
pkgs.testers.runNixOSTest {
  name = "znc-mutable-upgrade";
  nodes.server =
    { lib, ... }:
    {
      imports = [
        ../znc.nix
        ../private-access
      ];
      mine.znc = {
        enable = true;
        domain = "znc.example.test";
        users = { };
      };
      networking.dhcpcd.denyInterfaces = [ "pub0" ];
      environment.systemPackages = with pkgs; [
        curl
        iproute2
        iptables
        socat
      ];
      services.nginx = {
        enable = true;
        streamConfig = lib.mkForce "";
        virtualHosts = lib.mkForce {
          localhost = {
            listen = [
              {
                addr = "127.0.0.1";
                port = 8888;
              }
            ];
            locations."/".proxyPass = "http://127.0.0.1:6697";
          };
        };
      };
      systemd.services = {
        # The test seeds an existing install before its first start.
        znc.wantedBy = lib.mkForce [ ];
        irc-fixture.serviceConfig.ExecStart = "${pkgs.iproute2}/bin/ip netns exec remote ${pkgs.socat}/bin/socat -u TCP4-LISTEN:6697,reuseaddr,fork OPEN:/tmp/irc-received,creat,append";
        backend-probe.serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 -m http.server 6697 --bind :: --directory /run";
      };
    };
  testScript = ''
    start_all()
    server.wait_for_unit("multi-user.target")
    server.succeed("ip netns add remote; ip link add pub0 type veth peer name peer netns remote")
    server.succeed("ip addr add 192.0.2.1/24 dev pub0; ip link set pub0 up; ip -6 addr add fd00:2::1/64 dev pub0 nodad")
    server.succeed("ip -n remote addr add 192.0.2.2/24 dev peer; ip -n remote link set peer up; ip -n remote link set lo up; ip -n remote -6 addr add fd00:2::2/64 dev peer nodad")
    server.succeed("systemctl start irc-fixture")
    server.succeed("install -d -o znc -g znc /var/lib/znc/configs /var/lib/znc/users/mutable/moddata/retained")
    server.succeed("install -o znc -g znc -m 600 ${./legacy.conf} /var/lib/znc/configs/znc.conf")
    server.succeed("echo keep-module-data > /var/lib/znc/users/mutable/moddata/retained/.registry; chown -R znc:znc /var/lib/znc/users")
    server.succeed("systemctl start znc")
    server.wait_for_unit("znc.service")
    server.wait_until_succeeds("grep -F 'NICK mutable-nick' /tmp/irc-received")

    def local_access():
        server.wait_until_succeeds("curl -fsS http://127.0.0.1:6697/ | grep -i znc", timeout=30)
        server.succeed("curl -fsS http://127.0.0.1:8888/ | grep -i znc")
        server.succeed("ss -H -ltn 'sport = :6697' | grep -F '127.0.0.1:6697'")
        assert server.succeed("ss -H -ltn 'sport = :6697' | wc -l").strip() == "1"

    def remote_denied():
        for address in ["192.0.2.1", "[fd00:2::1]"]:
            server.fail(f"ip netns exec remote curl --noproxy '*' -gfsS --max-time 1 http://{address}:6697/")

    for action in [
        "true",
        "iptables -I INPUT -j ACCEPT; ip6tables -I INPUT -j ACCEPT",
        "systemctl stop firewall",
        "systemctl restart znc",
        "systemctl restart firewall; systemctl restart znc",
    ]:
        server.succeed(action)
        server.wait_for_unit("znc.service")
        local_access()
        remote_denied()

    server.succeed("systemctl stop znc")
    # ZNC rewrites its own listener name and formatting. Check retained semantics.
    saved = server.succeed("cat /var/lib/znc/configs/znc.conf")
    for setting in ["mutable-nick", "mutable-alt", "mutable-ident", "Mutable fixture", "Keep my mutable settings", "controlpanel", "<Network retained>", "192.0.2.2 6697", "keepnick", "<Chan #retained>", "Buffer = 37", "Hash = fixture-only"]:
        assert setting.lower() in saved.lower(), setting
    server.succeed("grep -Fx keep-module-data /var/lib/znc/users/mutable/moddata/retained/.registry")
    before = server.succeed("sha256sum /var/lib/znc/configs/znc.conf")
    for _ in range(2):
        server.succeed("${pkgs.python3}/bin/python3 ${./loopback.py} /var/lib/znc/configs/znc.conf 6697")
        assert server.succeed("sha256sum /var/lib/znc/configs/znc.conf") == before
    server.succeed("systemctl start znc")
    local_access()

    # Independently prove the guard, even if a backend later binds wildcard.
    server.succeed("systemctl stop znc; systemctl start backend-probe")
    server.wait_until_succeeds("curl -fsS http://127.0.0.1:6697/ >/dev/null")
    server.succeed("curl --noproxy '*' -gfsS http://[::1]:6697/ >/dev/null")
    for tool in ["iptables", "ip6tables"]:
        server.succeed(f"{tool} -t raw -Z PREROUTING")
    for action in ["iptables -I INPUT -j ACCEPT; ip6tables -I INPUT -j ACCEPT", "systemctl stop firewall"]:
        server.succeed(action)
        remote_denied()
    for tool in ["iptables", "ip6tables"]:
        packets = server.succeed(f"{tool} -t raw -nxvL PREROUTING | awk '$3 == \"DROP\" && /dpt:6697/ {{print $1}}'")
        assert int(packets.strip()) > 0, f"{tool}: remote probes must reach the backend guard"
    server.succeed("systemctl stop backend-probe; systemctl start znc")
    local_access()
  '';
}
