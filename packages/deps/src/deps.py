"""Report and apply the dependency updates that Renovate finds."""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path, PurePath

# NOTE: Renovate groupName values; "other" collects branches no rule groups.
GROUPS = ("flake", "opentofu", "images", "sources", "actions", "other")
# NOTE: Renovate also reports local modules and provider blocks; neither carries a version.
UNVERSIONED = {"local", "unspecified-version"}
SYSTEM = "x86_64-linux"
SOURCES = f"legacyPackages.{SYSTEM}.sources"
# NOTE: Pins that only custom managers detect, by file type.
PINS = {
    ".nix": re.compile(r'\b[A-Za-z]*[iI]mage\s*=\s*"(?![a-z]+-archive:|\d+")'),
    ".tf": re.compile(r'\b[A-Za-z]*[iI]mage\s*=\s*"(?![a-z]+-archive:|\d+")'),
    ".py": re.compile(r'"(?:docker\.io|ghcr\.io|quay\.io)/'),
}
FETCHED_VERSION = re.compile(r'^\s*version\s*=\s*"', re.M)
FETCHER = re.compile(r"\bfetch(?:FromGitHub|url|git|zip)\b")


@dataclass(frozen=True)
class Update:
    group: str
    major: bool
    manager: str
    file: str
    dep: str
    datasource: str
    current: str
    current_digest: str | None
    new: str
    new_digest: str | None
    replace: str | None
    lockfile: bool
    locked: str | None = None
    new_version: str | None = None

    @property
    def label(self) -> str:
        if self.lockfile:
            return f"{self.locked} -> {self.new_version} (lock)"
        cur = self.current or (self.current_digest or "")[7:19]
        new = self.new if self.new != self.current else (self.new_digest or "")[7:19]
        return f"{cur} -> {new}"


def package_files(report: dict):
    """(manager, package file) pairs from a Renovate repository report."""
    for manager, files in report["packageFiles"].items():
        for package_file in files:
            yield manager, package_file


def inventory(report: dict) -> list[tuple[str, str, str]]:
    """Detected (file, dependency, version) triples, skipped ones included."""
    found = set()
    for _, package_file in package_files(report):
        for dep in package_file["deps"]:
            if dep.get("skipReason") in UNVERSIONED:
                continue
            version = dep.get("lockedVersion") or dep.get("currentValue") or ""
            if dep.get("currentDigest"):
                version += "@" + dep["currentDigest"][7:19]
            if dep.get("skipReason"):
                version += f" ({dep['skipReason']})"
            found.add((package_file["packageFile"], dep.get("depName", "?"), version))
    return sorted(found)


def parse(report: dict) -> list[Update]:
    """Updates from a Renovate repository report, one per dependency and bucket."""
    updates = []
    for manager, package_file in package_files(report):
        for dep in package_file["deps"]:
            for update in dep.get("updates", []):
                if update.get("updateType") == "lockFileMaintenance":
                    continue
                branch = update["branchName"].removeprefix("renovate/")
                group = branch.removeprefix("major-")
                if group not in GROUPS:
                    group = "other"
                new = update.get("newValue") or dep.get("currentValue", "")
                updates.append(
                    Update(
                        group=group,
                        major=update.get("updateType") == "major",
                        manager=manager,
                        file=package_file["packageFile"],
                        dep=dep["depName"],
                        datasource=dep["datasource"],
                        current=dep.get("currentValue", ""),
                        current_digest=dep.get("currentDigest"),
                        new=new,
                        new_digest=update.get("newDigest"),
                        replace=dep.get("replaceString"),
                        lockfile=bool(update.get("isLockfileUpdate")),
                        locked=dep.get("lockedVersion"),
                        new_version=update.get("newVersion"),
                    )
                )
    return updates


def select(updates: list[Update], groups: list[str], major: bool) -> list[Update]:
    """Highest allowed update per dependency occurrence."""
    chosen: dict[tuple[str, str, str], Update] = {}
    for update in updates:
        if update.group not in groups or (update.major and not major):
            continue
        key = (update.file, update.dep, update.current)
        if key not in chosen or update.major:
            chosen[key] = update
    return list(chosen.values())


def apply(text: str, update: Update) -> str:
    """Rewrite one dependency occurrence in a package file."""
    if update.lockfile or update.manager == "nix":
        return text
    if update.replace is None:
        if update.manager != "terraform":
            raise ValueError(f"{update.file}: {update.dep} has no replaceable text")
        return _apply_terraform(text, update)
    if update.replace not in text:
        raise ValueError(f"{update.file}: {update.dep} changed since lookup")
    new = update.replace
    if update.new != update.current:
        if update.datasource == "docker":
            new = new.replace(f"{update.dep}:{update.current}", f"{update.dep}:{update.new}", 1)
        else:
            head, quoted, tail = new.rpartition(f'"{update.current}"')
            if not quoted:
                head, quoted, tail = new.rpartition(update.current)
            new = head + quoted.replace(update.current, update.new) + tail
    if update.current_digest and update.new_digest:
        new = new.replace(update.current_digest, update.new_digest)
    return text.replace(update.replace, new)


