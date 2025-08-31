// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

library Error {
    error INVALID_ADDRESS();
    error ONLY_OWNER();
    error ZERO_AMOUNT_INVALID_AMOUNT();
    error EMPLOYEE_ALREADY_ACTIVE();
    error INVALID_INVITE_CODE();
    error INVITE_USED();
    error WITHDRAWAL_PAUSED();
    error INSUFFICIENT_BALANCE();
    error INVALID_ID();
    error NOT_VALID_ORGANISATION();
}
