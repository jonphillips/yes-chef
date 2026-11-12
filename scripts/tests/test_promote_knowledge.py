import contextlib
import importlib.machinery
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "promote-knowledge"
loader = importlib.machinery.SourceFileLoader("promote_knowledge", str(SCRIPT))
module = loader.load_module()


class PromoteKnowledgeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.knowledge_path = self.root / "BuiltInKnowledge.json"
        self.icloud = self.root / "Knowledge"
        self.icloud.mkdir()
        self.original = {
            "version": 1,
            "aliases": {"old name": "old name"},
            "areas": {"lemon": "Produce", "banana": "Produce"},
            "trips": {},
            "keepers": [],
            "pantryStaples": [],
        }
        self.write_knowledge(self.original)

    def tearDown(self):
        self.temp.cleanup()

    def write_knowledge(self, data):
        self.knowledge_path.write_text(json.dumps(data))

    def export(self, name, date, *, fixes=None, areas=None, trips=None, variant="production"):
        path = self.icloud / name
        path.write_text(json.dumps({
            "exportedAt": date,
            "variant": variant,
            "nameFixes": fixes or [],
            "areas": areas or [],
            "trips": trips or [],
        }))
        return path

    def run_script(self, *paths, dry_run=False):
        argv = [str(SCRIPT)] + (["-n"] if dry_run else []) + [str(path) for path in paths]
        output = io.StringIO()
        with patch.object(module, "KNOWLEDGE", self.knowledge_path), patch.object(module, "ICLOUD", self.icloud), \
             patch("sys.argv", argv), contextlib.redirect_stdout(output):
            result = module.main()
        return result, output.getvalue()

    def test_add_skip_and_change(self):
        path = self.export("a.json", "2026-11-12T10:00:00Z", fixes=[
            {"from": "New Name", "to": "new name"},
            {"from": "old name", "to": "changed"},
        ], areas=[
            {"name": "lemon", "area": "Deli", "source": "user"},
            {"name": "banana", "area": "Produce", "source": "user"},
        ])
        result, output = self.run_script(path)
        self.assertEqual(result, 0)
        self.assertIn("Added: 1  Changed: 2  Conflicts: 2  Skipped: 1", output)
        data = json.loads(self.knowledge_path.read_text())
        self.assertEqual(data["aliases"]["new name"], "new name")
        self.assertNotIn("New Name", data["aliases"])
        self.assertEqual(data["aliases"]["old name"], "changed")
        self.assertEqual(data["areas"]["lemon"], "Deli")
        self.assertEqual(data["version"], 2)

    def test_newer_of_disagreeing_exports_wins(self):
        older = self.export("older.json", "2026-11-11T10:00:00Z", fixes=[{"from": "mint", "to": "herb"}])
        newer = self.export("newer.json", "2026-11-12T10:00:00Z", fixes=[{"from": "mint", "to": "mint"}])
        result, output = self.run_script(older, newer)
        self.assertEqual(result, 0)
        self.assertIn("Conflicts: 1", output)
        self.assertEqual(json.loads(self.knowledge_path.read_text())["aliases"]["mint"], "mint")

    def test_refuses_alias_chain(self):
        self.original["aliases"].update({"alias": "target", "target": "destination"})
        self.write_knowledge(self.original)
        path = self.export("chain.json", "2026-11-12T10:00:00Z", fixes=[{"from": "mint", "to": "alias"}])
        with self.assertRaises(ValueError):
            self.run_script(path)

    def test_refuses_chain_through_an_existing_alias(self):
        self.original["aliases"].update({"scallion": "green onions", "green onions": "green onions"})
        self.write_knowledge(self.original)
        path = self.export("chain.json", "2026-11-12T10:00:00Z", fixes=[{"from": "green onions", "to": "spring onions"}])
        before = self.knowledge_path.read_text()
        with self.assertRaises(ValueError):
            self.run_script(path)
        self.assertEqual(self.knowledge_path.read_text(), before)
        self.assertTrue(path.exists())

    def test_skips_dev_exports(self):
        dev = self.export("dev.json", "2026-11-12T10:00:00Z", fixes=[{"from": "mint", "to": "mint"}], variant="dev")
        result, output = self.run_script(dev)
        self.assertEqual(result, 0)
        self.assertIn("Skipped dev export: dev.json", output)
        self.assertNotIn("mint", json.loads(self.knowledge_path.read_text())["aliases"])
        self.assertTrue(dev.exists())

    def test_dry_run_changes_nothing(self):
        path = self.export("dry.json", "2026-11-12T10:00:00Z", fixes=[{"from": "mint", "to": "mint"}])
        before_knowledge = self.knowledge_path.read_text()
        before_export = path.read_text()
        result, _ = self.run_script(path, dry_run=True)
        self.assertEqual(result, 0)
        self.assertEqual(self.knowledge_path.read_text(), before_knowledge)
        self.assertEqual(path.read_text(), before_export)


if __name__ == "__main__":
    unittest.main()
