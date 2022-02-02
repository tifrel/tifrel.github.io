---
title: "Build on NEAR: Our first smart contract (part 1.2)"
date: 2022-02-02T00:00:00+00:00
# weight: 1
# aliases: ["/first"]
tags: ["Build on NEAR", "Rust", "NEAR protocol", Smart contracts]
draft: false
# editPost:
#   URL: "https://github.com/<path_to_repo>/content"
#   Text: "Suggest Changes" # edit text
#   appendFilePath: true # to append file path to Edit link
---

In the [the last part](../build-on-near-1.1), we explored Wasm compilation,
smart contracts in general, and testing on NEAR. We've already written tests for
our toy example of a blockchained "Buy Me A Coffee", which is where we pick up
this post.

## The methods

Let us start the development with the `impl` block, as our testing already tells
us which methods are needed:

```rs
// We require `env` to interact with the rest of the NEAR world, and of course
// the types as a "language" for these interactions.
use near_sdk::{env, near_bindgen, AccountId, Balance, Promise};

#[near_bindgen]
impl BuyMeACoffee {
  // This is our bread and butter-method. It needs to be payable, because this
  // that's the whole point of this "Buy me a coffee" thing.
  #[payable]
  pub fn buy_coffee(&mut self) -> Promise {
    // Get call parameters
    let account = env::predecessor_account_id();
    let mut donation = env::attached_deposit();

    // Update the donation amount for the caller
    let old_donation = self.coffee_near_from.get(&account).unwrap_or(0);
    donation += old_donation;
    self.coffee_near_from.insert(&account, &donation);

    // Check if we need to update our top donor
    self.check_top_coffee_buyer(account, donation);

    // Finally, transact tokens to owner, but leave some for storage staking.
    Promise::new(self.owner.clone()).transfer(donation / 100 * 95)
  }

  fn check_top_coffee_buyer(&mut self, donor: AccountId, donation: Balance) {
    match self.top_coffee_buyer {
      // Yay, we someone just bought us coffee for the first time.
      None => {
        self.top_coffee_buyer = Some((donor, donation));
      }
      // Someone just outcompeted someone else in coffee donations for us.
      Some((_, top_donation)) if top_donation < donation => {
        self.top_coffee_buyer = Some((donor, donation));
      }
      // In any other cases, nothing to do
      _ => {}
    }
  }

  // Get the donation amount for a specific account
  pub fn coffee_near_from(&self, account: AccountId) -> Balance {
    self.coffee_near_from.get(&account).unwrap_or(0)
  }

  // Get the account that donated most
  pub fn top_coffee_buyer(&self) -> Option<(AccountId, Balance)> {
    self.top_coffee_buyer.clone() // clone required because of borrowing rules
  }
```

We do have a lot to unpack here, so let's go over it, starting with method
mutability.

### Method mutability

Maybe you're coming from an EVM background and consider methods to be either
mutable, view, or pure. You won't need the background though to understand this
tabular rundown of it:

| Naming  | Rust signature                                              | What that means                          |
| ------- | ----------------------------------------------------------- | ---------------------------------------- |
| mutable | `fn(&mut self, ...)`                                        | Anything can happen inside the method    |
| view    | `fn(&self, ...)`                                            | No state mutations, but state dependency |
| pure    | `fn(...)` (no `self` parameter, but inside an `impl` block) | Independent on contract state            |

You should make sure not to mark methods as `fn(&mut self)` if you don't require
to mutate state. Every mutable contract method will automatically rewrite the
contract state when it terminates, thus costing extra gas. Luckily, the Rust
compiler emits a warning when it encounters unnecessary `mut` modifiers.

### Method visibility

Since I assume you're somewhat familiar with Rust, I also assume you're familiar
with visibility rules. They translate to NEAR smart contracts 1:1. A method
marked as `pub` can be seen by the whole world, and it may be called by the
whole world, specifically other NEAR accounts, and thus other contracts deployed
on NEAR. If your method is not marked as `pub`, it can be seen and used from
within the contract, but not elsewhere. We thus call them internal methods.
There is however a third category that is not part of a standard Rust:
`#[private]` methods. You are allowed to cross-contract call those from the same
contract. As they need an interface to communicate with the outside world, being
a cross-contract call after all, they will need to be `pub`. The signatures go
as follows:

