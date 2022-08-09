// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IERC165.sol";
import "./interfaces/IERC1155.sol";
import "./security/ReentrancyGuard.sol";
import "./access/Runnable.sol";
import "./ERC1155Receiver.sol";

contract FicoMarketplace is ReentrancyGuard, Runnable, ERC1155Receiver {
    struct OrderDetail {
        address owner;
        address buyer;
        uint256 tokenId;
        uint256 nftType;
        address nftAddress;
        uint256 price;
        uint256 amount;
        bool sold;
        bool enable;
    }

    struct NftType {
        address nftAddress;
        bool enable;
    }

    bytes4 public constant ERC1155_ERC165 = 0xd9b67a26;
    address public _ficoTokenAddress;
    address public _feeRecepientAddress;
    uint256 public _marketFeePercent;
    uint256 public _orderCount = 0;

    mapping(uint256 => OrderDetail) public _orders;
    mapping(uint256 => NftType) public _nftSupports; //1: rod, 2: fish, 3: material, 4: mystery box

    constructor(
        address tokenAddress,
        address mysteryBoxNftAddress,
        address feeRecepientAddress
    ) {
        require(tokenAddress != address(0), "Address 0");
        require(mysteryBoxNftAddress != address(0), "Address 0");
        _ficoTokenAddress = tokenAddress;
        _feeRecepientAddress = feeRecepientAddress;
        _nftSupports[4] = NftType(mysteryBoxNftAddress, true);
        _marketFeePercent = 5; //5%
        _isRunning = true;
    }

    function createOrder(
        uint256 nftType,
        uint256 tokenId,
        uint256 unitPrice,
        uint256 amount
    ) external whenRunning nonReentrant returns (uint256) {
        require(unitPrice > 0, "Can not create order with zero price");
        require(amount > 0, "Can not create order with zero amount");
        require(
            _nftSupports[nftType].nftAddress != address(0),
            "Nft type not support"
        );
        require(_nftSupports[nftType].enable, "Nft type not enable");

        IERC1155 nftContract = IERC1155(_nftSupports[nftType].nftAddress);
        require(
            nftContract.balanceOf(msg.sender, tokenId) > 0,
            "You have no permission to create order for this token"
        );
        require(
            nftContract.balanceOf(msg.sender, tokenId) >= amount,
            "Invalid amount"
        );

        uint256 _price = unitPrice * amount;
        //Create order with unique orderId
        _orderCount += 1;
        _orders[_orderCount] = OrderDetail(
            msg.sender,
            address(0),
            tokenId,
            nftType,
            _nftSupports[nftType].nftAddress,
            _price,
            amount,
            false,
            true
        );

        //Transfer rod to this contract
        nftContract.safeTransferFrom(
            msg.sender,
            address(this),
            tokenId,
            amount,
            ""
        );

        emit OrderCreated(
            _orderCount,
            nftType,
            _nftSupports[nftType].nftAddress,
            msg.sender,
            tokenId,
            amount,
            _price
        );
        return _orderCount;
    }

    function cancelOrder(uint256 orderId)
        external
        whenRunning
        nonReentrant
        returns (bool)
    {
        OrderDetail memory orderDetail = _orders[orderId];
        require(orderDetail.enable, "Order not found");
        require(!orderDetail.sold, "Already sold");
        require(orderDetail.owner == msg.sender, "Forbidden to cancel order");

        //Cancel order
        orderDetail.enable = false;
        _orders[orderId] = orderDetail;

        //Transfer rod to owner
        IERC1155 ficoRodContract = IERC1155(orderDetail.nftAddress);
        ficoRodContract.safeTransferFrom(
            address(this),
            msg.sender,
            orderDetail.tokenId,
            orderDetail.amount,
            ""
        );

        emit OrderCanceled(orderId, orderDetail.tokenId, orderDetail.amount);
        return true;
    }

    function purchase(uint256 orderId)
        external
        whenRunning
        nonReentrant
        returns (uint256)
    {
        IERC20 ficoTokenContract = IERC20(_ficoTokenAddress);
        OrderDetail memory orderDetail = _orders[orderId];
        require(msg.sender != orderDetail.owner, "Buyer can not be the same as seller");
        require(orderDetail.enable, "Order not found");
        require(!orderDetail.sold, "Already sold");
        require(
            _nftSupports[orderDetail.nftType].enable,
            "Nft type not enable"
        );
        require(
            ficoTokenContract.balanceOf(msg.sender) >= orderDetail.price,
            "Not enough balance"
        );

        //Finish order
        orderDetail.sold = true;
        orderDetail.buyer = msg.sender;
        _orders[orderId] = orderDetail;

        uint256 ownerReceived = orderDetail.price;
        uint256 feeAmount = 0;
        if (_marketFeePercent > 0) {
            feeAmount = (orderDetail.price * _marketFeePercent) / 100;
            ownerReceived -= feeAmount;
            require(
                ficoTokenContract.transferFrom(
                    msg.sender,
                    _feeRecepientAddress,
                    feeAmount
                ),
                "Fail to transfer fee"
            );
        }

        //Transfer token to owner
        require(
            ficoTokenContract.transferFrom(
                msg.sender,
                orderDetail.owner,
                ownerReceived
            ),
            "Fail to transfer token to owner"
        );

        //Transfer rod to buyer
        IERC1155(orderDetail.nftAddress).safeTransferFrom(
            address(this),
            msg.sender,
            orderDetail.tokenId,
            orderDetail.amount,
            ""
        );

        emit Purchased(orderId, msg.sender, ownerReceived, feeAmount);
        return orderDetail.price;
    }

    function setFeeRecepientAddress(address newAddress) external onlyOwner {
        require(newAddress != address(0), "Zero address");
        _feeRecepientAddress = newAddress;
    }

    function setFicoTokenAddress(address newAddress) external onlyOwner {
        require(newAddress != address(0), "Zero address");
        _ficoTokenAddress = newAddress;
    }

    function setFeePercent(uint256 marketFeePercent) external onlyOwner {
        _marketFeePercent = marketFeePercent;
        emit UpdatedFee(_marketFeePercent);
    }

    function setNftSupport(
        uint256 nftType,
        address nftAddress,
        bool enable
    ) external onlyOwner {
        require(nftAddress != address(0), "Zero address");
        require(
            IERC165(nftAddress).supportsInterface(ERC1155_ERC165),
            "Interface not support"
        );
        _nftSupports[nftType].nftAddress = nftAddress;
        _nftSupports[nftType].enable = enable;
    }

    function setNftSupportEnable(uint256 nftType, bool enable)
        external
        onlyOwner
    {
        _nftSupports[nftType].enable = enable;
    }

    function withdrawToken(address tokenAddress, address recepient)
        external
        onlyOwner
    {
        IERC20 token = IERC20(tokenAddress);
        require(
            token.transfer(recepient, token.balanceOf(address(this))),
            "Failure withdraw"
        );
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    event UpdatedFee(uint256 marketFeePercent);
    event OrderCreated(
        uint256 orderId,
        uint256 nftType,
        address nftAddress,
        address seller,
        uint256 tokenId,
        uint256 amount,
        uint256 price
    );
    event Purchased(
        uint256 orderId,
        address buyer,
        uint256 ownerReceived,
        uint256 fee
    );
    event OrderCanceled(uint256 orderId, uint256 tokenId, uint256 amount);
}
