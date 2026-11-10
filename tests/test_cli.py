import os
import pathlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class CliTests(unittest.TestCase):
    def test_rejects_unpinned_source_before_network_access(self):
        result = subprocess.run(
            ['bash', str(ROOT / 'scripts/build.sh')],
            env={**os.environ, 'KERNEL_COMMIT': 'rpi-6.12.y'},
            text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn('40-character', result.stderr)


    def test_help(self):
        result = subprocess.run(['bash', str(ROOT / 'scripts/build.sh'), '--help'],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('configure|build', result.stdout)

    def test_rejects_invalid_jobs(self):
        result = subprocess.run(['bash', str(ROOT / 'scripts/build.sh')],
                                env={**os.environ, 'JOBS': '0'},
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn('JOBS', result.stderr)

    def test_rejects_unknown_defconfig(self):
        result = subprocess.run(['bash', str(ROOT / 'scripts/build.sh')],
                                env={**os.environ, 'DEFCONFIG': '../../bad'},
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn('DEFCONFIG', result.stderr)

    def test_rejects_unknown_mode(self):
        result = subprocess.run(['bash', str(ROOT / 'scripts/build.sh'), 'install'],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn('Mode', result.stderr)


if __name__ == '__main__':
    unittest.main()
