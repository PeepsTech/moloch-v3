pragma solidity ^0.7.0;

// SPDX-License-Identifier: MIT

import './Registry.sol';
import './Module.sol';

import './interfaces/IMember.sol';
import './interfaces/IBank.sol';
import './interfaces/IProposal.sol';

import './../adapters/interfaces/IVoting.sol';

import './../utils/SafeMath.sol';
import './../helpers/FlagHelper.sol';
import './../guards/ModuleGuard.sol';
import './../guards/ReentrancyGuard.sol';

contract Core is IMember, IProposal, Module, ModuleGuard, ReentrancyGuard {
    using FlagHelper for uint256;
    using SafeMath for uint256;

    // DA0 Constants 
    address public constant GUILD = address(0xdead);
    address public constant ESCROW = address(0xbeef);
    address public constant TOTAL = address(0xbabe);
    uint256 public constant MAX_TOKENS = 100;

    // Events
    event UpdateMember(address dao, address member, uint256 shares);
    event UpdateDelegateKey(address dao, address indexed memberAddress, address newDelegateKey);
    event SponsorProposal(uint256 proposalId, uint256 proposalIndex, uint256 startingTime);
    event NewProposal(uint256 proposalId, uint256 proposalIndex);
    event TokensCollected(address indexed moloch, address indexed token, uint256 amountToCollect);
    event Transfer(address indexed fromAddress, address indexed toAddress, address token, uint256 amount);

    struct Member {
        uint256 flags;
        address delegateKey;
        uint256 nbShares;
    }

    struct Proposal {
        uint256 flags; // using bit function to read the flag. That means that we have up to 256 slots for flags
    }

    struct BankingState {
        address[] tokens;
        mapping(address => bool) availableTokens;
        mapping(address => mapping(address => uint256)) tokenBalances;
    }

    uint256 public totalShares = 1; // Maximum number of shares 2**256 - 1

    // Member Mappings 
    mapping(address => mapping(address => Member)) members;
    mapping(address => mapping(address => address)) memberAddresses;
    mapping(address => mapping(address => address)) memberAddressesByDelegatedKey;

    // Proposal Mappings
    mapping(address => uint256) public proposalCount;
    mapping(address => mapping(uint256 => Proposal)) public proposals;

    // Banking Mappings 
    mapping(address => BankingState) states;

    /***********************************
            PROPOSAL FUNCTIONS 
    ************************************/

    function isActiveMember(Registry dao, address addr) override external view returns (bool) {
        address memberAddr = memberAddressesByDelegatedKey[address(dao)][addr];
        uint256 memberFlags = members[address(dao)][memberAddr].flags;
        return memberFlags.exists() && !memberFlags.isJailed() && members[address(dao)][memberAddr].nbShares > 0;
    }

    function memberAddress(Registry dao, address memberOrDelegateKey) override external view returns (address) {
        return memberAddresses[address(dao)][memberOrDelegateKey];
    }

    function updateMember(Registry dao, address memberAddr, uint256 shares) override external onlyModule(dao) {
        Member storage member = members[address(dao)][memberAddr];
        if(member.delegateKey == address(0x0)) {
            member.flags = 1;
            member.delegateKey = memberAddr;
        }

        member.nbShares = shares;
        
        totalShares = totalShares.add(shares);
        
        memberAddressesByDelegatedKey[address(dao)][member.delegateKey] = memberAddr;

        emit UpdateMember(address(dao), memberAddr, shares);
    }

    function updateDelegateKey(Registry dao, address memberAddr, address newDelegateKey) override external onlyModule(dao) {
        require(newDelegateKey != address(0), "newDelegateKey cannot be 0");

        // skip checks if member is setting the delegate key to their member address
        if (newDelegateKey != memberAddr) {
            require(memberAddresses[address(dao)][newDelegateKey] == address(0x0), "cannot overwrite existing members");
            require(memberAddresses[address(dao)][memberAddressesByDelegatedKey[address(dao)][newDelegateKey]] == address(0x0), "cannot overwrite existing delegate keys");
        }

        Member storage member = members[address(dao)][memberAddr];
        require(member.flags.exists(), "member does not exist");
        memberAddressesByDelegatedKey[address(dao)][member.delegateKey] = address(0x0);
        memberAddressesByDelegatedKey[address(dao)][newDelegateKey] = memberAddr;
        member.delegateKey = newDelegateKey;

        emit UpdateDelegateKey(address(dao), memberAddr, newDelegateKey);
    }

    function burnShares(Registry dao, address memberAddr, uint256 sharesToBurn) override external onlyModule(dao) {
        require(_enoughSharesToBurn(dao, memberAddr, sharesToBurn), "insufficient shares");
        
        Member storage member = members[address(dao)][memberAddr];
        member.nbShares = member.nbShares.sub(sharesToBurn);
        totalShares = totalShares.sub(sharesToBurn);

        emit UpdateMember(address(dao), memberAddr, member.nbShares);
    }

    /**
     * Public read-only functions 
     */
    function nbShares(Registry dao, address member) override external view returns (uint256) {
        return members[address(dao)][member].nbShares;
    }

    function getTotalShares() override external view returns(uint256) {
        return totalShares;
    }

    /**
     * Internal Utility Functions
     */

    function _enoughSharesToBurn(Registry dao, address memberAddr, uint256 sharesToBurn) internal view returns (bool) {
        return sharesToBurn > 0 && members[address(dao)][memberAddr].nbShares >= sharesToBurn;
    }

    /***********************************
            PROPOSAL FUNCTIONS 
    ************************************/
    
    function createProposal(Registry dao) override external onlyModule(dao) returns(uint256) {
        uint256 counter = proposalCount[address(dao)];
        proposals[address(dao)][counter++] = Proposal(1);
        proposalCount[address(dao)] = counter;
        uint256 proposalId = counter - 1;

        emit NewProposal(proposalId, counter);
        
        return proposalId;
    }


    function sponsorProposal(Registry dao, uint256 proposalId, address sponsoringMember, bytes calldata votingData) override external onlyModule(dao) {
        Proposal memory proposal = proposals[address(dao)][proposalId];
        require(proposal.flags.exists(), "proposal does not exist for this dao");
        require(!proposal.flags.isSponsored(), "the proposal has already been sponsored");
        require(!proposal.flags.isCancelled(), "the proposal has been cancelled");

        IMember memberContract = IMember(dao.getAddress(MEMBER_MODULE));
        require(memberContract.isActiveMember(dao, sponsoringMember), "only active members can sponsor someone joining");

        IVoting votingContract = IVoting(dao.getAddress(VOTING_MODULE));
        uint256 votingId = votingContract.startNewVotingForProposal(dao, proposalId, votingData);
        
        emit SponsorProposal(proposalId, votingId, block.timestamp);
    }

    /***********************************
            BANK FUNCTIONS 
    ************************************/
    function addToEscrow(Registry dao, address token, uint256 amount) override external onlyModule(dao) {
        require(token != GUILD && token != ESCROW && token != TOTAL, "invalid token");
        unsafeAddToBalance(address(dao), ESCROW, token, amount);
        if (!states[address(dao)].availableTokens[token]) {
            require(states[address(dao)].tokens.length < MAX_TOKENS, "max limit reached");
            states[address(dao)].availableTokens[token] = true;
            states[address(dao)].tokens.push(token);
        }
    }

    function addToGuild(Registry dao, address token, uint256 amount) override external onlyModule(dao) {
        require(token != GUILD && token != ESCROW && token != TOTAL, "invalid token");
        unsafeAddToBalance(address(dao), GUILD, token, amount);
        if (!states[address(dao)].availableTokens[token]) {
            require(states[address(dao)].tokens.length < MAX_TOKENS, "max limit reached");
            states[address(dao)].availableTokens[token] = true;
            states[address(dao)].tokens.push(token);
        }
    }
    
    function transferFromGuild(Registry dao, address applicant, address token, uint256 amount) override external onlyModule(dao) {
        require(states[address(dao)].tokenBalances[GUILD][token] >= amount, "insufficient balance");
        unsafeSubtractFromBalance(address(dao), GUILD, token, amount);
        unsafeAddToBalance(address(dao), applicant, token, amount);
        emit Transfer(GUILD, applicant, token, amount);
    }


    // @DEV - should this be a core function or put into an adapter so that people can ragequit individual tokens? 
    function ragequit(Registry dao, address memberAddr, uint256 sharesToBurn) override external onlyModule(dao) {
        //Get the total shares before burning member shares
        IMember memberContract = IMember(dao.getAddress(MEMBER_MODULE));
        uint256 totalShares = memberContract.getTotalShares();
        //Burn shares if member has enough shares
        memberContract.burnShares(dao, memberAddr, sharesToBurn);
        //Update internal Guild and Member balances
        for (uint256 i = 0; i < states[address(dao)].tokens.length; i++) {
            address token = states[address(dao)].tokens[i];
            uint256 amountToRagequit = fairShare(states[address(dao)].tokenBalances[GUILD][token], sharesToBurn, totalShares);
            if (amountToRagequit > 0) { // gas optimization to allow a higher maximum token limit
                // deliberately not using safemath here to keep overflows from preventing the function execution 
                // (which would break ragekicks) if a token overflows, 
                // it is because the supply was artificially inflated to oblivion, so we probably don't care about it anyways
                states[address(dao)].tokenBalances[GUILD][token] -= amountToRagequit;
                states[address(dao)].tokenBalances[memberAddr][token] += amountToRagequit;
                //TODO: do we want to emit an event for each token transfer?
                // emit Transfer(GUILD, applicant, token, amount);
            }
        }
    }

    function isNotReservedAddress(address applicant) override pure external returns (bool) {
        return applicant != address(0x0) && applicant != GUILD && applicant != ESCROW && applicant != TOTAL;
    }

    /**
     * Public read-only functions 
     */
    function balanceOf(Registry dao, address user, address token) override external view returns (uint256) {
        return states[address(dao)].tokenBalances[user][token];
    }
    
    /**
     * Internal bookkeeping
     */
    function unsafeAddToBalance(address dao, address user, address token, uint256 amount) internal {
        states[dao].tokenBalances[user][token] += amount;
        states[dao].tokenBalances[TOTAL][token] += amount;
    }

    function unsafeSubtractFromBalance(address dao, address user, address token, uint256 amount) internal {
        states[dao].tokenBalances[user][token] -= amount;
        states[dao].tokenBalances[TOTAL][token] -= amount;
    }

    function unsafeInternalTransfer(address dao, address from, address to, address token, uint256 amount) internal {
        unsafeSubtractFromBalance(dao, from, token, amount);
        unsafeAddToBalance(dao, to, token, amount);
    }

    /**
     * Internal utility for Rage Quit
     */
    function fairShare(uint256 balance, uint256 shares, uint256 _totalShares) internal pure returns (uint256) {
        require(_totalShares != 0, "total shares should not be 0");
        if (balance == 0) {
            return 0;
        }
        uint256 prod = balance * shares;
        if (prod / balance == shares) { // no overflow in multiplication above?
            return prod / _totalShares;
        }
        return (balance / _totalShares) * shares;
    }

}