| Naming   | Rust signature      | What that means                                     |
| -------- | ------------------- | --------------------------------------------------- |
| public   | `pub fn`            | Anyone can call                                     |
| private  | `#[private] pub fn` | This contract can call via cross-contract calls     |
| internal | `fn`                | This contract can call, but only from other methods |

### `#[payable]`, environment, and promises

The last bit we need to understand is `#[payable]`, and the strings attached to
it. A function that is marked as `#[payable]` accepts calls that have NEAR
tokens attached to the call. Unlike gas fees, those tokens do not serve the
purpose of paying for computation, but they behave like a transfer to the
contract, with the method called being signalling the intent of the transfer. In
our case, the intent is a simple donation. In other instances, you might wish to
mint some tokens based on the amount of transferred NEAR, or simply require a
minimum amount to pay for some service. To access these "meta-parameters", we
need functions from `near_sdk::env`:

- `near_sdk::env::predecessor_account_id` gives us the `AccountId` of whoever
  called the contract. `AccountId` is a type alias for `String`, but you can
  verify that it's actually a valid NEAR account ID using
  `near_sdk::env::is_valid_account_id`.
- `near_sdk::env::attached_deposit` returns the `Balance` of NEAR (actually
  yoctoNEAR) with which the method was called. `Balance` is a type alias for
  `u128`.

