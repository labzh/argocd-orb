#!/bin/bash
set -xe

# reference: https://docs.github.com/en/developers/apps/building-github-apps/authenticating-with-github-apps#authenticating-as-a-github-app

b64enc() { openssl enc -base64 -A | tr '+/' '-_' | tr -d '='; }

ORGANISATION="$(echo "${ORGANISATION}" | circleci env subst)"

app_id=${GITHUB_APP_ID}
b64_app_private_key=${GITHUB_B64_APP_PRIVATE_KEY}
duration_seconds=${DURATION_SECONDS-600}

# issued at time, 60 seconds in the past to allow for clock drift
iat=$(($(date +%s) - 60))
exp="$((iat + duration_seconds))"

# create the JWT
signed_content="$(echo -n '{"alg":"RS256","typ":"JWT"}' | b64enc).$(echo -n "{\"iat\":${iat},\"exp\":${exp},\"iss\":${app_id}}" | b64enc)"
sig=$(echo -n "$signed_content" | openssl dgst -binary -sha256 -sign <(echo "${b64_app_private_key}" | base64 -d) | b64enc)
jwt=$(printf '%s.%s\n' "${signed_content}" "${sig}")

# get the access token

echo "Getting access token for $ORGANISATION"

res=$(curl -s \
  -H "Authorization: Bearer ${jwt}" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: $API_VERSION" \
  "https://api.github.com/orgs/$ORGANISATION/installation")

installation_id=$(echo "${res}" | jq -rM '.id')
if [[ $installation_id == "null" ]]; then
  echo "Error: installation_id is empty."
  echo "${res}"
  exit 1
fi

res=$(curl -s -X POST \
  -H "Authorization: Bearer $jwt" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: $API_VERSION" \
  "https://api.github.com/app/installations/$installation_id/access_tokens")

access_token=$(echo "${res}" | jq -rM '.token')
if [[ $access_token == "null" ]]; then
  echo "Error: access_token is empty"
  echo "${res}"
  exit 1
fi

echo "export GITHUB_APP_INSTALLATION_TOKEN=${access_token}" >> "$BASH_ENV"
