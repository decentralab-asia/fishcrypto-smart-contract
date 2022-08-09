// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC1155.sol";
import "./interfaces/IFicoMysteryBox.sol";
import "./access/Ownable.sol";
import "./access/Pauseable.sol";
import "./access/Pauseable.sol";

contract FicoMysteryBox is IFicoMysteryBox, ERC1155, Pausable, Ownable {
    uint256 public totalSupply = 0;
    string public name;
    string public symbol;

    modifier onlyOperator() {
        require(_operators[msg.sender], "Forbidden");
        _;
    }

    mapping(address => bool) public _operators;

    constructor(
        string memory _name,
        string memory _symbol,
        string memory uri
    ) ERC1155(uri) {
        name = _name;
        symbol = _symbol;
        _operators[msg.sender] = true;
    }

    function mint(address to) public override onlyOperator returns (uint256) {
        totalSupply += 1;
        _mint(to, totalSupply, 1, "");
        return totalSupply;
    }

    function burn(address from, uint256 tokenId)
        external
        override
        onlyOperator
    {
        _burn(from, tokenId, 1);
    }

    function setURI(string memory _uri) external override onlyOwner {
        _setURI(_uri);
    }

    function setOperator(address operatorAddress, bool value)
        external
        override
        onlyOwner
    {
        _operators[operatorAddress] = value;
        emit OperatorSetted(operatorAddress, value);
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);

        require(!paused(), "ERC1155Pausable: token transfer while paused");
    }

    event OperatorSetted(address operatorAddress, bool value);
}
