pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Vesting is Ownable {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_LOCK_LENGTH = 100;

    IERC20 public token;
    uint256 public startAt;

    uint256 public totalLocked;
    uint256 public totalReleased;

    struct LockBatchInput {
        address account;
        uint256[] unlockAt;
        uint256[] amounts;
    }

    struct Lock {
        uint256[] amounts;
        uint256[] unlockAt;
        uint256 released;
    }

    struct Balance {
        Lock[] locks;
    }

    mapping (address => Balance) private balances;

    event TokensVested(address indexed _to, uint256 _amount);
    event TokensClaimed(address indexed _beneficiary, uint256 _amount);

    constructor(IERC20 _baseToken, uint256 _startAt) {
        token = _baseToken;
        startAt = _startAt;
    }

    function getLocks(address _participant, uint _index)
        public
        view
        returns (
            uint256[] memory amounts,
            uint256[] memory unlocks
        )
    {
        Lock memory lock = balances[_participant].locks[_index];
        return (lock.amounts, lock.unlockAt);
    }

    function getLocksLength(address _participant) public view returns (uint256) {
        return balances[_participant].locks.length;
    }

    function getItemsLengthByLockIndex(address _participant, uint256 _lockIndex)
        external
        view
        returns (uint256)
    {
        require(balances[_participant].locks.length > _lockIndex, "Index not exist");

        return balances[_participant].locks[_lockIndex].amounts.length;
    }

    function lock(address _account, uint256[] memory _unlockAt, uint256[] memory _amounts)
        external
        onlyOwner
        returns (uint256 totalAmount)
    {
        require(_account != address(0), "Zero address");
        require(
            _unlockAt.length == _amounts.length &&
            _unlockAt.length <= MAX_LOCK_LENGTH,
            "Wrong array length"
        );
        require(_unlockAt.length != 0, "Zero array length");

        for (uint i = 0; i < _unlockAt.length; i++) {
            if (i > 0) {
                if (_unlockAt[i-1] >= _unlockAt[i]) {
                    require(false, "Timeline violation");
                }
            }

            totalAmount += _amounts[i];
        }

        // transfer funds from the msg.sender
        // Will fail if the allowance is less than _totalAmount
        IERC20(token).safeTransferFrom(msg.sender, address(this), totalAmount);

        balances[_account].locks.push(Lock({
            amounts: _amounts,
            unlockAt: _unlockAt,
            released: 0
        }));
    }

    function lockBatch(LockBatchInput[] memory _input)
        external
        onlyOwner
        returns (uint256 totalAmount)
    {
        uint256 inputsLen = _input.length;
        uint256 lockLen = 0;

        uint i = 0;
        for (i; i < inputsLen; i++) {
            lockLen = _input[i].unlockAt.length;
            for (uint ii = 0; ii < lockLen; ii++) {
                if (_input[i].account == address(0)) {
                    require(false, "Zero address");
                } else if (
                    _input[i].unlockAt.length != _input[i].amounts.length ||
                    _input[i].unlockAt.length > MAX_LOCK_LENGTH
                ) {
                    require(false, "Wrong array length");
                } else if (_input[i].unlockAt.length == 0) {
                    require(false, "Zero array length");
                }

                if (ii > 0) {
                    if (_input[i].unlockAt[ii-1] >= _input[i].unlockAt[ii]) {
                        require(false, "Timeline violation");
                    }
                }

                totalAmount += _input[i].amounts[ii];
            }
        }

        // transfer funds from the msg.sender
        // Will fail if the allowance is less than _totalAmount
        IERC20(token).safeTransferFrom(msg.sender, address(this), totalAmount);

        i = 0;
        for (i; i < inputsLen; i++) {
            balances[_input[i].account].locks.push(Lock({
                amounts: _input[i].amounts,
                unlockAt: _input[i].unlockAt,
                released: 0
            }));
        }
    }

    function getNextUnlock(address _participant, uint256 _lockIndex) public view returns (uint256) {
        uint256 locksLen = balances[_participant].locks.length;

        require(locksLen > _lockIndex, "Index not exist");

        Lock memory _lock = balances[_participant].locks[_lockIndex];

        for (uint i = 0; i < locksLen; i++) {
            if (block.timestamp < _lock.unlockAt[i]) {
                return _lock.unlockAt[i];
            }
        }
    }

    function pendingReward(address _participant) external view returns (uint256 reward) {
        reward = _pendingReward(_participant, 0, balances[_participant].locks.length);
    }

    function pendingRewardInRange(address _participant, uint256 _from, uint256 _to)
        external
        view
        returns (uint256 reward)
    {
        reward = _pendingReward(_participant, _from, _to);
    }

    function claim(address _participant) external returns (uint256 claimed) {
        claimed = _claim(_participant, 0, balances[_participant].locks.length);
    }

    function claimInRange(address _participant, uint256 _from, uint256 _to)
        external
        returns (uint256 claimed)
    {
        claimed = _claim(_participant, _from, _to);
    }

    function _pendingReward(address _participant, uint256 _from, uint256 _to)
        internal
        view
        returns (uint256 reward)
    {
        uint amount;
        uint released;
        uint i = _from;
        uint ii = 0;
        for (i; i < _to; i++) {
            uint len = balances[_participant].locks[i].amounts.length;
            for (ii; ii < len; ii++) {
                if (block.timestamp >= balances[_participant].locks[i].unlockAt[ii]) {
                    amount += balances[_participant].locks[i].amounts[ii];
                }
            }

            released += balances[_participant].locks[i].released;
            ii = 0;
        }

        if (amount >= released) {
            reward = amount - released;
        }
    }

    function _claim(address _participant, uint256 _from, uint256 _to)
        internal
        returns (uint256 claimed)
    {
        uint amount;
        uint released;
        uint i = _from;
        uint ii = 0;
        for (i; i < _to; i++) {
            uint toRelease;
            uint len = balances[_participant].locks[i].amounts.length;
            for (ii; ii < len; ii++) {
                if (block.timestamp >= balances[_participant].locks[i].unlockAt[ii]) {
                    amount += balances[_participant].locks[i].amounts[ii];
                    toRelease += balances[_participant].locks[i].amounts[ii];
                }
            }

            released += balances[_participant].locks[i].released;
            if (toRelease > 0) {
                balances[_participant].locks[i].released += toRelease;
            }

            ii = 0;
        }

        require(amount >= released, "Nothing to claim");

        claimed = amount - released;
        if (claimed > 0) {
            IERC20(token).safeTransfer(_participant, claimed);
            emit TokensClaimed(_participant, claimed);
        }
    }
}