Those are the methods we need for now, feel free to dig around in
[the docs](https://docs.rs/near-sdk/latest/near_sdk/env/index.html) and find
other functions you're interested in.

The last thing we need is a way to transfer native tokens from the contract.
NEAR uses something called a `Promise` for that. You can actually think of
promises as an instruction to the NEAR protocol to make things happen outside of
your contract. While token transfer is the easiest example, these instructions
may be cross-contract calls, account creation, or staking. Again,
[the docs](https://docs.rs/near-sdk/latest/near_sdk/struct.Promise.html) will
hold far more and more recent information.

## The state and its initialization

Now that we know how the functions inside our contract work, and which storage
they rely on, it's time to implement the contracts state:

```rs
use near_sdk::borsh::{self, BorshDeserialize, BorshSerialize};
// We need a map type and we cannot use `std`. Luckily NEAR SDK comes with
// batteries included.
use near_sdk::collections::UnorderedMap;
// We require `env` to interact with the rest of the NEAR world, and of course
// the types as a "language" for these interactions.
use near_sdk::{near_bindgen, AccountId, Balance, PanicOnDefault};

// We obviously need to change the storage part of our contract.
// Note how we can no longer derive `Default`, as it's not implemented for
// `UnorderedMap`. Instead we use `PanicOnDefault`, which is required by NEAR
// to signal that `Default` is not implemented for this contracts storage.
// Our other options would be to talk the `initialize` method below, and use at
// a custom implementation of `Default`.
#[near_bindgen]
#[derive(PanicOnDefault, BorshDeserialize, BorshSerialize)]
pub struct BuyMeACoffee {
  owner: AccountId,
  coffee_near_from: UnorderedMap<AccountId, Balance>,
  top_coffee_buyer: Option<(AccountId, Balance)>,
}

#[near_bindgen]
impl BuyMeACoffee {
  // Because we no longer have an implementation for `Default` on our contract,
  // we need to tell NEAR how to initialize it
  #[init]
  pub fn initialize(owner: AccountId) -> Self {
    // Assert that the AccountId of the provided owner is valid, or fail
    // deployment
    assert!(env::is_valid_account_id(owner.as_bytes()));

    Self {
      owner,
      // The text inside the call to `new` is a key prefix for the onchain
      // storage key. It could just have been 0, but you should make a habit out
      // of properly prefixing your storage items. This will help whenever you
      // want to interact with raw onchain storage.
      coffee_near_from: UnorderedMap::new("coffee.tifrel.testnet.map".as_bytes()),
      top_coffee_buyer: None,
    }
  }
}
```

Let's unravel this by field:

- `owner` is where the coffee donations go to. We want to set this once when we
  initialize the contract and never touch it again. The `owner` will be an
  `AccountId`, and we already learned how to verify those. It is a common
  practice to do all your checks (permissions, deposit requirements etc.) at the
  very start of your contract and fail early to avoid unnecessary gas costs.
- `coffee_near_from` tracks cumulative donations by `AccountId`. The natural
  type for this would be `std::collections::HashMap`, so why don't we use that?
  We compile to WebAssembly, and a significant implication is the inavailability
  of `std`. More on that in the following paragraph.
- `top_coffee_buyer` is a pretty self-explanatory leaderboard with a single
  entry.

If you've just finished [the Rust book](https://doc.rust-lang.org/stable/book/),
you might ask why would people want to give up on `std`? One reason is that
`std` has things like TCP socket abstractions in it, and making these available
on-chain brings with it the headache of
[the oracle problem](https://blog.chain.link/what-is-the-blockchain-oracle-problem/)
on steroids, as you could e.g. have WebSockets connections inside smart
contracts. But clearly, things like `Vec` and `HashMap` are base data structures
and not having them sounds like a royal pain. It would be, if it wasn't for
[`near_sdk::collections`](https://docs.rs/near-sdk/latest/near_sdk/collections/index.html).
The module not only contains collection types to make our lives more liveable,
but these data structures are optimized for the on-chain trie storage, which is
quite different from your computers RAM, which the data structures in
`std::collections` are optimized for. The contained `Vector` and `LazyOption`
types are straight-forward to use and do not come with alternatives, so
duplicating the docs here isn't really worth it. We are interested in something
akin to a `HashMap`, and there are three types on offer:

<!-- FIXME:
Is `LookupMap` actually the most efficient option? => Revisit when profiled
-->

- `LookupMap` is the least powerful, but most efficient option. It allows you to
  look up values by key, but cannot be iterated.
- `UnorderedMap` allows you to iterate over keys and/or values, but doesn't
  guarantee any order.
- `TreeMap` allows you to iterate over keys and/or values, ordered by the key.

We don't need to iterate explicitly, but over the course of this series we will
touch on storage migrations. For that we will need to iterate over all the
entries, and we thus choose `UnorderedMap` to keep track of who donated how much
NEAR to pay for coffee.

Types from `near_sdk::collections` come with another string attached: They don't
have `Default` implemented on them, thus we cannot derive it for our contract.
While we could write our own implementation of `Default`, no parameters would be
allowed. Remember that we want to set the `owner` of a contract while
initializing? That's why we have a custom `initialize` method on the contract,
and require two attributes:

- `#[init] fn initialize` such that the function is available to call during
  deployment
- `#[derive(PanicOnDefault)] struct BuyMeACoffee { ... }`, where the naming is a
  bit misleading. We don't care what happens if
  `Default::default::<BuyMeACoffee>` is called, because it is not implemented.
  Due to `#[near_bindgen]`, we will however get a compiler error on the missing
  implementation of `Default` on `BuyMeACoffee`. Deriving `PanicOnDefault`
  simply tells NEAR that we explicitly opt out of using the `Default` trait, and
  thus allows us to compile the contract without this implementation.

As a sidenote, we should have probably implemented `top_coffee_buyer` as
`near_sdk::collections::LazyOption`. To pretend at least some brevity, I will
skip it here, but it is done that way in the
[actual implementation on GitHub](https://github.com/tifrel/build-on-near/commit/dce408d7c522c755d746e3c85ee7d2344e679fc3).

## Deploying to testnet

We finally arrive at the point where we can deploy the contract. Which we will
do with our trusty NEAR CLI:

```sh
wasm='target/wasm32-unknown-unknown/release/near_buy_me_a_coffee.wasm'
near deploy --accountId coffee.tifrel.testnet --wasmFile "$wasm" \
  --initFunction initialize \
  --initArgs '{"owner": "tifrel.testnet"}'
```

```plain
Starting deployment. Account id: coffee.tifrel.testnet, node: https://rpc.testnet.near.org, helper: https://helper.testnet.near.org, file: target/wasm32-unknown-unknown/release/near_buy_me_a_coffee.wasm
Transaction Id 25g5CJxyMurDgsSSCuWndkhnuzGc2CPp322LC9hWCiUB
To see the transaction in the transaction explorer, please open this url in your browser
https://explorer.testnet.near.org/transactions/25g5CJxyMurDgsSSCuWndkhnuzGc2CPp322LC9hWCiUB
Done deploying and initializing coffee.tifrel.testnet
```

That's it! The contract is on the chain, and all the world can interact with it.
Let's verify that by creating two subaccounts:

```sh
near create-account someone.tifrel.testnet \
  --masterAccount tifrel.testnet \
  --initialBalance 5

near create-account sometwo.tifrel.testnet \
  --masterAccount tifrel.testnet \
  --initialBalance 5
```

We can use these accounts for interacting with the contract:

```sh
near call coffee.tifrel.testnet buy_coffee '{}' \
  --accountId someone.tifrel.testnet \
  --deposit 1
```

```plain
Scheduling a call: coffee.tifrel.testnet.buy_coffee({}) with attached 1 NEAR
Doing account.functionCall()
Transaction Id 7bdK7tRpQUgMGBiYXkXixM4EPpsPqghRBm9kHyqdLJKp
To see the transaction in the transaction explorer, please open this url in your browser
https://explorer.testnet.near.org/transactions/7bdK7tRpQUgMGBiYXkXixM4EPpsPqghRBm9kHyqdLJKp
```

And we can ue whichever account we want to verify that the mutations we wanted
actually got recorded on-chain:

```sh
near view coffee.tifrel.testnet coffee_near_from '{"account": "someone.tifrel.testnet"}' --accountId tifrel.testnet
```

```plain
View call: coffee.tifrel.testnet.coffee_near_from({"account": "someone.tifrel.testnet"})
1e+24
```

```sh
near view coffee.tifrel.testnet top_coffee_buyer --accountId tifrel.testnet
```

```plain
View call: coffee.tifrel.testnet.top_coffee_buyer()
[ 'someone.tifrel.testnet', 1e+24 ]
```

And if we do all this with the other created account, we will see
`top_coffee_buyer` getting updated:

```sh
near call coffee.tifrel.testnet buy_coffee '{}' \
  --accountId sometwo.tifrel.testnet \
  --deposit 2
```

```plain
Scheduling a call: coffee.tifrel.testnet.buy_coffee({}) with attached 2 NEAR
Doing account.functionCall()
Transaction Id no99p6t2osKCGu1ZeFz7xc5J3TWAnfFNdhvKqbVnVVV
To see the transaction in the transaction explorer, please open this url in your browser
https://explorer.testnet.near.org/transactions/no99p6t2osKCGu1ZeFz7xc5J3TWAnfFNdhvKqbVnVVV
''
```

```sh
near view coffee.tifrel.testnet coffee_near_from '{"account": "sometwo.tifrel.testnet"}' --accountId tifrel.testnet
```

```plain
View call: coffee.tifrel.testnet.coffee_near_from({"account": "sometwo.tifrel.testnet"})
2e+24
```

```sh
near view coffee.tifrel.testnet top_coffee_buyer --accountId tifrel.testnet
```

```plain
View call: coffee.tifrel.testnet.top_coffee_buyer()
[ 'sometwo.tifrel.testnet', 2e+24 ]
```

## Wrap-up

As we did last time, we covered some significant ground today. We started
knowing how to enforce the desired smart contracts logic, and we got to a point
of understanding and applying the following concepts:

- Visibility and mutability of smart contract methods
- The blockchain environments and the types that define our interactions
- The inavailability of `std` and its implications
- Deploying to a live network and interacting with the contract

You could actually pick up from here doing some integration tests. That however,
is a topic for another post.

<!-- You could actually pick up from here doing some integration tests. That however, is a topic for [another post](../build-on-near-2). -->
