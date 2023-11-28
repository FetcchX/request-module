// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import {IAccount} from "@safe-global/safe-core-protocol/contracts/interfaces/Accounts.sol";
import {ISafeProtocolPlugin} from "@safe-global/safe-core-protocol/contracts/interfaces/Modules.sol";
import {ISafeProtocolManager} from "@safe-global/safe-core-protocol/contracts/interfaces/Manager.sol";
import {PLUGIN_PERMISSION_NONE, PLUGIN_PERMISSION_EXECUTE_CALL, PLUGIN_PERMISSION_EXECUTE_DELEGATECALL} from "@safe-global/safe-core-protocol/contracts/common/Constants.sol";
import {SafeTransaction, SafeRootAccess} from "@safe-global/safe-core-protocol/contracts/DataTypes.sol";

contract SafeRequestPlugin is ISafeProtocolPlugin {
    string public name = "Request Plugin";
    string public version = "0.0.1";
    uint8 public permissions = PLUGIN_PERMISSION_EXECUTE_CALL;

    struct Request {
        bool isApproved;
        uint48 validUntil;
        uint48 validAfter;
        uint256 maxAmount;
        address receiver;
        address tokenAddr;
    }

    struct RecurringRequest {
        bool isApproved;
        uint256 allowedAmount;
        uint48 timePeriod;
        uint48 timeLimit;
        uint48 nextInterval;
        address receiver;
        address tokenAddr;
    }

    mapping(address => uint256) public requestCounter;

    mapping(address => mapping(uint256 => Request)) private requestSessions;

    mapping(address => uint256) public recurringRequestCounter;

    mapping(address => mapping(uint256 => RecurringRequest))
        private recurringRequestSessions;

    event RequestSessionSet(address account, uint256 requestId);
    event RecurringSessionSet(address account, uint256 recurringId);

    event RequestExecuted(address account, uint256 requestId);
    event RecurringRequestExecuted(address account, uint256 recurringId);

    error InvalidTime();
    error InvalidAmount();
    error InvalidAddr();
    error InvalidRequest();
    error InvalidLength();
    error InvalidRecurringRequest();

    function setRequestSession(Request memory _data) public {
        requestCounter[msg.sender] += 1;
        requestSessions[msg.sender][requestCounter[msg.sender]] = _data;
        emit RequestSessionSet(msg.sender, requestCounter[msg.sender]);
    }

    function setRecurringRequestSession(RecurringRequest memory _data) public {
        recurringRequestCounter[msg.sender] += 1;
        recurringRequestSessions[msg.sender][
            recurringRequestCounter[msg.sender]
        ] = _data;
        emit RecurringSessionSet(
            msg.sender,
            recurringRequestCounter[msg.sender]
        );
    }

    function approveRequest(uint256 requestId) external {
        if (requestId > requestCounter[msg.sender]) revert InvalidRequest();
        requestSessions[msg.sender][requestId].isApproved = true;
    }

    function approveRecurringRequest(uint256 recurringId) external {
        if (recurringId > recurringRequestCounter[msg.sender])
            revert InvalidRecurringRequest();
        recurringRequestSessions[msg.sender][recurringId].isApproved = true;
    }

    function execRequest(
        ISafeProtocolManager manager,
        address account,
        SafeTransaction calldata safetx,
        uint256 requestId
    ) external returns (bytes[] memory data) {
        if (safetx.actions.length > 1) revert InvalidLength();
        Request memory _data = requestSessions[account][requestId];
        if (_data.isApproved) {
            if (_data.validAfter > block.timestamp) revert InvalidTime();
            if (_data.validUntil < block.timestamp) revert InvalidTime();

            address receiver = address(bytes20(safetx.actions[0].data[16:36]));
            uint256 amount = uint256(bytes32(safetx.actions[0].data[36:68]));

            if (_data.receiver != receiver) revert InvalidAddr();
            if (_data.tokenAddr != safetx.actions[0].to) revert InvalidAddr();
            if (_data.maxAmount == 0) revert InvalidAmount();
            requestSessions[account][requestId].maxAmount -= amount;

            (data) = manager.executeTransaction(account, safetx);
        }

        emit RequestExecuted(account, requestId);
    }

    function execRecurringRequest(
        ISafeProtocolManager manager,
        address account,
        SafeTransaction calldata safetx,
        uint256 recurringId
    ) external returns (bytes[] memory data) {
        if (safetx.actions.length > 1) revert InvalidLength();
        RecurringRequest memory _data = recurringRequestSessions[account][
            recurringId
        ];
        if (_data.isApproved) {
            if (_data.nextInterval > block.timestamp) revert InvalidTime();
            if (_data.timeLimit < block.timestamp) revert InvalidTime();

            address receiver = address(bytes20(safetx.actions[0].data[16:36]));
            uint256 amount = uint256(bytes32(safetx.actions[0].data[36:68]));

            if (_data.receiver != receiver) revert InvalidAddr();
            if (_data.tokenAddr != safetx.actions[0].to) revert InvalidAddr();
            if (_data.allowedAmount != amount) revert InvalidAmount();

            recurringRequestSessions[account][recurringId].nextInterval += _data
                .timePeriod;

            (data) = manager.executeTransaction(account, safetx);
        }

        emit RecurringRequestExecuted(account, recurringId);
    }

    function newRequest(
        uint48 validUntil,
        uint48 validAfter,
        uint256 amount,
        address receiver,
        address token
    ) external {
        Request memory newReq = Request(
            false,
            validUntil,
            validAfter,
            amount,
            receiver,
            token
        );
        setRequestSession(newReq);
    }

    function newRecurringRequest(
        uint256 allowedAmount,
        uint48 timePeriod,
        uint48 timeLimit,
        address receiver,
        address token
    ) external {
        RecurringRequest memory newRecurringReq = RecurringRequest(
            false,
            allowedAmount,
            timePeriod,
            timeLimit,
            0,
            receiver,
            token
        );
        setRecurringRequestSession(newRecurringReq);
    }

    /**
     * @dev returns the SessionStorage object for a given smartAccount
     */
    function getRequest(
        address smartAccount,
        uint256 requestId
    ) external view returns (Request memory) {
        return requestSessions[smartAccount][requestId];
    }

    function supportsInterface(
        bytes4 interfaceId
    ) external view override returns (bool) {
        return
            interfaceId == type(ISafeProtocolPlugin).interfaceId ||
            interfaceId == 0x01ffc9a7;
    }

    function metadataProvider()
        external
        view
        override
        returns (uint256 providerType, bytes memory location)
    {}

    function requiresPermissions() external view override returns (uint8) {
        return permissions;
    }
}
