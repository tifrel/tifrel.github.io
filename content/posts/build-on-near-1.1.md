---
title: "Build on NEAR: Our first smart contract (part 1.1)"
date: 2022-01-30T00:00:00+00:00
# weight: 1
# aliases: ["/first"]
tags: ["Build on NEAR", "Rust", "NEAR protocol", Smart contracts]
draft: false
# editPost:
#   URL: "https://github.com/<path_to_repo>/content"
#   Text: "Suggest Changes" # edit text
#   appendFilePath: true # to append file path to Edit link
---

In the [kick-off post](../build-on-near-0), we explored NEAR accounts and the
CLI as prerequisites for deploying smart contracts on top of the NEAR protocol.
This posts goes over the facets of writing smart contracts in general and
conclude with the foundations for the remainder of the series.

The actual contract will be a simple "Buy me a coffee" contract, so basically a
donation of NEAR to an account that the contract has been deployed with.
Additionally, we will keep track of donations.

## A plain rust struct, compiled to WebAssembly

Picking up our average Rust dev, with start with a new library project:

```sh
cargo init --lib
```

First of all let's have a struct that holds some state and define a method that
changes the state and returns some value. This is our `src/lib.rs` including
logic and some tests:

<!-- src/lib.rs -->

```rs
#[derive(Default)]
pub struct Contract {
  last_number: u32,
}

impl Contract {
  pub fn execute(&mut self, x: u32) -> u32 {
    let r = self.last_number + x;
    self.last_number = x;
    r
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn contract_works() {
    let mut contract = Contract::default();
    assert_eq!(contract.execute(4), 4);
    assert_eq!(contract.execute(2), 6);
  }
}
```

Don't worry about the usefulness, we will replace this soon with something more
elaborate, but we need to acquainted with the requirements and specifics for
deploying that code on NEAR. In Rustland, your smart contract is nothing more
than some data, you could also call it storage or state, and some associated
logic within `impl` blocks.

The most obvious part is compilation to WebAssembly. If you haven't done so
already, you should install the WebAssembly compilation target for Rust:

```sh
rustup target add wasm32-unknown-unknown
```

By default, `cargo` will build for the machine architecture you're compiling on.
However, we want to target WebAssembly, and will use this `.cargo/config.toml`:

<!-- .cargo/config.toml -->

```toml
[alias]
emit = "build --release --target wasm32-unknown-unknown"

[target.wasm32-unknown-unknown]
rustflags = ["-C", "link-arg=-s"]

[profile.release]
codegen-units = 1      # generate a single blob of machine/Wasm instructions
opt-level = "z"        # optimize for code size
lto = true             # compile at link time
debug = false          # no debug symbols/checks
panic = "abort"        # usually unwind, but that's extra overhead
overflow-checks = true # enable safety checks for arithmetic operations
```

Although not necessary lecture, let's go over these adjustments in a bit more
detail:

- `alias.emit`: Eases compilation, as we either have test builds, run via
  `cargo test`, or release builds to Wasm, which are now handily available using
  `cargo emit`.
- `target.wasm32-unknown-unknown.rustflags`: Additional flags passed to `rustc`
  when compiling to Wasm. We instruct `rustc` to pass the `-s` flag on to the
  linker, which means the linker should optimize for code size over performance.
  Some flag-passing inception going on.
- `profile.release`: Modify the optimization options for the release build
  - `codegen-units = 1`: We want a single unit/blob of machine code from our
    crate, which is then linked against the dependency crates.
  - `opt-level = "z"`: Aggressively optimize for code size. Disables loop
    vectorization.
  - `lto`: **l**ink-**t**ime-**o**ptimizations
  - `debug`: include debug information/checks (e.g. arithmetic overflows)
  - `panic = "abort"`: Rust usually unwinds the call stack on a panic. Unwinding
    the stack is extra logic that requires extra space. Instead, we simply drop
    everything we're doing an return.
  - `overflow-checks`: Check for arithmetic overflows. This does cost extra
    computation and space, but prevents vulnerabilities. Image you issued a
    burnable token, someone burns more than he has and voíla, that someone now
    has more tokens than all other token holders combined.

