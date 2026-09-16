"""Exercise local UI dispatch without starting any app, VM, or build."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class VMDispatchTests(unittest.TestCase):
    def test_vm_success_and_failure_never_launch_host_ui(self):
        for result in (0, 77):
            with self.subTest(result=result), tempfile.TemporaryDirectory() as root:
                directory = Path(root)
                log = directory / "calls"
                for name in ("python3", "xcodegen", "xcodebuild"):
                    script = directory / name
                    script.write_text('#!/bin/bash\nprintf "%s %s\\n" "${0##*/}" "$*" >> "$DISPATCH_LOG"\n'
                                      'if [[ "$1" == tools/test-ui-vm.py ]]; then exit "$VM_RESULT"; fi\n'
                                      'if [[ "${0##*/}" == xcodebuild ]]; then exit 99; fi\nexit 0\n')
                    script.chmod(0o755)
                env = {**os.environ, "PATH": f"{directory}:/usr/bin:/bin", "DISPATCH_LOG": str(log), "VM_RESULT": str(result)}
                env.pop("VOLANT_HOST_UI_TESTS", None)
                completed = subprocess.run(["/bin/bash", "Scripts/test.sh", "--ui", "only"], env=env, capture_output=True, text=True)
                self.assertEqual(completed.returncode, result, completed.stderr)
                calls = log.read_text()
                self.assertIn("python3 tools/test-ui-vm.py", calls)
                self.assertNotIn("xcodebuild", calls)


unittest.main()
