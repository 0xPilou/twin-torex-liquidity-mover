# Uniswap Basic Liquidity Mover for TOREX

This repository contains the implementation of a basic liquidity mover for TOREX, which is easily automatable with
Gelato.

There is a draft TDD for this project [here](TDD.md).

This repository is based on the [Foundry Template by Paul Razvan Berg](https://github.com/PaulRBerg/foundry-template/).

## How To Use With Gelato

1. Deploy the contract or find an already deployed one.
2. Go to [Gelato App](https://app.gelato.network/).
3. Connect your wallet.
4. Start creating a new task by clicking on "+ Create Task".
5. For "Trigger type", select "Time Interval" and set the desired time interval.
6. For "What to trigger", select "Transaction".
7. For "Target Smart Contract", select the network and enter the address of the deployed contract.
8. For "Function to be automated", select
   `moveLiquidity(address: torex, address: rewardAddress, uint256: minRewardAmount)`
9. Arguments:
   - `torex`: The address of the TOREX you want to move liquidity for.
   - `rewardAddress`: The address for which the profit of the liquidity movement is sent.
   - `minRewardAmount`: The minimum amount of reward to be made in the quote tokens. Do account for gas cost so the
     reward amount would cover it.
10. For "Task Properties", give the task a name.
11. Create the task by clicking on "Create Task" and signing the transaction.
12. Check that the task shows up in your dashboard and you should be done.

Do note that for automation transactions to be executed by Gelato, you need to your fund Gelato account by going to
"1Balance" in the app, once you've connected your wallet.

## License

This project is licensed under MIT.