def _apply_terraform(text: str, update: Update) -> str:
    pattern = re.compile(
        r"(\b"
        + re.escape(update.dep)
        + r'\s*=\s*\{[^}]*?\bversion\s*=\s*")'
        + re.escape(update.current)
        + '"'
    )
    new = update.new
    operator = re.match(r"^\s*([=!<>~]+)\s*", update.current)
    if operator and not re.match(r"^\s*[=!<>~]", new):
        new = f"{operator.group(1)} {new}"
    result, count = pattern.subn(lambda m: f'{m.group(1)}{new}"', text)
    if count == 0:
        raise ValueError(f"{update.file}: {update.dep} {update.current} not found")
    return result


def unwatched(config: dict, files: dict[str, str]) -> list[str]:
    """Pins in the given file texts that no Renovate custom manager matches."""
    managers = [
        (
            [re.compile(f.strip("/")) for f in m["managerFilePatterns"]],
            [re.compile(r.replace("(?<", "(?P<")) for r in m["matchStrings"]],
        )
        for m in config.get("customManagers", [])
    ]
    found = []
    for name, text in files.items():
        if any(PurePath(name).full_match(glob) for glob in config.get("ignorePaths", [])):
            continue
        suffix = PurePath(name).suffix
        pins = [m.start() for m in PINS[suffix].finditer(text)] if suffix in PINS else []
        if suffix == ".nix" and FETCHER.search(text):
            pins += [m.end() - 1 for m in FETCHED_VERSION.finditer(text)]
        if not pins:
            continue
        spans = [
            match.span()
            for patterns, regexes in managers
            if any(p.search(name) for p in patterns)
            for regex in regexes
            for match in regex.finditer(text)
        ]
        for pin in pins:
            if not any(start <= pin < end for start, end in spans):
                line = text.count("\n", 0, pin) + 1
                found.append(f"{name}:{line}: {text.splitlines()[line - 1].strip()}")
    return found


def lint(paths: list[str]) -> None:
    files = paths or run("git", "ls-files", capture=True).split()
    texts = {
        name: Path(name).read_text()
        for name in files
        if PurePath(name).suffix in PINS and Path(name).is_file()
    }
    found = unwatched(json.loads(Path("renovate.json").read_text()), texts)
    for entry in found:
        print(entry)
    if found:
        raise SystemExit("Renovate cannot see these pins; follow the README Workflow conventions")


def run(*args: str, capture: bool = False) -> str:
    print("$", " ".join(args), file=sys.stderr)
    result = subprocess.run(args, check=True, text=True, capture_output=capture)
    return result.stdout if capture else ""


def renovate_report() -> dict:
    """The local repository's Renovate report; lookup problems go to stderr."""
    env = dict(os.environ, LOG_LEVEL="warn")
    if "RENOVATE_GITHUB_COM_TOKEN" not in env:
        token = env.get("GITHUB_TOKEN") or _gh_token()
        if token:
            env["RENOVATE_GITHUB_COM_TOKEN"] = token
    print("$ renovate --platform=local --dry-run=lookup", file=sys.stderr)
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp, "report.json")
        result = subprocess.run(
            [
                "renovate",
                "--platform=local",
                "--dry-run=lookup",
                "--report-type=file",
                f"--report-path={path}",
            ],
            env=env,
            text=True,
            capture_output=True,
        )
        if result.returncode != 0 or not path.exists():
            sys.stderr.write(result.stdout[-4000:] + result.stderr[-4000:])
            raise SystemExit("renovate lookup failed")
        report = json.loads(path.read_text())
    local = report["repositories"]["local"]
    for problem in report["problems"] + local["problems"]:
        level = {40: "warning", 50: "error", 60: "fatal"}.get(problem.get("level"), "problem")
        print(f"renovate {level}: {problem.get('msg') or problem}", file=sys.stderr)
    for _, package_file in package_files(local):
        for dep in package_file["deps"]:
            for warning in dep.get("warnings", []):
                print(f"{package_file['packageFile']}: {warning.get('message')}", file=sys.stderr)
    return local


def _gh_token() -> str | None:
    try:
        return run("gh", "auth", "token", capture=True).strip() or None
    except (OSError, subprocess.CalledProcessError):
        return None


