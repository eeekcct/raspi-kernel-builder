#!/usr/bin/env python3
"""Check the final, dependency-resolved Linux configuration."""
import pathlib
import sys


def main():
    lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
    values = dict(line.split('=', 1) for line in lines if line.startswith('CONFIG_') and '=' in line)
    required = {
        'CONFIG_64BIT': 'y',
        'CONFIG_ARM64': 'y',
        'CONFIG_BPF_SYSCALL': 'y',
        'CONFIG_DEBUG_INFO_BTF': 'y',
        'CONFIG_ARM64_VA_BITS': '48',
        'CONFIG_ARM64_VA_BITS_48': 'y',
    }
    errors = [f'{key}: expected {value}, got {values.get(key, "unset")}'
              for key, value in required.items() if values.get(key) != value]
    if errors:
        print('\n'.join(errors), file=sys.stderr)
        return 1
    print('CONFIG_OK: ARM64, BPF syscall, BTF, 48-bit VA')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
