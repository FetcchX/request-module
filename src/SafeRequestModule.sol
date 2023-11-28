// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import {IAccount} from "@safe-global/safe-core-protocol/contracts/interfaces/Accounts.sol";
import {ISafeProtocolPlugin} from "@safe-global/safe-core-protocol/contracts/interfaces/Modules.sol";
import {ISafeProtocolManager} from "@safe-global/safe-core-protocol/contracts/interfaces/Manager.sol";
import {PLUGIN_PERMISSION_NONE, PLUGIN_PERMISSION_EXECUTE_CALL, PLUGIN_PERMISSION_EXECUTE_DELEGATECALL} from "@safe-global/safe-core-protocol/contracts/common/Constants.sol";
import {SafeTransaction, SafeRootAccess} from "@safe-global/safe-core-protocol/contracts/DataTypes.sol";

struct RequestData {
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

contract SafeRequestPlugin is ISafeProtocolPlugin {
    /// @dev Name of plugin
    string public constant NAME = "Request Module";

    /// @dev Version of plugin
    string public constant VERSION = "0.0.1";

    /// @dev Permission required by plugin
    uint8 public constant PERMISSION = PLUGIN_PERMISSION_EXECUTE_CALL;

    /// @dev mapping to keep track of request counter
    mapping(address => uint256) private requestCounter;

    /// @dev mapping to keep track of request data for particular ids
    mapping(address => mapping(uint256 => RequestData)) public requestSessions;

    /// @dev mapping to keep track of recurring request counter
    mapping(address => uint256) private recurringRequestCounter;

    /// @dev mapping to keep track of recurring request data for particular ids
    mapping(address => mapping(uint256 => RecurringRequest))
        public recurringRequestSessions;

    /// @dev Trigger when request session is set
    event RequestSessionSet(address account, uint256 requestId);

    /// @dev Trigger when request session is approved
    event RequestSessionApproved(address account, uint256 requestId);

    /// @dev Trigger when request is executed
    event RequestExecuted(address account, uint256 requestId);

    /// @dev Trigger when recurring request session is set
    event RecurringSessionSet(address account, uint256 recurringId);

    /// @dev Trigger when recurring request session is approved
    event RecurringSessionApproved(address account, uint256 recurringId);

    /// @dev Trigger when recurring request is executed
    event RecurringRequestExecuted(address account, uint256 recurringId);

    /// @dev Error of time is invalid
    error InvalidTime();

    /// @dev Error of amount is invalid
    error InvalidAmount();

    /// @dev Error if address is invalid
    error InvalidAddr();

    /// @dev Error if request is invalid
    error InvalidRequest();

    /// @dev Error if length of array is invalid
    error InvalidLength();

    /// @dev Error if recurring request is invalid
    error InvalidRecurringRequest();

    /// @dev A funtion that returns name of the plugin
    /// @return name string name of the plugin
    function name() external view returns (string memory name) {
        name = NAME;
    }

    /// @dev A function that returns version of the plugin
    /// @return version string version of the plugin
    function version() external view returns (string memory version) {
        version = VERSION;
    }

    /// @dev A function that returns information about the type of metadata provider and its location
    function metadataProvider()
        external
        view
        override
        returns (uint256 providerType, bytes memory location)
    {}

    /// @dev A function that indicates permissions required by the.
    /// @dev Permissions types and value: EXECUTE_CALL = 1, CALL_TO_SELF = 2, EXECUTE_DELEGATECALL = 4.
    /// @return permissions Bit-based permissions required by the plugin.
    function requiresPermissions() external view override returns (uint8) {
        return PERMISSION;
    }

    /// @dev This function is used to set request sessions
    /// @param _data Request data object
    function setRequestSession(RequestData memory _data) public {
        requestCounter[msg.sender] += 1;
        requestSessions[msg.sender][requestCounter[msg.sender]] = _data;
        emit RequestSessionSet(msg.sender, requestCounter[msg.sender]);
    }

    /// @dev This function is used to approve request sessions
    /// @param requestId Id of request to approve
    function approveRequest(uint256 requestId) external {
        if (requestId > requestCounter[msg.sender]) revert InvalidRequest();
        requestSessions[msg.sender][requestId].isApproved = true;
        emit RequestSessionApproved(msg.sender, requestId);
    }

    /// @dev This function is used to set recurring request sessions
    /// @param _data Recurring request data object
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

    /// @dev This function is used to approve recurring request sessions
    /// @param recurringId Id of recurring request to approve
    function approveRecurringRequest(uint256 recurringId) external {
        if (recurringId > recurringRequestCounter[msg.sender])
            revert InvalidRecurringRequest();
        recurringRequestSessions[msg.sender][recurringId].isApproved = true;
        emit RecurringSessionApproved(msg.sender, recurringId);
    }

    /// @dev This function is used to execute request by safe account
    /// @param manager Address of safe account manager
    /// @param account Address of safe account
    /// @param safetx Safe transaction object
    /// @param requestId Id of request to execute
    function execRequest(
        ISafeProtocolManager manager,
        address account,
        SafeTransaction calldata safetx,
        uint256 requestId
    ) external returns (bytes[] memory data) {
        if (safetx.actions.length > 1) revert InvalidLength();
        RequestData memory _data = requestSessions[account][requestId];
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

    /// @dev This function is used to execute recurring request by safe account
    /// @param manager Address of safe account manager
    /// @param account Address of safe account
    /// @param safetx Safe transaction object
    /// @param recurringId Id of recurring request to execute
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

    /// @dev This function is used to send new request session to safe account
    /// @param validUntil End time of session
    /// @param validAfter start time of session
    /// @param amount Amount of tokens that can be transferred
    /// @param receiver Address of receiver
    /// @param token Address of token
    function newRequest(
        uint48 validUntil,
        uint48 validAfter,
        uint256 amount,
        address receiver,
        address token
    ) external {
        RequestData memory newReq = RequestData(
            false,
            validUntil,
            validAfter,
            amount,
            receiver,
            token
        );
        setRequestSession(newReq);
    }

    /// @dev This function is used to send new recurringrequest session to safe account
    /// @param allowedAmount Amount of tokens that can be transferred per recurring session
    /// @param timePeriod Recurring time intervals
    /// @param timeLimit Max time limit for session
    /// @param receiver Address of receiver
    /// @param token Address of token
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

    function supportsInterface(
        bytes4 interfaceId
    ) external view override returns (bool) {
        return
            interfaceId == type(ISafeProtocolPlugin).interfaceId ||
            interfaceId == 0x01ffc9a7;
    }
}
