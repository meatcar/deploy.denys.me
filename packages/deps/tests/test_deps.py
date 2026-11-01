import pytest

from deps import Update, apply, inventory, parse, rewrite, select, unwatched

OLD = "sha256:" + "a" * 64
NEW = "sha256:" + "b" * 64


def update(**fields):
    defaults = dict(
        group="images",
        major=False,
        manager="regex",
        file="host.nix",
        dep="traefik",
        datasource="docker",
        current="v3.7.5",
        current_digest=None,
        new="v3.7.17",
        new_digest=None,
        replace='image = "traefik:v3.7.5"',
        lockfile=False,
    )
    return Update(**(defaults | fields))


def report(deps, manager="regex", package_file="host.nix"):
    return {"packageFiles": {manager: [{"packageFile": package_file, "deps": deps}]}}


def test_parse_groups_by_branch_and_flags_majors():
    lines = report(
        [
            {
                "depName": "mysql",
                "datasource": "docker",
                "currentValue": "9.7.2",
                "replaceString": '"mysql:9.7.2"',
                "updates": [
                    {"newValue": "9.7.4", "branchName": "renovate/images"},
                    {
                        "newValue": "26.10.0",
                        "updateType": "major",
                        "branchName": "renovate/major-images",
                    },
                    {
                        "branchName": "renovate/lock-file-maintenance",
                        "updateType": "lockFileMaintenance",
                    },
                    {"newValue": "9.8.0", "branchName": "renovate/mysql-9.x"},
                ],
            }
        ]
    )
    updates = parse(lines)
    assert [(u.group, u.new, u.major) for u in updates] == [
        ("images", "9.7.4", False),
        ("images", "26.10.0", True),
        ("other", "9.8.0", False),
    ]


def test_select_skips_majors_unless_requested():
    minor = update(new="9.7.4")
    major = update(new="26.10.0", major=True)
    assert select([minor, major], ["images"], major=False) == [minor]
    assert select([minor, major], ["images"], major=True) == [major]
    assert select([minor], ["flake"], major=True) == []


def test_apply_image_changes_only_the_matching_reference():
    text = 'a = { image = "traefik:v3.7.5@' + OLD + '"; };\nb = "traefik:v3.7.5";\n'
    changed = apply(
        text,
        update(current_digest=OLD, new_digest=NEW, replace='image = "traefik:v3.7.5@' + OLD + '"'),
    )
    assert changed == 'a = { image = "traefik:v3.7.17@' + NEW + '"; };\nb = "traefik:v3.7.5";\n'


def test_apply_annotated_version_keeps_comment():
    replace = '# renovate: datasource=github-releases depName=x/v2.0.0\n    version = "2.0.0"'
    text = f"{{\n    {replace};\n}}\n"
    changed = apply(
        text, update(datasource="github-releases", current="2.0.0", new="2.1.0", replace=replace)
    )
    assert "depName=x/v2.0.0" in changed
    assert 'version = "2.1.0";' in changed


def test_apply_terraform_keeps_operator_and_other_providers():
    text = (
        'netbird = {\n  source  = "netbirdio/netbird"\n  version = "= 0.0.10"\n}\n'
        'other = {\n  source  = "acme/other"\n  version = "= 0.0.10"\n}\n'
    )
    changed = apply(
        text,
        update(manager="terraform", dep="netbird", current="= 0.0.10", new="0.0.11", replace=None),
    )
    assert 'version = "= 0.0.11"' in changed
    assert changed.count('"= 0.0.10"') == 1


def test_apply_terraform_finds_version_anywhere_in_its_block():
    text = (
        'other = {\n  source = "acme/other"\n  version = "= 0.0.10"\n}\n'
        'nb = {\n  version = "= 0.0.10" # pinned\n  source = "netbirdio/netbird"\n}\n'
    )
    changed = apply(
        text,
        update(manager="terraform", dep="nb", current="= 0.0.10", new="0.0.11", replace=None),
    )
    assert changed == text.replace('version = "= 0.0.10" # pinned', 'version = "= 0.0.11" # pinned')


def test_apply_rejects_files_changed_since_lookup():
    with pytest.raises(ValueError, match="changed since lookup"):
        apply('image = "traefik:v3.8.0"', update())


def test_apply_leaves_lockfile_updates_to_the_lock_tool():
    text = 'version = "~> 6.50"'
    assert apply(text, update(manager="terraform", lockfile=True, replace=None)) == text


def test_rewrite_writes_nothing_when_any_file_is_stale(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / "a.nix").write_text('image = "traefik:v3.7.5"')
    (tmp_path / "b.nix").write_text('image = "traefik:v3.8.0"')
    with pytest.raises(ValueError, match="b.nix"):
        rewrite([update(file="a.nix"), update(file="b.nix")])
    assert (tmp_path / "a.nix").read_text() == 'image = "traefik:v3.7.5"'


def test_inventory_lists_every_dependency_including_skipped_and_locked():
    lines = report(
        [
            {"depName": "aws", "currentValue": "~> 6.50", "lockedVersion": "6.52.0"},
            {"depName": "traefik", "currentValue": "v3.7.5", "currentDigest": OLD},
            {"depName": "transit", "currentValue": "latest", "skipReason": "invalid-value"},
            {"depName": "state", "skipReason": "local"},
        ]
    )
    assert inventory(lines) == [
        ("host.nix", "aws", "6.52.0"),
        ("host.nix", "traefik", "v3.7.5@aaaaaaaaaaaa"),
        ("host.nix", "transit", "latest (invalid-value)"),
    ]


def test_unwatched_reports_pins_no_custom_manager_matches():
    config = {
        "ignorePaths": ["legacy/**"],
        "customManagers": [
            {
                "managerFilePatterns": ["/\\.nix$/"],
                "matchStrings": [
                    'image = "(?<depName>[^"$:]+):(?<currentValue>[^"$]+)"',
                    '# renovate: \\S+\\n\\s*version = "(?<currentValue>[^"]+)"',
                ],
            }
        ],
    }
    files = {
        "ok.nix": 'image = "traefik:v3.7.5";\n# renovate: x\nversion = "1.0";\nfetchurl {}',
        "bad.nix": 'a = 1;\nimage = "app:${v}";\nlocal = { image = "docker-archive:/x"; };',
        "src.nix": 'version = "2.0";\nsrc = fetchFromGitHub {};',
        "plain.nix": 'version = "3.0";',
        "legacy/old.nix": 'image = "redis";',
        "test.py": 'IMAGE = "docker.io/library/redis"',
    }
    assert unwatched(config, files) == [
        'bad.nix:2: image = "app:${v}";',
        'src.nix:1: version = "2.0";',
        'test.py:1: IMAGE = "docker.io/library/redis"',
    ]
