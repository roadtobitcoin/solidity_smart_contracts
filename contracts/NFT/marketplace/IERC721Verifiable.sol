// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/IERC721.sol";


interface IERC721Verifiable is IERC721 {
    function verifyFingerprint(uint256, bytes32) external view returns (bool);
}
