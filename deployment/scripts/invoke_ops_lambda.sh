#!/usr/bin/env bash
set -euo pipefail

payload="$1"
description="$2"
output_file="$3"

max_attempts="${OPS_INVOKE_MAX_ATTEMPTS:-8}"
attempt=1
status=0

if [ -z "${OPS_FUNCTION_NAME:-}" ]; then
  echo "OPS_FUNCTION_NAME is required" >&2
  exit 1
fi

echo "Invoking ${description} via ops Lambda..."
while true; do
  if aws lambda invoke \
    --function-name "$OPS_FUNCTION_NAME" \
    --payload "$payload" \
    --cli-binary-format raw-in-base64-out \
    --cli-connect-timeout 30 \
    --cli-read-timeout 900 \
    "$output_file" >/tmp/ops-invoke.log 2>/tmp/ops-invoke.err; then
    break
  else
    status=$?
  fi

  if grep -Eq 'TooManyRequestsException|ReservedFunctionConcurrentInvocationLimitExceeded' /tmp/ops-invoke.err && [ "$attempt" -lt "$max_attempts" ]; then
    attempt=$((attempt + 1))
    echo "Ops Lambda is already running; waiting 30s before retry ${attempt}/${max_attempts}"
    sleep 30
    continue
  fi

  cat /tmp/ops-invoke.err >&2
  exit "$status"
done

cat "$output_file"
jq -e '.body | fromjson | select(.success == true)' "$output_file" >/dev/null
echo "✓ ${description} completed"
