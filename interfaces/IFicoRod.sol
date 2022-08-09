// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./IERC1155.sol";

interface IFicoRod is IERC1155 {
    function mint(address to, uint256 data) external returns (uint256);

    function burn(address from, uint256 tokenId) external;

    function setURI(string memory uri) external;

    function setOperator(address operatorAddress, bool value) external;

    function getRodData(uint256 tokenId) external view returns (uint256);
}
