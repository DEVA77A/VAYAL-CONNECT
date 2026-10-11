"""Copy changed versioned backend files after verifying the destination baseline.
No deletions, secrets, environments, or unrelated files are copied.
"""
import argparse
from pathlib import Path
import subprocess


def git(repo, *args):
    return subprocess.check_output(["git", "-C", str(repo), *args])


def normalized(data):
    return data.replace(b"\r\n", b"\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", type=Path, required=True)
    parser.add_argument("--base", required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[1]
    repo = source.parent
    target = args.target.resolve()
    if target == source or source in target.parents or not (target / "app").is_dir():
        raise SystemExit("Target must be the existing separate backend source folder.")
    changed = git(repo, "diff", "--name-only", args.base, "--", "vayalconnect-backend").decode().splitlines()
    new = git(repo, "ls-files", "--others", "--exclude-standard", "--", "vayalconnect-backend").decode().splitlines()
    planned = []
    conflicts = []
    for item in sorted(set(changed + new)):
        relative = Path(item).relative_to("vayalconnect-backend")
        if relative.parts[0] not in ("app", "tests", "scripts", "docs") or relative.name.startswith(".env"):
            raise SystemExit("Unexpected path; aborting sync.")
        src, dest = source / relative, target / relative
        if not src.is_file():
            raise SystemExit("Deleted paths are not synced.")
        if target not in dest.resolve().parents:
            raise SystemExit("Target path escaped the backend directory.")
        if dest.exists():
            current = normalized(dest.read_bytes())
            if current == normalized(src.read_bytes()):
                continue
            baseline = subprocess.run(["git", "-C", str(repo), "show", args.base + ":" + item], capture_output=True)
            if baseline.returncode or current != normalized(baseline.stdout):
                conflicts.append(str(relative))
                continue
        planned.append((src, dest))
    if conflicts:
        raise SystemExit("Destination changes preserved; sync aborted: " + ", ".join(conflicts))
    for src, dest in planned:
        print(str(src.relative_to(source)))
    if args.apply:
        for src, dest in planned:
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(src.read_bytes())
    print(("Synced " if args.apply else "Would sync ") + str(len(planned)) + " backend files.")


if __name__ == "__main__":
    main()
