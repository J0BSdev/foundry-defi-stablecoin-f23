// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// -----------------------------------------------------------------------------
// 10 početničkih vježbi — svaka u svom kontraktu, jedan “lagani” bug.
// NatSpec samo upućuje što pogledati, bez rješenja.
// -----------------------------------------------------------------------------

error Beginner02__NotBoss();
error Beginner05__AmountZero();
error Beginner05__TransferFailed();
error Beginner07__NotFriend();

/// @notice 
contract Beginner01 {
    function share(uint256 total, uint256 people) external pure returns (uint256 each) {
        require(people > 0, "people must be greater than 0");
        each = total / people;
    }
}

/// @notice 
contract Beginner02 {
    address public boss;

    function setBoss(address newBoss) external {
        if (msg.sender != boss) {
            revert Beginner02__NotBoss();
        }
        boss = newBoss;
    }
}

/// @notice 
contract Beginner03 {
    uint256[] public nums;

    function sumAll() external view returns (uint256 s) {
        for (uint256 i = 0; i < nums.length; i++) {
            s += nums[i];
        }
    }
}

/// @notice 
contract Beginner04 {
    function countToThree() external pure returns (uint256 n) {
        uint256 i = 0;
        while (i != 3) {
            n++;
        }
    }
}

/// @notice 5
interface IERC20Tiny {
    function transfer(address to, uint256 amount) external returns (bool);
}

contract Beginner05 {
    IERC20Tiny public token;

    constructor(address token_) {
        token = IERC20Tiny(token_);
    }

    function sendTo(address to, uint256 amount) external {
        if (amount == 0) {
            revert Beginner05__AmountZero();
            
        }
        bool success = token.transfer(to, amount);
        if (!success) {
            revert Beginner05__TransferFailed();
        }
    }
}

/// @notice 
contract Beginner06 {
    mapping(address => uint256) public balance;

    function withdraw(uint256 amount) external {
        require(balance[msg.sender] > amount, "too much");
        balance[msg.sender] -= amount;
}

/// @notice 
contract Beginner07 {
    address public friend;

    function setFriend(address a) external {
        friend = a;
    }
}

/// @notice 
contract Beginner08 {
    function isPassing(uint256 score) external pure returns (bool) {
        return score > 50;
    }
}

/// @notice
contract Beginner09 {
    uint256 public secret;

    function setSecret(uint256 s) external {
        secret = s;
    }
}

/// @notice 
contract Beginner10 {
    function remainder(uint256 x, uint256 y) external pure returns (uint256) {
        return x % y;
    }
}
