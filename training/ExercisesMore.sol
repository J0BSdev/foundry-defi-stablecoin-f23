// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// -----------------------------------------------------------------------------
// Rješenja za vježbe 5–8 (kratko u komentarima ispod svakog kontrakta).
// -----------------------------------------------------------------------------

/// @notice Vježba 5 — Problem: `.transfer()` šalje samo 2300 gas primatelju; mnogi kontrakti
/// padnu ili ne mogu izvršiti logiku. Rješenje: `call{value:}` + provjera `ok` (i CEI redoslijed).
contract ExerciseFive {
    mapping(address => uint256) public balances;

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function payout(uint256 amount) external {
        require(balances[msg.sender] >= amount, "no funds");
        balances[msg.sender] -= amount;
        (bool ok,) = payable(msg.sender).call{value: amount}("");
        require(ok, "send failed");
    }
}

/// @notice Vježba 6 — Problem: entropija iz `block.timestamp`, `block.number`, itd. nije tajna;
/// validator / MEV može utjecati. Za pravi novac treba Chainlink VRF (ili sličan oracle) ili
/// commit–reveal protokol. Ovdje samo ograničavamo tko može pokrenuti izbor + dokumentacija.
contract ExerciseSix {
    address public owner;
    address[] private entrants;
    address public winner;

    constructor() {
        owner = msg.sender;
    }

    function enter() external {
        entrants.push(msg.sender);
    }

    /// @dev Za produkciju: zamijeni tijelo s VRF callbackom koji dobije `requestId` i `randomWords`.
    function pickWinner() external {
        require(msg.sender == owner, "not owner");
        require(entrants.length > 0, "empty");
        // Primjer ZA UČENJE — i dalje nije sigurno kao jedini izvor slučajnosti:
        uint256 i = uint256(keccak256(abi.encodePacked(block.prevrandao, address(this), entrants.length)))
            % entrants.length;
        winner = entrants[i];
    }
}

/// @notice Vježba 7 — Problem: `setOwner` bez kontrole — bilo tko može preuzeti vlasništvo.
/// Rješenje: samo trenutni `owner` smije predati ulogu.
contract ExerciseSeven {
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    function setOwner(address newOwner) external {
        require(msg.sender == owner, "not owner");
        owner = newOwner;
    }
}

/// @notice Vježba 8 — Problem: `unchecked { a + b }` može “preliti” uint256 (wrap) ako zbroj premaši max.
/// Rješenje: obično zbrajanje u Solidity 0.8+ (automatski revert na overflow) ili eksplicitni `require`.
contract ExerciseEight {
    function sum(uint256 a, uint256 b) external pure returns (uint256) {
        return a + b;
    }
}
