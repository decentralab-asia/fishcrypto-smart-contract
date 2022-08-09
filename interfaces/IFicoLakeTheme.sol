// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./IERC1155.sol";

interface IFicoLakeTheme is IERC1155 {
    function mint(address to) external returns (uint256);

    function burn(address from, uint256 tokenId) external;

    function setURI(string memory _uri) external;

    function setOperator(address operatorAddress, bool value) external;
}
