import argparse
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--serial', required=True)
parser.add_argument('--payload-file', required=True)
args = parser.parse_args()

payload = Path(args.payload_file).read_text(encoding='utf-8')
proc = subprocess.run(
    ['adb','-s',args.serial,'shell','uinput','-'],
    input=payload.encode('utf-8'),
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
print(proc.stdout.decode('utf-8', errors='replace'), end='')
print(proc.stderr.decode('utf-8', errors='replace'), end='')
print(f'EXIT:{proc.returncode}')
