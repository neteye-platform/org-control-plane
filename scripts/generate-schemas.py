#!/usr/bin/env python3
"""Generate the JSON Schemas of the YAML files from the module variable types.

The type of a module variable is the single source of truth for the shape of
the YAML files. This script parses the type expression (object, optional, list,
set, map and the primitive types) and writes one JSON Schema per kind of file
in schemas/. A comment line just before an object attribute becomes the
description of that attribute.

Run it from anywhere: `python3 scripts/generate-schemas.py`. A pre-commit hook
runs it and fails when a schema is out of date.
"""

from __future__ import annotations

import copy
import json
import re
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCHEMAS_DIR = ROOT / "schemas"
JSON_SCHEMA_DRAFT = "https://json-schema.org/draft/2020-12/schema"

TOKEN_RE = re.compile(
    r"""
    (?P<comment>(?:\#|//)[^\n]*)
  | (?P<space>\s+)
  | (?P<heredoc><<-?(?P<marker>\w+)\n.*?\n\s*(?P=marker)\b)
  | (?P<string>"(?:[^"\\]|\\.)*")
  | (?P<number>-?\d+(?:\.\d+)?)
  | (?P<ident>[A-Za-z_][A-Za-z0-9_-]*)
  | (?P<punct>[(){}\[\],=:])
  | (?P<other>\S)
    """,
    re.VERBOSE | re.DOTALL,
)

PRIMITIVES = {
    "string": {"type": "string"},
    "number": {"type": "number"},
    "bool": {"type": "boolean"},
    "any": {},
}


@dataclass
class Token:
    kind: str
    value: str
    line: int


def tokenize(text: str) -> list[Token]:
    tokens, pos, line = [], 0, 1
    while pos < len(text):
        match = TOKEN_RE.match(text, pos)
        if not match:
            raise SyntaxError(f"line {line}: unexpected character {text[pos]!r}")
        kind, value = match.lastgroup, match.group()
        if kind != "space":
            tokens.append(Token(kind, value, line))
        line += value.count("\n")
        pos = match.end()
    return tokens


class TypeParser:
    """Recursive descent parser for a Terraform type constraint."""

    def __init__(self, tokens: list[Token], pos: int):
        self.tokens, self.pos = tokens, pos

    def peek(self) -> Token:
        while self.tokens[self.pos].kind == "comment":
            self.pos += 1
        return self.tokens[self.pos]

    def expect(self, value: str) -> Token:
        token = self.peek()
        if token.value != value:
            raise SyntaxError(
                f"line {token.line}: expected {value!r}, got {token.value!r}"
            )
        self.pos += 1
        return token

    def comments_before(self) -> list[str]:
        """Return the comment lines just before the next token and skip them."""
        lines = []
        while self.tokens[self.pos].kind == "comment":
            lines.append(
                re.sub(r"^(?:#|//)\s?", "", self.tokens[self.pos].value).strip()
            )
            self.pos += 1
        return lines

    def skip_expression(self) -> None:
        """Skip a default value up to the closing parenthesis of `optional(...)`."""
        depth = 0
        while True:
            token = self.peek()
            if token.value in "([{":
                depth += 1
            elif token.value in ")]}":
                if depth == 0:
                    return
                depth -= 1
            self.pos += 1

    def parse(self) -> tuple[dict, bool]:
        """Parse one type. Return its schema and whether it is optional."""
        token = self.peek()
        if token.kind != "ident":
            raise SyntaxError(
                f"line {token.line}: expected a type, got {token.value!r}"
            )
        self.pos += 1
        name = token.value

        if name in PRIMITIVES:
            return dict(PRIMITIVES[name]), False

        self.expect("(")
        if name == "optional":
            schema, _ = self.parse()
            if self.peek().value == ",":
                self.pos += 1
                self.skip_expression()
            self.expect(")")
            return schema, True
        if name in ("list", "set"):
            items, _ = self.parse()
            self.expect(")")
            schema = {"type": "array", "items": items}
            if name == "set":
                schema["uniqueItems"] = True
            return schema, False
        if name == "map":
            values, _ = self.parse()
            self.expect(")")
            return {"type": "object", "additionalProperties": values}, False
        if name == "object":
            schema = self.parse_object()
            self.expect(")")
            return schema, False
        raise SyntaxError(f"line {token.line}: unsupported type {name!r}")

    def parse_object(self) -> dict:
        self.expect("{")
        properties, required = {}, []
        while True:
            description = self.comments_before()
            token = self.peek()
            if token.value == "}":
                self.pos += 1
                break
            if token.value == ",":
                self.pos += 1
                continue
            self.pos += 1
            self.expect("=")
            schema, optional = self.parse()
            if description:
                schema = {"description": " ".join(description), **schema}
            properties[token.value] = schema
            if not optional:
                required.append(token.value)
        schema = {
            "type": "object",
            "properties": properties,
            "additionalProperties": False,
        }
        if required:
            schema["required"] = required
        return schema


