---
title: "Build on NEAR: Getting started (part 0)"
date: 2022-01-20T00:00:00+00:00
# weight: 1
# aliases: ["/first"]
tags: ["Build on NEAR", "Rust", "NEAR protocol", "Smart contracts"]
draft: false
# editPost:
#   URL: "https://github.com/<path_to_repo>/content"
#   Text: "Suggest Changes" # edit text
#   appendFilePath: true # to append file path to Edit link
---

So you know how to build with Rust, or have experience with smart contracts, now
you want to build on NEAR? This series is for you. I will do my best to explain
blockchain concepts and advanced Rust whenever I can, and whenever I feel that
it's necessary. Following topics will be covered:

0. Interacting with the NEAR network, for which you will need an account and
   should have a look at the NEAR CLI tool (this post)
1. Building smart contracts, testing them, and deploying them to a testing
   network
   1. [Basics and testing](../build-on-near-1.1)
   2. [In-depth and deployment](../build-on-near-1.2)
2. Integration testing, storage migration, redeployments
3. Gas costs and profiling, cross-contract calling, simulation testing, mainnet
4. Indexing, testing the indexer, storage migrations and indexing

Let's kickstart this series by getting you a NEAR account.

### Getting a NEAR account

<!-- TODO: amazon associate account and link ledger -->

This is as easy as following the instructions on the
[testnet wallet](https://wallet.testnet.near.org/). You will need to claim a
username (e.g. `tifrel.testnet`), which will be your on-chain identity, to which
you can later add sub-accounts (e.g. `sub.tifrel.testnet`). Unless you have a
Ledger, you should choose to secure your account with a passphrase and store
that in a safe place. If you're new to blockchains, you control your account by
a key, which is derived from the passphrase, not by your account name, so make
sure not to loose your keys, or worse, leak them!

Your testnet account will be automatically funded with 200 NEAR tokens (200 N),
which do no carry any value with them. They're sole purpose is to have people
play around with NEAR and test things without risking any assets. NEAR testnet
doesn't have a faucet yet, and it might never have one. The current canonical
way of obtaining more testnet tokens is the creation of another testnet account,
whose initial funds you may transfer to your actual testnet account.

<!-- TODO: keep eye on: https://examples.near.org/pow-faucet -->

Of course, NEAR also has a network were tokens carry value, and where
potentially valuable digital assets are built on, such as Fungible Tokens (FTs)
and Non-Fungible Tokens (NFTs). You can set up your mainnet account using the
[mainnet wallet](https://wallet.near.org/), but it requires you to deposit NEAR,
which in turn requires you to have some NEAR before you have a NEAR account. You
can get it on any exchange, but that process is out of scope for this post.

### Using the NEAR CLI

One way to interact with the NEAR network is the
[NEAR CLI](https://github.com/near/near-cli), which can be installed using NPM:

```sh
sudo npm i -g near-cli
near --version
```

To locally save your account credentials, issue `near login`, and follow the
steps on the opened website. Note that you might not yet be aware of the file
existing at `~/.near-credentials/testnet/tifrel.testnet.json`. It contains your
account name and an [ed25519 keypair](https://ed25519.cr.yp.to/), with which you
will sign transactions. You can check some aspects of your account using
`near state tifrel.testnet`, which for your virgin NEAR account should give
something similar to this:

```
Account tifrel.testnet
{
  amount: '199999917070150000000000000',
  locked: '0',
  code_hash: '11111111111111111111111111111111',
  storage_usage: 346,
  storage_paid_at: 0,
  block_height: 80295093,
  block_hash: '4fBE9ShHcHDieveQapGYqeHbuuHZpcc9PJ5tPKb87hNP',
  formattedAmount: '199.99991707015'
}
```

Wonder why the `amount`, your NEAR balance, is such an obscenely high number?
Every balance in the network is actually tracked in yoctoNEAR (yN), to allow for
high precision. It alleviates the problems that come with floating-point
numbers, but in turn creates an atomic unit, 1 yN, as an absolute minimum of all
measurement for the NEAR token.

The last part to talk about is `near create-account`, which enables us to create
the already mentioned sub-accounts. The reason is simple: Each account may have
either one or no smart contract associated to it, but each smart contract has an
associated account. In other words, if you were to deploy more than one smart
contract, you need to have more than one accounts. Sub-accounts give us the
possibility to publicly express that these contracts may be related. Let's try
it:

```sh
near create-account coffee.tifrel.testnet \
  --masterAccount tifrel.testnet \
  --initialBalance 10
```

```plain
Saving key to '~/.near-credentials/testnet/coffee.tifrel.testnet.json'
Account coffee.tifrel.testnet for network "testnet" was created.
```

```sh
near state coffee.tifrel.testnet
```

```
Account coffee.tifrel.testnet
{
  amount: '10000000000000000000000000',
  locked: '0',
  code_hash: '11111111111111111111111111111111',
  storage_usage: 182,
  storage_paid_at: 0,
  block_height: 80295991,
  block_hash: '4rQ55N2h8BqY52RNRerrvm7pL2oF4MEMtRHaAA2Yo3Yw',
  formattedAmount: '10'
}
```

As claimed, you will find a credentials file at
`~/.near-credentials/testnet/coffee.tifrel.testnet.json`, and as requested, the
new account is claimed with an initial balance of 10 N. You might be curious to
issue `near state tifrel.testnet` once more and find out that a bit more than 10
N has been deducted. The difference accounts for what is called "gas", a fee
paid to the node runners for performing the trusted computations that give rise
to a blockchain networks security guarantees. Because the computation was a
plain transfer of native tokens, the gas cost is small with less than 0.0001 N
when I ran it. Executing smart contract methods requires more gas, and the
specifics
[can be arbitrarily complicated](https://docs.near.org/docs/concepts/gas).

<!-- Thanks to NEARs focus on providing a great UX, developers can actually pay
the gas of deployed contracts, e.g. to ease with onboarding, but usually the gas
is paid by the caller of a contracts method. -->

Note: If you already have a NEAR account and want to open a new one, you could
use this command to fund your new account with the existential deposit.

## Wrap-up

To kick off our NEAR journey, we got ourselves an account and learned to
interact with the NEAR testnet using the NEAR CLI. The
[next post](../build-on-near-1) will get us into writing our first smart
contract.
