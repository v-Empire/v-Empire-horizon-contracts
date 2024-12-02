// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

// VEMPVault is the master of VEMP. He can make VEMP and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once VEMP is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract VEMPVault is
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
        uint256 accVEMPPerShare; // Accumulated VEMPs per share, times 1e18. See below.
    }

    // VEMP tokens created per block.
    uint256 public VEMPPerBlock;

    // Info of each pool.
    PoolInfo public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;
    // Info of each user that is whitelisted.
    mapping(address => bool) public isWhitelisted;
    // Info of each user for pending reward.
    mapping(address => uint256) public pendingClaimReward;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;
    // The block number when VEMP mining starts.
    uint256 public startBlock;
    // total LP staked
    uint256 public totalVEMPStaked;
    // Reward receiver address
    address public receiver;

    // Event emitted whenever a user's whitelist status is updated
    event WhitelistUpdated(address indexed user, bool status);
    event Claim(address user, address receiver, uint256 reward);
    event RewardPerBlock(uint256 oldRewardPerBlock, uint256 newRewardPerBlock);
    event ReceiverUpdated(address oldReceiver, address newReceiver);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier isWhitelistAddress() {
        require(isWhitelisted[msg.sender], "VEMPVault: caller is not whitelist");
        _;
    }

    function initialize(
        address initialOwner,
        address _receiver,
        uint256 _VEMPPerBlock,
        uint256 _startBlock
    ) public initializer {
        require(
            initialOwner != address(0),
            "VEMPLockContract: Invalid Owner Address"
        );
        require(_receiver != address(0), "VEMPVault: Invalid receiver address");

        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

        VEMPPerBlock = _VEMPPerBlock;
        startBlock = _startBlock;
        receiver = _receiver;

        uint256 lastRewardBlock = block.number > startBlock
            ? block.number
            : startBlock;
        totalAllocPoint = totalAllocPoint + 100;
        poolInfo.allocPoint = 100;
        poolInfo.lastRewardBlock = lastRewardBlock;
        poolInfo.accVEMPPerShare = 0;

        UserInfo storage user = userInfo[receiver];
        totalVEMPStaked = 1 ether;
        user.amount = 1 ether;
        user.rewardDebt = ((user.amount * poolInfo.accVEMPPerShare) / 1e18);
    }

    //to recieve ETH from admin
    receive() external payable {
        require(msg.sender == owner(), "VEMPVault: Invalid Reward Sender");
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
    function pendingVEMP() external view returns (uint256) {
        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[receiver];
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
                ((VEMPReward * 1e18) / lpSupply);
        }
        return (((user.amount * accVEMPPerShare) / 1e18) - user.rewardDebt);
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
            ((VEMPReward * 1e18) / lpSupply);
        pool.lastRewardBlock = rewardBlockNumber;
    }

    // Claim VEMP Reward tokens to VEMPVault for VEMP allocation.
    function claimPendingReward() public nonReentrant isWhitelistAddress {
        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[receiver];
        updatePool();

        uint256 pending = 0;
        if (user.amount > 0 || pendingClaimReward[receiver] > 0) {
            pending = (((user.amount * pool.accVEMPPerShare) / 1e18) -
                user.rewardDebt);
            safeVEMPTransfer(receiver, pending);
        }

        user.rewardDebt = ((user.amount * pool.accVEMPPerShare) / 1e18);

        emit Claim(msg.sender, receiver, pending);
    }

    // Safe VEMP transfer function, just in case if rounding error causes pool to not have enough VEMPs.
    function safeVEMPTransfer(address _to, uint256 _amount) internal {
        uint256 VEMPBal = address(this).balance;
        if (_amount > VEMPBal) {
            pendingClaimReward[_to] = pendingClaimReward[_to] + (_amount - VEMPBal);
            payable(_to).transfer(VEMPBal);
        } else {
            payable(_to).transfer(_amount);
            if (pendingClaimReward[_to] > 0) {
                uint256 VEMPBalAfter = address(this).balance;
                if (pendingClaimReward[_to] > VEMPBalAfter) {
                    pendingClaimReward[_to] = pendingClaimReward[_to] - VEMPBalAfter;
                    payable(_to).transfer(VEMPBalAfter);
                } else {
                    payable(_to).transfer(pendingClaimReward[_to]);
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

    /**
     * @dev Updates the reward receiver address. Transfers the `userInfo` from the
     * old receiver to the new receiver.
     * @param _newReceiver The address of the new reward receiver.
     */
    function updateReceiver(address _newReceiver) public onlyOwner {
        require(_newReceiver != address(0), "VEMPVault: Invalid receiver address");
        require(_newReceiver != receiver, "VEMPVault: Same receiver address");

        UserInfo storage oldUser = userInfo[receiver];
        UserInfo storage newUser = userInfo[_newReceiver];

        updatePool();
        // Transfer user info to the new receiver
        newUser.amount = oldUser.amount;
        newUser.rewardDebt = oldUser.rewardDebt;
        pendingClaimReward[_newReceiver] = pendingClaimReward[receiver];
        pendingClaimReward[receiver] = 0;

        // Reset the old receiver's user info
        oldUser.amount = 0;
        oldUser.rewardDebt = 0;

        // Update the receiver address
        address oldReceiver = receiver;
        receiver = _newReceiver;

        emit ReceiverUpdated(oldReceiver, _newReceiver);
    }

    /**
     * @notice Updates the whitelist status of a given address.
     * @param _user The address to be added to or removed from the whitelist.
     * @param _status The desired whitelist status (true to whitelist, false to remove).
     */
    function whitelistAddress(address _user, bool _status) public onlyOwner {
        require(_user != address(0), "Invalid address");
        isWhitelisted[_user] = _status;

        // Emit the event
        emit WhitelistUpdated(_user, _status);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
