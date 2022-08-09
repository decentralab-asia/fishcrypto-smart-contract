// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IERC721.sol";
import "./interfaces/IFicoLakeTheme.sol";
import "./security/ReentrancyGuard.sol";
import "./access/Runnable.sol";

contract FicoThemeBoxSale is ReentrancyGuard, Runnable {
    IFicoLakeTheme public _themeNft;
    uint256 public _startTimeWl;
    uint256 public _endTimeWl;
    uint256 public _startTime;
    mapping(uint32 => uint256) public _priceByLevels;
    uint256 public _maxBox;
    uint256 public _purchasedBox;
    uint256 public _boxsPerUser;
    mapping(address => uint256) public _userBoxCounts;
    mapping(address => bool) public _whiteList;

    constructor(
        address themeBoxNFTAddress,
        uint256 maxBox, // 10000
        uint256 startTimeWl, // 1649079900
        uint256 endTimeWl, // 1649080800
        uint256 startTime, // 1649080800
        uint256 boxPerUser // 5
    ) {
        require(
            themeBoxNFTAddress != address(0),
            "themeBoxNFTAddress is zero address"
        );

        _themeNft = IFicoLakeTheme(themeBoxNFTAddress);
        _maxBox = maxBox;
        _startTime = startTime;
        _startTimeWl = startTimeWl;
        _endTimeWl = endTimeWl;
        _boxsPerUser = boxPerUser;
        _priceByLevels[1] = 0.0333e18;
        _priceByLevels[2] = 0.0378e18;
        _priceByLevels[3] = 0.0422e18;
        _priceByLevels[4] = 0.0489e18;
        _priceByLevels[5] = 0.0556e18;
    }

    function purchase(uint256 quantity)
        external
        payable
        nonReentrant
        whenRunning
    {
        uint256 price = getPriceByLevel();
        require(quantity > 0, "Invalid quantity");
        require(_purchasedBox + quantity <= _maxBox, "Max box");
        require(msg.value >= price * quantity, "Not enough BNB");
        require(
            (_startTimeWl <= block.timestamp &&
                _endTimeWl >= block.timestamp) ||
                (_startTime <= block.timestamp),
            "Can not purchase this time"
        );
        if (_startTimeWl <= block.timestamp && _endTimeWl >= block.timestamp) {
            require(_whiteList[msg.sender], "User not in white list");
        }
        require(
            _userBoxCounts[msg.sender] + quantity <= _boxsPerUser,
            "Exceeded the limit of boxes purchased"
        );
        _purchasedBox += quantity;
        _userBoxCounts[msg.sender] += quantity;

        //Mint
        for (uint256 index = 0; index < quantity; index++) {
            //Mint NFT
            uint256 themeBoxTokenId = _themeNft.mint(msg.sender);
            emit Purchased(msg.sender, themeBoxTokenId, price);
        }
    }

    function getPriceByLevel() public view returns (uint256) {
        uint256 purchasedBox = _purchasedBox;
        if (purchasedBox >= 0 && purchasedBox <= 2000) {
            return _priceByLevels[1];
        }
        if (purchasedBox >= 2001 && purchasedBox <= 4000) {
            return _priceByLevels[2];
        }
        if (purchasedBox >= 4001 && purchasedBox <= 6000) {
            return _priceByLevels[3];
        }
        if (purchasedBox >= 6001 && purchasedBox <= 8000) {
            return _priceByLevels[4];
        }
        return _priceByLevels[5];
    }

    function setWhiteList(address[] memory addrs, bool status)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < addrs.length; i++) {
            _whiteList[addrs[i]] = status;
        }
    }

    function isWhiteList(address addr) external view returns (bool) {
        return _whiteList[addr];
    }

    function setSaleInfo(
        uint256 startTimeWl,
        uint256 endTimeWl,
        uint256 startTime,
        uint256 maxBox
    ) external onlyOwner {
        _startTimeWl = startTimeWl;
        _endTimeWl = endTimeWl;
        _startTime = startTime;
        _maxBox = maxBox;
    }

    function setSalePrice(uint256[] calldata prices) external onlyOwner {
        require(prices.length == 5, "Invalid size");
        for (uint32 i = 0; i < 5; i++) {
            require(prices[i] > 0, "Invalid price");
            _priceByLevels[i + 1] = prices[i];
        }
    }

    function getSaleInfo(address from)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        uint256 userBoxCount = _userBoxCounts[from];
        return (
            _startTimeWl,
            _endTimeWl,
            _startTime,
            _boxsPerUser,
            _maxBox,
            _purchasedBox,
            userBoxCount
        );
    }

    function setThemeBoxNFT(address newAddress) external onlyOwner {
        require(newAddress != address(0), "Address 0");
        _themeNft = IFicoLakeTheme(newAddress);
    }

    function setBoxPerUser(uint256 boxPerUser) external onlyOwner {
        require(boxPerUser > 0, "boxPerUser is 0");
        _boxsPerUser = boxPerUser;
    }

    function withdrawToken(
        address tokenAddress,
        address recepient,
        uint256 value
    ) external onlyOwner {
        require(
            IERC20(tokenAddress).transfer(recepient, value),
            "Withdraw fail"
        );
    }

    function withdrawBnb() external onlyOwner {
        address payable sender = payable(msg.sender);
        sender.transfer(address(this).balance);
    }

    event Purchased(address account, uint256 tokenId, uint256 price);
}
