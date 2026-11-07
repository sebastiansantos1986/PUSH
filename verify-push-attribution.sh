#!/bin/bash
# PUSH - Attribution integrity verification
# Developer: Sebastian Santos
# Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
set -eu
ROOT="${1:-.}"
if [ ! -d "$ROOT" ]; then
  echo "ERROR: Source directory not found: $ROOT" >&2
  exit 2
fi
found=0
failed=0
while IFS= read -r -d '' file; do
  found=$((found + 1))
  if grep -Fq 'Developer: Sebastian Santos' "$file" && grep -Fq 'Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS' "$file"; then
    printf '[PASS] %s\n' "$file"
  else
    printf '[FAIL] Attribution missing or modified: %s\n' "$file" >&2
    failed=$((failed + 1))
  fi
done < <(find "$ROOT" -type f -name '*.swift' -not -path '*/.build/*' -not -path '*/DerivedData/*' -print0)
printf 'Checked: %s | Failed: %s\n' "$found" "$failed"
if [ "$found" -eq 0 ]; then
  echo 'ERROR: No Swift files found.' >&2
  exit 2
fi
if [ "$failed" -ne 0 ]; then
  echo 'ERROR: PUSH developer attribution integrity check failed.' >&2
  exit 1
fi
echo 'PUSH developer attribution integrity check passed.'
