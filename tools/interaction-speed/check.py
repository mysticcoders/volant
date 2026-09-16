"""Regression checks for telemetry classification and honest failure reporting."""
import pathlib, subprocess, tempfile, unittest

SCRIPT = pathlib.Path(__file__).with_name('summarize-summons.py')
class SummonSummaryTests(unittest.TestCase):
    def run_summary(self, text):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / 'log.txt'
            path.write_text(text)
            return subprocess.run(['python3', str(SCRIPT), str(path)], text=True, capture_output=True)
    def test_separates_sources_and_failed_readiness(self):
        result = self.run_summary('''prefix end] Summon: source=hotkey ready=1 elapsed_ms=2.0
prefix end] Summon: source=hotkey ready=1 elapsed_ms=4.0
prefix end] Summon: source=hotkey ready=0 elapsed_ms=999.0
prefix end] Summon: source=workspace ready=1 elapsed_ms=80.0
''')
        self.assertEqual(result.returncode, 0)
        self.assertIn('hotkey: ready=2, incomplete/cancelled=1', result.stdout)
        self.assertIn('median=3.000 ms, p95=4.000 ms', result.stdout)
        self.assertIn('workspace: ready=1', result.stdout)
    def test_empty_capture_is_not_a_pass(self):
        result = self.run_summary('unrelated log\n')
        self.assertIn('No completed summon events', result.stdout)
        self.assertIn('No ready hotkey samples', result.stdout)
    def test_nonfinite_duration_is_rejected(self):
        result = self.run_summary('end] Summon: source=hotkey ready=1 elapsed_ms=nan\n')
        self.assertNotEqual(result.returncode, 0)

unittest.main()
