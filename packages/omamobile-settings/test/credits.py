#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""tools/gen-credits.py's list logic and the shipped app/credits.json (logins only)."""
import importlib.util, json, os, unittest
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.abspath(os.path.join(here, "..", "..", ".."))
spec = importlib.util.spec_from_file_location("gen_credits", os.path.join(root, "tools", "gen-credits.py"))
gen = importlib.util.module_from_spec(spec); spec.loader.exec_module(gen)


class Build(unittest.TestCase):
    def test_order_duplicates_and_bots(self):
        out = gen.build_credits(["derek", "ann-1", "Derek", "ci[bot]", "bob"])
        self.assertEqual(out, [{"login": "derek"}, {"login": "ann-1"}, {"login": "bob"}])

    def test_bad_login_fails(self):
        with self.assertRaises(ValueError):
            gen.build_credits(["bad login"])
        with self.assertRaises(ValueError):
            gen.build_credits(["a@b"])

    def test_no_name_matching_left(self):
        self.assertFalse(hasattr(gen, "parse_shortlog"))
        self.assertFalse(hasattr(gen, "valid_name"))


class Shipped(unittest.TestCase):
    def test_file(self):
        with open(os.path.join(root, "packages", "omamobile-settings", "app", "credits.json"), encoding="utf-8") as f:
            data = json.load(f)
        self.assertEqual(list(data), ["people"])
        self.assertGreater(len(data["people"]), 5)
        logins = [p["login"].lower() for p in data["people"]]
        self.assertEqual(len(logins), len(set(logins)))
        for p in data["people"]:
            self.assertEqual(set(p), {"login"})
            self.assertRegex(p["login"], r"^[A-Za-z0-9][A-Za-z0-9-]{0,38}$")


if __name__ == "__main__":
    unittest.main()
