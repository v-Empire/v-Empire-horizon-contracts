// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract VEMPLockContract is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    /// @notice Address of the ERC20 native token (VEMP token)
    address public vempToken;

    /// @notice Mapping to keep track of the user lock vemp tokens for each user
    mapping(address => uint256) public userVEMPLock;

    /// @notice Total VEMP tokens locked by all users
    uint256 public totalVempLock;

    /// @notice Total VEMP tokens withdrawn by the admin
    uint256 public totalWithdrawTokens;

    /// @dev Event emitted when a user's lock vemp tokens
    event UserLockVempTokens(address[] indexed user, uint256[] amount);

    /// @dev Event emitted when a user locks VEMP tokens
    event LockVemp(address indexed user, uint256 amount);

    /// @dev Event emitted when the owner withdraws tokens from the contract
    event WithdrawTokensByAdmin(address indexed to, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Creates a VEMPLockContract contract.
     * @param token_ The address of the ERC20 native token contract.
     * @param initialOwner The address of the initial owner of the contract.
     */
    function initialize(
        address token_,
        address initialOwner
    ) public initializer {
        require(
            initialOwner != address(0),
            "VEMPLockContract: Invalid Owner Address"
        );
        require(token_ != address(0), "VEMPLockContract: Invalid VEMP Address");

        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

        vempToken = token_;
    }

    /**
     * @notice Set the lock amount for a specific user.
     * @param _user The address of the user.
     * @param _amount The maximum number of tokens the user can claim.
     * @dev Only the owner can call this function.
     */
    function UpdateUserLockAmount(
        address[] memory _user,
        uint256[] memory _amount
    ) public onlyOwner {
        require(
            _user.length == _amount.length,
            "VEMPLockContract: Invalid Data"
        );
        for (uint i = 0; i < _user.length; i++) {
            require(
                _user[i] != address(0),
                "VEMPLockContract: Invalid User Address"
            );
            userVEMPLock[_user[i]] = _amount[i];
        }
        emit UserLockVempTokens(_user, _amount);
    }

    /**
     * @notice Allows users to lock their VEMP tokens in the contract.
     * @param _amount The amount of VEMP tokens to lock.
     */
    function lockVEMP(uint256 _amount) public {
        require(_amount > 0, "VEMPLockContract: Invalid Amount");
        require(
            IERC20(vempToken).transferFrom(msg.sender, address(this), _amount),
            "VEMPLockContract: Transfer Failed"
        );

        userVEMPLock[msg.sender] += _amount;
        totalVempLock += _amount; // Update total locked VEMP tokens

        emit LockVemp(msg.sender, _amount);
    }

    /**
     * @notice Withdraws VEMP tokens from the contract to the specified address.
     * @param to The address to send the withdrawn tokens to.
     * @param amount The amount of tokens to withdraw.
     * @dev Only the owner can call this function.
     */
    function withdrawTokensByAdmin(
        address to,
        uint256 amount
    ) public onlyOwner {
        require(to != address(0), "VEMPLockContract: Invalid Address");
        require(amount > 0, "VEMPLockContract: Invalid Amount");
        require(
            IERC20(vempToken).balanceOf(address(this)) >= amount,
            "VEMPLockContract: Insufficient Balance"
        );

        IERC20(vempToken).transfer(to, amount);
        totalWithdrawTokens += amount; // Update total withdrawn tokens

        emit WithdrawTokensByAdmin(to, amount);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
