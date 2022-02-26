#!/usr/bin/env bash

commit_msg="$1"
if [[ -z "$commit_msg" ]]; then
  echo "Empty commit message, aborting" >&2
  exit 1
fi
if [[ ! -z "$2" ]]; then
  echo "Too many arguments" >&2
  exit 1
fi

rm -rf ./public/*
hugo --minify || exit 1

git add .
git commit -m "$commit_msg"
git push


(
  cd public || exit 1
  git add .
  git commit -m "$commit_msg"
  git push
) || exit 1
