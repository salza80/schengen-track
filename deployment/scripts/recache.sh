# fetch_urls.sh
# Description: A script to fetch a list of URLs and print whether each fetch was successful or not.
# Used in github actions to re-cache main urls after deploy and cloudfront cache invalidation
# Usage:
#   ./fetch_urls.sh <list_file>
#
#   Parameters:
#     <list_file>: A text file containing a list of URLs, one per line.
#
# Example:
#   ./fetch_urls.sh urls-staging.txt
#
list_file="$1"

while IFS= read -r url; do
  echo "Fetching: $url"
  if curl -sSf "$url" >/dev/null; then
    echo "Successfully fetched: $url"
  else
    echo "Failed to fetch: $url"
  fi
done < "$list_file"
