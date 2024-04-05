#!/bin/bash
set -xe

APP_NAME="$(echo "${APP_NAME}" | circleci env subst)"
BOOTSTRAP_APP_NAME="$(echo "${BOOTSTRAP_APP_NAME}" | circleci env subst)"
BOOTSTRAP_CHART_NAME="$(echo "${BOOTSTRAP_CHART_NAME}" | circleci env subst)"
BOOTSTRAP_VALUES_FILE="$(echo "${BOOTSTRAP_VALUES_FILE}" | circleci env subst)"
REPOSITORY="$(echo "${REPOSITORY}" | circleci env subst)"
ENVIRONMENT="$(echo "${ENVIRONMENT}" | circleci env subst)"
ORGANISATION="$(echo "${ORGANISATION}" | circleci env subst)"
IMAGE_TAG="$(echo "${IMAGE_TAG}" | circleci env subst)"
REGIONS="$(echo "${REGIONS}" | circleci env subst)"
REPOSITORY_PROTOCOL="$(echo "${REPOSITORY_PROTOCOL:-"https"}" | circleci env subst)"

IFS=" "

# Trust GitHub in order to avoid interactive prompt for adding it to secure hosts
mkdir -p ~/.ssh
cat > ~/.ssh/config <<- EOM
Host github.com
StrictHostKeyChecking no
HostName github.com
EOM

git config --global user.email "$GITHUB_APP_USER_ID+${GITHUB_APP_NAME}[bot]@users.noreply.github.com"
git config --global user.name "${GITHUB_APP_NAME}[bot]"

git clone "https://git:$GITHUB_APP_INSTALLATION_TOKEN@github.com/$ORGANISATION/$REPOSITORY.git"
cd "$REPOSITORY" || exit 1

git checkout "$DEFAULT_BRANCH"

values_file="$BOOTSTRAP_HELM_CHART_PATH/${BOOTSTRAP_CHART_NAME:-$BOOTSTRAP_APP_NAME}/$BOOTSTRAP_VALUES_FILE"

if ! yq -i "del(.services.$APP_NAME.regions)" "$values_file"; then
  exit 1
fi

read -r -a regions <<< "$REGIONS"
for region in "${regions[@]}"
do
  yq eval -i ".services.$APP_NAME.regions += [{\"name\": \"$region\"}]" "$values_file"
done

if [ "$HELM_REPOSITORY" = 1 ]; then
  yq eval -i ".services.$APP_NAME.source.path = \"$HELM_CHART_PATH\"" "$values_file"

  if [ "$REPOSITORY_PROTOCOL" = "https" ]; then
    yq eval -i ".services.$APP_NAME.source.repoURL = \"https://github.com/$CIRCLE_PROJECT_USERNAME/$CIRCLE_PROJECT_REPONAME\"" "$values_file"
  else
    yq eval -i ".services.$APP_NAME.source.repoURL = \"$CIRCLE_REPOSITORY_URL\"" "$values_file"
  fi

  yq eval -i ".services.$APP_NAME.source.targetRevision = \"$HELM_TARGET_REVISION\"" "$values_file"

  yq -i "del(.services.$APP_NAME.source.values_files)" "$values_file"
  read -r -a helm_values_files <<< "${HELM_VALUES_FILES:-""}"
  for helm_values_file in "${helm_values_files[@]}"
  do
    yq eval -i ".services.$APP_NAME.source.values_files += [\"$helm_values_file\"]" "$values_file"
  done
fi

yq eval -i ".services.$APP_NAME.parameters.image.tag = \"$IMAGE_TAG\"" "$values_file"

BRANCH="$APP_NAME-$IMAGE_TAG"

