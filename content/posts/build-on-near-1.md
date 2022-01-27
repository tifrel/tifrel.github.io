---
title: "Build on NEAR: Our first smart contract (part 1)"
date: 2022-01-20T00:00:00+00:00
# weight: 1
# aliases: ["/first"]
tags: ["Build on NEAR", "Rust", "NEAR protocol", Smart contracts]
draft: true
# editPost:
#   URL: "https://github.com/<path_to_repo>/content"
#   Text: "Suggest Changes" # edit text
#   appendFilePath: true # to append file path to Edit link
---

<!--
  TODO:
  - [] init
  - [] set up empty struct and compilation to wasm
  - [] unit tests for TDD
  - [] deploy to mainnet (at tifrel.testnet)
  - [] remove from mainnet and redeploy to coffee.tifrel.testnet
-->

In the last post

<!-- TODO: relative link? to last post -->
<!-- FIXME: did we actually do this? did we do more or less? -->

The actual contract will be a simple "Buy me a coffee" contract, so basically a
donation of the networks native token (the NEAR token) to a

Picking up our average Rust dev, with start with a new library project:

```sh
cargo init --lib
```
