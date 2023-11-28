// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import {UserOperation, ValidatorBase} from "modulekit/modulekit/ValidatorBase.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract RequestValidator is ValidatorBase {
    struct RequestData {
        bool isApproved;
        uint48 validUntil;
        uint48 validAfter;
        uint256 maxAmount;
        address receiver;
        address tokenAddr;
    }

    mapping(address => uint256) public requestCounter;

    mapping(address => mapping(uint256 => RequestData)) private requestSessions;

    error InvalidTime();
    error InvalidAmount();
    error InvalidAddr();
    error InvalidRequest();

    function enable(bytes calldata _data) external payable {}

    function disable(bytes calldata) external payable {}

    function setRequestSessions(RequestData memory _data) public {
        requestCounter[msg.sender] += 1;
        requestSessions[msg.sender][requestCounter[msg.sender]] = _data;
    }

    function approveRequest(uint256 requestId) external {
        if (requestId > requestCounter[msg.sender]) revert InvalidRequest();
        requestSessions[msg.sender][requestId].isApproved = true;
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
        (
            uint48 _validUntil,
            uint48 _validAfter,
            uint256 _requestId,
            uint256 _amount,
            address _token,
            address _receiver
        ) = abi.decode(
                moduleSignature,
                (uint48, uint48, uint256, uint256, address, address)
            );

        bool isValid = validateSession(
            userOp.sender,
            _validUntil,
            _validAfter,
            _requestId,
            _amount,
            _token,
            _receiver
        );

        return isValid ? 0 : 1;
    }

    function validateSession(
        address smartAccount,
        uint48 validUntil,
        uint48 validAfter,
        uint256 requestId,
        uint256 amount,
        address token,
        address receiver
    ) public returns (bool isValid) {
        RequestData memory data = requestSessions[smartAccount][requestId];
        if (data.isApproved) {
            if (data.validAfter < block.timestamp) revert InvalidTime();
            if (data.validUntil > block.timestamp) revert InvalidTime();
            if (data.receiver != receiver) revert InvalidAddr();
            if (data.tokenAddr != token) revert InvalidAddr();
            if (data.maxAmount == 0) revert InvalidAmount();
            requestSessions[smartAccount][requestId].maxAmount -= amount;

            isValid = true;
        } else {
            RequestData memory newRequest = RequestData(
                false,
                validUntil,
                validAfter,
                amount,
                receiver,
                token
            );
            setRequestSessions(newRequest);

            isValid = false;
        }
    }

    /**
     * @dev returns the SessionStorage object for a given smartAccount
     */
    function getRequestData(
        address smartAccount,
        uint256 requestId
    ) external view returns (RequestData memory) {
        return requestSessions[smartAccount][requestId];
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
