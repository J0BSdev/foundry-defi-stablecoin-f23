// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console2} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract OpenInvariantTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dsce;
    HelperConfig config;
    DecentralizedStableCoin dsc;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        handler = new Handler(dsce, dsc);
        targetContract(address(handler));
        //targetContract(address(dsce));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalBtcDeposited = IERC20(wbtc).balanceOf(address(dsce));

        uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dsce.getUsdValue(wbtc, totalBtcDeposited);

        console2.log("totalSupply", totalSupply);
        console2.log("totalWethDeposited", totalWethDeposited);
        console2.log("totalBtcDeposited", totalBtcDeposited);
        console2.log("wethValue", wethValue);
        console2.log("wbtcValue", wbtcValue);
        console2.log("timesMintIsCalled", handler.timesMintIsCalled());
        assert(wethValue + wbtcValue >= totalSupply);
    }


function invariants_gettersShouldNotRevert()public view{
   dsce.getTokenAmountFromUsd(weth, 1000000000000000000);
   dsce.getTokenAmountFromUsd(wbtc, 1000000000000000000);
   dsce.getUsdValue(weth, 1000000000000000000);
   dsce.getUsdValue(wbtc, 1000000000000000000);

}
}