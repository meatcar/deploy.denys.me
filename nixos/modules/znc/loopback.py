#!/usr/bin/env python3
"""Restrict the persisted ZNC backend listener before service startup."""

import os
from pathlib import Path
import stat
import sys
import tempfile


def migrate(data, port):
    lines = data.splitlines(keepends=True)
    stack, listeners = [], []
    fields = {}
    commented = False
    for index, line in enumerate(lines):
        # Match ZNC's line-oriented comments, not comment markers inside values.
        text = line.lstrip().rstrip(b"\r\n")
        if commented or text.startswith(b"/*"):
            commented = not text.endswith(b"*/")
            continue
        if not text or text.startswith((b"#", b"//")):
            continue
        if text.startswith(b"<") and text.endswith(b">"):
            tag, *name = text[1:-1].strip().split(None, 1)
            tag = tag.lower()
            if tag.startswith(b"/"):
                if name or not stack or stack.pop() != tag[1:]:
                    raise ValueError
                if not stack and tag == b"/listener":
                    listeners.append((index, fields))
            else:
                if not name or stack == [b"listener"]:
                    raise ValueError
                if not stack and tag == b"listener":
                    fields = {}
                stack.append(tag)
        elif stack == [b"listener"]:
            key, separator, value = text.partition(b"=")
            key = key.strip().lower()
            if not separator or key in fields:
                raise ValueError
            fields[key] = (index, value.strip())
    if stack or commented:
        raise ValueError
    targets = [
        (end, fields)
        for end, fields in listeners
        if b"port" in fields and int(fields[b"port"][1]) == port
    ]
    # Do not guess which listener to retain or silently delete mutable listeners.
    if len(targets) != 1:
        raise ValueError
    end, fields = targets[0]
    port_line = lines[fields[b"port"][0]]
    indent = port_line[: len(port_line) - len(port_line.lstrip())]
    newline = b"\r\n" if port_line.endswith(b"\r\n") else b"\n"
    for key, value in [
        (b"Host", b"127.0.0.1"),
        (b"IPv4", b"true"),
        (b"IPv6", b"false"),
    ]:
        if key.lower() in fields:
            index = fields[key.lower()][0]
            lines[index] = lines[index].partition(b"=")[0] + b"= " + value + newline
        else:
            lines[end] = indent + key + b" = " + value + newline + lines[end]
    return b"".join(lines)


def main():
    path = Path(sys.argv[1])
    if path.is_symlink():
        raise ValueError
    original = path.read_bytes()
    updated = migrate(original, int(sys.argv[2]))
    if updated == original:
        return
    metadata = path.stat()
    with tempfile.NamedTemporaryFile(
        dir=path.parent, prefix=".znc-loopback-", delete=False
    ) as output:
        temporary = Path(output.name)
        try:
            created = os.fstat(output.fileno())
            # ZNC's syscall sandbox forbids chown, including a redundant chown.
            if (created.st_uid, created.st_gid) != (metadata.st_uid, metadata.st_gid):
                raise ValueError
            os.fchmod(output.fileno(), stat.S_IMODE(metadata.st_mode))
            output.write(updated)
            output.flush()
            os.fsync(output.fileno())
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError):
        sys.exit("ZNC loopback migration refused the persisted configuration")
