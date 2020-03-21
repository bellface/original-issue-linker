#!/usr/bin/env bash

set -eu

# base64 command decoding option is not compatible between BusyBox and BSD
# Try both options
base64_decode() {
  base64 -d 2>/dev/null || base64 -D 2>/dev/null
}

# Build JSON payload via jq and printf
format_strings_in_json() {
  local format="$1"; shift
  local args=()

  for param in "$@"; do
    args=("${args[@]+"${args[@]}"}" "$(printf %s "$param" | jq -aRs .)")
  done

  # shellcheck disable=SC2059
  printf "$format" "${args[@]+"${args[@]}"}"
}

# Validate that repository name has the format: "vendor/package"
validate_repository() {
  local repository="$1"
  local role="$2"

  if [[ ! "$repository" =~ ^[A-Za-z0-9_-]+/[A-Za-z0-9_-]+$ ]]; then
    >&2 echo "The repository you passed as $role has not a valid name."
    exit 1
  fi
}

# Create an issue on GitHub
create_issue() {
  local repository="$1"
  local title="$2"
  local body="$3"

  >&2 echo '-----------------'
  >&2 echo ''
  >&2 echo "Creating issue on $repository..."
  >&2 echo ''
  >&2 echo '<Title>'
  >&2 echo "$title"
  >&2 echo ''
  >&2 echo '<Body>'
  >&2 echo "$body"
  >&2 echo ''
  >&2 echo '-----------------'
  >&2 echo ''

  if ! curl --fail "$BASE_URI/repos/$repository/issues" \
    -H 'Content-Type: application/json' \
    -H "Authorization: token $GITHUB_TOKEN" \
    -d "$(format_strings_in_json \
      '{"title":%s,"body":%s,"labels":[%s]}' \
      "$title" "$body" "$ISSUE_LABEL" \
    )"; then
    exit 1
  fi

  >&2 echo ''
}

# Close an issue on GitHub
close_issue() {
  local repository="$1"
  local number="$2"

  >&2 echo '-----------------'
  >&2 echo ''
  >&2 echo "Closing issue #$number on $repository..."
  >&2 echo ''
  >&2 echo '-----------------'
  >&2 echo ''

  if ! curl --fail "$BASE_URI/repos/$repository/issues/$number" \
    -H 'Content-Type: application/json' \
    -H "Authorization: token $GITHUB_TOKEN" \
    -d '{"state":"closed"}'; then
    exit 1
  fi

  >&2 echo ''
}

# Fetch issues on GitHub
fetch_issues() {
  local repository="$1"
  local page="$2"

  >&2 echo '-----------------'
  >&2 echo ''
  >&2 echo "Fetching issues of $repository (page $page)..."
  >&2 echo ''
  >&2 echo '-----------------'
  >&2 echo ''

  if ! curl --fail "$BASE_URI/repos/$repository/issues?page=$page&per_page=100&filter=all&state=all&direction=asc" \
    -H "Authorization: token $GITHUB_TOKEN"; then
    exit 1
  fi

  >&2 echo ''
}

# Configuration which can be passed as environmental variables
BASE_URI=${BASE_URI:-https://api.github.com}
GITHUB_TOKEN=${GITHUB_TOKEN:-}
START_PAGE=${START_PAGE:-1}
TITLE_FORMAT=${TITLE_FORMAT:-[OLD] %s}
REFERENCE_FORMAT=${REFERENCE_FORMAT:-This is a reference to %s.}
ISSUE_LABEL=${ISSUE_LABEL:-Old Issue Reference}

# Validate command compatibilites
required_commands=(curl jq)
for command in "${required_commands[@]}"; do
  if ! type "$command" >/dev/null 2>&1; then
    >&2 echo '"'"$command"'"'" command is not installed."
    exit 1
  fi
done

# Validate that GITHUB_TOKEN is iet
if [[ -z "$GITHUB_TOKEN" ]]; then
  >&2 echo 'The environment variable "GITHUB_TOKEN" is not set.'
  exit 1
fi

# Validate that START_PAGE is numeric and positive
if [[ ! "$START_PAGE" =~ ^[1-9][0-9]*$ ]]; then
  >&2 echo 'The environment variable "START_PAGE" must be a positive integer.'
  exit 1
fi

# Validate that TITLE_FORMAT contains one placeholder
if [[ $(awk -F'%s' '{print NF-1}' <<< "$TITLE_FORMAT") -ne 1 ]]; then
  >&2 echo 'The environment variable "TITLE_FORMAT" must contain one placeholder "%s".'
  exit 1
fi

# Validate that REFERENCE_FORMAT contains one placeholder
if [[ $(awk -F'%s' '{print NF-1}' <<< "$REFERENCE_FORMAT") -ne 1 ]]; then
  >&2 echo 'The environment variable "REFERENCE_FORMAT" must contain one placeholder "%s".'
  exit 1
fi

# Validate source repository
source="$1"
validate_repository "$source" 'source repository'

shift

# Iterate over all pages
for (( page = START_PAGE; ; page++ )); do

  # Fetch source repository issues on current page
  source_issues=()
  for issue in $(fetch_issues "$source" "$page" | jq -r '.[] | @base64'); do
    source_issues=("${source_issues[@]+"${source_issues[@]}"}" "$issue")
  done
  source_issues_count=${#source_issues[@]}

  # Break if there are no more source issues
  if [[ "$source_issues_count" -eq 0 ]]; then
    break
  fi

  >&2 echo "[Source] issues in $source (page $page): $source_issues_count"
  >&2 echo ''

  # Iterate over all destination repositories
  for destination in "$@"; do

    # Validate destination repository
    validate_repository "$destination" 'destination repository'

    # Fetch destination repository issues on current page
    destination_issues_count=$(fetch_issues "$destination" "$page" | jq -r '. | length')

    >&2 echo "[Destination] issues in $destination (page $page): $destination_issues_count"
    >&2 echo ''

    # Iterate over all destination repositoriy issues to be linked
    for (( i = destination_issues_count; i < source_issues_count; i++ )); do
      title="$(echo "${source_issues[$i]}" | base64_decode | jq -r '.title')"
      body="$(echo "${source_issues[$i]}" | base64_decode | jq -r '.body' )"

      quotation="$(printf %s "$body" | perl -pe 's/^/> /g')"
      # shellcheck disable=SC2059
      reference="$(printf "$REFERENCE_FORMAT" "$source#$(( (i + 1) + 100 * (page - 1) ))")"

      # shellcheck disable=SC2059
      new_title="$(printf "$TITLE_FORMAT" "$title")"
      new_body="$(printf "%s\n%s" "$reference" "$quotation")"

      # Create issue and immediately close it
      new_number=$(create_issue "$destination" "$new_title" "$new_body" | jq -r '.number')
      >&2 close_issue "$destination" "$new_number"
    done
  done
done
