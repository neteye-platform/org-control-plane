"""Tests of the pull request comment script in plan-core.yaml."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from workflow import step_script

TESTS = Path(__file__).resolve().parent
FIXTURES = TESTS / "fixtures"
APP = "steward"
UNIT = "repositories/ai"
MARKER = f"<!-- terragrunt-plan: {UNIT} -->"
SUMMARY = "<!-- terragrunt-plan-summary -->"
NO_CHANGES = {
    "call": "createComment",
    "issue_number": 7,
    "body": f"{SUMMARY}\n### Terragrunt plan\n\n✅ No changes in 1 unit.\n",
}


def comment(comment_id: int, body: str, login: str = f"{APP}[bot]") -> dict:
    return {"id": comment_id, "user": {"login": login, "type": "Bot"}, "body": body}


class PlanCommentTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if shutil.which("node") is None:
            raise RuntimeError("the tests of the workflow scripts need node")
        cls.tmp = Path(tempfile.mkdtemp())
        cls.script = cls.tmp / "script.js"
        cls.script.write_text(
            step_script("plan-core.yaml", "Update pull request comments", "script"),
            encoding="utf-8",
        )

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp)

    def run_script(
        self, *units, existing=(), without_text=(), no_units=False, secrets=("s3cr3t",)
    ) -> list:
        """Run the script for `units`, a list of (unit, plan) pairs.

        `plan` is the base path of `.json` and `.txt` files, or None for a
        failed plan. `secrets` are the SSM values, None without the file.
        """
        plans = Path(tempfile.mkdtemp(dir=self.tmp))
        secrets_file = plans / "secrets"
        if secrets is not None:
            secrets_file.write_text(
                "".join(f"{v}\n" for v in secrets), encoding="utf-8"
            )
        entries = []
        for unit, plan in units:
            directory = unit.replace("repositories/", "repositories/.terragrunt-stack/")
            entries.append({"unit": unit, "dir": directory})
            (plans / directory).mkdir(parents=True)
            if plan is not None:
                for suffix in (".json",) if unit in without_text else (".json", ".txt"):
                    shutil.copy(
                        Path(plan).with_suffix(suffix),
                        plans / directory / f"tfplan{suffix}",
                    )
        env = {
            **os.environ,
            "UNITS": "" if no_units else json.dumps(entries),
            "PLANS": str(plans),
            "SECRETS": str(secrets_file),
            "APP_SLUG": APP,
        }
        result = subprocess.run(
            [
                "node",
                TESTS / "github_script_harness.js",
                self.script,
                json.dumps(list(existing)),
            ],
            env=env,
            capture_output=True,
            text=True,
            check=True,
        )
        calls = json.loads(result.stdout)
        self.assertEqual([c["call"] for c in calls].count("listComments"), 1)
        return [c for c in calls if c["call"] != "listComments"]

    def run_unit(self, plan, existing=(), unit=UNIT, **kwargs) -> list:
        return self.run_script((unit, plan), existing=existing, **kwargs)

    def write_plan(self, name: str, plan: dict, text: str) -> Path:
        base = self.tmp / name
        base.with_suffix(".json").write_text(json.dumps(plan), encoding="utf-8")
        base.with_suffix(".txt").write_text(text, encoding="utf-8")
        return base.with_suffix("")

    def test_changes_create_one_comment(self):
        calls = self.run_unit(FIXTURES / "plan-changes")
        self.assertEqual([c["call"] for c in calls], ["createComment"])
        body = calls[0]["body"]
        self.assertTrue(
            body.startswith(f"{MARKER}\n### Terragrunt plan: `repositories/ai`")
        )
        self.assertIn("2 to add, 1 to change, 2 to destroy, 1 to move", body)

    def test_table_lists_destructive_actions_first(self):
        body = self.run_unit(FIXTURES / "plan-changes")[0]["body"]
        rows = [
            line for line in body.splitlines() if line.startswith("| ") and "`" in line
        ]
        self.assertEqual(
            rows,
            [
                "| 🗑️ destroy | `terraform_data.del` |",
                "| 🔁 replace | `terraform_data.rep` |",
                "| ➕ create | `terraform_data.new` |",
                "| ✏️ update | `terraform_data.upd` |",
                "| 🚚 move | `terraform_data.moved` |",
            ],
        )
        self.assertNotIn("terraform_data.keep", body)

    def test_diff_keeps_only_resource_changes(self):
        body = self.run_unit(FIXTURES / "plan-changes")[0]["body"]
        diff = body.split("```diff\n", 1)[1].split("\n```", 1)[0]
        self.assertTrue(diff.startswith("  # terraform_data.del will be destroyed"))
        self.assertIn('+   resource "terraform_data" "new" {', diff)
        self.assertIn('-   resource "terraform_data" "del" {', diff)
        self.assertIn('!   resource "terraform_data" "upd" {', diff)
        self.assertIn('! resource "terraform_data" "rep" {', diff)
        for noise in (
            "Plan:",
            "Changes to Outputs",
            "Terraform used the selected providers",
        ):
            self.assertNotIn(noise, diff)

    def test_hidden_lines_and_drift_are_removed(self):
        plan = {
            "resource_changes": [{"address": "a.b", "change": {"actions": ["update"]}}]
        }
        lines = [
            "Note: Objects have changed outside of Terraform",
            "",
            "  # a.drift has changed",
            '  ~ resource "a" "drift" {}',
            "",
            "Terraform will perform the following actions:",
            "",
            "  # a.b will be updated in-place",
            '  ~ resource "a" "b" {',
            '      ~ name = "x" -> "y"',
            "",
            "        # (3 unchanged attributes hidden)",
            "",
            "      ~ block {",
            '          + item = "z"',
            "",
            "            # (1 unchanged block hidden)",
            "        }",
            "    }",
            "",
            "Plan: 0 to add, 1 to change, 0 to destroy.",
        ]
        text = "\n".join(lines)
        body = self.run_unit(self.write_plan("hidden", plan, text))[0]["body"]
        diff = body.split("```diff\n", 1)[1].split("\n```", 1)[0]
        self.assertEqual(
            diff.splitlines(),
            [
                "  # a.b will be updated in-place",
                '!   resource "a" "b" {',
                '!       name = "x" -> "y"',
                "",
                "!       block {",
                '+           item = "z"',
                "        }",
                "    }",
            ],
        )

    def test_existing_comment_of_the_app_is_updated(self):
        existing = [
            comment(1, f"{MARKER}\nold"),
            comment(2, f"{MARKER}\nold", login="github-actions[bot]"),
        ]
        calls = self.run_unit(FIXTURES / "plan-changes", existing=existing)
        self.assertEqual(
            [(c["call"], c.get("comment_id")) for c in calls], [("updateComment", 1)]
        )

    def test_comments_of_other_units_and_users_are_ignored(self):
        existing = [
            comment(1, "<!-- terragrunt-plan: repositories/a -->\nold"),
            comment(2, f"{MARKER}\nold", login="someone-else[bot]"),
            comment(3, f"text before\n{MARKER}"),
        ]
        calls = self.run_script(
            (UNIT, FIXTURES / "plan-changes"),
            ("repositories/a", FIXTURES / "plan-changes"),
            existing=existing,
        )
        self.assertEqual(
            [(c["call"], c.get("comment_id")) for c in calls],
            [("createComment", None), ("updateComment", 1)],
        )
        self.assertTrue(calls[0]["body"].startswith(MARKER))

    def test_no_changes_delete_the_old_comment(self):
        calls = self.run_unit(
            FIXTURES / "plan-no-changes", existing=[comment(1, f"{MARKER}\nold")]
        )
        self.assertEqual(
            calls, [{"call": "deleteComment", "comment_id": 1}, NO_CHANGES]
        )

    def test_no_changes_create_one_summary_comment(self):
        self.assertEqual(self.run_unit(FIXTURES / "plan-no-changes"), [NO_CHANGES])

    def test_the_summary_comment_is_updated(self):
        calls = self.run_unit(
            FIXTURES / "plan-no-changes", existing=[comment(1, f"{SUMMARY}\nold")]
        )
        self.assertEqual(
            [(c["call"], c.get("comment_id")) for c in calls], [("updateComment", 1)]
        )
        self.assertIn("✅ No changes", calls[0]["body"])

    def test_changes_delete_the_summary_comment(self):
        calls = self.run_unit(
            FIXTURES / "plan-changes",
            existing=[
                comment(1, f"{SUMMARY}\nold"),
                comment(2, f"{SUMMARY}\nold", login="someone-else[bot]"),
            ],
        )
        self.assertEqual(
            [(c["call"], c.get("comment_id")) for c in calls],
            [("createComment", None), ("deleteComment", 1)],
        )

    def test_a_failed_plan_deletes_the_summary_comment(self):
        calls = self.run_unit(None, existing=[comment(1, f"{SUMMARY}\nold")])
        self.assertEqual(
            [(c["call"], c.get("comment_id")) for c in calls],
            [("createComment", None), ("deleteComment", 1)],
        )
        self.assertIn("❌ The plan failed", calls[0]["body"])

    def test_only_output_changes_count_as_no_changes(self):
        plan = {
            "resource_changes": [
                {"address": "a.b", "change": {"actions": ["no-op"]}},
                {"address": "data.a.c", "change": {"actions": ["read"]}},
            ],
            "output_changes": {"o": {"actions": ["create"]}},
        }
        self.assertEqual(
            self.run_unit(self.write_plan("outputs", plan, "")), [NO_CHANGES]
        )

    def test_missing_text_plan_counts_as_a_failure(self):
        calls = self.run_script((UNIT, FIXTURES / "plan-changes"), without_text=(UNIT,))
        self.assertEqual([c["call"] for c in calls], ["createComment"])
        self.assertIn("❌ The plan failed", calls[0]["body"])

    def test_without_units_every_comment_reports_a_failure(self):
        calls = self.run_script(
            existing=[
                comment(1, f"{MARKER}\nold"),
                comment(2, "<!-- terragrunt-plan: teams -->\nold"),
                comment(3, f"{MARKER}\nold", login="someone-else[bot]"),
            ],
            no_units=True,
        )
        self.assertEqual(
            [(c["call"], c["comment_id"]) for c in calls],
            [("updateComment", 1), ("updateComment", 2)],
        )
        self.assertTrue(calls[1]["body"].startswith("<!-- terragrunt-plan: teams -->"))
        for call in calls:
            self.assertIn("❌ The plan failed", call["body"])

    def test_without_units_the_summary_comment_reports_a_failure(self):
        calls = self.run_script(existing=[comment(1, f"{SUMMARY}\nold")], no_units=True)
        self.assertEqual(
            [(c["call"], c.get("comment_id")) for c in calls], [("updateComment", 1)]
        )
        self.assertIn("❌ The plan failed", calls[0]["body"])

    def test_without_units_and_comments_one_failure_is_reported(self):
        calls = self.run_script(no_units=True)
        self.assertEqual([c["call"] for c in calls], ["createComment"])
        self.assertTrue(calls[0]["body"].startswith(SUMMARY))
        self.assertIn("❌ The plan failed", calls[0]["body"])

    def test_comments_of_removed_units_are_deleted(self):
        calls = self.run_unit(
            FIXTURES / "plan-no-changes",
            existing=[
                comment(1, "<!-- terragrunt-plan: repositories/removed -->\nold"),
                comment(
                    2,
                    "<!-- terragrunt-plan: repositories/other -->\nold",
                    login="someone-else[bot]",
                ),
            ],
        )
        self.assertEqual(
            calls, [{"call": "deleteComment", "comment_id": 1}, NO_CHANGES]
        )

    def test_failed_plan_replaces_the_comment(self):
        calls = self.run_unit(None, existing=[comment(1, f"{MARKER}\nold")])
        self.assertEqual([c["call"] for c in calls], ["updateComment"])
        self.assertIn(
            "❌ The plan failed, see the [run](https://github.com/acme/control-plane/actions/runs/42).",
            calls[0]["body"],
        )

    def test_each_unit_has_its_own_comment(self):
        calls = self.run_script(
            ("org-settings", FIXTURES / "plan-changes"),
            ("teams", None),
            ("repositories/ai", FIXTURES / "plan-no-changes"),
            ("repositories/nep", FIXTURES / "plan-changes"),
            existing=[
                comment(1, f"{MARKER}\nold"),
                comment(2, "<!-- terragrunt-plan: repositories/nep -->\nold"),
            ],
        )
        self.assertEqual(
            [(c["call"], c.get("comment_id")) for c in calls],
            [
                ("createComment", None),
                ("createComment", None),
                ("deleteComment", 1),
                ("updateComment", 2),
            ],
        )
        self.assertIn("### Terragrunt plan: `org-settings`", calls[0]["body"])
        self.assertIn("2 to add", calls[0]["body"])
        self.assertTrue(calls[1]["body"].startswith("<!-- terragrunt-plan: teams -->"))
        self.assertIn("❌ The plan failed", calls[1]["body"])
        self.assertTrue(
            calls[3]["body"].startswith(
                "<!-- terragrunt-plan: repositories/nep -->\n### Terragrunt plan: `repositories/nep`"
            )
        )

    def test_import_forget_and_replace_actions(self):
        plan = {
            "resource_changes": [
                {
                    "address": "a.import",
                    "change": {"actions": ["no-op"], "importing": {"id": "x"}},
                },
                {"address": "a.forget", "change": {"actions": ["forget"]}},
                {"address": "a.replace", "change": {"actions": ["create", "delete"]}},
            ]
        }
        body = self.run_unit(self.write_plan("actions", plan, ""))[0]["body"]
        self.assertIn(
            "1 to add, 0 to change, 1 to destroy, 1 to import, 1 to remove from state",
            body,
        )
        self.assertIn("| 📤 remove from state | `a.forget` |", body)
        self.assertIn("| 📥 import | `a.import` |", body)

    def test_backticks_in_the_diff_do_not_close_the_code_block(self):
        plan = {
            "resource_changes": [{"address": "a.b", "change": {"actions": ["update"]}}]
        }
        lines = [
            "Terraform will perform the following actions:",
            "",
            "  # a.b will be updated in-place",
            '  ~ resource "a" "b" {',
            '      ~ description = "old" -> "use ```code``` and ````more````"',
            "    }",
            "",
            "Plan: 0 to add, 1 to change, 0 to destroy.",
        ]
        text = "\n".join(lines)
        body = self.run_unit(self.write_plan("fence", plan, text))[0]["body"]
        self.assertIn("\n`````diff\n", body)
        self.assertTrue(body.rstrip().endswith("`````\n\n</details>".rstrip()))

    def test_ssm_values_never_reach_a_comment(self):
        plan = {
            "resource_changes": [{"address": "a.b", "change": {"actions": ["update"]}}]
        }
        lines = [
            "  # a.b will be updated in-place",
            '  ~ resource "a" "b" {',
            '      ~ key   = "-----BEGIN KEY-----" -> "line-1"',
            '      ~ email = "billing@example.com"',
            "    }",
        ]
        base = self.write_plan("secrets", plan, "\n".join(lines))
        secrets = ("billing@example.com", "line-1", "-----BEGIN KEY-----")
        body = self.run_unit(base, secrets=secrets)[0]["body"]
        for secret in ("billing@example.com", "line-1", "BEGIN KEY"):
            self.assertNotIn(secret, body)
        self.assertIn('email = "***"', body)

    def test_without_the_ssm_values_no_plan_is_published(self):
        calls = self.run_script((UNIT, FIXTURES / "plan-changes"), secrets=None)
        self.assertEqual([c["call"] for c in calls], ["createComment"])
        self.assertIn("❌ The plan failed", calls[0]["body"])
        self.assertNotIn("terraform_data", calls[0]["body"])

    def test_an_empty_ssm_values_file_publishes_no_plan(self):
        calls = self.run_script((UNIT, FIXTURES / "plan-changes"), secrets=())
        self.assertEqual([c["call"] for c in calls], ["createComment"])
        self.assertIn("❌ The plan failed", calls[0]["body"])

    def test_truncated_diffs_are_redacted(self):
        secret = "x" * 50
        plan = {
            "resource_changes": [{"address": "a.b", "change": {"actions": ["update"]}}]
        }
        text = "Terraform will perform the following actions:\n\n" + (
            f'  ~ v = "{secret}"\n' * 6000
        )
        body = self.run_unit(self.write_plan("cut", plan, text), secrets=(secret,))[0][
            "body"
        ]
        self.assertIn("_The diff is truncated", body)
        self.assertNotIn("xxx", body)

    def test_pipes_in_addresses_do_not_break_the_table(self):
        plan = {
            "resource_changes": [
                {"address": 'a.b["x|y"]', "change": {"actions": ["create"]}}
            ]
        }
        body = self.run_unit(self.write_plan("pipe", plan, ""))[0]["body"]
        self.assertIn('| ➕ create | `a.b["x\\|y"]` |', body)

    def test_long_plans_are_truncated(self):
        changes = [
            {"address": f'a.b["{i:04}"]', "change": {"actions": ["update"]}}
            for i in range(250)
        ]
        text = "Terraform will perform the following actions:\n\n" + "".join(
            f'  # a.b["{i:04}"] will be updated in-place\n  ~ resource "a" "b" {{\n      ~ v = "1" -> "2"\n    }}\n\n'
            for i in range(4000)
        )
        body = self.run_unit(
            self.write_plan("long", {"resource_changes": changes}, text)
        )[0]["body"]
        self.assertLess(len(body), 65536)
        self.assertIn("| | _and 50 more_ |", body)
        self.assertIn('`a.b["0199"]`', body)
        self.assertNotIn('`a.b["0200"]`', body)
        self.assertIn(
            "_The diff is truncated, see the [full plan](https://github.com/acme/control-plane/actions/runs/42)._",
            body,
        )
        self.assertTrue(body.rstrip().endswith("</details>"))
        # The diff is cut at the end of a line.
        diff = body.split("```diff\n", 1)[1].split("\n```", 1)[0]
        self.assertRegex(
            diff.splitlines()[-1],
            r"^(  # a\.b\[\"\d{4}\"\] will be updated in-place|!   resource \"a\" \"b\" \{|!       v = \"1\" -> \"2\"|    \}|)$",
        )


if __name__ == "__main__":
    unittest.main()
