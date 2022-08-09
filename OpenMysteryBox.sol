// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./interfaces/IFicoMysteryBox.sol";
import "./interfaces/IFicoRod.sol";
import "./security/ReentrancyGuard.sol";
import "./access/Runnable.sol";

contract OpenMysteryBox is ReentrancyGuard, Runnable {
    IFicoMysteryBox public mysteryBoxNft;
    IFicoRod public rodNft;

    uint256 public rodPerBox;
    uint256 public numberSpecialRod;
    uint256 defaultRodType;
    uint256 specialRodType;

    constructor(address mysteryBoxNFTAddress, address rodNFTAddress) {
        require(
            mysteryBoxNFTAddress != address(0),
            "mysteryBoxNFTAddress is zero address"
        );
        require(rodNFTAddress != address(0), "rodNFTAddress is zero address");

        mysteryBoxNft = IFicoMysteryBox(mysteryBoxNFTAddress);
        rodNft = IFicoRod(rodNFTAddress);
        rodPerBox = 7;
        numberSpecialRod = 1;
        defaultRodType = 0;
        specialRodType = 3;
    }

    function openBox(uint256 boxId) external nonReentrant whenRunning {
        require(
            mysteryBoxNft.balanceOf(msg.sender, boxId) > 0,
            "Not own the box"
        );
        require(rodPerBox > 0, "At least one rod per box");

        //Burn box
        mysteryBoxNft.burn(msg.sender, boxId);

        //Mint rod
        for (uint256 index = 0; index < rodPerBox; index++) {
            uint256 rodType = defaultRodType;
            if (index < numberSpecialRod) {
                rodType = specialRodType;
            }
            rodNft.mint(msg.sender, rodType);
        }
        emit OpenBox(boxId, rodPerBox);
    }

    function setMysteryBoxNFT(address newAddress) external onlyOwner {
        require(newAddress != address(0), "Address 0");
        mysteryBoxNft = IFicoMysteryBox(newAddress);
    }

    function setRodNFT(address newAddress) external onlyOwner {
        require(newAddress != address(0), "Address 0");
        rodNft = IFicoRod(newAddress);
    }

    function setRodPerBox(uint256 _rodPerBox) external onlyOwner {
        rodPerBox = _rodPerBox;
    }

    function setNumberSpecialRod(uint256 _numberSpecialRod) external onlyOwner {
        numberSpecialRod = _numberSpecialRod;
    }

    function setSpecialRodType(uint256 _specialRodType) external onlyOwner {
        specialRodType = _specialRodType;
    }

    event OpenBox(uint256 boxId, uint256 rodPerBox);
}
