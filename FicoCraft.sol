// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IERC165.sol";
import "./interfaces/IFicoRod.sol";
import "./security/ReentrancyGuard.sol";
import "./access/Runnable.sol";
import "./ERC1155Receiver.sol";

contract FicoCraft is ReentrancyGuard, Runnable, ERC1155Receiver {
    struct CraftDetail {
        uint256 craftId;
        uint32 numOfRod;
        uint32 status; //0: new, 1: valid, 2: invalid, 3: claimed
        uint32 craftRodType; //1: common, 2: rare
        uint32 craftRodResult;
        uint256[] rods;
        address crafter;
    }

    bytes4 public constant ERC1155_ERC165 = 0xd9b67a26;
    address public _ficoTokenAddress;
    address public _rodAddress;
    address public _feeRecepientAddress;
    mapping(uint256 => uint256) public _craftFees;
    uint256 public _craftBnbFee;
    uint256 public _craftCount = 0;
    mapping(uint32 => uint32) public _numOfRods;

    mapping(uint256 => CraftDetail) public _crafts;
    mapping(address => bool) public _operators;

    modifier onlyOperator() {
        require(_operators[msg.sender], "Forbidden");
        _;
    }

    constructor(
        address tokenAddress,
        address rodAddress,
        address feeRecepientAddress
    ) {
        require(feeRecepientAddress != address(0), "Address 0");
        require(tokenAddress != address(0), "Address 0");
        require(rodAddress != address(0), "Address 0");
        _ficoTokenAddress = tokenAddress;
        _feeRecepientAddress = feeRecepientAddress;
        _rodAddress = rodAddress;
        _numOfRods[1] = 3;
        _craftFees[1] = 1200e18;
        _numOfRods[2] = 4;
        _craftFees[2] = 2400e18;
        _craftBnbFee = 0.0006e18;
        _isRunning = true;
        _operators[msg.sender] = true;
    }

    function createCraft(uint32 rodType, uint256[] calldata rods)
        external
        payable
        whenRunning
        nonReentrant
    {
        require(msg.value >= _craftBnbFee, "Not enough default fee");
        require(rodType == 1 || rodType == 2, "Invalid rod type");
        require(rods.length == _numOfRods[rodType], "Invalid rod amount");

        //Set variable
        _craftCount += 1;
        _crafts[_craftCount] = CraftDetail(
            _craftCount,
            _numOfRods[rodType],
            0,
            0,
            0,
            rods,
            msg.sender
        );

        //Transfer fee
        IERC20 tokenContract = IERC20(_ficoTokenAddress);
        //Transfer fee
        require(
            tokenContract.transferFrom(
                msg.sender,
                _feeRecepientAddress,
                _craftFees[rodType]
            ),
            "Fail to transfer fee"
        );

        //Batch transfer rod to contract
        uint256[] memory quantity = new uint256[](_numOfRods[rodType]);
        for (uint256 i = 0; i < _numOfRods[rodType]; i++) {
            quantity[i] = 1;
        }
        IERC1155 rodContract = IERC1155(_rodAddress);
        rodContract.safeBatchTransferFrom(
            msg.sender,
            address(this),
            rods,
            quantity,
            ""
        );

        emit CraftCreated(
            _craftCount,
            _numOfRods[rodType],
            rodType,
            rods,
            msg.sender
        );
    }

    function updateCraft(
        uint256 craftId,
        uint32 status,
        uint32 rodType,
        uint32 rodData
    ) external whenRunning nonReentrant onlyOperator {
        require(craftId > 0, "Invalid craft id");
        require(_crafts[craftId].status == 0, "Craft can not update");
        _crafts[craftId].status = status;
        _crafts[craftId].craftRodType = rodType;
        _crafts[craftId].craftRodResult = rodData;
    }

    function batchUpdateCraft(
        uint256[] calldata craftIds,
        uint32[] calldata statuses,
        uint32[] calldata rodTypes,
        uint32[] calldata rodDatas
    ) external whenRunning nonReentrant onlyOperator {
        require(craftIds.length == statuses.length, "Invalid length");
        require(craftIds.length == rodDatas.length, "Invalid length");
        for (uint256 i = 0; i < craftIds.length; i++) {
            if (_crafts[craftIds[i]].status == 0 && craftIds[i] > 0) {
                _crafts[craftIds[i]].status = statuses[i];
                _crafts[craftIds[i]].craftRodType = rodTypes[i];
                _crafts[craftIds[i]].craftRodResult = rodDatas[i];
            }
        }
    }

    function claim(uint256 craftId) external whenRunning nonReentrant {
        require(craftId > 0, "Invalid craft id");
        CraftDetail memory craftDetail = _crafts[craftId];
        require(
            craftDetail.status == 1 || craftDetail.status == 2,
            "Craft can not claim"
        );
        require(msg.sender == craftDetail.crafter, "Can not claim this craft");

        IFicoRod rodContract = IFicoRod(_rodAddress);
        uint32 status = craftDetail.status;
        craftDetail.status = 3;
        if (status == 1) {
            //Burn
            for (uint256 i = 0; i < craftDetail.numOfRod; i++) {
                rodContract.burn(address(this), craftDetail.rods[i]);
            }

            //Gen new rod
            uint256 newRodId = rodContract.mint(
                msg.sender,
                craftDetail.craftRodResult
            );
            emit Claim(craftId, craftDetail.status, newRodId);
        } else {
            //Invalid
            uint256[] memory quantity = new uint256[](craftDetail.numOfRod);
            for (uint256 i = 0; i < craftDetail.numOfRod; i++) {
                quantity[i] = 1;
            }
            rodContract.safeBatchTransferFrom(
                address(this),
                msg.sender,
                craftDetail.rods,
                quantity,
                ""
            );
            emit Claim(craftId, craftDetail.status, 0);
        }
    }

    function setFeeRecepientAddress(address newAddress) external onlyOwner {
        require(newAddress != address(0), "Zero address");
        _feeRecepientAddress = newAddress;
    }

    function setFicoTokenAddress(address newAddress) external onlyOwner {
        require(newAddress != address(0), "Zero address");
        _ficoTokenAddress = newAddress;
    }

    function setRodAddress(address newAddress) external onlyOwner {
        require(newAddress != address(0), "Zero address");
        _rodAddress = newAddress;
    }

    function setCraftFee(uint32 rodType, uint256 craftFee) external onlyOwner {
        _craftFees[rodType] = craftFee;
    }

    function setCraftBnbFee(uint256 craftBnbFee) external onlyOwner {
        _craftBnbFee = craftBnbFee;
    }

    function setNumOfRod(uint32 rodType, uint32 numOfRod) external onlyOwner {
        _numOfRods[rodType] = numOfRod;
    }

    function withdrawToken(address tokenAddress, address recepient)
        external
        onlyOwner
    {
        require(tokenAddress != address(0), "Token zero address");
        require(recepient != address(0), "Recepient zero address");
        IERC20 token = IERC20(tokenAddress);
        require(
            token.transfer(recepient, token.balanceOf(address(this))),
            "Failure withdraw"
        );
    }

    function withdrawBnb() external onlyOwner {
        address payable sender = payable(msg.sender);
        sender.transfer(address(this).balance);
    }

    function setOperator(address operatorAddress, bool value)
        external
        onlyOwner
    {
        require(
            operatorAddress != address(0),
            "operatorAddress is zero address"
        );
        _operators[operatorAddress] = value;
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) external virtual override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) external virtual override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    event CraftCreated(
        uint256 craftId,
        uint32 numOfRod,
        uint32 rodType,
        uint256[] rodIds,
        address crafter
    );
    event Claim(uint256 craftId, uint32 status, uint256 newRodId);
}
