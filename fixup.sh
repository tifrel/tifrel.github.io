#!/usr/bin/env bash

rm -rf ./public/*
hugo --minify || exit 1

git fixup
git push -f


(
  cd public || exit 1
  git fixup
  git push -f
) || exit 1
