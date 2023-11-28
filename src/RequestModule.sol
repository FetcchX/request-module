// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import {UserOperation, ValidatorBase} from "modulekit/modulekit/ValidatorBase.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

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

contract RequestModule is ValidatorBase {
    /// @dev Name of plugin
    string public constant NAME = "Request Module";

    /// @dev Version of plugin
    string public constant VERSION = "0.0.1";

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

    /// @dev Trigger when recurring request session is set
    event RecurringSessionSet(address account, uint256 recurringId);

    /// @dev Trigger when recurring request session is approved
    event RecurringSessionApproved(address account, uint256 recurringId);

    /// @dev Error of time is invalid
    error InvalidTime();

    /// @dev Error of amount is invalid
    error InvalidAmount();

    /// @dev Error if address is invalid
    error InvalidAddr();

    /// @dev Error if request is invalid
    error InvalidRequest();

    /// @dev Error if recurring request is invalid
    error InvalidRecurringRequest();

    // @dev A funtion that returns name of the plugin
    /// @return name string name of the plugin
    function name() external view returns (string memory name) {
        name = NAME;
    }

    /// @dev A function that returns version of the plugin
    /// @return version string version of the plugin
    function version() external view returns (string memory version) {
        version = VERSION;
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

    /**
     * @dev validates userOperation
     * @param userOp User Operation to be validated.
     * @param userOpHash Hash of the User Operation to be validated.
     * @return sigValidationResult 0 if signature is valid, SIG_VALIDATION_FAILED otherwise.
     */
    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash
    ) external override returns (uint256) {
        (bytes memory moduleSignature, ) = abi.decode(
            userOp.signature,
            (bytes, address)
        );

        (bool isRecurring, uint256 requestId) = abi.decode(
            moduleSignature,
            (bool, uint256)
        );

        // we expect _op.callData to be `SmartAccount.execute(to, value, calldata)` calldata
        (address tokenAddr, , ) = abi.decode(
            userOp.callData[4:],
            (address, uint256, bytes)
        );

        bytes calldata callData;
        {
            //offset represents where does the inner bytes array start
            uint256 offset = uint256(bytes32(userOp.callData[4 + 64:4 + 96]));
            uint256 length = uint256(
                bytes32(userOp.callData[4 + offset:4 + offset + 32])
            );
            //we expect data to be the `IERC20.transfer(address, uint256)` calldata
            callData = userOp.callData[4 + offset + 32:4 +
                offset +
                32 +
                length];
        }
        (address receiver, uint256 amount) = abi.decode(
            callData[4:],
            (address, uint256)
        );

        bool isValid;
        if (isRecurring) {
            RecurringRequest memory recurringData = recurringRequestSessions[
                userOp.sender
            ][requestId];
            if (recurringData.nextInterval > block.timestamp)
                revert InvalidTime();
            if (recurringData.timeLimit < block.timestamp) revert InvalidTime();
            if (recurringData.allowedAmount != amount) revert InvalidAmount();

            if (recurringData.receiver != receiver) revert InvalidAddr();
            if (recurringData.tokenAddr != tokenAddr) revert InvalidAddr();

            recurringRequestSessions[userOp.sender][requestId]
                .nextInterval += recurringData.timePeriod;
        } else {
            RequestData memory requestData = requestSessions[userOp.sender][
                requestId
            ];

            if (requestData.isApproved) {
                if (requestData.validAfter < block.timestamp)
                    revert InvalidTime();
                if (requestData.validUntil > block.timestamp)
                    revert InvalidTime();

                if (requestData.receiver != receiver) revert InvalidAddr();
                if (requestData.tokenAddr != tokenAddr) revert InvalidAddr();

                if (requestData.maxAmount == 0) revert InvalidAmount();
                requestSessions[userOp.sender][requestId].maxAmount -= amount;

                isValid = true;
            }
        }

        return isValid ? 0 : 1;
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

    /**
     * @dev isValidSignature according to BaseAuthorizationModule
     * @param _dataHash Hash of the data to be validated.
     * @param _signature Signature over the the _dataHash.
     * @return always returns 0xffffffff as signing messages is not supported by SessionKeys
     */
    function isValidSignature(
        bytes32 _dataHash,
        bytes memory _signature
    ) public view override returns (bytes4) {
        (_dataHash, _signature);
        return 0xffffffff; // do not support it here
    }
}
