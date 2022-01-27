---
title: "Fees on common crypto exchanges"
date: 2022-01-20T00:00:00+00:00
weight: 1
# aliases: ["/first"]
tags: ["Cryptocurrencies", "Blockchain", "Trading"]
draft: true
# editPost:
#   URL: "https://github.com/<path_to_repo>/content"
#   Text: "Suggest Changes" # edit text
#   appendFilePath: true # to append file path to Edit link
---

<!-- TODO: OKX -->

### The fees

| Fee                  | Binance    | FTX   | Coinbase | Kraken      | Okex  |
| -------------------- | ---------- | ----- | -------- | ----------- | ----- |
| Fiat deposit         |            | free  | 0.15 EUR | free        |       |
| Crypto deposit       | free       | free  |          | free        |       |
| Make offer (spot)    | 0.10%      | 0.02% | 0.50%    | 0.16%       | 0.08% |
| Take offer (spot)    | 0.10%      | 0.07% | 0.50%    | 0.26%       | 0.10% |
| Make offer (futures) | 0.02%      | 0.02% |          | 0.02%       | 0.02% |
| Take offer (futures) | 0.04%      | 0.07% |          | 0.05%       | 0.05% |
| Fiat withdrawal      |            | free  | 0.15 EUR | 0.09 EUR    |       |
| Crypto withdrawal    | 0.0005 BTC | free  |          | 0.00002 BTC |       |

- Crypto withdrawal fees are for mainnet Bitcoin
  - Each crypto has its own fee, but as BTC is the dominant player in the field,
    BTC fees are used as an indicator
- When multiple variants where available (e.g. fiat deposit methods), the
  cheapest is selected
- All featured exchanges offer discounts for higher trading discounts
  - Discounts can also be offered to "VIP users" etc.
- Binance specialties:
  - Two types of futures, here USD-margined futures are assumed
  - Depositing/withdrawing EUR is a mess. They suspended all SEPA payments,
    which had free deposits and 1.5 EUR withdrawal. All the other options are a
    bit sketchy, might involve intermediaries, and can incur additional fees
    outside of Binance. Too opaque to make a closing statement.
  - You will get discounts when paying fees in BNB, and further discounts
    depending on the amount of BNB that you hold.
- FTX specialties:
  - FTX has its own token FTT, and holding or staking it results in discounts
- Okex specialties:
  - Okex has its own token OKB, and holding or staking it results in discounts
  - Okex features different token classes. Given fees are for Class-A tokens
    (e.g. ETH, BTC), which incur the highest fees.
  - Futures incur an **additional 0.03% settelment fee**.
  - I couldn't find any fiat/crypto funding/withdrawal fees on their website,
    but [CryptoFeeSaver] reports free crypto withdrawals, and 75 USD for any
    fiat withdrawals

### Information sources

- [Kraken](https://support.kraken.com/hc/en-us/articles/360030303832-Overview-of-fees-on-Kraken)
- [Binance trading](https://www.binance.com/en/fee/trading),
  [Binance crypto deposit/withdrawal](https://www.binance.com/en/fee/cryptoFee),
  [Binance fiat deposit/withdrawal](https://www.binance.com/en/fee/fiatFee)
- [FTX general](https://help.ftx.com/hc/en-us/articles/360024479432-Fees),
  [FTX crypto deposit/withdrawal](https://help.ftx.com/hc/en-us/articles/360034865571-Blockchain-Deposits-and-Withdrawals),
  [FTX fiat deposit/withdrawal](https://help.ftx.com/hc/en-us/articles/360042050452-Depositing-Withdrawing-Fiat-)
- [Coinbase](https://help.coinbase.com/en/exchange/trading-and-funding/exchange-fees)

### Concluding thoughts

Coinbase has high trading fees, and crypto withdrawal/deposit are hidden away. I
am not even sure if it's possible to withdraw crypto from Coinbase. Seems like
we have reasons of stay away from them. Binance does better on paper, but by
suspending the most convenient SEPA option, their ridiculous crypto withdrawal
feeds, they seem rather like they just want to hold your assets and then
actively keep you from ever cashing out. They do however get props for the
documentation, along with Kraken, whereas finding out fee schedules for Coinbase
and FTX was rather tedious.
