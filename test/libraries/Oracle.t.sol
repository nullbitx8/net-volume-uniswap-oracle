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

    function testTwoObservationsChronologicalZeroSecondsAgoExact() public {
        oracle.initialize(OracleImplementation.InitializeParams({time: 5, token0Volume: 2, token1Volume: -1}));
        oracle.grow(2);
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 4, token0Volume: 3, token1Volume: -2}));
        (int256 token0VolumeCumulative, int256 token1VolumeCumulative) = observeSingle(oracle, 0);
        assertEq(token0VolumeCumulative, 8);
        assertEq(token1VolumeCumulative, -4);
    }

    function testTwoObservationsChronologicalZeroSecondsAgoCounterfactual() public {
        oracle.initialize(OracleImplementation.InitializeParams({time: 5, token0Volume: 2, token1Volume: -1}));
        oracle.grow(2);
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 4, token0Volume: 3, token1Volume: -2}));
        oracle.advanceTime(7);
        (int256 token0VolumeCumulative, int256 token1VolumeCumulative) = observeSingle(oracle, 0);
        assertEq(token0VolumeCumulative, 29);
        assertEq(token1VolumeCumulative, -18);
    }

    function testTwoObservationsChronologicalSecondsAgoExactlyFirstObservation() public {
        oracle.initialize(OracleImplementation.InitializeParams({time: 5, token0Volume: 2, token1Volume: -1}));
        oracle.grow(2);
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 4, token0Volume: 3, token1Volume: -2}));
        oracle.advanceTime(7);
        (int256 token0VolumeCumulative, int256 token1VolumeCumulative) = observeSingle(oracle, 11);
        assertEq(token0VolumeCumulative, 0);
        assertEq(token1VolumeCumulative, 0);
    }

    function testTwoObservationsChronologicalSecondsAgoBetween() public {
        oracle.initialize(OracleImplementation.InitializeParams({time: 5, token0Volume: 2, token1Volume: -1}));
        oracle.grow(2);
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 4, token0Volume: 3, token1Volume: -2}));
        oracle.advanceTime(7);
        (int256 token0VolumeCumulative, int256 token1VolumeCumulative) = observeSingle(oracle, 9);
        assertEq(token0VolumeCumulative, 4);
        assertEq(token1VolumeCumulative, -2);
    }

    function testTwoObservationsReverseOrderZeroSecondsAgoExact() public {
        oracle.initialize(OracleImplementation.InitializeParams({time: 5, token0Volume: 2, token1Volume: -1}));
        oracle.grow(2);
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 4, token0Volume: 3, token1Volume: -2}));
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 3, token0Volume: 1, token1Volume: -1}));
        (int256 token0VolumeCumulative, int256 token1VolumeCumulative) = observeSingle(oracle, 0);
        assertEq(token0VolumeCumulative, 17);
        assertEq(token1VolumeCumulative, -10);
    }

    function testTwoObservationsReverseOrderZeroSecondsAgoCounterfactual() public {
        oracle.initialize(OracleImplementation.InitializeParams({time: 5, token0Volume: 2, token1Volume: -1}));
        oracle.grow(2);
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 4, token0Volume: 3, token1Volume: -2}));
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 3, token0Volume: 1, token1Volume: -1}));
        oracle.advanceTime(7);
        (int256 token0VolumeCumulative, int256 token1VolumeCumulative) = observeSingle(oracle, 0);
        assertEq(token0VolumeCumulative, 24);
        assertEq(token1VolumeCumulative, -17);
    }

    function testTwoObservationsReverseOrderSecondsAgoExactlyOnFirstObservation() public {
        oracle.initialize(OracleImplementation.InitializeParams({time: 5, token0Volume: 2, token1Volume: -1}));
        oracle.grow(2);
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 4, token0Volume: 3, token1Volume: -2}));
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 3, token0Volume: 1, token1Volume: -1}));
        oracle.advanceTime(7);
        (int256 token0VolumeCumulative, int256 token1VolumeCumulative) = observeSingle(oracle, 10);
        assertEq(token0VolumeCumulative, 8);
        assertEq(token1VolumeCumulative, -4);
    }

    function testTwoObservationsReverseOrderSecondsAgoBetween() public {
        oracle.initialize(OracleImplementation.InitializeParams({time: 5, token0Volume: 2, token1Volume: -1}));
        oracle.grow(2);
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 4, token0Volume: 3, token1Volume: -2}));
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 3, token0Volume: 1, token1Volume: -1}));
        oracle.advanceTime(7);
        (int256 token0VolumeCumulative, int256 token1VolumeCumulative) = observeSingle(oracle, 9);
        assertEq(token0VolumeCumulative, 11);
        assertEq(token1VolumeCumulative, -6);
    }

    function testCanFetchMultipleObservations() public {
        oracle.initialize(OracleImplementation.InitializeParams({time: 5, token0Volume: 2, token1Volume: -1}));
        oracle.grow(4);
        oracle.update(OracleImplementation.UpdateParams({advanceTimeBy: 13, token0Volume: 3, token1Volume: -2}));
        oracle.advanceTime(5);
        uint32[] memory secondsAgos = new uint32[](6);
        secondsAgos[0] = 0;
        secondsAgos[1] = 3;
        secondsAgos[2] = 8;
        secondsAgos[3] = 13;
        secondsAgos[4] = 15;
        secondsAgos[5] = 18;
        (int256[] memory token0VolumeCumulatives, int256[] memory token1VolumeCumulatives) =
            oracle.observe(secondsAgos);
        assertEq(token0VolumeCumulatives.length, 6);
        assertEq(token1VolumeCumulatives.length, 6);
        assertEq(token0VolumeCumulatives[0], 41);
        assertEq(token1VolumeCumulatives[0], -23);
        assertEq(token0VolumeCumulatives[1], 32);
        assertEq(token1VolumeCumulatives[1], -17);
        assertEq(token0VolumeCumulatives[2], 20);
        assertEq(token1VolumeCumulatives[2], -10);
        assertEq(token0VolumeCumulatives[3], 10);
        assertEq(token1VolumeCumulatives[3], -5);
        assertEq(token0VolumeCumulatives[4], 6);
        assertEq(token1VolumeCumulatives[4], -3);
        assertEq(token0VolumeCumulatives[5], 0);
        assertEq(token1VolumeCumulatives[5], 0);
    }

    function testObserveGasSinceMostRecent() public {
        oracle.initialize(OracleImplementation.InitializeParams({time: 5, token0Volume: 2, token1Volume: -1}));
        oracle.advanceTime(2);
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 1;
        snap("OracleObserveSinceMostRecent", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testObserveGasCurrentTime() public {
        oracle.initialize(OracleImplementation.InitializeParams({time: 5, token0Volume: 2, token1Volume: -1}));
        uint32[] memory secondsAgos = new uint32[](1);
        secondsAgos[0] = 0;
        snap("OracleObserveCurrentTime", oracle.getGasCostOfObserve(secondsAgos));
    }

    function testObserveGasCurrentTimeCounterfactual() public {
        oracle.initialize(OracleImplementation.InitializeParams({time: 5, token0Volume: 2, token1Volume: -1}));
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

        (int256 token0VolumeCumulative, int256 token1VolumeCumulative) = observeSingle(oracle, 0);
        assertEq(token0VolumeCumulative, 61);
        assertEq(token1VolumeCumulative, -39);
    }

    function testManyObservationsLatestObservation5SecondsAfterLatest(uint32 startingTime) public {
        setupOracleWithManyObservations(startingTime);

        // latest observation 5 seconds after latest
        oracle.advanceTime(5);
        (int256 token0VolumeCumulative, int256 token1VolumeCumulative) = observeSingle(oracle, 5);
        assertEq(token0VolumeCumulative, 61);
        assertEq(token1VolumeCumulative, -39);
    }

    function testManyObservationsCurrentObservation5SecondsAfterLatest(uint32 startingTime) public {
        setupOracleWithManyObservations(startingTime);

        oracle.advanceTime(5);
        (int256 token0VolumeCumulative, int256 token1VolumeCumulative) = observeSingle(oracle, 0);
        assertEq(token0VolumeCumulative, 96);
        assertEq(token1VolumeCumulative, -64);
    }

    function testManyObservationsBetweenLatestObservationAtLatest(uint32 startingTime) public {
        setupOracleWithManyObservations(startingTime);

        (int256 token0VolumeCumulative, int256 token1VolumeCumulative) = observeSingle(oracle, 3);
        assertEq(token0VolumeCumulative, 43);
        assertEq(token1VolumeCumulative, -27);
    }

    function testManyObservationsBetweenLatestObservationAfterLatest(uint32 startingTime) public {
        setupOracleWithManyObservations(startingTime);

        oracle.advanceTime(5);
        (int256 token0VolumeCumulative, int256 token1VolumeCumulative) = observeSingle(oracle, 8);
        assertEq(token0VolumeCumulative, 43);
        assertEq(token1VolumeCumulative, -27);
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
        (int256 token0VolumeCumulative, int256 token1VolumeCumulative) = observeSingle(oracle, 14);
        assertEq(token0VolumeCumulative, 4);
        assertEq(token1VolumeCumulative, -2);
    }

    function testManyObservationsOldestAfterTime(uint32 startingTime) public {
        setupOracleWithManyObservations(startingTime);
        oracle.advanceTime(6);
        (int256 token0VolumeCumulative, int256 token1VolumeCumulative) = observeSingle(oracle, 20);
        assertEq(token0VolumeCumulative, 4);
        assertEq(token1VolumeCumulative, -2);
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
        (int256[] memory token0VolumeCumulatives, int256[] memory token1VolumeCumulatives) =
            oracle.observe(secondsAgos);
        assertEq(token0VolumeCumulatives[0], 4);
        assertEq(token1VolumeCumulatives[0], -2);
        assertEq(token0VolumeCumulatives[1], 13);
        assertEq(token1VolumeCumulatives[1], -8);
        assertEq(token0VolumeCumulatives[2], 20);
        assertEq(token1VolumeCumulatives[2], -12);
        assertEq(token0VolumeCumulatives[3], 37);
        assertEq(token1VolumeCumulatives[3], -23);
        assertEq(token0VolumeCumulatives[4], 68);
        assertEq(token1VolumeCumulatives[4], -44);
        assertEq(token0VolumeCumulatives[5], 96);
        assertEq(token1VolumeCumulatives[5], -64);
        assertEq(token0VolumeCumulatives[6], 103);
        assertEq(token1VolumeCumulatives[6], -69);
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
        (int256 token0VolumeCumulative, int256 token1VolumeCumulative) = observeSingle(oracle, 100 * 13);
        assertEq(token0VolumeCumulative, 27970560813);
        assertEq(token1VolumeCumulative, -27970560813);

        // can observe into the ordered portion with unexact seconds ago
        (token0VolumeCumulative, token1VolumeCumulative) = observeSingle(oracle, 100 * 13 + 5);
        assertEq(token0VolumeCumulative, 27970232823);
        assertEq(token1VolumeCumulative, -27970232823);

        // can observe at exactly the latest observation
        (token0VolumeCumulative, token1VolumeCumulative) = observeSingle(oracle, 0);
        assertEq(token0VolumeCumulative, 28055903863);
        assertEq(token1VolumeCumulative, -28055903863);

        // can observe into the unordered portion of array at exact seconds ago
        (token0VolumeCumulative, token1VolumeCumulative) = observeSingle(oracle, 200 * 13);
        assertEq(token0VolumeCumulative, 27885347763);
        assertEq(token1VolumeCumulative, -27885347763);

        // can observe into the unordered portion of array at seconds ago between observations
        (token0VolumeCumulative, token1VolumeCumulative) = observeSingle(oracle, 200 * 13 + 5);
        assertEq(token0VolumeCumulative, 27885020273);
        assertEq(token1VolumeCumulative, -27885020273);

        // can observe the oldest observation
        (token0VolumeCumulative, token1VolumeCumulative) = observeSingle(oracle, 65534 * 13);
        assertEq(token0VolumeCumulative, 175890);
        assertEq(token1VolumeCumulative, -175890);

        // can observe at exactly the latest observation after some time passes
        oracle.advanceTime(5);
        (token0VolumeCumulative, token1VolumeCumulative) = observeSingle(oracle, 5);
        assertEq(token0VolumeCumulative, 28055903863);
        assertEq(token1VolumeCumulative, -28055903863);

        // can observe after the latest observation counterfactual
        (token0VolumeCumulative, token1VolumeCumulative) = observeSingle(oracle, 3);
        assertEq(token0VolumeCumulative, 28056035261);
        assertEq(token1VolumeCumulative, -28056035261);

        // can observe the oldest observation after time passes
        (token0VolumeCumulative, token1VolumeCumulative) = observeSingle(oracle, 65534 * 13 + 5);
        assertEq(token0VolumeCumulative, 175890);
        assertEq(token1VolumeCumulative, -175890);
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