As you can see, anything is optimized aggressively for storage. You will find
this a recurring theme, as on-chain storage is a scarce resource, and thus
protected by an economic incentive called
[storage staking](https://docs.near.org/docs/concepts/storage-staking). Your
contract always needs some immovable NEAR attached to "rent" (indirectly, by
lowering total supply) the storage it uses on the chain. If you decide to reduce
your contracts storage requirements or to take it offline, you can recover these
funds, giving you an incentive not to occupy chain-storage lightheadedly.

As we seperated all our "What kind of machine code do we want?" options into
`.cargo/config.toml`, our `Cargo.toml` can stay clean:

<!-- Cargo.toml -->

```toml
[package]
name = "near-buy-me-a-coffee"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
near-sdk = "3.1.0"
```

Again, let's look at the relevant sections:

- `lib.crate-type = "cdylib"`: That's just a
  [general requirement for WebAssembly](https://stackoverflow.com/questions/56227766/why-must-a-wasm-library-in-rust-set-the-crate-type-to-cdylib)
  and it being naturally loaded on-demand.
- `dependencies.near-sdk`: All we will need to do all things NEAR, e.g.
  transactions, cross-contract calls, or blockchain-specific testing

Once you've got this set up, you issue a `cargo emit`. You will find your Wasm
blob at `target/wasm32-unknown-unknown/release/near_buy_me_a_coffee.wasm`.
Looking at it with an editor should give you a bunch of funny symbols. It's some
kind of machine code after all, so if it's not human-readable, that's a good
sign.

Find the
[code on github](https://github.com/tifrel/build-on-near/tree/3625f1cc7bfc2c6935f4f7e3d2d0eaa3ccc81ebc)

## Adding NEAR

Now, let's turn this struct into a smart contract. Again, we take a look at our
`src/lib.rs`, and then talk about the changes we applied:

<!-- src/lib.rs -->

```rs
// these traits allow us to convert the struct into the borsh binary format,
// which is used by NEAR and thus required for smart contracts on the protocol
use near_sdk::borsh::{self, BorshDeserialize, BorshSerialize};
// this macro wraps our with everything necessary to deploy it to the chain.
use near_sdk::near_bindgen;

#[near_bindgen]
#[derive(Default, BorshDeserialize, BorshSerialize)]
pub struct Contract {
  last_number: u32,
}

#[near_bindgen]
impl Contract {
  pub fn execute(&mut self, x: u32) -> u32 {
    let r = self.last_number + x;
    self.last_number = x;
    r
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  // needed for creating the blockchain context, see macro definition below
  use near_sdk::test_utils::VMContextBuilder;
  use near_sdk::{testing_env, MockedBlockchain};
  use std::convert::TryInto;

  // part of writing unit tests is setting up a mock context
  macro_rules! init_context {
    ($account:expr) => {
      // first convert the `&str` to a `near_sdk::json_types::ValidAccountId`
      let account = $account.to_string().try_into().unwrap();

      // build the `near_sdk::VMContext`
      let context = VMContextBuilder::new()
        .predecessor_account_id(account)
        .build();

      // this actually initializes the context
      testing_env!(context);
    };
  }

  #[test]
  fn contract_works() {
    // initialize the testing context
    init_context!("tifrel.testnet");

    // the actual test stays as it was in the plain-rust case
    let mut contract = Contract::default();
    assert_eq!(contract.execute(4), 4);
    assert_eq!(contract.execute(2), 6);
  }
}
```

- [Borsh](https://borsh.io/) is a binary serialization format that allows to
  translate between something easily comprehensible, e.g. a `struct`, an `enum`,
  or a plain `i32` and something that's efficient to store and transmit, aka
  some raw bytes. We need it, because that's how we store data on the NEAR
  blockchain.
- `near_sdk::near_bindgen` automagically wraps your contract and equips it with
  all it needs to a) compile to Wasm and b) interact with other parts of the
  NEAR protocol, e.g. other smart contracts or NEAR acconts. All parts of your
  smart contract (`struct { ... }`, `impl` blocks) need to be wrapped.

If all you wanted to do is deploying some logic on-chain, that's already all you
need. But we want to deploy something high-quality. We want to make use of
practices like TDD, so we take the time to understand testing for the
blockchain-world as well: Before contract method calls, we need to initialize a
context.
[The context](https://docs.rs/near-sdk/latest/near_sdk/struct.VMContext.html)
holds information like the calling account of a contracts methods, NEAR tokens
attached to the call, or block information. A context will be used for all
subsequent function calls, until it is set again.

Find the
[code on github](https://github.com/tifrel/build-on-near/tree/d35994ccfc5a5ebf2afbe147d4a71ec0448c9a65)

## Writing tests for our actual contract

Now that we've gained an understanding of how to write smart contracts on NEAR,
let's start by writing the test for our actual "Buy Me A Coffee Contract":

```rs
#[cfg(test)]
mod tests {
  use super::*;
  use near_sdk::test_utils::VMContextBuilder;
  use near_sdk::{testing_env, MockedBlockchain};
  use std::convert::TryInto;

  // Handy if you don't wish to deal with yoctoNEAR all the time
  const ONE_NEAR: near_sdk::Balance = 1_000_000_000_000_000_000_000_000;

  macro_rules! init_context {
    ($account:expr) => {
      let account = $account.to_string().try_into().unwrap();

      let context = VMContextBuilder::new()
        .predecessor_account_id(account)
        .build();

      testing_env!(context);
    };

    // Another macro pattern, as we now need to send some NEAR with our contract
    // calls
    ($account:expr, $deposit:expr) => {
      let account = $account.to_string().try_into().unwrap();

      let context = VMContextBuilder::new()
        .predecessor_account_id(account)
        .attached_deposit($deposit)
        .build();

      testing_env!(context);
    };
  }

  #[test]
  fn contract_works() {
    init_context!("tifrel.testnet");

    let mut contract = BuyMeACoffee::initialize("tifrel.testnet".into());
    assert_eq!(contract.top_coffee_buyer(), None);

    // our next contract call will be by "lovely-person.testnet", with one NEAR
    // attached to the call
    init_context!("lovely-person.testnet", 1 * ONE_NEAR);
    contract.buy_coffee();
    // We can see the donation if we query the contract by `AccountId`
    assert_eq!(
      contract.coffee_near_from("lovely-person.testnet".into()),
      1 * ONE_NEAR
    );
    // Since it's the first donation, it has taken the leaderboard
    assert_eq!(
      contract.top_coffee_buyer(),
      Some(("lovely-person.testnet".into(), 1 * ONE_NEAR))
    );

    // Let's do it again
    init_context!("another-lovely-person.testnet", 2 * ONE_NEAR);
    contract.buy_coffee();
    assert_eq!(
      contract.coffee_near_from("another-lovely-person.testnet".into()),
      2 * ONE_NEAR
    );
    assert_eq!(
      contract.top_coffee_buyer(),
      Some(("another-lovely-person.testnet".into(), 2 * ONE_NEAR))
    );
  }
}
```

This test ensures that

1. The contract initializes
2. NEAR accounts can send NEAR tokens to it
3. We can query the contract for specific accounts and get their total NEAR
   donation
4. The account that donated the most can be queried. Think of it as a
   single-slot hall of fame.

What's the best part? Now we can issue `cargo test`, and actually verify that
what we're building is doing what we want it to. Remember that `cargo run` on a
library doesn't do anything, and `cargo build` is shaky ground when you want to
attach (potentially valuable) digital assets to whatever you're building.

## Wrap-up

We have gotten familiar with the basics of smart contracts in Wasm environemnts,
and learned how to set up tests for NEAR smart contracts. The
[next post](../build-on-near-1.2) we will TDD ourselves to deployment.
