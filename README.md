### **Introduction**

- This module enables smart accounts to authorize users or dapps to access a limited quantity of assets within specific time frames. It supports various use cases, such as subscription-based dapps or DCA dapps, allowing token withdrawals at predefined intervals. Unlike traditional methods where a smart account must deposit a substantial token amount upfront, this module allows controlled withdrawals over time. In addition to accounts granting access, this module allows users or dapps to directly request tokens from an account with time restrictions. The account can then approve these requests, ensuring authenticity and providing a versatile solution for managing one-time and recurring transactions on smart accounts.

### **Installation**

- Smart accounts can activate the request module directly through module enable options tailored to the specific smart account type. In the case of Safe accounts, the module must be initially registered in the registry before the manager can enable it.

### **Usage**

### **1. Creating a Request Session**

To create a new request session and a recurring request session, users can call the **`setRequestSession`** function and **`setRecurringRequestSession`** function respectively, providing the necessary request data.

```solidity
function setRequestSession(
  RequestData _data //Request data object
);
```

```solidity
function setRecurringRequestSession(
	RecurringRequest _data //Recurring request data object
);
```

### **2. Approving a Request Session**

Users can approve a specific request session using the **`approveRequest`** function and can approve a recurring request session with the **`approveRecurringRequest`** function, passing the request ID as an argument.

```solidity
function approveRequest(
	uint256 requested //Id of request to be approved
);
```

```solidity
function **approveRecurringRequest**(
	uint256 recurringId //Id of recurring request to be approved
);
```

### **3. Executing Requests from Safe Account**

To execute a one-time request or a recurring request, users can use the **`execRequest`** and **`execRecurringRequest`** functions, respectively. These functions require the Safe account manager's address, the Safe account address, the Safe transaction object, and the corresponding request or recurring request ID.

```solidity
function execRequest(
	ISafeProtocolManager manager, //Address of safe manager
  address account, //Address of safe account
  SafeTransaction safetx, //Safe transaction object
	uint256 requestId //Id of request to be executed
);
```

```solidity
function execRecurringRequest(
  ISafeProtocolManager manager, //Address of safe manager
  address account, //Address of safe account
  SafeTransaction safetx, //Safe transaction object
	uint256 recurringId //Id of recurring request to be executed
);
```

### **4. Executing Requests from Smart Accounts**

The contract has `validateUserOp` to validate user operations by checking the signature of the user's request against the stored request session data. Validation includes checks for approval status, validity periods, amounts, and matching addresses.

```solidity
function validateUserOp(
	UserOperation calldata userOp, // User Operation to be validated
	bytes32 userOpHash //Hash of the User Operation to be validated
)
```

### **5. Sending New Request Sessions**

The contract provides functions **`newRequest`** and **`newRecurringRequest`** to simplify the process of creating and sending new request sessions to a smart account.

```solidity
function newRequest(
	uint48 validUntil, //End time of request session
	uint48 validAfter, //Start time of request session
	uint256 amount, //Max amount that can be transferred
	address receiver, //Address of receiver
	address token //Address of token that can be transferred
);
```

```solidity
function newRecurringRequest(
	uint256 allowedAmount, //Max amount per transfer for a session
	uint48 timePeriod, //Recurring time intervals
	uint48 timeLimit, //Max time limit for session
	address receiver, //Address of receiver
	address token //Address of token that can be transferred
);
```

### **Contributing**

- Create an issue followed by a pull request on → https://github.com/FetcchX/request-module

### **License**

- Licensed under the MIT License, Copyright © 2023-present [Fetcch](https://fetcch.xyz).

- See [LICENSE](./LICENSE) for more information.

### Demo

- https://safe-request-plugin-demo.vercel.app/
