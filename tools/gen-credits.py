#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Write packages/omamobile-settings/app/credits.json, the list the Settings
About page shows under Credits.

Sources, all facts and nothing typed by hand:
  - `git shortlog -sne` of omamobile (the repo this script is in), for
    names and commit counts;
  - GitHub's own commit list of derekross/omamobile, which says which
    GitHub login each commit email belongs to;
  - GitHub's contributors list of derekross/omamobile (logins), and of
    the family's other repositories (FAMILY_REPOS);
  - the authors of merged pull requests to derekross/linux-omamobile
    (logins). Its contributors list is not used: it counts upstream Linux
    authors.
Emails are used to match identities and are never written to the file.
Two guesses, both printed to stderr so a refresh can be checked: commit
names that are the same full name are one person only when at most one
GitHub login is behind them, and a name with no login of its own takes the
contributor login that spells the same letters ("Jane Doe" -> janedoe).

Refresh:  tools/gen-credits.py, in a clone whose origin is derekross/omamobile,
after a fetch; then commit app/credits.json. It needs git and an
authenticated `gh`.
"""
import argparse, json, os, re, subprocess, sys

NOREPLY = re.compile(r"^(?:\d+\+)?([^@]+)@users\.noreply\.github\.com$", re.I)
FAMILY_REPOS = ["derekross/omacam", "derekross/omamobile-installer", "derekross/omatel",
                "derekross/omaphone", "derekross/omamessages", "derekross/omamobile-website"]
KERNEL_PR_REPO = "derekross/linux-omamobile"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "packages", "omamobile-settings", "app", "credits.json")


def parse_shortlog(text):
    """'  12\tName <email>' lines -> [(count, name, email)]."""
    rows = []
    for line in text.splitlines():
        m = re.match(r"^\s*(\d+)\t(.*?)\s*<([^>]*)>\s*$", line)
        if m:
            rows.append((int(m.group(1)), m.group(2).strip(), m.group(3).strip().lower()))
    return rows


LOGIN_RE = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$")


def valid_name(name):
    """The app's own rule (Backend::parseCredits)."""
    name = name.strip()
    return bool(name) and len(name) <= 100 and "@" not in name and "<" not in name


