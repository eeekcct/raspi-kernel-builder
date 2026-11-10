import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class ConfigTests(unittest.TestCase):
    def check_config(self, content):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / '.config'
            path.write_text(content)
            return subprocess.run(
                [sys.executable, str(ROOT / 'scripts/verify-config.py'), str(path)],
                capture_output=True, text=True,
            )

    def test_accepts_required_config(self):
        result = self.check_config(
            'CONFIG_64BIT=y\nCONFIG_ARM64=y\nCONFIG_BPF_SYSCALL=y\n'
            'CONFIG_DEBUG_INFO_BTF=y\nCONFIG_ARM64_VA_BITS=48\n'
            'CONFIG_ARM64_VA_BITS_48=y\n'
        )
        self.assertEqual(result.returncode, 0, result.stderr)


    def test_rejects_missing_btf(self):
        result = self.check_config('CONFIG_ARM64=y\nCONFIG_ARM64_VA_BITS=48\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('CONFIG_DEBUG_INFO_BTF', result.stderr)

    def test_rejects_39_bit_va(self):
        result = self.check_config(
            'CONFIG_64BIT=y\nCONFIG_ARM64=y\nCONFIG_BPF_SYSCALL=y\n'
            'CONFIG_DEBUG_INFO_BTF=y\nCONFIG_ARM64_VA_BITS=39\n'
            'CONFIG_ARM64_VA_BITS_39=y\n'
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('expected 48, got 39', result.stderr)

    def test_rejects_commented_out_btf(self):
        result = self.check_config('# CONFIG_DEBUG_INFO_BTF is not set\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('CONFIG_DEBUG_INFO_BTF', result.stderr)


if __name__ == '__main__':
    unittest.main()