def variable_type(module: str, variable: str) -> dict:
    """Return the schema of the `type` of a variable declared in variables.tf."""
    tokens = tokenize(
        (ROOT / "modules" / module / "variables.tf").read_text(encoding="utf-8")
    )
    for i, token in enumerate(tokens):
        if token.value == "variable" and tokens[i + 1].value == f'"{variable}"':
            depth = 0
            for j in range(i + 2, len(tokens)):
                if tokens[j].value == "{":
                    depth += 1
                elif tokens[j].value == "}":
                    depth -= 1
                elif (
                    depth == 1
                    and tokens[j].value == "type"
                    and tokens[j + 1].value == "="
                ):
                    schema, _ = TypeParser(tokens, j + 2).parse()
                    return schema
    raise LookupError(
        f"variable {variable!r} with a type not found in module {module!r}"
    )


def element(schema: dict, depth: int) -> dict:
    """Return the value schema of a map nested `depth` times."""
    for _ in range(depth):
        schema = schema["additionalProperties"]
    return schema


def document(title: str, source: str, schema: dict) -> dict:
    return {
        "$schema": JSON_SCHEMA_DRAFT,
        "$comment": f"Generated by scripts/generate-schemas.py from {source}. Do not edit.",
        "title": title,
        **schema,
    }


def build() -> dict[str, dict]:
    repositories_source = "modules/github-repositories/variables.tf"
    repository = element(variable_type("github-repositories", "settings"), 2)

    # Category defaults hold any field except the repository name.
    category_defaults = copy.deepcopy(repository)
    del category_defaults["properties"]["name"]

    # The org defaults are the first tier: the fields that change an inherited
    # value have no effect there.
    org_defaults = copy.deepcopy(category_defaults)
    for field in ("extra_team_access", "extra_user_access", "extra_labels"):
        del org_defaults["properties"][field]
    ruleset = org_defaults["properties"]["branch_rulesets"]["additionalProperties"][
        "properties"
    ]
    del ruleset["conditions"]["properties"]["ref_name"]["properties"][
        "include_override"
    ]
    del ruleset["rules"]["properties"]["required_status_checks"]["properties"][
        "required_check_override"
    ]

    # Policy of this organization, not of the module: every repository file
    # names the repository, describes it and sets at least one topic.
    repository["required"] = ["name", "description", "topics"]
    repository["properties"]["topics"]["minItems"] = 1

    return {
        "repository.schema.json": document(
            "Repository", repositories_source, repository
        ),
        "repository-category-defaults.schema.json": document(
            "Repository category defaults", repositories_source, category_defaults
        ),
        "repository-org-defaults.schema.json": document(
            "Repository org defaults", repositories_source, org_defaults
        ),
        "team.schema.json": document(
            "Team",
            "modules/github-teams/variables.tf",
            element(variable_type("github-teams", "teams"), 1),
        ),
        "org-settings.schema.json": document(
            "Organization settings",
            "modules/github-org-settings/variables.tf",
            variable_type("github-org-settings", "settings"),
        ),
    }


def main() -> None:
    SCHEMAS_DIR.mkdir(exist_ok=True)
    for name, schema in build().items():
        path = SCHEMAS_DIR / name
        content = json.dumps(schema, indent=2, ensure_ascii=False) + "\n"
        if not path.exists() or path.read_text(encoding="utf-8") != content:
            path.write_text(content, encoding="utf-8")
            print(f"Updated {path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