# Get the SHA of the latest commit on the base branch
BASE_SHA=$(curl -s \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: $GITHUB_API_VERSION" \
  -u "$GITHUB_APP_CLIENT_ID:$GITHUB_APP_INSTALLATION_TOKEN" \
  "https://api.github.com/repos/$ORGANISATION/$REPOSITORY/git/refs/heads/$DEFAULT_BRANCH" | jq -r '.object.sha')

# Create a new branch from the base SHA
curl -s -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: $GITHUB_API_VERSION" \
  -u "$GITHUB_APP_CLIENT_ID:$GITHUB_APP_INSTALLATION_TOKEN" \
  -d "{\"ref\": \"refs/heads/$BRANCH\", \"sha\": \"$BASE_SHA\"}" \
  "https://api.github.com/repos/$ORGANISATION/$REPOSITORY/git/refs"

# Get the SHA of the latest commit on the branch
LATEST_COMMIT=$(curl -s \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: $GITHUB_API_VERSION" \
  -u "$GITHUB_APP_CLIENT_ID:$GITHUB_APP_INSTALLATION_TOKEN" \
  "https://api.github.com/repos/$ORGANISATION/$REPOSITORY/git/ref/heads/$BRANCH" | jq -r '.object.sha')

# Get the tree associated with the latest commit
TREE_SHA=$(curl -s \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: $GITHUB_API_VERSION" \
  -u "$GITHUB_APP_CLIENT_ID:$GITHUB_APP_INSTALLATION_TOKEN" \
  "https://api.github.com/repos/$ORGANISATION/$REPOSITORY/git/commits/$LATEST_COMMIT" | jq -r '.tree.sha')

NEW_CONTENT=$(base64 -w 0 "$values_file")

# Create a new blob with the content of the file
BLOB_SHA=$(curl -s -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: $GITHUB_API_VERSION" \
  -u "$GITHUB_APP_CLIENT_ID:$GITHUB_APP_INSTALLATION_TOKEN" \
  -d "{\"content\": \"$NEW_CONTENT\", \"encoding\": \"base64\"}" \
  "https://api.github.com/repos/$ORGANISATION/$REPOSITORY/git/blobs" | jq -r '.sha')

# Create a new tree that points to the blob
NEW_TREE_SHA=$(curl -s -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: $GITHUB_API_VERSION" \
  -u "$GITHUB_APP_CLIENT_ID:$GITHUB_APP_INSTALLATION_TOKEN" \
  -d "{\"base_tree\":\"$TREE_SHA\",\"tree\":[{\"path\":\"$values_file\",\"mode\":\"100644\",\"type\":\"blob\",\"sha\":\"$BLOB_SHA\"}]}" \
  "https://api.github.com/repos/$ORGANISATION/$REPOSITORY/git/trees" | jq -r '.sha')

COMMIT_MESSAGE="LSCD deploying $APP_NAME:$IMAGE_TAG on $ENVIRONMENT"

# Create a new commit that points to the new tree
NEW_COMMIT_SHA=$(curl -s -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: $GITHUB_API_VERSION" \
  -u "$GITHUB_APP_CLIENT_ID:$GITHUB_APP_INSTALLATION_TOKEN" \
  -d "{\"message\":\"$COMMIT_MESSAGE\",\"tree\":\"$NEW_TREE_SHA\",\"parents\":[\"$LATEST_COMMIT\"]}" \
  "https://api.github.com/repos/$ORGANISATION/$REPOSITORY/git/commits" | jq -r '.sha')

# Update the branch to point to the new commit
curl -s -X PATCH \
  -d "{\"sha\":\"$NEW_COMMIT_SHA\"}" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: $GITHUB_API_VERSION" \
  -u "$GITHUB_APP_CLIENT_ID:$GITHUB_APP_INSTALLATION_TOKEN" \
  "https://api.github.com/repos/$ORGANISATION/$REPOSITORY/git/refs/heads/$BRANCH"

ORIGIN_REPOSITORY="https://github.com/$CIRCLE_PROJECT_USERNAME/$CIRCLE_PROJECT_REPONAME"

response=$(curl -s -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: $GITHUB_API_VERSION" \
  -u "$GITHUB_APP_CLIENT_ID:$GITHUB_APP_INSTALLATION_TOKEN" \
  -d '{
    "title": "LSCD: '"$APP_NAME $IMAGE_TAG"'",
    "body": "'"[CircleCI]($CIRCLE_BUILD_URL) is deploying [$APP_NAME]($ORIGIN_REPOSITORY) triggered by this [commit]($ORIGIN_REPOSITORY/commit/$CIRCLE_SHA1)"'",
    "head": "'"$BRANCH"'",
    "base": "'"$DEFAULT_BRANCH"'"
  }' "https://api.github.com/repos/$ORGANISATION/$REPOSITORY/pulls")

PR_NUMBER=$(echo "$response" | jq '.number')

if [ "$PR_NUMBER" = "null" ]; then
  echo "Error: Github PR creation failed"
  echo "$response"
  exit 1
fi

response=$(curl -s -X PUT \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: $GITHUB_API_VERSION" \
  -u "$GITHUB_APP_CLIENT_ID:$GITHUB_APP_INSTALLATION_TOKEN" \
  -d '{
    "merge_method": "merge"
  }' "https://api.github.com/repos/$ORGANISATION/$REPOSITORY/pulls/$PR_NUMBER/merge")

MERGED=$(echo "$response" | jq '.merged')

if [ "$MERGED" != "true" ]; then
  echo "Error: Github PR merge failed (https://github.com/$ORGANISATION/$REPOSITORY/pull/$PR_NUMBER)"
  echo "$response"
  exit 1
fi

echo "https://github.com/$ORGANISATION/$REPOSITORY/pull/$PR_NUMBER"
