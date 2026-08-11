// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";
import {
    IL1Bridgehub,
    L2TransactionRequestDirect
} from "contracts/core/bridgehub/IL1Bridgehub.sol";
import {REQUIRED_L2_GAS_PRICE_PER_PUBDATA} from "contracts/common/Config.sol";
import {Utils} from "./utils/Utils.sol";

contract PrividiumCanaryDeposit is Script {
    uint256 internal constant CANARY_L2_GAS_LIMIT = 1_000_000;

    function run(
        address bridgehubAddress,
        uint256 chainId,
        address recipient,
        uint256 amount
    ) external returns (bytes32 l2TransactionHash) {
        require(recipient == tx.origin, "canary must be a self-deposit");
        require(amount > 0, "canary amount must be positive");

        IL1Bridgehub bridgehub = IL1Bridgehub(bridgehubAddress);
        uint256 l1GasPrice = Utils.bytesToUint256(vm.rpc("eth_gasPrice", "[]"));
        uint256 baseCost = bridgehub.l2TransactionBaseCost(
            chainId,
            l1GasPrice,
            CANARY_L2_GAS_LIMIT,
            REQUIRED_L2_GAS_PRICE_PER_PUBDATA
        );
        uint256 mintValue = baseCost * 2 + amount;
        L2TransactionRequestDirect memory request = L2TransactionRequestDirect({
            chainId: chainId,
            mintValue: mintValue,
            l2Contract: recipient,
            l2Value: amount,
            l2Calldata: hex"",
            l2GasLimit: CANARY_L2_GAS_LIMIT,
            l2GasPerPubdataByteLimit: REQUIRED_L2_GAS_PRICE_PER_PUBDATA,
            factoryDeps: new bytes[](0),
            refundRecipient: recipient
        });

        vm.recordLogs();
        vm.broadcast(tx.origin);
        bridgehub.requestL2TransactionDirect{value: mintValue}(request);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        l2TransactionHash = Utils.extractPriorityOpFromLogs(bridgehub.getZKChain(chainId), logs);

        vm.serializeUint("canary", "l2_chain_id", chainId);
        vm.serializeAddress("canary", "address", recipient);
        vm.serializeUint("canary", "amount_wei", amount);
        string memory output = vm.serializeBytes32("canary", "l2_transaction_hash", l2TransactionHash);
        vm.writeJson(output, "script-out/prividium-canary.json");
    }
}
