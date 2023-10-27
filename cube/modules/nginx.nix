{ config, pkgs, ... }:
let
  wwwDir = pkgs.writeTextDir "index.html" ''
    <!DOCTYPE html>
    <html lang="en-US">
      <head>
        <meta charset="utf-8">
        <title>${config.networking.fqdn}</title>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        html { font-size: 16px; }
        body {
          font-size: 2rem;
          font-family: sans-serif;
          text-align: center;
        }
        :root {
          --color: cornflowerblue;
        }
        a, a:visited {
          display: inline-block;
          text-decoration: none;
          color: var(--color);
          border-bottom: 2px dotted var(--color);
          margin: 0.2em;
          padding: 0.2em;
        }
        a:hover {
          --color: blue;
        }
        .dev {
          font-size: 1rem;
          margin-top: 100vh;
        }
        .dev {
          --color: #ccc;
          color: var(--color);
        }
        </style>
      </head>
      <body>
        <section>
          <h1>🕋 ${config.networking.fqdn}</h1>
          <div>
            <a href="https://plex.${config.networking.fqdn}/">🍿 Watch</a>
          </div>
          <div>
            <a href="https://ombi.${config.networking.fqdn}/">🙏 Request</a>
          </div>
        </section>
        <section class=dev>
          <h2>⚙ dev</h1>
          <span>
            <a href="https://tautulli.${config.networking.fqdn}/">📊 tautulli</a>
          </span>
          <span>
            <a href="https://jackett.${config.networking.fqdn}/">🧥 jackett</a>
          </span>
          <span>
            <a href="https://sonarr.${config.networking.fqdn}/">📺 sonarr</a>
          </span>
          <span>
            <a href="https://radarr.${config.networking.fqdn}/">🎬 radarr</a>
          </span>
          <span>
            <a href="https://transmission.${config.networking.fqdn}/">🧨 transmit</a>
          </span>
        </section>
      </body>
    </html>
  '';
in
{
  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    virtualHosts."${config.networking.fqdn}" = {
      enableACME = true;
      forceSSL = true;
      default = true;
      locations."/" = {
        root = wwwDir;
        index = "index.html";
      };
    };
  };
}
