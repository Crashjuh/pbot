#!/usr/bin/env python3

import sys
import subprocess

url = 'https://based.lol/run.ty'

if len(sys.argv) <= 1:
    print('usage: ty` <code> [-stdin=<input>]')
    sys.exit(0)

cmd = ' '.join(sys.argv[1:]).replace('\\n', '\n')

[code, *input] = cmd.split('-stdin=')

print(
    subprocess.run([
        'curl', url,
        '--data-urlencode', f'code={code}',
        '--data-urlencode', f'input={"".join(input)}'
    ], text=True, capture_output=True).stdout.rstrip()
)
