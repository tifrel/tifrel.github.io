---
title: "Build on NEAR: Integration testing and storage migrations (part 2)"
date: 2022-02-25T00:00:00+00:00
# weight: 1
# aliases: ["/first"]
tags: ["Build on NEAR", "Rust", "NEAR protocol", Smart contracts]
draft: true
# editPost:
#   URL: "https://github.com/<path_to_repo>/content"
#   Text: "Suggest Changes" # edit text
#   appendFilePath: true # to append file path to Edit link
---

[The last part](../build-on-near-1.2) of the Build on NEAR series had us
finalize a unit-tested smart contract. Today, we'll level it up by having
integration tests. Our contract is simple, and thus the integration tests will
not differ that much from the unit tests. It shows however how to interact with
the chain and the smart contract from the outside. As integration tests more
accurately reflect how third parties will interact with your contracts, I
consider them as the most important tests for smart contracts. Enough opinion,
let's give it a go!

## Introducing the tooling: ´near-workspaces-ava´

The NEAR team has kindly provided us with
[NEAR sandbox](https://github.com/near/sandbox), a way to run your own local
version of NEAR, with settings optimized for testing.
[NEAR workspaces](https://github.com/near/workspaces) wraps this sandbox and
provides [bindings for JS](https://github.com/near/workspaces-js) as well as
[Rust](https://github.com/near/workspaces-rs). Using workspaces, you can
interact with the sandbox and NEAR testnet. Be warned though that the Rust
version is still in early alpha, so let's use the opportunity to keep our JS
muscles in good shape.

The JS workspaces provide us with another goodie that's crucial to our efforts:
[´near-workspaces-ava´](https://github.com/near/workspaces-js/tree/main/packages/ava),
which is based on the awesome
[JS unit test runner called AVA](https://github.com/avajs/ava). We're gonna
abuse it to write our integration tests though, since it fulfills a few
important criteria:

- Batteries included. No need for assertion libraries and all the other clutter.
- Runs concurrently. Since each test spins up its own blockchain and thus takes
  some time, it's quite the convenience to have someone else take care of
  parallelization for us.
- Easy to pick up. We will already deal with another language in our tech stack,
  so having a straight-forward testing framework avoids an even steeper learning
  curve.

And when I say easy to pick up, it boils down to running one command in our
contract repo to set up the tests:

```sh
npx near-workspaces-init
```

Did we yet talk about the awesome focus and effort that the NEAR people put into
making development on their chain a smooth experience? This one command wraps up
all the complexity of running local chains in parallel to test your contracts.

You might wish to look around the changes in the repo, as this setup already
comes with a testing example in `near-workspaces/__tests__/main.ava.js`. You
should probably verify that it works on your machine:

```sh
( cd near-workspaces && npm install && npm test )
```

If you're running an M1 Mac the these commands require some hand-massaging
before they work. As it's a more specific issue, I'll leave the
[workaround at GitHub](https://github.com/near/workspaces-js/issues/110), as I
neither know about its reproducibility, nor the longevity of the problem. Once
you can `npm test`, we continue our mission and first remove the example:

```sh
mv near-workspaces testing
rm -r test.sh test.bat testing/compiled-contracts
```

And begin by setting up the tests in a clean `testing/__tests__/main.ava.js`:

```ts
import { Workspace } from "near-workspaces-ava";

function intNEAR(x: number): number {
  return Math.round(x * 1e24);
}
function NEAR(x: number): string {
  return Math.round(x * 1000).toString() + "0".repeat(21);
}

const workspace = Workspace.init(async ({ root }) => {
  // Create a subaccounts
  const someone = await root.createAccount("someone", {
    initialBalance: NEAR(5),
  });
  const sometwo = await root.createAccount("sometwo", {
    initialBalance: NEAR(5),
  });

  // Deploy contract
  const contract = await root.createAndDeploy(
    // Subaccount name
    "coffee",

    // Relative path (from package.json location) to the compiled contract
    "../target/wasm32-unknown-unknown/release/near_buy_me_a_coffee.wasm",

    // Optional: specify initialization
    {
      method: "initialize",
      args: { owner: root.accountId },
    }
  );

  // Make things accessible in tests
  return { root, someone, sometwo, contract };
});
```

This will ensure that prior to every test, the chain is primed with two created
accounts and a deployed smart contract. Next we write a single test to go over
the functionality of our contract:

<!-- prettier-ignore-start -->
```ts
workspace.test(
  "BuyMeACoffee works",
  async (test, { contract, root, someone, sometwo }) => {
    const topCoffeeBuyer = async () => contract.view("top_coffee_buyer", {});

    // First coffee bought
    await someone.call(contract, "buy_coffee", {}, { attachedDeposit: NEAR(1) });
    test.log("Deposited!");
    const fromSomeone = await root.call(contract, "coffee_near_from", {
      account: someone.accountId,
    });
    test.is(fromSomeone, intNEAR(1));
    test.deepEqual(await topCoffeeBuyer(), [someone.accountId, intNEAR(1)]);

    // Second coffee bought
    await sometwo.call(contract, "buy_coffee", {}, { attachedDeposit: NEAR(2) });
    const fromSometwo = await root.call(contract, "coffee_near_from", {
      account: sometwo.accountId,
    });
    test.is(fromSometwo, parseInt(NEAR(2)));
    test.deepEqual(await topCoffeeBuyer(), [sometwo.accountId, intNEAR(2)]);
  }
);
```
<!-- prettier-ignore-end -->

This already encompasses the bash script we used last time to test our contract.
Even better, it runs locally, so you don't have to deal with polluted state as
you do on testnet. Try it out by running `npm test`!

As usual, you can
[browse the implementation on GitHub](https://github.com/tifrel/build-on-near/tree/edde891f1d2ee56959f31d950046d2632ef78b05).

## Storage migration

One of the scarier things you might do with a smart contract is migrating its
storage, and you probably want to double check your integration tests on that.
Let's pretend that additionally to keeping track of the account that has the
highest cumulative donation for our reckless coffee consumption, we also want to
highlight a biggest one-time benefactor:

```rs
#[near_bindgen]
#[derive(PanicOnDefault, BorshDeserialize, BorshSerialize)]
pub struct BuyMeACoffee {
  owner: AccountId,
  coffee_near_from: UnorderedMap<AccountId, Balance>,
  top_coffee_buyer: LazyOption<(AccountId, Balance)>,
  // This field has been added
  top_coffee_bought: LazyOption<(AccountId, Balance)>,
}
```

`top_coffee_bought` will be a new method as well, but we won't indulge in the
implementation here, feel free to browse the commit on GitHub though. Focusing
on the actual migration, we need a way to make our new contract aware of it's
previous version and how to deserialize it from on-chain storage:

```rs
#[derive(BorshDeserialize)]
pub struct OldBuyMeACoffee {
  owner: AccountId,
  coffee_near_from: UnorderedMap<AccountId, Balance>,
  top_coffee_buyer: LazyOption<(AccountId, Balance)>,
}
```

Notice how we only derive `BorshDeserialize` and omit marking `#[near_bindgen]`.
Furthermore, we need a way of translating the old contract storage into its
updated version:

```rs
#[near_bindgen]
impl BuyMeACoffee {
  #[private]
  #[init(ignore_state)]
  pub fn migrate() -> Self {
    //
    let state = env::state_read::<OldBuyMeACoffee>()
      .expect("Couldn't deserialize prior contract state");
    state.into()
  }

  // other methods
}

impl From<OldBuyMeACoffee> for BuyMeACoffee {
  fn from(old_state: OldBuyMeACoffee) -> BuyMeACoffee {
    let top_coffee_bought = new_lazy_option!("top_coffee_bought");
    BuyMeACoffee {
      owner: old_state.owner,
      coffee_near_from: old_state.coffee_near_from,
      top_coffee_buyer: old_state.top_coffee_buyer,
      top_coffee_bought,
    }
  }
}
```

You should of course unit test the new contract, but trying to unit-test the
migration is a major headache and has for me resulted in a bunch of panics on
deserializing the contract state. Luckily, we already learned how to integration
test. Since it's much closer to the real deal, it will also give us more
confidence that our migration code works as intended:

<!-- prettier-ignore-start -->
```ts
import { Workspace } from "near-workspaces-ava";

function intNEAR(x: number): number {
  return Math.round(x * 1e24);
}
function NEAR(x: number): string {
  return Math.round(x * 1000).toString() + "0".repeat(21);
}

const workspace = Workspace.init(async ({ root }) => {
  const someone = await root.createAccount("someone", {
    initialBalance: NEAR(5),
  });
  const sometwo = await root.createAccount("sometwo", {
    initialBalance: NEAR(5),
  });

  return { root, someone, sometwo };
});

workspace.test(
  "BuyMeACoffee migration works",
  async (test, { root, someone, sometwo }) => {
    // Deploy contract
    let contract = await root.createAndDeploy(
      "coffee",
      "../target/wasm32-unknown-unknown/release/buy_me_a_coffee_v1.wasm",
      { method: "initialize", args: { owner: root.accountId } }
    );
    const topCoffeeBuyer = async () => contract.view("top_coffee_buyer", {});

    // First coffee bought
    await someone.call(contract, "buy_coffee", {}, { attachedDeposit: NEAR(1) });
    test.is(
      await contract.view("coffee_near_from", { account: someone.accountId }),
      intNEAR(1)
    );
    test.deepEqual(await topCoffeeBuyer(), [someone.accountId, intNEAR(1)]);

    // Second coffee bought
    await sometwo.call(contract, "buy_coffee", {}, { attachedDeposit: NEAR(2) });
    test.is(
      await contract.view("coffee_near_from", { account: sometwo.accountId }),
      parseInt(NEAR(2))
    );
    test.deepEqual(await topCoffeeBuyer(), [sometwo.accountId, intNEAR(2)]);

    // Perform migration
    const tx = (
      await contract
        .createTransaction(contract)
        .deployContractFile(
          "../target/wasm32-unknown-unknown/release/buy_me_a_coffee_v2.wasm"
        )
    ).functionCall("migrate", {});
    await tx.signAndSend();

    // Existing state/methods are untouched
    test.is(
      await contract.view("coffee_near_from", { account: someone.accountId }),
      parseInt(NEAR(1))
    );
    test.is(
      await contract.view("coffee_near_from", { account: sometwo.accountId }),
      parseInt(NEAR(2))
    );
    test.deepEqual(await topCoffeeBuyer(), [sometwo.accountId, intNEAR(2)]);

    const topCoffeeBought = async () => contract.view("top_coffee_bought", {});
    test.deepEqual(await topCoffeeBought(), null);
  }
);
```
<!-- prettier-ignore-end -->

[I've linked the commit](https://github.com/tifrel/build-on-near/tree/612c661b6d37c48f2f1b174fb1dbb5cda885f397),
where you can not only find the tested migration, but also the implementation of
the refined `BuyMeACoffee` contract.

And that's all there is to it. We can now call the contract upgrade on testnet
with high confidence that we won't corrupt the state:

```sh
near deploy --accountId coffee.tifrel.testnet \
  --wasmFile 'target/wasm32-unknown-unknown/release/buy_me_a_coffee_v2.wasm' \
  --initFunction migrate --initArgs '{}'
```

As we did last time, we can test manually again:

```sh
near view coffee.tifrel.testnet top_coffee_buyer
```

```sh
View call: coffee.tifrel.testnet.top_coffee_buyer()
[ 'sometwo.tifrel.testnet', 2e+24 ]
```

```sh
near view coffee.tifrel.testnet top_coffee_bought
```

```
View call: coffee.tifrel.testnet.top_coffee_bought()
null
```

The fact that we got an uncorrupted response from viewing `top_coffee_buyer` and
no panic from `top_coffee_bought` suffices for me to call our upgrade a success.

The
[NEAR SDK docs](https://www.near-sdk.io/upgrading/production-basics#using-enums)
propose using enums for upgrading. Out of brevity, we will skip this strategy
here, but you should be aware of it. While the enum method seems more
higher-level, and thus more maintainable to me, it brings with it extra overhead
of nesting, both for a code maintainer and for the contract size. As I value
performance and simplicitly, I will probably prefer the barebones state
migration without using an enum to keep track of versioning.

## Wrap-up

Again, we've covered some nice ground today. First, we've upped our testing game
to the integration level. Second, we've talked about upgrading contracts. And it
wasn't only upgrades, it was an upgrade involving a storage migration. Upgrades
that don't touch the storage are trivial in comparison, and we've seen the value
of our integration tests in action. I'll catch you in the next part of the
series, where we will learn how to interact between contracts (cross-contract
calls), and how to keep an eye on our gas costs.

<!-- TODO:
  - [] write the wrap-up
  - [] publish git repo
  - []
-->
