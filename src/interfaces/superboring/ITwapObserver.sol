pragma solidity ^0.8.24;

interface ITwapObserver {
    /**
     * @dev Get the type id of the observer.
     *
     * Note:
     *   - This is useful for safe down-casting to the actual implementation.
     */
    function getTypeId() external view returns (bytes32); // keccak
        // 0xac2a7a01d08bec8d803b8d20516dcd7baca72524f2400f9e19acb905302f03e4 for UniswapV3PoolTwapObserver
}
