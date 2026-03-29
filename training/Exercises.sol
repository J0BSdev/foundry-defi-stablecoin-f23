// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

error ExerciseFour__RecipientsZero();
error ExerciseTwo__NoClaimable();
error ExerciseTwo__TransferFailed();
error ExerciseFour__EachZero();

interface IERC20Like {
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @notice Vježba 1 — pogledaj `onlyOwner`.
contract ExerciseOne {
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    function setOwner(address newOwner) external onlyOwner {
        owner = newOwner;
    }
}

/// @notice Vježba 2 — pogledaj `claim`.
contract ExerciseTwo {
    IERC20Like public token;
    mapping(address => uint256) public claimable;

    constructor(address token_) {
        token = IERC20Like(token_);
    }

    function claim() external {
        if (claimable[msg.sender] == 0) {
            revert ExerciseTwo__NoClaimable();
        }
        uint256 amount = claimable[msg.sender];
        claimable[msg.sender] = 0;
        token.transfer(msg.sender, amount);
        if (!token.transfer(msg.sender, amount)) {
            revert ExerciseTwo__TransferFailed();
        }
    }
}

/// @notice Vježba 3 — pogledaj `withdraw`.
contract ExerciseThree {
    mapping(address => uint256) public balances;

    receive() external payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw(uint256 amount) external {
        require(balances[msg.sender] >= amount, "no funds");
        balances[msg.sender] -= amount;
        (bool ok,) = payable(msg.sender).call{value: amount}("");
        require(ok, "send failed");
    }
}

/// @notice Vježba 4 — pogledaj `distribute`.
contract ExerciseFour {
    function distribute(uint256 total, uint256 recipients) external pure returns (uint256 each) {
        if (recipients == 0) {
            revert ExerciseFour__RecipientsZero();
        }
        each = total / recipients;
        if (each == 0) {
            revert ExerciseFour__EachZero();
        }
    }
}
