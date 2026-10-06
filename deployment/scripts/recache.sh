# recache.sh
# Description: A script to fetch a list of URLs and print whether each fetch was successful or not.
# Used in github actions to re-cache main urls after deploy and cloudfront cache invalidation
# Usage:
#   ./recache.sh <list_file>
#
#   Parameters:
#     <list_file>: A text file containing a list of URLs, one per line.
#
# Example:
#   ./recache.sh urls-staging.txt
#
list_file="$1"

while IFS= read -r url; do
  [ -z "$url" ] && continue

  case "$url" in
    https://*) https_url="$url" ;;
    http://*) https_url="https://${url#http://}" ;;
    *) https_url="https://$url" ;;
  esac

  echo "Fetching: $https_url"
  if curl --fail --silent --show-error --location --compressed \
    --proto '=https' --proto-redir '=https' "$https_url" >/dev/null; then
    echo "Successfully fetched: $https_url"
  else
    echo "Failed to fetch: $https_url"
  fi
done < "$list_file"
