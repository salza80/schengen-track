#!/usr/bin/env bash
# recache.sh
# Generate and fetch public URLs for every catalogue locale.
# Used in github actions to re-cache main urls after deploy and cloudfront cache invalidation
# Usage:
#   ./recache.sh <list_file> [full|sample]
#
#   Parameters:
#     <list_file>: A text file containing the environment hostname.
#
# Example:
#   ./recache.sh urls-staging.txt sample
#
set -euo pipefail

list_file="$1"
profile="${2:-full}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
generated_list="$(mktemp)"
trap 'rm -f "$generated_list"' EXIT
node "$script_dir/recache_urls.cjs" "$list_file" "$profile" > "$generated_list"
echo "Warming $(wc -l < "$generated_list" | tr -d ' ') URLs (4 concurrent requests)"

fetch_url() {
  local https_url="$1"
  echo "Fetching: $https_url"
  if curl --fail --silent --show-error --location --compressed \
    --connect-timeout 10 --max-time 60 \
    --retry 3 --retry-delay 2 --retry-all-errors \
    --proto '=https' --proto-redir '=https' "$https_url" >/dev/null; then
    echo "Successfully fetched: $https_url"
  else
    echo "Failed to fetch: $https_url"
    return 1
  fi
}
export -f fetch_url

if ! tr '\n' '\0' < "$generated_list" | xargs -0 -n 1 -P 4 bash -c 'fetch_url "$1"' _; then
  echo "One or more URLs failed to recache"
  exit 1
fi
