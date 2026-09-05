import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

from cli_proxy_api.deployment import Deployment


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def deploy_key(key, management_key, management_url, api_url):
    client = urllib.request.build_opener(NoRedirect, urllib.request.ProxyHandler({}))
    client.addheaders = [("User-Agent", "cli-proxy-api-deploy/1.0")]
    request = urllib.request.Request(
        management_url + "/v0/management/api-keys",
        method="PATCH",
        headers={
            "Authorization": "Bearer " + management_key,
            "Content-Type": "application/json",
        },
        # NOTE: Replacing a key with itself appends only when it is absent.
        data=json.dumps({"old": key, "new": key}).encode(),
    )
    with client.open(request, timeout=15):
        pass
    request = urllib.request.Request(
        api_url + "/v1/models", headers={"Authorization": "Bearer " + key}
    )
    for attempt in range(10):
        try:
            with client.open(request, timeout=15) as response:
                if response.status != 200 or not isinstance(json.load(response)["data"], list):
                    raise ValueError("Invalid model-list response")
            return
        except urllib.error.HTTPError as error:
            if error.code != 401 or attempt == 9:
                raise
            time.sleep(0.5)


def deploy(deployment):
    key = os.environ.pop("CLI_PROXY_API_KEY")
    management_key = deployment.ssh(
        "sudo",
        "-n",
        "cat",
        "--",
        deployment.state_directory + "/manager/admin-key",
    ).stdout.strip()
    if not key or not management_key:
        raise ValueError("Empty credential")
    deploy_key(key, management_key, deployment.management_url, deployment.api_url)
    print("CLIProxyAPI key deployed and authenticated through the public API.")


def main():
    parser = argparse.ArgumentParser(description="Deploy the key supplied in CLI_PROXY_API_KEY")
    parser.add_argument(
        "--config",
        default=os.environ.get("CLI_PROXY_API_CONFIG"),
        required=not os.environ.get("CLI_PROXY_API_CONFIG"),
    )
    args = parser.parse_args()
    try:
        deploy(Deployment.load(args.config))
    except Exception as error:
        status = f" HTTP {error.code}" if isinstance(error, urllib.error.HTTPError) else ""
        print(
            f"CLIProxyAPI key deployment failed ({type(error).__name__}{status}); secret publication stopped.",
            file=sys.stderr,
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
