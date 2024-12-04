// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";

import {CurrencyLibrary, Currency} from "v4-core/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDeltaLibrary, BalanceDelta} from "v4-core/types/BalanceDelta.sol";

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";

import {Oracle} from "./libraries/Oracle.sol";

contract NetVolumeOracleV2 is BaseHook {
    using BalanceDeltaLibrary for BalanceDelta;
    using CurrencyLibrary for Currency;
    using Oracle for Oracle.Observation[65535];
    using PoolIdLibrary for PoolKey;

    struct ObservationState {
        uint16 index;
        uint16 cardinality;
        uint16 cardinalityNext;
    }

    // pool to state mappings
    mapping(PoolId => Oracle.Observation[65535]) public observations;
    mapping(PoolId => ObservationState) public states;


    constructor(
        IPoolManager _manager
    ) BaseHook(_manager) {}

    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: true,
                beforeAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    
    function afterInitialize(address, PoolKey calldata key, uint160, int24)
        external
        override
        onlyPoolManager
        returns (bytes4)
    {
        PoolId id = key.toId();
        (states[id].cardinality, states[id].cardinalityNext) = observations[id].initialize(uint32(block.timestamp));
        return this.afterInitialize.selector;
    }

    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        BalanceDelta delta,
        bytes calldata
    ) external override onlyPoolManager returns (bytes4, int128) {
        PoolId id = key.toId();

        (states[id].index, states[id].cardinality) = observations[id].write(
            states[id].index,
            uint32(block.timestamp),
            delta.amount0(),
            delta.amount1(),
            states[id].cardinality,
            states[id].cardinalityNext
        );

        return (this.afterSwap.selector, 0);
    }

    /// @notice Observe the given pool for the timestamps
    function observe(PoolKey calldata key, uint32[] calldata secondsAgos)
        external
        view
        returns (int256[] memory token0VolumeCumulatives, int256[] memory token1VolumeCumulatives)
    {
        PoolId id = key.toId();

        ObservationState memory state = states[id];

        return observations[id].observe(
            uint32(block.timestamp),
            secondsAgos,
            state.index,
            state.cardinality
        );
    }

    /// @notice Returns the state for the given pool key
    function getState(PoolKey calldata key) 
        external
        view
        returns (ObservationState memory) {
        return states[key.toId()];
    }

    /// @notice Returns the observation for the given pool key and observation index
    function getObservation(PoolKey calldata key, uint256 index)
        external
        view
        returns (Oracle.Observation memory)
    {
        return observations[key.toId()][index];
    }

    /// @notice Increase the cardinality target for the given pool
    function increaseCardinalityNext(PoolKey calldata key, uint16 cardinalityNext)
        external
        returns (uint16 cardinalityNextOld, uint16 cardinalityNextNew)
    {
        PoolId id = key.toId();

        ObservationState storage state = states[id];

        cardinalityNextOld = state.cardinalityNext;
        cardinalityNextNew = observations[id].grow(cardinalityNextOld, cardinalityNext);
        state.cardinalityNext = cardinalityNextNew;
    }

    function getNetVolume(PoolKey calldata key, uint32 startTime, uint32 endTime)
        external
        view
        returns (int256 token0NetVolume, int256 token1NetVolume)
    {
        PoolId id = key.toId();

        ObservationState memory state = states[id];

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = uint32(block.timestamp) - startTime;
        secondsAgos[1] = uint32(block.timestamp) - endTime;

        (
            int256[] memory token0VolumeCumulatives,
            int256[] memory token1VolumeCumulatives
        ) = observations[id].observe(
            uint32(block.timestamp),
            secondsAgos,
            state.index,
            state.cardinality
        );

        token0NetVolume = (token0VolumeCumulatives[1] - token0VolumeCumulatives[0])
            / int256(uint256(endTime - startTime));

        token1NetVolume = (token1VolumeCumulatives[1] - token1VolumeCumulatives[0])
            / int256(uint256(endTime - startTime));
    }
}
