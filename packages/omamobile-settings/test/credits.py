#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""tools/gen-credits.py's merge logic and the shipped app/credits.json."""
import importlib.util, json, os, re, sys, unittest
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.abspath(os.path.join(here, "..", "..", ".."))
spec = importlib.util.spec_from_file_location("gen_credits", os.path.join(root, "tools", "gen-credits.py"))
gen = importlib.util.module_from_spec(spec); spec.loader.exec_module(gen)


class Merge(unittest.TestCase):
    def test_merge(self):
        repo = gen.parse_shortlog("    5\tAnn Lee <ann@x.org>\n     2\tAnn L. <annlee@users.noreply.github.com>\n"
                                  "     1\tBob <12+bobby@users.noreply.github.com>\n     3\tAnn Lee <other@x.org>\n")
        out = gen.build_credits(repo, {"ann@x.org": "annlee"}, ["annlee", "carol", "ci[bot]"])
        self.assertEqual(out[0], {"name": "Ann Lee", "login": "annlee"})
        self.assertIn({"name": "Bob", "login": "bobby"}, out)
        self.assertIn({"name": "carol", "login": "carol"}, out)   # contributor with no commit here
        self.assertFalse([p for p in out if "bot" in p.get("login", "")])
        self.assertEqual(len(out), 3)
        self.assertNotIn("@x.org", json.dumps(out))


class Validation(unittest.TestCase):
    def test_at_name_uses_other_variant_or_login(self):
        rows = gen.parse_shortlog("5\tLefteris @Som <l@x.org>\n2\tLef <l@x.org>\n3\tBad <b@x.org>\n")
        out = gen.build_credits(rows, {"l@x.org": "lef1"}, ["lef1"])
        self.assertEqual(out[0], {"name": "Lef", "login": "lef1"})
        out = gen.build_credits(gen.parse_shortlog("4\tx@y <z@x.org>\n"), {"z@x.org": "zed"}, [])
        self.assertEqual(out, [{"name": "zed", "login": "zed"}])

    def test_unusable_entries_fail(self):
        with self.assertRaises(ValueError):
            gen.build_credits(gen.parse_shortlog("4\tx@y <z@x.org>\n"), {}, [])  # no valid name, no login
        with self.assertRaises(ValueError):
            gen.build_credits(gen.parse_shortlog("4\tOk <z@x.org>\n"), {"z@x.org": "bad_login"}, [])

    def test_same_name_two_logins_is_two_people(self):
        rows = gen.parse_shortlog("5\tSteve <a@x.org>\n3\tSteve <b@x.org>\n")
        notes = []
        out = gen.build_credits(rows, {"a@x.org": "steve1", "b@x.org": "steve2"}, [], note=notes.append)
        self.assertEqual(out, [{"name": "Steve", "login": "steve1"}, {"name": "Steve", "login": "steve2"}])
        self.assertTrue(notes)
        rows = gen.parse_shortlog("5\tSteve <a@x.org>\n3\tSteve <b@x.org>\n")
        out = gen.build_credits(rows, {"a@x.org": "steve1"}, [])  # one login: one person
        self.assertEqual(out, [{"name": "Steve", "login": "steve1"}])

    def test_first_name_only_is_not_a_merge(self):
        rows = gen.parse_shortlog("5\tVictor <a@x.org>\n4\tVictor Vogel <b@x.org>\n")
        self.assertEqual(len(gen.build_credits(rows, {}, [])), 2)


class Identity(unittest.TestCase):
    def test_two_logins_stay_apart_and_bot_email_dropped(self):
        rows = gen.parse_shortlog("9\tJo <a@x.org>\n2\tJo <b@x.org>\n7\tbuild <c@x.org>\n3\tJo <d@x.org>\n")
        out = gen.build_credits(rows, {"a@x.org": "zed", "b@x.org": "alpha", "c@x.org": "ci[bot]", "d@x.org": "zed"}, [])
        # two logins behind one name stay two entries; the bot's email is dropped
        self.assertEqual(out, [{"name": "Jo", "login": "zed"}, {"name": "Jo", "login": "alpha"}])

    def test_human_group_kept_when_one_email_is_a_bot(self):
        rows = gen.parse_shortlog("4\tJo <a@x.org>\n6\tJo <bot@x.org>\n")
        out = gen.build_credits(rows, {"bot@x.org": "x[bot]", "a@x.org": "jo1"}, [])
        self.assertEqual(out, [{"name": "Jo", "login": "jo1"}])

    def test_contributor_login_not_listed_twice(self):
        rows = gen.parse_shortlog("5\tJane Doe <jane@x.org>\n")
        notes = []
        out = gen.build_credits(rows, {}, ["janedoe"], note=notes.append)
        self.assertEqual(out, [{"name": "Jane Doe", "login": "janedoe"}])
        self.assertEqual(len(notes), 1)  # the guess is reported
        out = gen.build_credits(rows, {"jane@x.org": "janedoe"}, ["janedoe"])
        self.assertEqual(len(out), 1)
        out = gen.build_credits(rows, {}, ["someoneelse"])  # unrelated login stays separate
        self.assertEqual(len(out), 2)
        notes = []
        out = gen.build_credits(rows, {}, ["janedoe", "jane-doe"], note=notes.append)  # two candidates: no guess
        self.assertEqual(len(out), 3)
        self.assertEqual(len(notes), 1)


class Shipped(unittest.TestCase):
    def test_file(self):
        with open(os.path.join(root, "packages", "omamobile-settings", "app", "credits.json"), encoding="utf-8") as f:
            data = json.load(f)
        self.assertEqual(list(data), ["people"])
        self.assertGreater(len(data["people"]), 5)
        keys = [(p["name"].lower(), p.get("login", "").lower()) for p in data["people"]]
        self.assertEqual(len(keys), len(set(keys)))
        logins = [p["login"].lower() for p in data["people"] if "login" in p]
        self.assertEqual(len(logins), len(set(logins)))
        for p in data["people"]:
            self.assertLessEqual(set(p), {"name", "login"})
            self.assertTrue(p["name"].strip())
            self.assertTrue(gen.valid_name(p["name"]))
            self.assertNotIn("<", p["name"])
            if "login" in p:
                self.assertRegex(p["login"], r"^[A-Za-z0-9][A-Za-z0-9-]{0,38}$")


if __name__ == "__main__":
    unittest.main()
