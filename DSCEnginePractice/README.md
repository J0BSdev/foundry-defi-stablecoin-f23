this is practice contract.

in this protocol user have to deposit collateral(ETH) and then borrow stablecoin(DSC). 

1. Users have to be capable of depositing collateral and minting DSC.

2. If User 

3. Users have to be capable of withdrawling ETH/WETH

4. Users should not be able to withdrawl WETH if they didnt return DSC, or more than they have

5. Protocol has to track how much ETH/WETH user have, and how much does he owe to protocol

6. Maximum DSC that user can mint is 50% from deposited collateral

This protocol is used for depositing collateral -> minting DSC-> then it track if user has 50% more collateral -> if not then revert -> user then has to be capable of withdrawling ETH, but only if he returns DSC

