#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Write packages/omamobile-settings/app/credits.json, the list the Settings
About page shows under Credits: GitHub logins only, no names, no emails.

Sources, all public on GitHub and nothing typed by hand:
  - GitHub's contributors list of derekross/omamobile (most commits first),
    then of the family's other repositories (FAMILY_REPOS);
  - the authors of merged pull requests to derekross/linux-omamobile. Its
    contributors list is not used: it counts upstream Linux authors.
Bots are left out. Nothing joins a login to a commit name.

Refresh:  tools/gen-credits.py, then commit app/credits.json. It needs an
authenticated `gh`.
"""
import argparse, json, os, re, subprocess, sys

FAMILY_REPOS = ["derekross/omacam", "derekross/omamobile-installer", "derekross/omatel",
                "derekross/omaphone", "derekross/omamessages", "derekross/omamobile-website"]
KERNEL_PR_REPO = "derekross/linux-omamobile"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "packages", "omamobile-settings", "app", "credits.json")
LOGIN_RE = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$")


def build_credits(logins):
    """logins in source order -> [{"login": l}], first spelling kept, case-insensitive
    duplicates and bots dropped. Raises ValueError on a login the app would refuse."""
    out, seen = [], set()
    for login in logins:
        if login.lower().endswith("[bot]") or login.lower() in seen:
            continue
        if not LOGIN_RE.match(login):
            raise ValueError("invalid login " + repr(login))
        seen.add(login.lower())
        out.append({"login": login})
    return out


def run(*cmd, cwd=None):
    try:
        return subprocess.run(cmd, cwd=cwd, check=True, capture_output=True, text=True).stdout
    except FileNotFoundError:
        sys.exit(f"credits: {cmd[0]} is not installed")
    except subprocess.CalledProcessError as e:
        sys.exit(f"credits: {' '.join(cmd[:3])} failed: {(e.stderr or '').strip()[:300]}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--repo", default="derekross/omamobile")
    ap.add_argument("--out", default=OUT)
    args = ap.parse_args()
    for repo in FAMILY_REPOS:  # a fork's contributors are its upstream's people
        if run("gh", "api", f"repos/{repo}", "-q", ".fork").strip() != "false":
            sys.exit(f"credits: {repo} is a fork or unreadable; check FAMILY_REPOS")
    logins = []
    for repo in [args.repo] + FAMILY_REPOS:
        logins += run("gh", "api", f"repos/{repo}/contributors", "--paginate", "-q", ".[] | select(.type == \"User\") | .login").split()
    logins += run("gh", "api", f"repos/{KERNEL_PR_REPO}/pulls?state=closed&per_page=100", "--paginate", "-q",
                  ".[] | select(.merged_at != null and .user.type == \"User\") | .user.login").split()
    try:
        people = build_credits(logins)
    except ValueError as e:
        sys.exit("credits: " + str(e))
    if not people:
        sys.exit("no people found; not writing " + args.out)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump({"people": people}, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print(f"{len(people)} people -> {args.out}")


if __name__ == "__main__":
    main()