def flake_ages() -> list[tuple[str, int]]:
    lock = json.loads(Path("flake.lock").read_text())
    nodes = lock["nodes"]
    now = time.time()
    ages = []
    for name, node in nodes[lock["root"]]["inputs"].items():
        if not isinstance(node, str):
            continue
        locked = nodes[node].get("locked", {})
        if "lastModified" in locked:
            ages.append((name, int((now - locked["lastModified"]) // 86400)))
    return sorted(ages, key=lambda item: -item[1])


def listing() -> None:
    rows = inventory(renovate_report())
    if not rows:
        raise SystemExit("renovate detected no dependencies")
    width = max(len(dep) for _, dep, _ in rows)
    for file in sorted({file for file, _, _ in rows}):
        print(f"{file}:")
        for _, dep, version in (row for row in rows if row[0] == file):
            print(f"  {dep.ljust(width)}  {version}")


def outdated(groups: list[str]) -> None:
    updates = [u for u in parse(renovate_report()) if u.group in groups]
    for group in groups:
        rows = sorted(
            {
                (u.dep, u.file, u.label + (" (major)" if u.major else ""))
                for u in updates
                if u.group == group
            }
        )
        if group == "flake":
            rows += [(f"{name} (flake.lock)", f"{days}d old", "") for name, days in flake_ages()]
        if not rows:
            print(f"{group}: up to date")
            continue
        print(f"{group}:")
        width = max(len(row[0]) for row in rows)
        for dep, file, label in rows:
            print(f"  {dep.ljust(width)}  {label}  {file}")


def source_fods() -> dict[str, list[str]]:
    expr = (
        "builtins.mapAttrs (_: p: map (d: d.drvPath)"
        " (builtins.filter builtins.isAttrs [ (p.src or null) (p.goModules or null) ]))"
    )
    return json.loads(run("nix", "eval", "--json", f".#{SOURCES}", "--apply", expr, capture=True))


def refresh_sources(names) -> None:
    for name in sorted(names):
        run("nix-update", "--flake", "--version=skip", f"{SOURCES}.{name}")


def fixup() -> None:
    """Repair locks and hashes after an edit that only bumped versions."""
    run("nix", "flake", "lock")
    refresh_sources(source_fods())
    run("nix", "fmt")


def rewrite(updates: list[Update]) -> dict[Path, str]:
    """New text for every file the updates touch; nothing is written."""
    texts = {}
    for file in sorted({u.file for u in updates}):
        text = Path(file).read_text()
        for update in (u for u in updates if u.file == file):
            text = apply(text, update)
        texts[Path(file)] = text
    return texts


def upgrade(groups: list[str], major: bool) -> None:
    chosen = select(parse(renovate_report()), groups, major)
    try:
        texts = rewrite(chosen)
    except ValueError as error:
        raise SystemExit(f"{error}; nothing changed") from error
    try:
        if "flake" in groups:
            run("nix", "flake", "update")
        # NOTE: Snapshot after the flake update; a nixpkgs bump changes every source drvPath.
        before = source_fods() if "sources" in groups else {}
        for path, text in texts.items():
            path.write_text(text)
        for update in chosen:
            if not update.lockfile and update.manager != "nix":
                print(f"  {update.dep}: {update.label}", file=sys.stderr)
        if "opentofu" in groups:
            locks = run("git", "ls-files", "*.terraform.lock.hcl", capture=True).split()
            for lock in locks:
                chdir = f"-chdir={Path(lock).parent}"
                run("tofu", chdir, "init", "-upgrade", "-backend=false", "-input=false")
        if "sources" in groups:
            after = source_fods()
            refresh_sources(n for n in after if after[n] != before.get(n))
        run("nix", "fmt")
    except subprocess.CalledProcessError as error:
        raise SystemExit(f"{error}; versions may be applied, run `deps fixup`") from error
    print("Review the diff, then run `nix flake check`.", file=sys.stderr)


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(prog="deps", description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    groups_help = f"any of {', '.join(GROUPS)} (default: all)"
    commands.add_parser("list", help="list detected dependencies and versions")
    commands.add_parser("fixup", help="refresh flake.lock and source hashes")
    commands.add_parser("lint", help="fail on pins Renovate cannot see").add_argument(
        "paths", nargs="*", help="files to check (default: tracked files)"
    )
    commands.add_parser("outdated", help="list available updates").add_argument(
        "groups", nargs="*", help=groups_help
    )
    upgrade_parser = commands.add_parser("upgrade", help="apply available updates")
    upgrade_parser.add_argument("--major", action="store_true", help="include major updates")
    upgrade_parser.add_argument("groups", nargs="*", help=groups_help)
    args = parser.parse_args(argv)
    if args.command == "list":
        return listing()
    if args.command == "fixup":
        return fixup()
    if args.command == "lint":
        return lint(args.paths)
    groups = args.groups or list(GROUPS)
    if unknown := set(groups) - set(GROUPS):
        parser.error(f"unknown group: {', '.join(sorted(unknown))}")
    if args.command == "outdated":
        outdated(groups)
    else:
        upgrade(groups, args.major)


if __name__ == "__main__":
    main()
