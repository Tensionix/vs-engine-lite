"""Run vsrepo with GitHub requests authenticated, retried, and diagnosable.

vsrepo fetches every plugin binary through a bare ``urllib.request.urlopen(url)``
- see ``fetch_ur1`` in vsrepo.py - with no headers, no retry, and no error
reporting. When a download fails it prints one line, "Failed to download <name>,
skipping installation and moving on", and swallows the reason.

Measured 13 August 2026 on a full VS Engine build: fmtconv r30 downloaded at
12.8 MB/s and neo_f3kdb failed immediately afterwards with no progress bar and
no message of its own. The absence of a progress bar matters - ``fetch_ur1``
prints one as soon as it has a response - so the failure happened inside
``urlopen`` itself, before any body was read. That is where this shim acts.

Three things are added, none of them inside vsrepo:

1. **Authentication.** Anonymous GitHub allows 60 requests an hour for the whole
   machine; measured, 51 were left before a plugin pass started. This mainly
   governs api.github.com, which vsrepo uses for its package database - release
   binaries come from github.com/.../releases/download and are not counted
   against that ceiling. So this raises a real ceiling, but it is not by itself
   the cure for a failed asset download.
2. **Retry.** Four attempts with growing backoff, at the request rather than at
   the package: vsrepo's caller already retries the whole `vsrepo install <id>`,
   which re-downloads everything that had already succeeded.
3. **Diagnosis.** Every failure prints the status code or the socket error and
   the URL, so "Failed to download" stops being mute.

Known limit: a connection that dies *during* the body read raises inside
vsrepo's own loop, not here, and is still covered only by the outer per-package
retry. The failure this was written for did not get that far.

Usage:
    python vsrepo_github_auth.py <path-to-vsrepo.py> [vsrepo arguments...]

Without a token in the environment it says so and continues anonymously, so a
machine that never had a key behaves exactly as it did before.
"""

from __future__ import annotations

import os
import runpy
import sys
import time
import urllib.error
import urllib.request

# Only the hosts that accept a token. `objects.githubusercontent.com` is
# deliberately absent: release assets redirect there with the credentials
# already in the query string, and a second auth mechanism is refused.
_GITHUB_HOSTS = frozenset(
    {
        "github.com",
        "api.github.com",
        "raw.githubusercontent.com",
        "codeload.github.com",
    }
)

_MIN_TOKEN_LENGTH = 20

# Four attempts, 2s / 5s / 10s apart. Long enough to outlast a reset or a brief
# 5xx, short enough that a genuinely missing asset is reported quickly.
_ATTEMPTS = 4
_BACKOFF = (2, 5, 10)

# A 404 means the asset moved or the package database is stale; retrying it just
# spends time. 429 and 5xx are worth another go, and so is a bare connection
# error.
_RETRYABLE_STATUS = frozenset({408, 425, 429, 500, 502, 503, 504})

# urllib raises for 304, but vsrepo asks for it on purpose: it sends
# If-Modified-Since for the package database and treats the refusal as "already
# current". Reporting that as a failure is the same false signal this shim was
# added to remove.
_EXPECTED_STATUS = frozenset({304})

_original_urlopen = urllib.request.urlopen


def _log(message: str) -> None:
    print(f"[vsrepo-auth] {message}", flush=True)


def _short(url: object, limit: int = 96) -> str:
    text = str(url)
    return text if len(text) <= limit else text[: limit - 3] + "..."


class _GitHubAuthHandler(urllib.request.BaseHandler):
    # Ahead of the default handlers, so the header is on the first request
    # rather than on a retry after a 403.
    handler_order = 100

    def __init__(self, token: str) -> None:
        self._token = token

    def http_request(self, req):
        host = (req.host or "").split(":")[0].lower()
        if host in _GITHUB_HOSTS and not req.has_header("Authorization"):
            # Unredirected: the header must not follow the redirect to the
            # signed asset URL, which refuses a second auth mechanism.
            req.add_unredirected_header("Authorization", "Bearer " + self._token)
        if not req.has_header("User-agent"):
            req.add_unredirected_header("User-agent", "Audion-VS-Engine")
        return req

    https_request = http_request


def _describe(error: BaseException) -> str:
    if isinstance(error, urllib.error.HTTPError):
        detail = f"HTTP {error.code} {error.reason}"
        remaining = error.headers.get("X-RateLimit-Remaining") if error.headers else None
        if remaining is not None:
            detail += f"; rate limit remaining {remaining}"
        return detail
    if isinstance(error, urllib.error.URLError):
        return f"connection failed: {error.reason}"
    return f"{type(error).__name__}: {error}"


def _is_retryable(error: BaseException) -> bool:
    if isinstance(error, urllib.error.HTTPError):
        return error.code in _RETRYABLE_STATUS
    return isinstance(error, (urllib.error.URLError, OSError))


def _retrying_urlopen(url, *args, **kwargs):
    last: BaseException | None = None
    for attempt in range(1, _ATTEMPTS + 1):
        try:
            return _original_urlopen(url, *args, **kwargs)
        except Exception as error:  # noqa: BLE001 - the reason is the point
            last = error
            if isinstance(error, urllib.error.HTTPError) and error.code in _EXPECTED_STATUS:
                raise
            target = _short(getattr(url, "full_url", url))
            _log(f"{_describe(error)} <- {target}")
            if not _is_retryable(error):
                # A 404 is an answer, not a hiccup. Say so instead of implying
                # that attempts were spent on it.
                _log("not retryable; reporting immediately")
                break
            if attempt == _ATTEMPTS:
                _log(f"giving up after {attempt} attempt(s)")
                break
            delay = _BACKOFF[min(attempt - 1, len(_BACKOFF) - 1)]
            _log(f"attempt {attempt}/{_ATTEMPTS} failed; retrying in {delay}s")
            time.sleep(delay)
    raise last  # type: ignore[misc]


def _read_token() -> str:
    for name in ("GITHUB_TOKEN", "GH_TOKEN"):
        value = (os.environ.get(name) or "").strip()
        # An empty api_key_*.txt is a template, not a key; the same length floor
        # the orchestrator uses keeps a placeholder from being sent as a token.
        if len(value) >= _MIN_TOKEN_LENGTH:
            return value
    return ""


def install_opener() -> bool:
    token = _read_token()
    if not token:
        _log("no GitHub token in the environment; staying anonymous")
        return False
    urllib.request.install_opener(urllib.request.build_opener(_GitHubAuthHandler(token)))
    _log("GitHub requests authenticated (rate limit 5000/h)")
    return True


def install_retry() -> None:
    urllib.request.urlopen = _retrying_urlopen  # type: ignore[assignment]
    _log(f"downloads retried up to {_ATTEMPTS}x with backoff, failures reported")


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: vsrepo_github_auth.py <path-to-vsrepo.py> [vsrepo arguments...]")
        return 2

    target = argv[1]
    if not os.path.isfile(target):
        _log(f"vsrepo.py not found: {target}")
        return 2

    install_opener()
    install_retry()

    # vsrepo reads sys.argv itself, so it has to see the arguments it would have
    # seen if it had been started directly.
    sys.argv = [target] + argv[2:]
    runpy.run_path(target, run_name="__main__")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
