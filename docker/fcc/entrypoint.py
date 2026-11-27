"""Configure an optional gateway token using FCC's managed configuration."""
import os
import re
import sys

from free_claude_code.config.loader import ManagedConfigStore


def main() -> None:
    args = sys.argv[1:]
    if not args:
        raise SystemExit("No container command supplied")
    # Diagnostics and one-off commands do not mutate the persisted settings.
    if args[0] == "fcc-server" and "--version" not in args:
        token = os.environ.pop("FCC_PROXY_TOKEN", "")
        enabled = os.environ.get("PROXY_AUTH_ENABLED", "false").lower()
        if token:
            if not re.fullmatch(r"[A-Za-z0-9_-]{32,128}", token):
                raise SystemExit("FCC_PROXY_TOKEN must contain 32-128 URL-safe characters")
            # Upstream deliberately ignores process ANTHROPIC_AUTH_TOKEN for
            # server auth. Persist it using FCC's own configuration store.
            os.environ["PROXY_AUTH_ENABLED"] = "true"
            store = ManagedConfigStore()
            store.initialize()
            snapshot = store.read()
            if snapshot.managed.get("ANTHROPIC_AUTH_TOKEN") != token:
                values = dict(snapshot.managed)
                values["ANTHROPIC_AUTH_TOKEN"] = token
                store.commit(values, expected=snapshot)
        elif enabled not in {"false", "0", "no", "off"}:
            raise SystemExit("Set FCC_PROXY_TOKEN when enabling proxy authentication")
    os.execvp(args[0], args)


if __name__ == "__main__":
    main()
