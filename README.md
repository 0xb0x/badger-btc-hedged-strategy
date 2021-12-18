# strategy
This strategy combines call options to hedge volatility [(vega hedging](https://www.investopedia.com/terms/v/vega-neutral.asp)) using a [bull call spread](https://www.investopedia.com/terms/b/bullcallspread.asp). It involves shorting a call option and purchasing another call options with a lower strike. When funds are deposited into this strategy part of it is deposited into the ribbon btc covered call vault to simulate a short call option position and the remaining is deposited into `contracts/VegaHedge.sol` which longs call options with lower strike to hedge against volatility.

Also due to the nature of withdrawals from the ribbon vault, the following function inplementations were changed to enable our strategy to remain compatible with badger:

`_withdrawSome(amount)` -> This initiates a withdrawal from the ribbon vault which could be completed later in the future

`_withdrawAll()` -> This completes an already initiated withdrawal from ribbon vault.

# todo
do more research
write tests for current strategy


# helpful links
https://www.opyn.co
https://www.ribbon.finance

# note
None of the contracts are currently deployed yet!