def build_credits(repo_rows, email_login, contributor_logins, note=lambda msg: None):
    """repo_rows: [(count, name, email)]; email_login: {email: login} from
    GitHub's commit list; contributor_logins: [login]. Returns the people
    list, most omamobile commits first. Names come from omamobile only (the
    most used valid spelling; the login if none is valid). Raises ValueError
    when an entry would fail the app's validation. note() gets each guess."""
    parent = {}

    def find(x):
        parent.setdefault(x, x)
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a, b):
        parent[find(a)] = find(b)

    def login_of(email):
        if email in email_login:
            return email_login[email]
        m = NOREPLY.match(email)
        return m.group(1) if m else None

    def is_bot(login):
        return bool(login) and login.lower().endswith("[bot]")

    # A bot's email is dropped; the person's other emails stay.
    repo_rows = [r for r in repo_rows if not is_bot(login_of(r[2]))]
    contributor_logins = [l for l in contributor_logins if not is_bot(l)]

    def compact(text):
        return re.sub(r"[^a-z0-9]", "", text.lower())

    name_logins, noted = {}, set()
    for _, name, email in repo_rows:
        if login_of(email):
            name_logins.setdefault(name.lower(), set()).add(login_of(email).lower())
    for _, name, email in repo_rows:
        login = login_of(email)
        if login:
            union("e:" + email, "l:" + login.lower())
        # the same full name is the same person, unless two logins say otherwise
        if len(name_logins.get(name.lower(), ())) <= 1:
            union("e:" + email, "n:" + name.lower())
        elif name.lower() not in noted:
            noted.add(name.lower())
            note(f"{name!r} has {len(name_logins[name.lower()])} logins; not merged by name")
        # "Jane Doe" with no login of its own and the contributor "janedoe" are one person,
        # but only when exactly one contributor login spells those letters
        if name.lower() not in name_logins and len(compact(name)) > 3:
            same = [cl for cl in contributor_logins if compact(cl) == compact(name)]
            if len(same) == 1:
                if name.lower() not in noted:
                    noted.add(name.lower())
                    note(f"{name!r} -> {same[0]} (same letters, no email link)")
                union("e:" + email, "l:" + same[0].lower())
            elif same and name.lower() not in noted:
                noted.add(name.lower())
                note(f"{name!r} spells {', '.join(same)}; not guessed")
    for login in contributor_logins:
        find("l:" + login.lower())

    groups = {}

    def group(key):
        return groups.setdefault(find(key), {"names": {}, "logins": {}, "lcount": {}, "commits": 0})

    for count, name, email in repo_rows:
        g = group("e:" + email)
        g["names"][name] = g["names"].get(name, 0) + count
        g["commits"] += count
        login = login_of(email)
        if login:
            g["logins"][login.lower()] = login
            g["lcount"][login] = g["lcount"].get(login, 0) + count
    for login in contributor_logins:
        group("l:" + login.lower())["logins"][login.lower()] = login

    people = []
    for g in groups.values():
        logins = sorted(g["logins"].values(), key=lambda l: (-g["lcount"].get(l, 0), l.lower()))
        valid = [(n, c) for n, c in g["names"].items() if valid_name(n)]
        if valid:
            name = max(valid, key=lambda kv: (kv[1], kv[0]))[0].strip()
        elif logins:
            name = logins[0]
        else:
            raise ValueError("no usable name for " + repr(sorted(g["names"])))
        entry = {"name": name}
        if logins:
            entry["login"] = logins[0]
        if not valid_name(name) or ("login" in entry and not LOGIN_RE.match(entry["login"])):
            raise ValueError("invalid entry " + repr(entry))
        people.append((-g["commits"], name.lower(), entry))
    out = [e for _, _, e in sorted(people, key=lambda t: (t[0], t[1]))]
    keys = [(e["name"].lower(), e.get("login", "").lower()) for e in out]
    if len(set(keys)) != len(keys):
        raise ValueError("duplicate person")
    logins = [e["login"].lower() for e in out if "login" in e]
    if len(set(logins)) != len(logins):
        raise ValueError("one login under two names")
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
    ap.add_argument("--ref", default="origin/main")
    ap.add_argument("--out", default=OUT)
    args = ap.parse_args()
    top = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    # names come from this clone and logins from GitHub: both must be the same repository
    remote = args.ref.split("/", 1)[0]
    url = run("git", "remote", "get-url", remote, cwd=top).strip().lower()
    if not re.search(r"[/:]" + re.escape(args.repo.lower()) + r"(?:\.git)?/?$", url) and \
            not re.search(r"[/:]derekross/omarchy-mobile(?:\.git)?/?$", url):
        sys.exit(f"credits: {remote} is {url}, not {args.repo}; use a clone of {args.repo} (or --ref)")
    repo_rows = parse_shortlog(run("git", "shortlog", "-sne", args.ref, cwd=top))
    email_login = {}
    for line in run("gh", "api", f"repos/{args.repo}/commits", "--paginate", "-q",
                    '.[] | select(.author.login != null) | [.commit.author.email, .author.login, .author.type] | @tsv').splitlines():
        email, login, kind = (line.split("\t") + ["", "", ""])[:3]
        if email and login:
            # a Bot account (apps too) without the [bot] suffix: marked so build_credits drops its email
            email_login[email.lower()] = login + "[bot]" if kind == "Bot" and not login.lower().endswith("[bot]") else login
    logins = []
    for repo in FAMILY_REPOS:  # a fork's contributors are its upstream's people
        if run("gh", "api", f"repos/{repo}", "-q", ".fork").strip() != "false":
            sys.exit(f"credits: {repo} is a fork or unreadable; check FAMILY_REPOS")
    for repo in [args.repo] + FAMILY_REPOS:
        logins += run("gh", "api", f"repos/{repo}/contributors", "--paginate", "-q", ".[] | select(.type == \"User\") | .login").split()
    logins += run("gh", "api", f"repos/{KERNEL_PR_REPO}/pulls?state=closed&per_page=100", "--paginate", "-q",
                  ".[] | select(.merged_at != null and .user.type == \"User\") | .user.login").split()
    seen = set()
    logins = [l for l in logins if not (l.lower() in seen or seen.add(l.lower()))]
    try:
        people = build_credits(repo_rows, email_login, logins, note=lambda m: print("credits: guess: " + m, file=sys.stderr))
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
