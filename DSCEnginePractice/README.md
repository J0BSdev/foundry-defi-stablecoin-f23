this is practice contract.

in this protocol user have to deposit collateral(ETH) and then borrow stablecoin(DSC). 

1. Users have to be capable of depositing collateral and minting DSC.

2. Users have to be capable of repaying their DSC debt

3. Users have to be capable of withdrawling WETH collateral

4. Users should not be able to withdrawl more WETH than they deposited

5. Users should not be able to withdrawl collateral if the remaining collateral isnt enough to suport their remaining DSC debt

6. Protocol has to track how much WETH each user have, and how much does he owe to protocol

7. Maximum DSC that user can mint is 50% from deposited collateral(ex. collateral value = 2000$)
                                                                   (maximum DSC debt value = 1000$)

8. Users can repy only part of their debt.

This protocol is used for depositing collateral -> minting DSC-> then it track if user has 50% more collateral -> if not then revert -> user then has to be capable of withdrawling ETH, but only if he returns DSC

 