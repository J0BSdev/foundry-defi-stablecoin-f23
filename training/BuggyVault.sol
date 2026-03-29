// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @notice Mali trening-kontrakt: pronađi zašto je `withdraw` nesiguran.
/// Hint: što se dogodi ako `withdraw` pozove drugi kontrakt koji opet pozove `withdraw`?
contract BuggyVault {
    mapping(address => uint256) public balances;

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    /// @notice Bug je u redoslijedu: vanjski poziv prije ažuriranja stanja.
    function withdraw(uint256 amount) external {
        require(balances[msg.sender] >= amount, "insufficient");

        (bool ok,) = payable(msg.sender).call{value: amount}("");
        require(ok, "send failed");

        balances[msg.sender] -= amount;
    }
}
