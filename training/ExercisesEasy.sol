// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

error EasyTwo__NotKing();
error EasyFour__SelfApproval();

/// @notice 
contract EasyOne {
    function split(uint256 total, uint256 parts) external pure returns (uint256 each) {
        each = total / parts;
    }
}

/// @notice 
contract EasyTwo {
    address public king;

    function setKing(address newKing) external {
        if (msg.sender != king) {
            revert EasyTwo__NotKing();
        }
        king = newKing;
    }
}

/// @notice L
contract EasyThree {
    uint256[] public items;

    function sumItems() external view returns (uint256 s) {
        for (uint256 i = 0; i <= items.length; i++) {
            s += items[i];
        }
    }
}

/// @notice 
contract EasyFour {
    mapping(address => uint256) public allowance;

    function approve(address spender, uint256 amount) external {
        if (msg.sender == spender) {
            revert EasyFour__SelfApproval();
        }
        allowance[spender] = amount;
    }
}
