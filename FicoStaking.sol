// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IFicoMysteryBox.sol";
import "./security/ReentrancyGuard.sol";
import "./access/Runnable.sol";

contract FicoStaking is ReentrancyGuard, Runnable {
    struct StakingPackage {
        uint256 id; //1: 7d 1b, 2: 15d 1b, 3: 2000
        uint256 rewardType; //1: box, 2: bait
        bool enable;
        uint256 rewardAmount;
        uint256 stakingAmount;
        uint256 durationInSeconds;
    }

    struct StakingDetail {
        uint256 id;
        uint256 grRewardId;
        uint256 grPersonalId;
        uint256 stakingPackage;
        address staker;
        uint256 stakingAmount;
        uint256 status; //1: staking, 2: claimed
        uint256 startDate;
        uint256 endDate;
    }

    address public _tokenAddress;
    address public _boxNftAddress;
    uint256 public _stakingCount = 0;
    uint256 public _totalBoxClaim = 0;
    uint256 public _totalBaitClaim = 0;
    mapping(uint256 => uint256) public _rwTypeTotalStaking;

    mapping(uint256 => StakingPackage) public _stakingPackages;
    mapping(uint256 => StakingDetail) public _stakingDetails;
    mapping(address => mapping(uint256 => StakingDetail))
        public _stakingDetailsGroupByAddress;
    mapping(uint256 => mapping(uint256 => StakingDetail))
        public _stakingDetailsGroupByReward;
    mapping(address => uint256) public _personalIds;
    mapping(uint256 => uint256) public _rewardTypeIds;
    mapping(uint256 => uint256) public _maxSlotRewards;

    constructor(address tokenAddress, address boxNftAddress) {
        require(tokenAddress != address(0), "Address 0");
        require(boxNftAddress != address(0), "Address 0");
        _tokenAddress = tokenAddress;
        _boxNftAddress = boxNftAddress;
        _isRunning = true;

        //Init data
        _stakingPackages[1] = StakingPackage(1, 1, true, 1, 400000e18, 604800);
        _stakingPackages[2] = StakingPackage(2, 1, true, 1, 200000e18, 1296000);
        _stakingPackages[3] = StakingPackage(3, 2, true, 2000, 10000e18, 864000);
        _maxSlotRewards[1] = 1000;
        _maxSlotRewards[2] = 9999999999999;
    }

    function staking(uint256 package)
        external
        whenRunning
        nonReentrant
        returns (uint256)
    {
        IERC20 tokenContract = IERC20(_tokenAddress);
        StakingPackage memory stakingPackage = _stakingPackages[package];
        require(stakingPackage.enable, "Staking package not support");
        require(
            _rewardTypeIds[stakingPackage.rewardType] + 1 <=
                _maxSlotRewards[stakingPackage.rewardType],
            "Out of slot"
        );
        require(
            tokenContract.balanceOf(msg.sender) >= stakingPackage.stakingAmount,
            "Not enough balance"
        );

        //Transfer token to lock
        require(
            tokenContract.transferFrom(
                msg.sender,
                address(this),
                stakingPackage.stakingAmount
            ),
            "Fail to transfer token to staking"
        );

        //Set staking detail
        _stakingCount += 1;
        _personalIds[msg.sender] += 1;
        _rewardTypeIds[stakingPackage.rewardType] += 1;
        StakingDetail memory stakingDetail = StakingDetail(
            _stakingCount,
            _rewardTypeIds[stakingPackage.rewardType],
            _personalIds[msg.sender],
            package,
            msg.sender,
            stakingPackage.stakingAmount,
            1,
            block.timestamp,
            block.timestamp + stakingPackage.durationInSeconds
        );
        _stakingDetails[_stakingCount] = stakingDetail;
        _stakingDetailsGroupByAddress[msg.sender][
            _personalIds[msg.sender]
        ] = stakingDetail;
        _stakingDetailsGroupByReward[stakingPackage.rewardType][
            _rewardTypeIds[stakingPackage.rewardType]
        ] = stakingDetail;

        emit StakingCreated(
            stakingDetail.id,
            stakingDetail.grRewardId,
            stakingDetail.grPersonalId,
            stakingDetail.stakingPackage,
            stakingDetail.staker,
            stakingDetail.stakingAmount,
            stakingDetail.status,
            stakingDetail.startDate,
            stakingDetail.endDate
        );
        return stakingDetail.id;
    }

    function claim(uint256 stakingId) external whenRunning nonReentrant {
        StakingDetail memory stakingDetail = _stakingDetails[stakingId];
        require(stakingDetail.status == 1, "Not ready to claim");
        require(stakingDetail.endDate <= block.timestamp, "Not yet claimed");
        require(stakingDetail.staker == msg.sender, "Not authorized to claim");

        StakingPackage memory stakingPackage = _stakingPackages[
            stakingDetail.stakingPackage
        ];
        //Set status staking detail
        stakingDetail.status = 2;
        _stakingDetails[stakingId] = stakingDetail;

        _stakingDetailsGroupByAddress[msg.sender][
            stakingDetail.grPersonalId
        ] = stakingDetail;

        _stakingDetailsGroupByReward[stakingPackage.rewardType][
            stakingDetail.grRewardId
        ] = stakingDetail;

        //Release staking token
        IERC20 tokenContract = IERC20(_tokenAddress);
        require(
            tokenContract.transfer(msg.sender, stakingDetail.stakingAmount),
            "Fail to release staking token"
        );

        //Release reward
        IFicoMysteryBox mysteryBoxNft = IFicoMysteryBox(_boxNftAddress);
        if (stakingPackage.rewardType == 1) {
            //Box
            _totalBoxClaim += 1;
            uint256 boxId = mysteryBoxNft.mint(msg.sender);
            emit ClaimBox(stakingId, msg.sender, boxId);
        } else {
            //Bait
            _totalBaitClaim += 1;
            emit ClaimBait(stakingId, msg.sender, stakingPackage.rewardAmount);
        }
    }

    function getStakingByReward(
        uint256 reward,
        uint256 limit,
        uint256 page
    ) external view returns (StakingDetail[] memory, uint256) {
        uint256 total = _rewardTypeIds[reward];
        uint256 idx = 0;
        StakingDetail[] memory stakingDetails = new StakingDetail[](limit);
        for (uint256 i = page * limit; i < page * limit + limit; i++) {
            if (total >= i) {
                StakingDetail
                    memory stakingDetail = _stakingDetailsGroupByReward[reward][
                        total - i
                    ];
                if (stakingDetail.grRewardId > 0) {
                    stakingDetails[idx++] = stakingDetail;
                }
            }
        }
        return (stakingDetails, total);
    }

    function getStakingByAddress(uint256 limit, uint256 page)
        external
        view
        returns (StakingDetail[] memory, uint256)
    {
        uint256 total = _personalIds[msg.sender];
        uint256 idx = 0;
        StakingDetail[] memory stakingDetails = new StakingDetail[](limit);
        for (uint256 i = page * limit; i < page * limit + limit; i++) {
            if (total >= i) {
                StakingDetail
                    memory stakingDetail = _stakingDetailsGroupByAddress[
                        msg.sender
                    ][total - i];
                if (stakingDetail.grRewardId > 0) {
                    stakingDetails[idx++] = stakingDetail;
                }
            }
        }
        return (stakingDetails, total);
    }

    function setTokenAddress(address newAddress) external onlyOwner {
        require(newAddress != address(0), "Zero address");
        _tokenAddress = newAddress;
    }

    function setBoxAddress(address newAddress) external onlyOwner {
        require(newAddress != address(0), "Zero address");
        _boxNftAddress = newAddress;
    }

    function setStakingPackage(
        uint256 id,
        uint256 rewardType,
        bool enable,
        uint256 rewardAmount,
        uint256 stakingAmount,
        uint256 durationInSeconds
    ) external onlyOwner {
        require(stakingAmount > 0, "Invalid staking amount");
        require(durationInSeconds > 0, "Invalid duration in second");
        StakingPackage memory stakingPackage = _stakingPackages[id];
        stakingPackage.rewardType = rewardType;
        stakingPackage.enable = enable;
        stakingPackage.rewardAmount = rewardAmount;
        stakingPackage.stakingAmount = stakingAmount;
        stakingPackage.durationInSeconds = durationInSeconds;
        _stakingPackages[id] = stakingPackage;
    }

    function setMaxSlotOfReward(uint256 reward, uint256 maxSlot)
        external
        onlyOwner
    {
        require(maxSlot > 0, "Invalid max slot");
        _maxSlotRewards[reward] = maxSlot;
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

    event StakingCreated(
        uint256 id,
        uint256 packageId,
        uint256 personalId,
        uint256 stakingPackage,
        address staker,
        uint256 stakingAmount,
        uint256 status,
        uint256 startDate,
        uint256 endDate
    );
    event ClaimBait(uint256 id, address staker, uint256 amountBait);
    event ClaimBox(uint256 id, address staker, uint256 boxId);
}
