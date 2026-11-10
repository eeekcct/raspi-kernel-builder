"""Exercise release-name resolution with a minimal stale Kbuild-cache fixture.

This is not a compilation test: real CI separately compiles the kernel.
"""
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class ReleaseTests(unittest.TestCase):
    def test_refreshes_generated_release_before_naming_package(self):
        text = (ROOT / 'scripts/build.sh').read_text()
        snippet = text[text.index('km olddefconfig\n'):text.index('DEST="$OUTPUT_DIR/')]
        with tempfile.TemporaryDirectory() as directory:
            obj = pathlib.Path(directory)
            (obj / 'include/config').mkdir(parents=True)
            (obj / 'include/config/kernel.release').write_text('6.12.116-v8+\n')
            (obj / '.config').write_text(
                'CONFIG_64BIT=y\nCONFIG_ARM64=y\nCONFIG_BPF_SYSCALL=y\n'
                'CONFIG_DEBUG_INFO_BTF=y\nCONFIG_ARM64_VA_BITS=48\n'
                'CONFIG_ARM64_VA_BITS_48=y\n'
            )
            # olddefconfig leaves generated Kbuild files stale; prepare refreshes them.
            harness = r'''
set -euo pipefail
OBJ=$1
HERE=$2
SRC=$3
km() {
  case "$1" in
    olddefconfig) : ;;
    prepare) printf '%s\n' '6.12.116-v8-btf48-test+' > "$OBJ/include/config/kernel.release" ;;
    *) echo "Unexpected make target: $1" >&2; return 1 ;;
  esac
}
make() { cat "$OBJ/include/config/kernel.release"; }
fail() { echo "$*" >&2; exit 2; }
'''
            result = subprocess.run(
                ['bash', '-c', harness + snippet + '\nprintf "RESULT=%s\\n" "$RELEASE"\n',
                 'release-test', str(obj), str(ROOT / 'scripts'), str(obj)],
                text=True, capture_output=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('RESULT=6.12.116-v8-btf48-test+', result.stdout)


if __name__ == '__main__':
    unittest.main()
