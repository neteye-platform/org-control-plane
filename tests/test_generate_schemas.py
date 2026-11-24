"""Tests of scripts/generate-schemas.py."""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location(
    "generate_schemas", ROOT / "scripts" / "generate-schemas.py"
)
generate_schemas = importlib.util.module_from_spec(SPEC)
sys.modules["generate_schemas"] = generate_schemas
SPEC.loader.exec_module(generate_schemas)

VARIABLES = """
variable "other" {
  type = string
}

variable "sample" {
  description = <<-EOT
    A heredoc with ( { [ characters that must not confuse the parser.
  EOT

  # A comment before the type is not a description.
  type = object({
    # The name.
    # On two lines.
    name = string
    count = optional(number, 3)
    enabled = optional(bool)
    anything = any
    tags = optional(set(string), ["a", "b"])
    labels = map(object({
      // A slash comment.
      color = string
    }))
    items = optional(list(object({ id = number, note = optional(string) })))
  })

  validation {
    condition     = length(var.sample.name) > 0 && !startswith(var.sample.name, "_")
    error_message = "Bad name."
  }
}
"""


class TypeParserTest(unittest.TestCase):
    def setUp(self):
        tmp = Path(tempfile.mkdtemp())
        (tmp / "modules" / "sample").mkdir(parents=True)
        (tmp / "modules" / "sample" / "variables.tf").write_text(
            VARIABLES, encoding="utf-8"
        )
        patcher = mock.patch.object(generate_schemas, "ROOT", tmp)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_variable_type(self):
        self.assertEqual(
            generate_schemas.variable_type("sample", "sample"),
            {
                "type": "object",
                "properties": {
                    "name": {
                        "description": "The name. On two lines.",
                        "type": "string",
                    },
                    "count": {"type": "number"},
                    "enabled": {"type": "boolean"},
                    "anything": {},
                    "tags": {
                        "type": "array",
                        "items": {"type": "string"},
                        "uniqueItems": True,
                    },
                    "labels": {
                        "type": "object",
                        "additionalProperties": {
                            "type": "object",
                            "properties": {
                                "color": {
                                    "description": "A slash comment.",
                                    "type": "string",
                                }
                            },
                            "additionalProperties": False,
                            "required": ["color"],
                        },
                    },
                    "items": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "properties": {
                                "id": {"type": "number"},
                                "note": {"type": "string"},
                            },
                            "additionalProperties": False,
                            "required": ["id"],
                        },
                    },
                },
                "additionalProperties": False,
                "required": ["name", "anything", "labels"],
            },
        )

    def test_primitive_variable(self):
        self.assertEqual(
            generate_schemas.variable_type("sample", "other"), {"type": "string"}
        )

    def test_missing_variable(self):
        with self.assertRaises(LookupError):
            generate_schemas.variable_type("sample", "missing")


class SchemasTest(unittest.TestCase):
    """The real schemas, built from the modules of this repository."""

    @classmethod
    def setUpClass(cls):
        cls.schemas = generate_schemas.build()

    def test_committed_schemas_are_up_to_date(self):
        for name, schema in self.schemas.items():
            committed = json.loads(
                (ROOT / "schemas" / name).read_text(encoding="utf-8")
            )
            self.assertEqual(
                committed,
                schema,
                f"schemas/{name} is out of date: run scripts/generate-schemas.py",
            )

    def test_repository_policy(self):
        repository = self.schemas["repository.schema.json"]
        self.assertEqual(repository["required"], ["name", "description", "topics"])
        self.assertEqual(repository["properties"]["topics"]["minItems"], 1)
        self.assertFalse(repository["additionalProperties"])

    def test_defaults_have_no_name_and_no_required_field(self):
        for name in (
            "repository-category-defaults.schema.json",
            "repository-org-defaults.schema.json",
        ):
            with self.subTest(schema=name):
                self.assertNotIn("name", self.schemas[name]["properties"])
                self.assertNotIn("required", self.schemas[name])

    def test_org_defaults_reject_the_fields_that_change_an_inherited_value(self):
        org = self.schemas["repository-org-defaults.schema.json"]["properties"]
        category = self.schemas["repository-category-defaults.schema.json"][
            "properties"
        ]
        for field in ("extra_team_access", "extra_user_access", "extra_labels"):
            self.assertIn(field, category)
            self.assertNotIn(field, org)

        org_rules = org["branch_rulesets"]["additionalProperties"]["properties"]
        self.assertNotIn(
            "include_override",
            org_rules["conditions"]["properties"]["ref_name"]["properties"],
        )
        self.assertNotIn(
            "required_check_override",
            org_rules["rules"]["properties"]["required_status_checks"]["properties"],
        )
        self.assertIn("extra_bypass_actors", org_rules)

    def test_descriptions_come_from_the_comments(self):
        properties = self.schemas["repository.schema.json"]["properties"]
        self.assertEqual(
            properties["description"]["description"],
            "Short description of the repository.",
        )
        self.assertEqual(
            self.schemas["team.schema.json"]["properties"]["privacy"]["description"],
            "Team privacy: secret or closed.",
        )


if __name__ == "__main__":
    unittest.main()
