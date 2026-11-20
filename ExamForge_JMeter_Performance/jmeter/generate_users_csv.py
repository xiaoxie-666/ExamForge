#!/usr/bin/env python3
"""Generate unique ExamForge load-test accounts. The CSV intentionally has no header."""
import argparse
import csv
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--count', type=int, default=1000)
parser.add_argument('--start', type=int, default=1001)
parser.add_argument('--exam-id', type=int, default=1)
parser.add_argument('--password', default=os.getenv('LOADTEST_USER_PASSWORD'))
parser.add_argument('--output', default=str(ROOT / 'users.csv'))
args = parser.parse_args()
if not args.password:
    parser.error('Set LOADTEST_USER_PASSWORD or pass --password.')
if args.count < 1 or args.start < 1001 or args.start + args.count - 1 > 2000:
    parser.error('count/start must select accounts within loadtest1001..loadtest2000')
if args.exam_id < 1:
    parser.error('--exam-id must be a positive integer')
out = Path(args.output).expanduser().resolve()
out.parent.mkdir(parents=True, exist_ok=True)
with out.open('w', newline='', encoding='utf-8') as f:
    writer = csv.writer(f, lineterminator='\n')
    for i in range(args.start, args.start + args.count):
        writer.writerow([f'loadtest{i:04d}', args.password, args.exam_id])
print(f'Generated {args.count} unique accounts for exam {args.exam_id}: {out}')
