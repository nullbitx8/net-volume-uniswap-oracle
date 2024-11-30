// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {OracleImplementation} from "../../test/libraries/OracleImplementation.sol";
import {Oracle} from "../../src/libraries/Oracle.sol";

contract TestOracle is Test, GasSnapshot {
    OracleImplementation initializedOracle;
    OracleImplementation oracle;

    function setUp() public {
        oracle = new OracleImplementation();
        initializedOracle = new OracleImplementation();
        initializedOracle.initialize(OracleImplementation.InitializeParams(
            {time: 0, token0Volume: 0, token1Volume: 0}
        ));
    }

    function testInitialize() public {
        snapStart("OracleInitialize");
        oracle.initialize(
            OracleImplementation.InitializeParams(
                {time: 1, token0Volume: 1, token1Volume: 1}
            )
        );
        snapEnd();

        assertEq(oracle.index(), 0);
        assertEq(oracle.cardinality(), 1);
        assertEq(oracle.cardinalityNext(), 1);
        assertObservation(
            oracle,
            0,
            Oracle.Observation({
                blockTimestamp: 1,
                token0VolumeCumulative: 0,
                token1VolumeCumulative: 0,
                initialized: true
            })
        );
    }

    function testGrow() public {
        initializedOracle.grow(5);
        assertEq(initializedOracle.index(), 0);
        assertEq(initializedOracle.cardinality(), 1);
        assertEq(initializedOracle.cardinalityNext(), 5);

        // does not touch first slot
        assertObservation(
            initializedOracle,
            0,
            Oracle.Observation({
                blockTimestamp: 0,
                token0VolumeCumulative: 0,
                token1VolumeCumulative: 0,
                initialized: true
            })
        );

        // adds data to all slots
        for (uint64 i = 1; i < 5; i++) {
            assertObservation(
                initializedOracle,
                i,
                Oracle.Observation({
                    blockTimestamp: 1,
                    token0VolumeCumulative: 0,
                    token1VolumeCumulative: 0,
                    initialized: false
                })
            );
        }

        // noop if initializedOracle is already gte size
        initializedOracle.grow(3);
        assertEq(initializedOracle.index(), 0);
        assertEq(initializedOracle.cardinality(), 1);
        assertEq(initializedOracle.cardinalityNext(), 5);
    }

    function testGrowAfterWrap() public {
        initializedOracle.grow(2);
        // index is now 1
        initializedOracle.update(
            OracleImplementation.UpdateParams(
                {advanceTimeBy: 2, token0Volume: 1, token1Volume: 1}
            )
        );
        // index is now 0 again
        initializedOracle.update(
            OracleImplementation.UpdateParams(
                {advanceTimeBy: 2, token0Volume: 1, token1Volume: 1}
            )
        );
        assertEq(initializedOracle.index(), 0);
        initializedOracle.grow(3);

        assertEq(initializedOracle.index(), 0);
        assertEq(initializedOracle.cardinality(), 2);
        assertEq(initializedOracle.cardinalityNext(), 3);
    }

    function testGas1Slot() public {
        snapStart("OracleGrow1Slot");
        initializedOracle.grow(2);
        snapEnd();
    }

    function testGas10Slots() public {
        snapStart("OracleGrow10Slots");
        initializedOracle.grow(11);
        snapEnd();
    }

    function testGas1SlotCardinalityGreater() public {
        initializedOracle.grow(2);
        snapStart("OracleGrow1SlotCardinalityGreater");
        initializedOracle.grow(3);
        snapEnd();
    }

    function testGas10SlotCardinalityGreater() public {
        initializedOracle.grow(2);
        snapStart("OracleGrow10SlotsCardinalityGreater");
        initializedOracle.grow(12);
        snapEnd();
    }

    function testWrite() public {
        // cardinality is 1 throughout the test since we never called grow
        assertEq(initializedOracle.cardinality(), 1);

        initializedOracle.update(
            OracleImplementation.UpdateParams(
                {advanceTimeBy: 1, token0Volume: 2, token1Volume: -1}
            )
        );
        assertEq(initializedOracle.index(), 0);
        assertObservation(
            initializedOracle,
            0,
            Oracle.Observation({
                blockTimestamp: 1,
                token0VolumeCumulative: 0,
                token1VolumeCumulative: 0,
                initialized: true
            })
        );

        initializedOracle.update(
            OracleImplementation.UpdateParams(
                {advanceTimeBy: 5, token0Volume: -2, token1Volume: 1}
            )
        );
        assertEq(initializedOracle.index(), 0);
        assertObservation(
            initializedOracle,
            0,
            Oracle.Observation({
                blockTimestamp: 6,
                token0VolumeCumulative: 10,
                token1VolumeCumulative: -5,
                initialized: true
            })
        );

        initializedOracle.update(
            OracleImplementation.UpdateParams(
                {advanceTimeBy: 3, token0Volume: -10, token1Volume: 10}
            )
        );
        assertEq(initializedOracle.index(), 0);
        assertObservation(
            initializedOracle,
            0,
            Oracle.Observation({
                blockTimestamp: 9,
                token0VolumeCumulative: 4,
                token1VolumeCumulative: -2,
                initialized: true
            })
        );
    }

    function testWriteKeepsIndexConstantIfTimeUnchanged() public {
        initializedOracle.grow(2);
        initializedOracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 1, token0Volume: 2, token1Volume: -1}));
        assertEq(initializedOracle.index(), 1);
        initializedOracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 0, token0Volume: 3, token1Volume: -2}));
        assertEq(initializedOracle.index(), 1);
    }

    function testWriteUpdatesVolumeIfTimeUnchanged() public {
        initializedOracle.grow(2);

        // first update
        initializedOracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 1, token0Volume: 2, token1Volume: -1}));
        assertEq(initializedOracle.index(), 1);
        assertObservation(
            initializedOracle,
            1,
            Oracle.Observation({
                blockTimestamp: 1,
                token0VolumeCumulative: 0,
                token1VolumeCumulative: 0,
                initialized: true
            })
        );

        // second update
        initializedOracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 0, token0Volume: 3, token1Volume: -2}));
        assertEq(initializedOracle.index(), 1);
        assertObservation(
            initializedOracle,
            1,
            Oracle.Observation({
                blockTimestamp: 1,
                token0VolumeCumulative: 2,
                token1VolumeCumulative: -1,
                initialized: true
            })
        );

        // third update
        initializedOracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 0, token0Volume: 3, token1Volume: -2}));
        assertEq(initializedOracle.index(), 1);
        assertObservation(
            initializedOracle,
            1,
            Oracle.Observation({
                blockTimestamp: 1,
                token0VolumeCumulative: 5,
                token1VolumeCumulative: -3,
                initialized: true
            })
        );
    }

    function testWriteTimeChanged() public {
        initializedOracle.grow(3);
        initializedOracle.update(
            OracleImplementation.UpdateParams(
                {advanceTimeBy: 6, token0Volume: 2, token1Volume: -1}
            )
        );
        assertEq(initializedOracle.index(), 1);
        assertObservation(
            initializedOracle,
            1,
            Oracle.Observation({
                blockTimestamp: 6,
                token0VolumeCumulative: 0,
                token1VolumeCumulative: 0,
                initialized: true
            })
        );

        initializedOracle.update(
            OracleImplementation.UpdateParams(
                {advanceTimeBy: 4, token0Volume: 3, token1Volume: -2}
            )
        );
        assertEq(initializedOracle.index(), 2);
        assertObservation(
            initializedOracle,
            2,
            Oracle.Observation({
                blockTimestamp: 10,
                token0VolumeCumulative: 8,
                token1VolumeCumulative: -4,
                initialized: true
            })
        );
    }

    function testWriteGrowsCardinalityWritingPast() public {
        initializedOracle.grow(2);
        initializedOracle.grow(4);
        assertEq(initializedOracle.cardinality(), 1);
        initializedOracle.update(
            OracleImplementation.UpdateParams(
                {advanceTimeBy: 3, token0Volume: 2, token1Volume: -1}
            )
        );
        assertEq(initializedOracle.cardinality(), 4);
        initializedOracle.update(
            OracleImplementation.UpdateParams(
                {advanceTimeBy: 4, token0Volume: 3, token1Volume: -2}
            )
        );
        assertEq(initializedOracle.cardinality(), 4);
        assertEq(initializedOracle.index(), 2);
        assertObservation(
            initializedOracle,
            2,
            Oracle.Observation({
                blockTimestamp: 7,
                token0VolumeCumulative: 8,
                token1VolumeCumulative: -4,
                initialized: true
            })
        );
    }

    function testWriteWrapsAround() public {
        initializedOracle.grow(3);
        initializedOracle.update(
            OracleImplementation.UpdateParams(
                {advanceTimeBy: 3, token0Volume: 2, token1Volume: -1}
            )
        );

        initializedOracle.update(
            OracleImplementation.UpdateParams(
                {advanceTimeBy: 4, token0Volume: 3, token1Volume: -2}
            )
        );

        initializedOracle.update(
            OracleImplementation.UpdateParams(
                {advanceTimeBy: 5, token0Volume: -6, token1Volume: 4}
            )
        );

        assertEq(initializedOracle.index(), 0);
        assertObservation(
            initializedOracle,
            0,
            Oracle.Observation({
                blockTimestamp: 12,
                token0VolumeCumulative: 23,
                token1VolumeCumulative: -14,
                initialized: true
            })
        );
    }

    function testObserveFailsBeforeInitialize() public {
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 0;
        vm.expectRevert(Oracle.OracleCardinalityCannotBeZero.selector);
        oracle.observe(secondsAgos);
    }

    function testObserveFailsIfOlderDoesNotExist() public {
        oracle.initialize(OracleImplementation.InitializeParams({time: 5, token0Volume: 0, token1Volume: 0}));
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 1;
        vm.expectRevert(abi.encodeWithSelector(Oracle.TargetPredatesOldestObservation.selector, 5, 4));
        oracle.observe(secondsAgos);
    }

    function testDoesNotFailAcrossOverflowBoundary() public {
        oracle.initialize(OracleImplementation.InitializeParams({time: 2 ** 32 - 1, token0Volume: 2, token1Volume: -1}));
        oracle.advanceTime(2);
        (int256 token0VolumeCumulative, int256 token1VolumeCumulative) = observeSingle(oracle, 1);
        assertEq(token0VolumeCumulative, 2);
        assertEq(token1VolumeCumulative, -1);
    }

    function testSingleObservationAtCurrentTime() public {
        oracle.initialize(OracleImplementation.InitializeParams({time: 5, token0Volume: 2, token1Volume: -1}));
        (int256 token0VolumeCumulative, int256 token1VolumeCumulative) = observeSingle(oracle, 0);
        assertEq(token0VolumeCumulative, 0);
        assertEq(token1VolumeCumulative, 0);
    }

    function testSingleObservationInRecentPast() public {
        oracle.initialize(OracleImplementation.InitializeParams({time: 5, token0Volume: 2, token1Volume: -1}));
        oracle.advanceTime(3);
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 4;
        vm.expectRevert(abi.encodeWithSelector(Oracle.TargetPredatesOldestObservation.selector, 5, 4));
        oracle.observe(secondsAgos);
    }

    function testSingleObservationSecondsAgo() public {
        oracle.initialize(OracleImplementation.InitializeParams({time: 5, token0Volume: 2, token1Volume: -1}));
        oracle.advanceTime(3);
        (int256 token0VolumeCumulative, int256 token1VolumeCumulative) = observeSingle(oracle, 3);
        assertEq(token0VolumeCumulative, 0);
        assertEq(token1VolumeCumulative, 0);
    }

    function testSingleObservationInPastCounterfactualInPast() public {
        oracle.initialize(OracleImplementation.InitializeParams({time: 5, token0Volume: 2, token1Volume: -1}));
        oracle.advanceTime(3);
        (int256 token0VolumeCumulative, int256 token1VolumeCumulative) = observeSingle(oracle, 1);
        assertEq(token0VolumeCumulative, 4);
        assertEq(token1VolumeCumulative, -2);
    }

    function testSingleObservationInPastCounterfactualNow() public {
        oracle.initialize(OracleImplementation.InitializeParams({time: 5, token0Volume: 2, token1Volume: -1}));
        oracle.advanceTime(3);
        (int256 token0VolumeCumulative, int256 token1VolumeCumulative) = observeSingle(oracle, 0);
        assertEq(token0VolumeCumulative, 6);
        assertEq(token1VolumeCumulative, -3);
    }

    /*
    function testTwoObservationsChronologicalZeroSecondsAgoExact() public {
        oracle.initialize(OracleImplementation.InitializeParams({liquidity: 5, tick: -5, time: 5}));
        oracle.grow(2);
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 4, tick: 1, liquidity: 2}));
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 0);
        assertEq(tickCumulative, -20);
        assertEq(secondsPerLiquidityCumulativeX128, 272225893536750770770699685945414569164);
    }

    function testTwoObservationsChronologicalZeroSecondsAgoCounterfactual() public {
        oracle.initialize(OracleImplementation.InitializeParams({liquidity: 5, tick: -5, time: 5}));
        oracle.grow(2);
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 4, tick: 1, liquidity: 2}));
        oracle.advanceTime(7);
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 0);
        assertEq(tickCumulative, -13);
        assertEq(secondsPerLiquidityCumulativeX128, 1463214177760035392892510811956603309260);
    }

    function testTwoObservationsChronologicalSecondsAgoExactlyFirstObservation() public {
        oracle.initialize(OracleImplementation.InitializeParams({liquidity: 5, tick: -5, time: 5}));
        oracle.grow(2);
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 4, tick: 1, liquidity: 2}));
        oracle.advanceTime(7);
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 11);
        assertEq(tickCumulative, 0);
        assertEq(secondsPerLiquidityCumulativeX128, 0);
    }

    function testTwoObservationsChronologicalSecondsAgoBetween() public {
        oracle.initialize(OracleImplementation.InitializeParams({liquidity: 5, tick: -5, time: 5}));
        oracle.grow(2);
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 4, tick: 1, liquidity: 2}));
        oracle.advanceTime(7);
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 9);
        assertEq(tickCumulative, -10);
        assertEq(secondsPerLiquidityCumulativeX128, 136112946768375385385349842972707284582);
    }

    function testTwoObservationsReverseOrderZeroSecondsAgoExact() public {
        oracle.initialize(OracleImplementation.InitializeParams({liquidity: 5, tick: -5, time: 5}));
        oracle.grow(2);
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 4, tick: 1, liquidity: 2}));
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 3, tick: -5, liquidity: 4}));
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 0);
        assertEq(tickCumulative, -17);
        assertEq(secondsPerLiquidityCumulativeX128, 782649443918158465965761597093066886348);
    }

    function testTwoObservationsReverseOrderZeroSecondsAgoCounterfactual() public {
        oracle.initialize(OracleImplementation.InitializeParams({liquidity: 5, tick: -5, time: 5}));
        oracle.grow(2);
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 4, tick: 1, liquidity: 2}));
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 3, tick: -5, liquidity: 4}));
        oracle.advanceTime(7);
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 0);
        assertEq(tickCumulative, -52);
        assertEq(secondsPerLiquidityCumulativeX128, 1378143586029800777026667160098661256396);
    }

    function testTwoObservationsReverseOrderSecondsAgoExactlyOnFirstObservation() public {
        oracle.initialize(OracleImplementation.InitializeParams({liquidity: 5, tick: -5, time: 5}));
        oracle.grow(2);
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 4, tick: 1, liquidity: 2}));
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 3, tick: -5, liquidity: 4}));
        oracle.advanceTime(7);
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 10);
        assertEq(tickCumulative, -20);
        assertEq(secondsPerLiquidityCumulativeX128, 272225893536750770770699685945414569164);
    }

    function testTwoObservationsReverseOrderSecondsAgoBetween() public {
        oracle.initialize(OracleImplementation.InitializeParams({liquidity: 5, tick: -5, time: 5}));
        oracle.grow(2);
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 4, tick: 1, liquidity: 2}));
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 3, tick: -5, liquidity: 4}));
        oracle.advanceTime(7);
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 9);
        assertEq(tickCumulative, -19);
        assertEq(secondsPerLiquidityCumulativeX128, 442367076997220002502386989661298674892);
    }

    function testCanFetchMultipleObservations() public {
        oracle.initialize(OracleImplementation.InitializeParams({liquidity: 2 ** 15, tick: 2, time: 5}));
        oracle.grow(4);
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 13, tick: 6, liquidity: 2 ** 12}));
        oracle.advanceTime(5);
        uint32[] memory secondsAgos = new uint32[](6);
        secondsAgos[0] = 0;
        secondsAgos[1] = 3;
        secondsAgos[2] = 8;
        secondsAgos[3] = 13;
        secondsAgos[4] = 15;
        secondsAgos[5] = 18;
        (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) =
            oracle.observe(secondsAgos);
        assertEq(tickCumulatives.length, 6);
        assertEq(tickCumulatives[0], 56);
        assertEq(tickCumulatives[1], 38);
        assertEq(tickCumulatives[2], 20);
        assertEq(tickCumulatives[3], 10);
        assertEq(tickCumulatives[4], 6);
        assertEq(tickCumulatives[5], 0);
        assertEq(secondsPerLiquidityCumulativeX128s.length, 6);
        assertEq(secondsPerLiquidityCumulativeX128s[0], 550383467004691728624232610897330176);
        assertEq(secondsPerLiquidityCumulativeX128s[1], 301153217795020002454768787094765568);
        assertEq(secondsPerLiquidityCumulativeX128s[2], 103845937170696552570609926584401920);
        assertEq(secondsPerLiquidityCumulativeX128s[3], 51922968585348276285304963292200960);
        assertEq(secondsPerLiquidityCumulativeX128s[4], 31153781151208965771182977975320576);
        assertEq(secondsPerLiquidityCumulativeX128s[5], 0);
    }

    function testObserveGasSinceMostRecent() public {
        oracle.initialize(OracleImplementation.InitializeParams({liquidity: 5, tick: -5, time: 5}));
        oracle.advanceTime(2);
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 1;
        snap("OracleObserveSinceMostRecent", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testObserveGasCurrentTime() public {
        oracle.initialize(OracleImplementation.InitializeParams({liquidity: 5, tick: -5, time: 5}));
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 0;
        snap("OracleObserveCurrentTime", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testObserveGasCurrentTimeCounterfactual() public {
        oracle.initialize(OracleImplementation.InitializeParams({liquidity: 5, tick: -5, time: 5}));
        initializedOracle.advanceTime(5);
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 0;
        snap("OracleObserveCurrentTimeCounterfactual", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testManyObservationsSimpleReads(uint32 startingTime) public {
        setupOracleWithManyObservations(startingTime);

        assertEq(oracle.index(), 1);
        assertEq(oracle.cardinality(), 5);
        assertEq(oracle.cardinalityNext(), 5);
    }

    function testManyObservationsLatestObservationSameTimeAsLatest(uint32 startingTime) public {
        setupOracleWithManyObservations(startingTime);

        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 0);
        assertEq(tickCumulative, -21);
        assertEq(secondsPerLiquidityCumulativeX128, 2104079302127802832415199655953100107502);
    }

    function testManyObservationsLatestObservation5SecondsAfterLatest(uint32 startingTime) public {
        setupOracleWithManyObservations(startingTime);

        // latest observation 5 seconds after latest
        oracle.advanceTime(5);
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 5);
        assertEq(tickCumulative, -21);
        assertEq(secondsPerLiquidityCumulativeX128, 2104079302127802832415199655953100107502);
    }

    function testManyObservationsCurrentObservation5SecondsAfterLatest(uint32 startingTime) public {
        setupOracleWithManyObservations(startingTime);

        oracle.advanceTime(5);
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 0);
        assertEq(tickCumulative, 9);
        assertEq(secondsPerLiquidityCumulativeX128, 2347138135642758877746181518404363115684);
    }

    function testManyObservationsBetweenLatestObservationAtLatest(uint32 startingTime) public {
        setupOracleWithManyObservations(startingTime);

        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 3);
        assertEq(tickCumulative, -33);
        assertEq(secondsPerLiquidityCumulativeX128, 1593655751746395137220137744805447790318);
    }

    function testManyObservationsBetweenLatestObservationAfterLatest(uint32 startingTime) public {
        setupOracleWithManyObservations(startingTime);

        oracle.advanceTime(5);
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 8);
        assertEq(tickCumulative, -33);
        assertEq(secondsPerLiquidityCumulativeX128, 1593655751746395137220137744805447790318);
    }

    function testManyObservationsOlderThanOldestReverts(uint32 startingTime) public {
        setupOracleWithManyObservations(startingTime);

        (uint32 oldestTimestamp,,,) = oracle.observations(oracle.index() + 1);
        uint32 secondsAgo = 15;
        // overflow desired here
        uint32 target;
        unchecked {
            target = oracle.time() - secondsAgo;
        }

        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = secondsAgo;
        vm.expectRevert(
            abi.encodeWithSelector(
                Oracle.TargetPredatesOldestObservation.selector, oldestTimestamp, uint32(int32(target))
            )
        );
        oracle.observe(secondsAgos);

        oracle.advanceTime(5);

        secondsAgos[0] = 20;
        vm.expectRevert(
            abi.encodeWithSelector(
                Oracle.TargetPredatesOldestObservation.selector, oldestTimestamp, uint32(int32(target))
            )
        );
        oracle.observe(secondsAgos);
    }

    function testManyObservationsOldest(uint32 startingTime) public {
        setupOracleWithManyObservations(startingTime);
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 14);
        assertEq(tickCumulative, -13);
        assertEq(secondsPerLiquidityCumulativeX128, 544451787073501541541399371890829138329);
    }

    function testManyObservationsOldestAfterTime(uint32 startingTime) public {
        setupOracleWithManyObservations(startingTime);
        oracle.advanceTime(6);
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) = observeSingle(oracle, 20);
        assertEq(tickCumulative, -13);
        assertEq(secondsPerLiquidityCumulativeX128, 544451787073501541541399371890829138329);
    }

    function testManyObservationsFetchManyValues(uint32 startingTime) public {
        setupOracleWithManyObservations(startingTime);
        oracle.advanceTime(6);
        uint32[] memory secondsAgos = new uint32[](7);
        secondsAgos[0] = 20;
        secondsAgos[1] = 17;
        secondsAgos[2] = 13;
        secondsAgos[3] = 10;
        secondsAgos[4] = 5;
        secondsAgos[5] = 1;
        secondsAgos[6] = 0;
        (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) =
            oracle.observe(secondsAgos);
        assertEq(tickCumulatives[0], -13);
        assertEq(secondsPerLiquidityCumulativeX128s[0], 544451787073501541541399371890829138329);
        assertEq(tickCumulatives[1], -31);
        assertEq(secondsPerLiquidityCumulativeX128s[1], 799663562264205389138930327464655296921);
        assertEq(tickCumulatives[2], -43);
        assertEq(secondsPerLiquidityCumulativeX128s[2], 1045423049484883168306923099498710116305);
        assertEq(tickCumulatives[3], -37);
        assertEq(secondsPerLiquidityCumulativeX128s[3], 1423514568285925905488450441089563684590);
        assertEq(tickCumulatives[4], -15);
        assertEq(secondsPerLiquidityCumulativeX128s[4], 2152691068830794041481396028443352709138);
        assertEq(tickCumulatives[5], 9);
        assertEq(secondsPerLiquidityCumulativeX128s[5], 2347138135642758877746181518404363115684);
        assertEq(tickCumulatives[6], 15);
        assertEq(secondsPerLiquidityCumulativeX128s[6], 2395749902345750086812377890894615717321);
    }

    function testGasAllOfLast20Seconds() public {
        setupOracleWithManyObservations(5);
        oracle.advanceTime(6);
        uint32[] memory secondsAgos = new uint32[](20);
        for (uint32 i = 0; i < 20; i++) {
            secondsAgos[i] = 20 - i;
        }
        snap("OracleObserveLast20Seconds", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testGasLatestEqual() public {
        setupOracleWithManyObservations(5);
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 0;
        snap("OracleObserveLatestEqual", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testGasLatestTransform() public {
        setupOracleWithManyObservations(5);
        oracle.advanceTime(5);
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 0;
        snap("OracleObserveLatestTransform", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testGasOldest() public {
        setupOracleWithManyObservations(5);
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 14;
        snap("OracleObserveOldest", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testGasBetweenOldestAndOldestPlusOne() public {
        setupOracleWithManyObservations(5);
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 13;
        snap("OracleObserveBetweenOldestAndOldestPlusOne", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testGasMiddle() public {
        setupOracleWithManyObservations(5);
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 5;
        snap("OracleObserveMiddle", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testFullOracle() public {
        setupFullOracle();

        assertEq(oracle.cardinalityNext(), 65535);
        assertEq(oracle.cardinality(), 65535);
        assertEq(oracle.index(), 165);

        // can observe into the ordered portion with exact seconds ago
        (int56 tickCumulative, uint160 secondsPerLiquidityCumulative) = observeSingle(oracle, 100 * 13);
        assertEq(tickCumulative, -27970560813);
        assertEq(secondsPerLiquidityCumulative, 60465049086512033878831623038233202591033);

        // can observe into the ordered portion with unexact seconds ago
        (tickCumulative, secondsPerLiquidityCumulative) = observeSingle(oracle, 100 * 13 + 5);
        assertEq(tickCumulative, -27970232823);
        assertEq(secondsPerLiquidityCumulative, 60465023149565257990964350912969670793706);

        // can observe at exactly the latest observation
        (tickCumulative, secondsPerLiquidityCumulative) = observeSingle(oracle, 0);
        assertEq(tickCumulative, -28055903863);
        assertEq(secondsPerLiquidityCumulative, 60471787506468701386237800669810720099776);

        // can observe into the unordered portion of array at exact seconds ago
        (tickCumulative, secondsPerLiquidityCumulative) = observeSingle(oracle, 200 * 13);
        assertEq(tickCumulative, -27885347763);
        assertEq(secondsPerLiquidityCumulative, 60458300386499273141628780395875293027404);

        // can observe into the unordered portion of array at seconds ago between observations
        (tickCumulative, secondsPerLiquidityCumulative) = observeSingle(oracle, 200 * 13 + 5);
        assertEq(tickCumulative, -27885020273);
        assertEq(secondsPerLiquidityCumulative, 60458274409952896081377821330361274907140);

        // can observe the oldest observation
        (tickCumulative, secondsPerLiquidityCumulative) = observeSingle(oracle, 13 * 65534);
        assertEq(tickCumulative, -175890);
        assertEq(secondsPerLiquidityCumulative, 33974356747348039873972993881117400879779);

        // can observe at exactly the latest observation after some time passes
        oracle.advanceTime(5);
        (tickCumulative, secondsPerLiquidityCumulative) = observeSingle(oracle, 5);
        assertEq(tickCumulative, -28055903863);
        assertEq(secondsPerLiquidityCumulative, 60471787506468701386237800669810720099776);

        // can observe after the latest observation counterfactual
        (tickCumulative, secondsPerLiquidityCumulative) = observeSingle(oracle, 3);
        assertEq(tickCumulative, -28056035261);
        assertEq(secondsPerLiquidityCumulative, 60471797865298117996489508104462919730461);

        // can observe the oldest observation after time passes
        (tickCumulative, secondsPerLiquidityCumulative) = observeSingle(oracle, 13 * 65534 + 5);
        assertEq(tickCumulative, -175890);
        assertEq(secondsPerLiquidityCumulative, 33974356747348039873972993881117400879779);
    }

    function testFullOracleGasCostObserveZero() public {
        setupFullOracle();
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 0;
        snap("FullOracleObserveZero", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testFullOracleGasCostObserve200By13() public {
        setupFullOracle();
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 200 * 13;
        snap("FullOracleObserve200By13", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testFullOracleGasCostObserve200By13Plus5() public {
        setupFullOracle();
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 200 * 13 + 5;
        snap("FullOracleObserve200By13Plus5", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testFullOracleGasCostObserve0After5Seconds() public {
        setupFullOracle();
        oracle.advanceTime(5);
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 0;
        snap("FullOracleObserve0After5Seconds", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testFullOracleGasCostObserve5After5Seconds() public {
        setupFullOracle();
        oracle.advanceTime(5);
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 5;
        snap("FullOracleObserve5After5Seconds", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testFullOracleGasCostObserveOldest() public {
        setupFullOracle();
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 13 * 65534;
        snap("FullOracleObserveOldest", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testFullOracleGasCostObserveOldestAfter5Seconds() public {
        setupFullOracle();
        oracle.advanceTime(5);
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 13 * 65534;
        snap("FullOracleObserveOldestAfter5Seconds", oracle.getGasCostOfObserve(secondsAgos));
    }
    */

    // fixtures and helpers

    function observeSingle(OracleImplementation _initializedOracle, uint32 secondsAgo)
        internal
        view
        returns (int256 token0VolumeCumulative, int256 token1VolumeCumulative)
    {
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = secondsAgo;

        (int256[] memory token0VolumeCumulatives, int256[] memory token1VolumeCumulatives) =
            _initializedOracle.observe(secondsAgos);

        return (token0VolumeCumulatives[0], token1VolumeCumulatives[0]);
    }

    function assertObservation(OracleImplementation _initializedOracle, uint64 idx, Oracle.Observation memory expected)
        internal
    {
        (uint32 blockTimestamp, int256 token0VolumeCumulative, int256 token1VolumeCumulative, bool initialized) =
            _initializedOracle.observations(idx);
        assertEq(blockTimestamp, expected.blockTimestamp);
        assertEq(token0VolumeCumulative, expected.token0VolumeCumulative);
        assertEq(token1VolumeCumulative, expected.token1VolumeCumulative);
        assertEq(initialized, expected.initialized);
    }

    function setupOracleWithManyObservations(uint32 startingTime) internal {
        oracle.initialize(OracleImplementation.InitializeParams({time: startingTime, token0Volume: 0, token1Volume: 0}));
        oracle.grow(5);
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 3, token0Volume: 2, token1Volume: -1}));
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 2, token0Volume: 3, token1Volume: -2}));
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 4, token0Volume: -6, token1Volume: 4}));
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 1, token0Volume: 5, token1Volume: -3}));
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 3, token0Volume: 6, token1Volume: -4})); 
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 6, token0Volume: 7, token1Volume: -5}));
    }

    function setupFullOracle() internal {
        uint16 BATCH_SIZE = 300;
        oracle.initialize(
            OracleImplementation.InitializeParams({
                // Monday, October 5, 2020 9:00:00 AM GMT-05:00
                time: 1601906400,
                token0Volume: 0,
                token1Volume: 0
            })
        );

        uint16 cardinalityNext = oracle.cardinalityNext();
        while (cardinalityNext < 65535) {
            uint16 growTo = cardinalityNext + BATCH_SIZE < 65535 ? 65535 : cardinalityNext + BATCH_SIZE;
            oracle.grow(growTo);
            cardinalityNext = growTo;
        }

        for (int24 i = 0; i < 65535; i += int24(uint24(BATCH_SIZE))) {
            OracleImplementation.UpdateParams[] memory batch = new OracleImplementation.UpdateParams[](BATCH_SIZE);
            for (int24 j = 0; j < int24(uint24(BATCH_SIZE)); j++) {
                batch[uint24(j)] = OracleImplementation.UpdateParams({
                    advanceTimeBy: 13,
                    token0Volume: i + j,
                    token1Volume: -i - j
                });
            }
            oracle.batchUpdate(batch);
        }
    }
}
