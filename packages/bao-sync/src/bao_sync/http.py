import json
import urllib.error
import urllib.request


class HTTPError(Exception):
    def __init__(self, method, url, status, retry_after=None):
        super().__init__(f"{method} {url.split('?')[0]} -> {status}")
        self.status = status
        self.retry_after = retry_after


def request(method, url, headers, body=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            payload = response.read()
    except urllib.error.HTTPError as error:
        # NOTE: Error bodies can echo request values; never include them.
        raise HTTPError(method, url, error.code, error.headers.get("Retry-After")) from None
    return json.loads(payload) if payload else None
