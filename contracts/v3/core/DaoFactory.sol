pragma solidity ^0.7.0;

// SPDX-License-Identifier: MIT

import './Module.sol';
import './Registry.sol';
import '../adapters/interfaces/IVoting.sol';
import '../core/interfaces/IProposal.sol';
import '../core/interfaces/IMember.sol';
import '../core/banking/Bank.sol';
import '../adapters/Onboarding.sol';
import '../adapters/Financing.sol';
import '../adapters/Managing.sol';
import '../adapters/Ragequit.sol';

contract DaoFactory is Module {

    event NewDao(address summoner, address dao);

    mapping(bytes32 => address) addresses;

    constructor (address coreAddress, address votingAddress, address managingAddress, address financingAddress, address onboardingAddress, address rageQuitAddress) {
        addresses[CORE_MODULE] = coreAddress;

        // Canonical Adapters
        addresses[VOTING_MODULE] = votingAddress;
        addresses[RAGEQUIT_MODULE] = ragequitAddress;
        addresses[MANAGING_MODULE] = managingAddress;
        addresses[FINANCING_MODULE] = financingAddress;
        addresses[ONBOARDING_MODULE] = onboardingAddress;
    }

    /*
     * @dev: A new DAO is instantiated with only the Core Modules enabled, to reduce the call cost. 
     *       Another call must be made to enable the default Adapters, see @registerDefaultAdapters.
     */
    function newDao(uint256 chunkSize, uint256 nbShares, uint256 votingPeriod, address[] initMembers, uint256[] initShares) external returns (address) {
        Registry dao = new Registry();
        address daoAddress = address(dao);
        //Registering Core Modules
        dao.addModule(CORE_MODULE, addresses[CORE_MODULE]);
        dao.addModule(VOTING_MODULE, addresses[VOTING_MODULE]);

        //Registring Adapters
        dao.addModule(ONBOARDING_MODULE, addresses[ONBOARDING_MODULE]);
        dao.addModule(FINANCING_MODULE, addresses[FINANCING_MODULE]);
        dao.addModule(MANAGING_MODULE, addresses[MANAGING_MODULE]);
        dao.addModule(RAGEQUIT_MODULE, addresses[RAGEQUIT_MODULE]);

        IVoting votingContract = IVoting(addresses[VOTING_MODULE]);
        votingContract.registerDao(daoAddress, votingPeriod);

        IMember memberContract = IMember(addresses[MEMBER_MODULE]);

        require(initMembers.length === initShares.length, "array length must match");

        for (uint256 i = 0; initMembers.length; i++){
            memberContract.updateMember(dao, initMember[i], initShares[i]);
        }
        

        OnboardingContract onboardingContract = OnboardingContract(addresses[ONBOARDING_MODULE]);
        onboardingContract.configureOnboarding(dao, chunkSize, nbShares);

        emit NewDao(msg.sender, daoAddress);

        return daoAddress;
    }

}