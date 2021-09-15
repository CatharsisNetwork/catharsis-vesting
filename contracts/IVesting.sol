// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

interface IVesting {
    function getLocks(address _participant, uint _index)
        external
        view
        returns (
            uint256[] memory amounts,
            uint256[] memory unlocks
        );

    function getLocksLength(address _participant)
        external
        view
        returns (uint256);

    function getItemsLengthByLockIndex(
        address _participant,
        uint256 _lockIndex
    )
        external
        view
        returns (uint256);

    function lock(
        address _account,
        uint256[] memory _unlockAt,
        uint256[] memory _amounts
    )
        external
        returns (uint256 totalAmount);

    function getNextUnlock(address _participant)
        external
        view
        returns (uint256 timestamp);

    function getNextUnlockByIndex(
        address _participant,
        uint256 _lockIndex
    )
        external
        view
        returns (uint256 timestamp);

    function pendingReward(address _participant)
        external
        view
        returns (uint256 reward);

    function pendingRewardInRange(address _participant, uint256 _from, uint256 _to)
        external
        view
        returns (uint256 reward);

    function claim(address _participant) external returns (uint256 claimed);

    function claimInRange(address _participant, uint256 _from, uint256 _to)
        external
        returns (uint256 claimed);
}