"""Skeleton for CLI end-to-end tests: subprocess + temp-file fixtures.

Copy, then keep only the cases the brief asks for. Every path goes through a temp
file; never $HOME, cwd, or the default task file.
"""
import csv
import io
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent


class E2EBase(unittest.TestCase):
    def setUp(self):
        fd, self.path = tempfile.mkstemp(prefix="e2e-", suffix=".json")
        os.close(fd)
        os.unlink(self.path)  # absent file, not an empty one: loaders treat empty as corrupt
        self.addCleanup(lambda: os.path.exists(self.path) and os.unlink(self.path))

    def run_cli(self, *args):
        return subprocess.run(
            [sys.executable, "-m", "pkg", "--file", self.path, *args],
            cwd=ROOT, capture_output=True, text=True,
        )

    def write_file(self, raw):
        with open(self.path, "w", encoding="utf-8") as fh:
            fh.write(raw)

    def snapshot(self):
        return pathlib.Path(self.path).read_text(encoding="utf-8")


class TestNewCommands(E2EBase):
    def seed(self):
        self.run_cli("add", "buy milk", "--tag", "home")
        self.run_cli("add", "write report", "--tag", "work")

    def test_success_exact_text(self):
        self.seed()
        r = self.run_cli("list")
        self.assertEqual(r.returncode, 0, r.stderr)
        # assert the exact string INCLUDING the trailing newline print() adds
        self.assertEqual(r.stdout, "[ ] 1  buy milk  #home\n[ ] 2  write report  #work\n")

    def test_no_match_is_success(self):
        self.seed()
        r = self.run_cli("search", "zzz")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout, "")

    def test_json_shape(self):
        self.seed()
        data = json.loads(self.run_cli("search", "milk", "--json").stdout)
        self.assertEqual([t["title"] for t in data], ["buy milk"])

    def test_file_owned_export(self):
        self.run_cli("add", "a", "--tag", "x")
        out = os.path.join(os.path.dirname(self.path), "e2e-out.csv")
        self.addCleanup(lambda: os.path.exists(out) and os.unlink(out))
        r = self.run_cli("export", "--out", out)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout, "")  # file mode prints nothing
        with open(out, encoding="utf-8") as fh:
            self.assertEqual(list(csv.reader(fh))[0], ["id", "title", "done", "tags", "created_at"])

    def test_stdout_is_parseable_csv(self):
        self.seed()
        rows = list(csv.reader(io.StringIO(self.run_cli("export").stdout)))
        self.assertEqual(len(rows), 3)

    def test_read_only_commands_do_not_rewrite(self):
        self.seed()
        before = self.snapshot()
        for args in (("list",), ("search", "milk"), ("stats",)):
            self.run_cli(*args)
        self.assertEqual(self.snapshot(), before)

    def test_empty_task_list_exits_0(self):
        for args in (("list",), ("search", "x"), ("stats",), ("export",)):
            r = self.run_cli(*args)
            self.assertEqual(r.returncode, 0, (args, r.stderr))

    def test_file_flag_reads_only_the_given_file(self):
        other = os.path.join(os.path.dirname(self.path), "e2e-other.json")
        self.addCleanup(lambda: os.path.exists(other) and os.unlink(other))
        if os.path.exists(other):
            os.unlink(other)
        subprocess.run(
            [sys.executable, "-m", "pkg", "--file", other, "add", "other task", "--tag", "x"],
            cwd=ROOT, capture_output=True, text=True, check=True,
        )
        self.assertEqual(self.run_cli("list").stdout, "")  # self.path untouched
        r = subprocess.run(
            [sys.executable, "-m", "pkg", "--file", other, "list"],
            cwd=ROOT, capture_output=True, text=True, check=True,
        )
        self.assertIn("other task", r.stdout)

    def test_corrupt_file_exit_1(self):
        self.write_file("{not json")
        for args in (("list",), ("stats",)):
            r = self.run_cli(*args)
            self.assertEqual(r.returncode, 1, (args, r.stderr))
            self.assertTrue(r.stderr.strip())

    def test_bad_args_exit_2(self):
        self.assertEqual(self.run_cli("nope").returncode, 2)
        self.assertEqual(self.run_cli("stats", "--nope").returncode, 2)


if __name__ == "__main__":
    unittest.main()
