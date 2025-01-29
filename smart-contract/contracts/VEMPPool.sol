// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity =0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

// MasterChef is the master of VEMP. He can make VEMP and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once VEMP is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract VEMPPool is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        uint256 allocPoint; // How many allocation points assigned to this pool. VEMPs to distribute per block.
        uint256 lastRewardBlock; // Last block number that VEMPs distribution occurs.
        uint256 accVEMPPerShare; // Accumulated VEMPs per share, times 1e12. See below.
    }

    // VEMP tokens created per block.
    uint256 public VEMPPerBlock;

    // Info of each pool.
    PoolInfo public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    // The block number when VEMP mining starts.
    uint256 public startBlock;
    // total LP staked
    uint256 public totalVEMPStaked;
    // reward end block number
    uint256 public rewardEndBlock;

    mapping(address => bool) public blackListUser;
    mapping(address => uint256) public pendingClaimReward;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event RewardPerBlock(uint256 oldRewardPerBlock, uint256 newRewardPerBlock);
    event BlackListAddressEvent(address _user, bool _status);
    event RewardDistributeEvent(address _to, uint256 _amount, uint256 _pendingReward, uint256 _totalReward);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address initialOwner,
        uint256 _VEMPPerBlock,
        uint256 _startBlock
    ) public initializer {
        require(
            initialOwner != address(0),
            "VEMPLockContract: Invalid Owner Address"
        );

        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

        VEMPPerBlock = _VEMPPerBlock;
        startBlock = _startBlock;
        rewardEndBlock = 0;

        uint256 lastRewardBlock = block.number > startBlock
            ? block.number
            : startBlock;
        totalAllocPoint = totalAllocPoint + 100;
        poolInfo.allocPoint = 100;
        poolInfo.lastRewardBlock = lastRewardBlock;
        poolInfo.accVEMPPerShare = 0;
    }

    //to recieve ETH from admin
    receive() external payable {}

    function blackListAddress(address _user, bool _status) public onlyOwner {
        require(_user != address(0), "Inavlid User Address");
        require(blackListUser[_user] != _status, "Already in same status");
        blackListUser[_user] = _status;

        emit BlackListAddressEvent(_user, _status);
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(
        uint256 _from,
        uint256 _to
    ) public pure returns (uint256) {
        if (_to >= _from) {
            return _to - _from;
        } else {
            return _from - _to;
        }
    }

    // View function to see pending VEMPs on frontend.
    function pendingVEMP(address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[_user];
        uint256 accVEMPPerShare = pool.accVEMPPerShare;
        uint256 rewardBlockNumber = block.number;

        uint256 lpSupply = totalVEMPStaked;
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(
                pool.lastRewardBlock,
                rewardBlockNumber
            );
            uint256 VEMPReward = ((multiplier *
                VEMPPerBlock *
                pool.allocPoint) / totalAllocPoint);
            accVEMPPerShare =
                accVEMPPerShare +
                ((VEMPReward * 1e12) / lpSupply);
        }
        return (((user.amount * accVEMPPerShare) / 1e12) - user.rewardDebt);
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool() internal {
        PoolInfo storage pool = poolInfo;

        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 rewardBlockNumber = block.number;

        uint256 lpSupply = totalVEMPStaked;
        if (lpSupply == 0) {
            pool.lastRewardBlock = rewardBlockNumber;
            return;
        }
        uint256 multiplier = getMultiplier(
            pool.lastRewardBlock,
            rewardBlockNumber
        );
        uint256 VEMPReward = ((multiplier * VEMPPerBlock * pool.allocPoint) /
            totalAllocPoint);
        pool.accVEMPPerShare =
            pool.accVEMPPerShare +
            ((VEMPReward * 1e12) / lpSupply);
        pool.lastRewardBlock = rewardBlockNumber;
    }

    // Deposit LP tokens to MasterChef for VEMP allocation.
    function deposit(uint256 _amount) public payable nonReentrant {
        require(blackListUser[msg.sender] != true, "Not allowed");
        require(msg.value == _amount, "VEMP must be equal to staked amount");
        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[msg.sender];
        updatePool();

        if (user.amount > 0 || pendingClaimReward[msg.sender] > 0) {
            uint256 pending = (((user.amount * pool.accVEMPPerShare) / 1e12) -
                user.rewardDebt);
            safeVEMPTransfer(msg.sender, pending);
        }

        totalVEMPStaked = totalVEMPStaked + msg.value;
        user.amount = user.amount + msg.value;
        user.rewardDebt = ((user.amount * pool.accVEMPPerShare) / 1e12);

        emit Deposit(msg.sender, msg.value);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _amount) public nonReentrant {
        require(blackListUser[msg.sender] != true, "Not allowed");
        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount && _amount > 0, "withdraw: not good");
        updatePool();
        if (user.amount > 0 || pendingClaimReward[msg.sender] > 0) {
            uint256 pending = (((user.amount * pool.accVEMPPerShare) / 1e12) -
                user.rewardDebt);
            safeVEMPTransfer(msg.sender, pending);
        }

        user.amount = user.amount - _amount;
        user.rewardDebt = ((user.amount * pool.accVEMPPerShare) / 1e12);
        totalVEMPStaked = totalVEMPStaked - _amount;
        payable(msg.sender).transfer(_amount);

        emit Withdraw(msg.sender, _amount);
    }

    // Safe VEMP transfer function, just in case if rounding error causes pool to not have enough VEMPs.
    function safeVEMPTransfer(address _to, uint256 _amount) internal {
        uint256 VEMPBal = address(this).balance - totalVEMPStaked;
        if (_amount > VEMPBal) {
            pendingClaimReward[_to] =
                pendingClaimReward[_to] +
                (_amount - VEMPBal);
            payable(_to).transfer(VEMPBal);
            emit RewardDistributeEvent(_to, (_amount - VEMPBal) , pendingClaimReward[_to], _amount);
        } else {
            payable(_to).transfer(_amount);
            if (pendingClaimReward[_to] > 0) {
                uint256 VEMPBalAfter = address(this).balance - totalVEMPStaked;
                if (pendingClaimReward[_to] > VEMPBalAfter) {
                    pendingClaimReward[_to] =
                        pendingClaimReward[_to] -
                        VEMPBalAfter;
                    payable(_to).transfer(VEMPBalAfter);
                    emit RewardDistributeEvent(_to, VEMPBalAfter, pendingClaimReward[_to], _amount);
                } else {
                    payable(_to).transfer(pendingClaimReward[_to]);
                    emit RewardDistributeEvent(_to, pendingClaimReward[_to], 0, _amount);
                    pendingClaimReward[_to] = 0;
                }
            }
        }
    }

    // Update Reward per block
    function updateRewardPerBlock(uint256 _newRewardPerBlock) public onlyOwner {
        updatePool();
        emit RewardPerBlock(VEMPPerBlock, _newRewardPerBlock);
        VEMPPerBlock = _newRewardPerBlock;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
