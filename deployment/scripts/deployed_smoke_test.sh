#!/usr/bin/env bash

set -euo pipefail

base_url="${1%/}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf -- "$tmp_dir"' EXIT

fail() {
  echo "Smoke test failed: $*" >&2
  exit 1
}

fetch() {
  local name="$1"
  local path="$2"
  shift 2
  curl --fail --silent --show-error --compressed \
    --retry 3 --retry-delay 2 --retry-all-errors \
    --proto '=https' --proto-redir '=https' \
    -D "$tmp_dir/$name.headers" -o "$tmp_dir/$name.body" \
    "$@" "$base_url$path"
}

assert_header() {
  local name="$1"
  local header="$2"
  local expected="$3"
  tr -d '\r' < "$tmp_dir/$name.headers" | \
    grep -Eqi "^${header}:.*${expected}" || \
    fail "$name did not return ${header} containing ${expected}"
}

assert_no_header() {
  local name="$1"
  local header="$2"
  if tr -d '\r' < "$tmp_dir/$name.headers" | grep -Eqi "^${header}:"; then
    fail "$name unexpectedly returned ${header}"
  fi
}

assert_eventual_cache_hit() {
  local name="$1"
  local path="$2"
  local attempt

  for attempt in {1..5}; do
    fetch "$name" "$path"
    if tr -d '\r' < "$tmp_dir/$name.headers" | grep -Eqi '^x-cache:.*Hit from cloudfront'; then
      return
    fi
    [ "$attempt" -eq 5 ] || sleep 1
  done

  fail "$name did not return x-cache containing Hit from cloudfront after 5 attempts"
}

echo "Checking main pages on $base_url"
for path in / /en/visits /en/days /en/about /en/blog /en/users/sign_in; do
  name="$(printf '%s' "$path" | tr '/?' '__')"
  fetch "page-$name" "$path"
done

echo "Checking anonymous calculator caching"
fetch visits-first /en/visits
assert_eventual_cache_hit visits-second /en/visits
assert_no_header visits-second set-cookie

fetch calendar-first /en/days
assert_eventual_cache_hit calendar-second /en/days
assert_no_header calendar-second set-cookie

echo "Checking calculator assets"
asset_paths="$(grep -oE '(src|href)="/assets/[^\"]+"' "$tmp_dir/visits-first.body" | cut -d '"' -f 2 | sort -u || true)"
[ -n "$asset_paths" ] || fail 'calculator HTML did not reference any local assets'
asset_index=0
while IFS= read -r asset_path; do
  asset_index=$((asset_index + 1))
  fetch "asset-$asset_index" "$asset_path"
  [ -s "$tmp_dir/asset-$asset_index.body" ] || fail "empty asset: $asset_path"
done <<< "$asset_paths"

echo "Checking API documentation caching"
fetch api-docs-first /api/docs
assert_eventual_cache_hit api-docs-second /api/docs
assert_no_header api-docs-second set-cookie

echo "Checking session traffic bypasses the shared cache"
fetch visits-session-first /en/visits -H 'Cookie: has_calculator_session=1'
fetch visits-session-second /en/visits -H 'Cookie: has_calculator_session=1'
assert_header visits-session-first x-cache 'Miss from cloudfront'
assert_no_header visits-session-first age
assert_header visits-session-second x-cache 'Miss from cloudfront'
assert_no_header visits-session-second age

echo "Checking private session endpoints"
session_status="$(curl --silent --show-error --compressed \
  --retry 3 --retry-delay 2 --retry-all-errors \
  --proto '=https' --proto-redir '=https' \
  -D "$tmp_dir/session-header.headers" -o "$tmp_dir/session-header.body" \
  -w '%{http_code}' "$base_url/en/session_header")"
[ "$session_status" = '204' ] || fail "session_header returned HTTP $session_status instead of 204"
assert_header session-header cache-control 'private.*no-store'

fetch csrf-token /en/csrf_token
assert_header csrf-token cache-control 'private.*no-store'
assert_header csrf-token set-cookie '_schengen_track_session='
jq -e '.param == "authenticity_token" and (.token | type == "string" and length > 0)' \
  "$tmp_dir/csrf-token.body" >/dev/null || fail 'csrf_token did not return a valid token'

echo "Checking login form and CSRF rejection"
curl --fail --silent --show-error --compressed \
  --retry 3 --retry-delay 2 --retry-all-errors \
  --proto '=https' --proto-redir '=https' \
  -c "$tmp_dir/login.cookies" -o "$tmp_dir/login-page.body" \
  "$base_url/en/users/sign_in"
login_token="$(grep -oE 'name="authenticity_token" value="[^"]+"' "$tmp_dir/login-page.body" | \
  tail -1 | sed -E 's/^.*value="([^"]+)"$/\1/')"
[ -n "$login_token" ] || fail 'login form did not contain an authenticity token'

login_status="$(curl --silent --show-error --compressed \
  --proto '=https' --proto-redir '=https' \
  -b "$tmp_dir/login.cookies" -c "$tmp_dir/login.cookies" \
  -D "$tmp_dir/login-submit.headers" -o "$tmp_dir/login-submit.body" \
  -w '%{http_code}' -X POST "$base_url/en/users/sign_in" \
  --data-urlencode "authenticity_token=$login_token" \
  --data-urlencode 'user[email]=deployed-smoke-account-that-does-not-exist@example.invalid' \
  --data-urlencode 'user[password]=invalid-smoke-password')"
[ "$login_status" = '422' ] || fail "invalid login returned HTTP $login_status instead of 422"
grep -Fqi 'Invalid email or password.' "$tmp_dir/login-submit.body" || \
  fail 'invalid login did not return the expected authentication error'
assert_no_header login-submit age

echo "Deployed smoke tests passed"
