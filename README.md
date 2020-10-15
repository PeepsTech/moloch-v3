## Overview

After almost two years of using Moloch DAOs the community realized that Moloch v2 included several functions that were not required by all DAOs. Moreover, many communities began to spring up with unique governance, membership and financial needs that could not be easily address by the core Moloch v2 contracts. Based on these two issues, the community decided to come together again to build a Moloch v3 that would balance an ethos of simplicity with extensibility.

The goals of this new generation of Molochs would be to: 
-Reduce the code to a core set of community primitives (ie. membership, governance, and finance);
-Keep that core as simple and generic as possible; 
-Create a set of interfaces for those core primitives that could be accessed by permissioned extensions (called Adapters);
-Allow for upgradability through the core's selective use of adapters to meet different use-cases and needs. 

This is the first draft of v3 architecture was prepared by David Roon of Open Law / the LAO and iterated upon based on feedback from the greater Moloch DAO community.

Inspired by the hexagonal architecture pattern David demonstrated that we can have additional layers of security and break the main contract into smaller contracts. With that, we create loosely coupled modules/contracts, easier to audit, and can be easily connected to the DAO.

The architecture is composed by 3 main types of components:
- A Core module keep track of the state changes of the DAO primitives and the adapters approved by the DAO;
- A set of standard interfaces for such primitives via which adapters can alter the state of the Core; and
- Adapters that can be added to the registry maintained by the Core to change the state of the Core.

**Core Modules** 
- The core module named Registry keeps track of all registered core modules, so they can be verified during the call executions
- Only Adapters or other parts of the Core are allowed to call a Core Module function
- The Core does not communicate with contract external to the DAO (ie. not included in the registry) directly, it needs to go through an Adapter
- Each core module is a Smart Contract with the `onlyAdapter` and/or `onlyModule` modifiers applied to its functions, it shall not expose its functions in a public way (`external` or `public` modifier should not be added to core module functions, except for the read-only functions)

**Adapters**
- Public/External accessible functions called from external users or other contracts
- Adapters do not keep track of the state of the DAO, they might use storage but the ideal is that any DAO relevant state change is propagated to the Core  
- Adapters just execute logic that changes the state of the DAO by calling the Core, they also can compose complex calls that interact with external contracts to pull/push additional data 
- Each Adapter is intended to be a specialized Smart Contract designed to do one thing very well or address a specific use case
- Adapters can have public access or access limited to members of the DAO (onlyMembers modifier)

**Everything Else**
- RPC clients responsible for calling the Adapters public/external functions to interact with the DAO Core

![moloch_v3_architecture](https://user-images.githubusercontent.com/708579/92758048-b8be9b80-f364-11ea-9c42-ac8b75cf26c4.png)

*illustration by David Roon and Open Law*


### Usage

#### Install
After saving locally run `npm install` 

#### Run Tests
This project uses truffle, to run the tests, simply run `truffle test`

## Contribute

Moloch exists thanks to its contributors. There are many ways you can participate and help build high quality software. Check out the [contribution guide](CONTRIBUTING.md)!

## License

Moloch is released under the [MIT License](LICENSE). So steal this code, do awesome stuff, slay Moloch, the God of Coordination Failure. 