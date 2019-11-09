#!/bin/bash

set -o errexit
set -o nounset

# Set up .netrc file with GitHub credentials
git_setup ( ) {
  cat <<- EOF > $HOME/.netrc
        machine github.com
        login $GITHUB_ACTOR
        password $GITHUB_TOKEN
        machine api.github.com
        login $GITHUB_ACTOR
        password $GITHUB_TOKEN
EOF

  chmod 600 $HOME/.netrc

  git config --global user.name 'Ponylang Main Bot'
  git config --global user.email 'ponylang.main@gmail.com'
}

# Gather expected arguments.
if [ $# -lt 1 ]
then
  echo "Tag is required"
  exit 1
fi

TAG=$1
# changes tag from "release-1.0.0" to "1.0.0"
VERSION="${TAG/refs\/tags\/release-/}"

git_setup

git checkout master

# update VERSION
echo "${VERSION}" > VERSION
echo "VERSION set to ${VERSION}"

# version the changelog
changelog-tool release "${VERSION}" -e

# commit CHANGELOG and VERSION updates
git add CHANGELOG.md VERSION
git commit -m "${VERSION} release"

# tag release
git tag "${VERSION}"

# push to release branch
git push origin master
git push origin "${VERSION}"

# release body
echo "Preparing to update GitHub release notes..."

body=$(changelog-tool get "$VERSION")

jsontemplate="
{
  \"tag_name\":\$version,
  \"name\":\$version,
  \"body\":\$body
}
"

json=$(jq -n \
--arg version "$VERSION" \
--arg body "$body" \
"${jsontemplate}")

echo "Uploading release notes..."

result=$(curl -X POST "https://api.github.com/repos/${GITHUB_REPOSITORY}/releases" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -u "${GITHUB_ACTOR}:${GITHUB_TOKEN}" \
  --data "${json}")

rslt_scan=$(echo "${result}" | jq -r '.id')
if [ "$rslt_scan" != null ]
then
  echo "Release notes uploaded"
else
  echo "Unable to upload release notes, here's the curl output..."
  echo "${result}"
  exit 1
fi

# delete release-VERSION tag
git push --delete origin "release-${VERSION}"
