// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./IVesting.sol";

/**
 * @title Vesting contract with batch lock and claim possibility,
 *      support only target token, user can claim and get actual
 *      reward data in range dependant on selected lock index.
 */
contract Vesting is IVesting, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_LOCK_LENGTH = 100;

    IERC20 public immutable token;
    uint256 public immutable startAt;

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

    mapping(address => Balance) private _balances;

    event TokensVested(address indexed _to, uint256 _amount);
    event TokensClaimed(address indexed _beneficiary, uint256 _amount);

    constructor(IERC20 _baseToken, uint256 _startAt) {
        token = _baseToken;
        startAt = _startAt;
    }

    /**
     * @dev Returns {_participant} vesting plan by {_index}.
     */
    function getLocks(address _participant, uint256 _index)
        external
        view
        override
        returns (uint256[] memory amounts, uint256[] memory unlocks)
    {
        Lock memory _lock = _balances[_participant].locks[_index];
        amounts = _lock.amounts;
        unlocks = _lock.unlockAt;
    }

    /**
     * @dev Returns amount of vesting plans by {_participant} address.
     */
    function getLocksLength(address _participant)
        external
        view
        override
        returns (uint256)
    {
        return _balances[_participant].locks.length;
    }

    /**
     * @dev Returns vesting plan {_lockIndex} length by {_participant} address.
     */
    function getItemsLengthByLockIndex(address _participant, uint256 _lockIndex)
        external
        view
        override
        returns (uint256)
    {
        require(
            _balances[_participant].locks.length > _lockIndex,
            "Index not exist"
        );

        return _balances[_participant].locks[_lockIndex].amounts.length;
    }

    /**
     * @dev Locking {_amounts} with {_unlockAt} date for specific {_account}.
     */
    function lock(
        address _account,
        uint256[] memory _unlockAt,
        uint256[] memory _amounts
    ) external override onlyOwner returns (uint256 totalAmount) {
        require(_account != address(0), "Zero address");
        require(
            _unlockAt.length == _amounts.length &&
                _unlockAt.length <= MAX_LOCK_LENGTH,
            "Wrong array length"
        );
        require(_unlockAt.length != 0, "Zero array length");

        for (uint256 i = 0; i < _unlockAt.length; i++) {
            if (i == 0) {
                require(_unlockAt[0] >= startAt, "Early unlock");
            }

            if (i > 0) {
                if (_unlockAt[i - 1] >= _unlockAt[i]) {
                    require(false, "Timeline violation");
                }
            }

            totalAmount += _amounts[i];
        }

        token.safeTransferFrom(msg.sender, address(this), totalAmount);

        _balances[_account].locks.push(
            Lock({amounts: _amounts, unlockAt: _unlockAt, released: 0})
        );

        emit TokensVested(_account, totalAmount);
    }

    /**
     * @dev Same as {Vesting.lock}, but in the batches.
     */
    function lockBatch(LockBatchInput[] memory _input)
        external
        onlyOwner
        returns (uint256 totalAmount)
    {
        uint256 inputsLen = _input.length;

        require(inputsLen != 0, "Empty input data");

        uint256 lockLen;
        uint256 i;
        uint256 ii;
        for (i; i < inputsLen; i++) {
            if (_input[i].account == address(0)) {
                require(false, "Zero address");
            }

            if (
                _input[i].amounts.length == 0 || _input[i].unlockAt.length == 0
            ) {
                require(false, "Zero array length");
            }

            if (
                _input[i].unlockAt.length != _input[i].amounts.length ||
                _input[i].unlockAt.length > MAX_LOCK_LENGTH
            ) {
                require(false, "Wrong array length");
            }

            lockLen = _input[i].unlockAt.length;
            for (ii; ii < lockLen; ii++) {
                if (ii == 0) {
                    require(_input[i].unlockAt[0] >= startAt, "Early unlock");
                }

                if (ii > 0) {
                    if (_input[i].unlockAt[ii - 1] >= _input[i].unlockAt[ii]) {
                        require(false, "Timeline violation");
                    }
                }

                totalAmount += _input[i].amounts[ii];
            }

            ii = 0;
        }

        token.safeTransferFrom(msg.sender, address(this), totalAmount);

        uint256 amount;
        uint256 l;

        i = 0;
        for (i; i < inputsLen; i++) {
            _balances[_input[i].account].locks.push(
                Lock({
                    amounts: _input[i].amounts,
                    unlockAt: _input[i].unlockAt,
                    released: 0
                })
            );

            l = _input[i].amounts.length;
            ii = 0;
            if (l > 1) {
                for (ii; ii < l; ii++) {
                    amount += _input[i].amounts[ii];
                    if (ii == l - 1) {
                        emit TokensVested(_input[i].account, amount);
                        amount = 0;
                    }
                }
            } else {
                emit TokensVested(_input[i].account, _input[i].amounts[0]);
            }
        }
    }

    /**
     * @dev Returns next unlock timestamp by all locks, if return zero,
     *      no time points available.
     */
    function getNextUnlock(address _participant)
        external
        view
        override
        returns (uint256 timestamp)
    {
        uint256 locksLen = _balances[_participant].locks.length;
        uint256 currentUnlock;
        uint256 i;
        for (i; i < locksLen; i++) {
            currentUnlock = _getNextUnlock(_participant, i);
            if (currentUnlock != 0) {
                if (timestamp == 0) {
                    timestamp = currentUnlock;
                } else {
                    if (currentUnlock < timestamp) {
                        timestamp = currentUnlock;
                    }
                }
            }
        }
    }

    /**
     * @dev Returns next unlock timestamp by {_lockIndex}.
     */
    function getNextUnlockByIndex(address _participant, uint256 _lockIndex)
        external
        view
        override
        returns (uint256 timestamp)
    {
        uint256 locksLen = _balances[_participant].locks.length;

        require(locksLen > _lockIndex, "Index not exist");

        timestamp = _getNextUnlock(_participant, _lockIndex);
    }

    /**
     * @dev Returns total pending reward by {_participant} address.
     */
    function pendingReward(address _participant)
        external
        view
        override
        returns (uint256 reward)
    {
        reward = _pendingReward(
            _participant,
            0,
            _balances[_participant].locks.length
        );
    }

    /**
     * @dev Returns pending reward by {_participant} address in range.
     */
    function pendingRewardInRange(
        address _participant,
        uint256 _from,
        uint256 _to
    ) external view override returns (uint256 reward) {
        reward = _pendingReward(_participant, _from, _to);
    }

    /**
     * @dev Claim available reward.
     */
    function claim(address _participant)
        external
        override
        nonReentrant
        returns (uint256 claimed)
    {
        claimed = _claim(_participant, 0, _balances[_participant].locks.length);
    }

    /**
     * @dev Claim available reward in range.
     */
    function claimInRange(
        address _participant,
        uint256 _from,
        uint256 _to
    ) external override nonReentrant returns (uint256 claimed) {
        claimed = _claim(_participant, _from, _to);
    }

    function _pendingReward(
        address _participant,
        uint256 _from,
        uint256 _to
    ) internal view returns (uint256 reward) {
        uint256 amount;
        uint256 released;
        uint256 i = _from;
        uint256 ii;
        for (i; i < _to; i++) {
            uint256 len = _balances[_participant].locks[i].amounts.length;
            for (ii; ii < len; ii++) {
                if (
                    block.timestamp >=
                    _balances[_participant].locks[i].unlockAt[ii]
                ) {
                    amount += _balances[_participant].locks[i].amounts[ii];
                }
            }

            released += _balances[_participant].locks[i].released;
            ii = 0;
        }

        if (amount >= released) {
            reward = amount - released;
        }
    }

    function _claim(
        address _participant,
        uint256 _from,
        uint256 _to
    ) internal returns (uint256 claimed) {
        uint256 amount;
        uint256 released;
        uint256 i = _from;
        uint256 ii;
        for (i; i < _to; i++) {
            uint256 toRelease;
            uint256 len = _balances[_participant].locks[i].amounts.length;
            for (ii; ii < len; ii++) {
                if (
                    block.timestamp >=
                    _balances[_participant].locks[i].unlockAt[ii]
                ) {
                    amount += _balances[_participant].locks[i].amounts[ii];
                    toRelease += _balances[_participant].locks[i].amounts[ii];
                }
            }

            released += _balances[_participant].locks[i].released;
            if (
                toRelease > 0 &&
                _balances[_participant].locks[i].released < toRelease
            ) {
                _balances[_participant].locks[i].released = toRelease;
            }

            ii = 0;
        }

        require(amount >= released, "Nothing to claim");

        claimed = amount - released;

        require(claimed > 0, "Zero claim");

        token.safeTransfer(_participant, claimed);
        emit TokensClaimed(_participant, claimed);
    }

    function _getNextUnlock(address _participant, uint256 _lockIndex)
        internal
        view
        returns (uint256 timestamp)
    {
        Lock memory _lock = _balances[_participant].locks[_lockIndex];
        uint256 lockLen = _lock.unlockAt.length;
        uint256 i;
        for (i; i < lockLen; i++) {
            if (block.timestamp < _lock.unlockAt[i]) {
                timestamp = _lock.unlockAt[i];
                return timestamp;
            }
        }
    }
}
