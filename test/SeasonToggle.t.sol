// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Test, console2 } from "forge-std/Test.sol";
import { SeasonToggle } from "../src/SeasonToggle.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";
import { DeployImplementation } from "../script/SeasonToggle.s.sol";
import { HatsModuleFactory } from "hats-module/HatsModuleFactory.sol";

contract DeployModuleFactory is Test {
  IHats public constant hats = IHats(0x9D2dfd6066d5935267291718E8AA16C8Ab729E9d); // v1.hatsprotocol.eth
  HatsModuleFactory public factory;
  bytes32 public FACTORY_SALT = bytes32(abi.encode(0x4a75)); // ~ H(4) A(a) T(7) S(5)

  function setUp() public virtual {
    factory = new HatsModuleFactory{salt: FACTORY_SALT}(hats, "0.1.0");
  }
}

contract SeasonToggleTest is Test, DeployImplementation, DeployModuleFactory {
  uint256 public fork = vm.createSelectFork(vm.rpcUrl("mainnet"), 16_947_805);

  uint256 public topHat1 = 0x0000000100000000000000000000000000000000000000000000000000000000;
  uint256 public hat1_1 = 0x0000000100010000000000000000000000000000000000000000000000000000;
  bytes32 maxBytes32 = bytes32(type(uint256).max);
  bytes largeBytes = abi.encodePacked("this is a fairly large bytes object");
  string public constant VERSION = "this is a test";
  uint256 public seasonDuration = 2 days;
  uint256 public extensionDelay = 5000; // 50%
  SeasonToggle public instance;

  string public IMPLEMENTATION_VERSION = "0.1.0";

  uint256 public hat1_1_1 = 0x0000000100010001000000000000000000000000000000000000000000000000;
  uint256 public MIN_SEASON_DURATION;
  uint256 public DELAY_DIVISOR = 10_000;
  uint256 public seasonStart;

  address public dao; // wears topHat1
  address public subdao; // wears hat1_1
  address public contributor; // wears hat1_1_1
  address public other; // wears no hat
  address public eligibility;

  uint256 public farBeforeThreshold;
  uint256 public justBeforeThreshold;
  uint256 public atThreshold;
  uint256 public justAfterThreshold;
  uint256 public farAfterThreshold;
  uint256 public seasonEnd;
  uint256 public justAfterSeason;
  uint256 public farAfterSeason;

  /// @notice Thrown when a non-admin attempts to extend a branch to a new season
  error SeasonToggle_NotBranchAdmin();
  /// @notice Thrown when attempting to extend a branch to a new season before its extendable
  error SeasonToggle_NotExtendable();
  /// @notice Valid extension delays are <= 10,000
  error SeasonToggle_InvalidExtensionDelay();
  /// @notice Season durations must be at least `MIN_SEASON_DURATION` long
  error SeasonToggle_SeasonDurationTooShort();

  function setUp() public virtual override {
    DeployModuleFactory.setUp();
    // set up addresses
    dao = makeAddr("dao");
    subdao = makeAddr("subdao");
    contributor = makeAddr("contributor");
    other = makeAddr("other");
    eligibility = makeAddr("eligibility");

    // deploy implementation
    DeployImplementation.prepare(IMPLEMENTATION_VERSION, false);
    DeployImplementation.run();

    // deploy an instance of the SeasonToggle contract for hat1_1
    instance = SeasonToggle(
      factory.createHatsModule(
        address(implementation), hat1_1, bytes(""), abi.encodePacked(seasonDuration, extensionDelay)
      )
    );
    seasonStart = block.timestamp;
    MIN_SEASON_DURATION = instance.MIN_SEASON_DURATION();

    // calculate threshold relative timestamps for warping
    farBeforeThreshold =
      seasonStart + seasonDuration - (((DELAY_DIVISOR - extensionDelay) * seasonDuration) / DELAY_DIVISOR) - 1000;
    justBeforeThreshold =
      seasonStart + seasonDuration - (((DELAY_DIVISOR - extensionDelay) * seasonDuration) / DELAY_DIVISOR) - 1;
    atThreshold = seasonStart + seasonDuration - (((DELAY_DIVISOR - extensionDelay) * seasonDuration) / DELAY_DIVISOR);
    justAfterThreshold =
      seasonStart + seasonDuration - (((DELAY_DIVISOR - extensionDelay) * seasonDuration) / DELAY_DIVISOR) + 1;
    farAfterThreshold =
      seasonStart + seasonDuration - (((DELAY_DIVISOR - extensionDelay) * seasonDuration) / DELAY_DIVISOR) + 1000;
    seasonEnd = seasonStart + seasonDuration;
    justAfterSeason = seasonStart + seasonDuration + 1;
    farAfterSeason = seasonStart + seasonDuration + 1000;

    // set up hats
    vm.startPrank(dao);
    // mint top hat to the dao
    topHat1 = hats.mintTopHat(dao, "Top hat", "");
    // create hat1_1
    hat1_1 = hats.createHat(topHat1, "hat1_1", 2, address(1), address(instance), true, "");
    vm.stopPrank();
  }

  function test_deploy_implementation() public {
    assertEq(implementation.version_(), IMPLEMENTATION_VERSION, "implementation version");
  }
}

contract SeasonToggleHarness is SeasonToggle {
  constructor() SeasonToggle("this is a test harness") { }

  function extensionThreshold_(uint256 seasonEnd, uint256 extensionDelay, uint256 seasonDuration)
    public
    pure
    returns (uint256)
  {
    return _extensionThreshold(seasonEnd, extensionDelay, seasonDuration);
  }
}

contract InternalTest is SeasonToggleTest {
  SeasonToggleHarness harnessImplementation;
  SeasonToggleHarness harness;

  function setUp() public virtual override {
    super.setUp();
    // deploy harness implementation
    harnessImplementation = new SeasonToggleHarness();
    // deploy harness proxy, for hat1_1
    harness = SeasonToggleHarness(
      factory.createHatsModule(
        address(harnessImplementation), hat1_1, bytes(""), abi.encodePacked(seasonDuration, extensionDelay)
      )
    );
    // mint hat1_1 to harness contract
    vm.prank(dao);
    hats.mintHat(hat1_1, address(harness));
  }
}

contract Internal_extensionThreshold is InternalTest {
  uint256 actual;
  uint256 expected;

  function test_fuzz_threshold(uint256 _seasonEnd, uint256 _extensionDelay, uint256 _seasonDuration) public {
    _extensionDelay = bound(_extensionDelay, 0, DELAY_DIVISOR);
    // seasonDuration must be at least 1 hour
    _seasonDuration = bound(_seasonDuration, 1 days, 100_000 days);
    _seasonEnd = bound(_seasonEnd, _seasonDuration, seasonStart + 100_000 days);

    actual = harness.extensionThreshold_(_seasonEnd, _extensionDelay, _seasonDuration);
    expected = (_seasonEnd) - (((DELAY_DIVISOR - _extensionDelay) * _seasonDuration) / DELAY_DIVISOR);

    assertEq(actual, expected, "Threshold");
  }

  function test_threshold_halfDelay() public {
    seasonEnd = block.timestamp + 1000 days;
    actual = harness.extensionThreshold_(seasonEnd, 5000, 500 days);
    expected = seasonEnd - 250 days; // 500 / (5000 / 10000) = 500 / 2
    assertEq(actual, expected);
  }

  function test_threshold_noDelay() public {
    seasonEnd = block.timestamp + 1000 days;
    actual = harness.extensionThreshold_(seasonEnd, 0, 500 days);
    expected = seasonEnd - 500 days; // 500 / (10000 / 10000) = 500 / 1
    assertEq(actual, expected);
  }

  function test_threshold_fullDelay() public {
    seasonEnd = block.timestamp + 1000 days;
    actual = harness.extensionThreshold_(seasonEnd, DELAY_DIVISOR, 500 days);
    expected = seasonEnd - 0 days; // 500 / (0 / 10000) = 500 / 2
    assertEq(actual, expected);
  }
}

contract SetUp is InternalTest {
  // attempt to set up the implementation again
  function test_reverts_forImplementation() public {
    vm.prank(address(this)); // this contract served as the factory for the harness, but not the implementation
    vm.expectRevert();
    implementation.setUp(abi.encodePacked(seasonDuration, extensionDelay));
  }

  function test_reverts_forNonFactoryCaller() public {
    vm.prank(other);
    vm.expectRevert();
    harness.setUp(abi.encodePacked(seasonDuration, extensionDelay));
  }

  function test_reverts_forInvalidSeasonDuration() public {
    vm.expectRevert();
    // try a just-too-short duration
    factory.createHatsModule(
      address(harnessImplementation), hat1_1, bytes(""), abi.encodePacked(MIN_SEASON_DURATION - 1, extensionDelay)
    );
  }

  function test_reverts_forInvalidExtensionDelay() public {
    vm.expectRevert();
    factory.createHatsModule(
      address(harnessImplementation), hat1_1, bytes(""), abi.encodePacked(seasonDuration, DELAY_DIVISOR + 1)
    );
  }
}

contract DeployInstance is SeasonToggleTest {
  function test_CorrectInitialVariables() public {
    assertEq(address(instance.IMPLEMENTATION()), address(implementation), "implementation");
    assertEq(address(instance.HATS()), address(hats), "hats");
    assertEq(instance.hatId(), hat1_1, "hatId");
    assertEq(instance.seasonDuration(), seasonDuration, "seasonDuration");
    assertEq(instance.extensionDelay(), extensionDelay, "extensionDelay");
    assertEq(instance.seasonEnd(), seasonStart + instance.seasonDuration(), "seasonEnd");
    assertEq(instance.version(), "0.1.0", "version");
  }
}

contract GetHatStatus is SeasonToggleTest {
  uint256 testHat;

  function setUp() public override {
    super.setUp();
    // create hat1_1_1
    vm.prank(dao);
    hat1_1_1 = hats.createHat(hat1_1, "hat1_1_1", 2, address(1), address(instance), true, "");
  }

  function inSeason(uint256 _testHat) public {
    vm.warp(seasonStart + 1);
    assertTrue(instance.getHatStatus(_testHat), "seasonStart + 1");

    vm.warp(seasonEnd - 1);
    assertTrue(instance.getHatStatus(_testHat), "seasonStart + seasonDuration - 1");
  }

  function outOfSeason(uint256 _testHat) public {
    // hats become inactive on the last second of the season
    vm.warp(seasonEnd);
    assertFalse(instance.getHatStatus(_testHat), "seasonStart + seasonDuration");

    vm.warp(justAfterSeason);
    assertFalse(instance.getHatStatus(_testHat), "seasonStart + seasonDuration + 1");

    vm.warp(farAfterSeason);
    assertFalse(instance.getHatStatus(_testHat), "seasonStart + seasonDuration + 100");
  }

  function test_true_forHatOutOfBranch() public {
    testHat = 1;
    inSeason(testHat);
    outOfSeason(testHat);
  }

  function test_true_forHatInBranch_inSeason() public {
    inSeason(hat1_1_1);
  }

  function test_true_forBranchRoot_inSeason() public {
    inSeason(hat1_1);
  }

  function test_false_forHatInBranch_outOfSeason() public {
    outOfSeason(hat1_1_1);
  }

  function test_false_forBranchRoot_outOfSeason() public {
    outOfSeason(hat1_1);
  }
}

contract Extend is SeasonToggleTest {
  uint256 newDuration;
  uint256 newDelay;

  function test_reverts_forNonBranchAdmin() public {
    vm.prank(other);
    vm.expectRevert(SeasonToggle_NotBranchAdmin.selector);
    instance.extend(0, 0);
  }

  function test_reverts_ifNotExtendable() public {
    vm.prank(dao);
    vm.warp(justBeforeThreshold);
    vm.expectRevert(SeasonToggle_NotExtendable.selector);
    instance.extend(0, 0);
  }

  function test_reverts_forInvalidDelayValue(uint256 delay) public {
    vm.assume(delay > DELAY_DIVISOR);
    // ensure its extendable
    vm.warp(justAfterThreshold);
    // try to extend with an invalid delay value
    vm.prank(dao);
    vm.expectRevert(SeasonToggle_InvalidExtensionDelay.selector);
    instance.extend(0, delay);
  }

  function test_reverts_forInvalidSeasonDuration(uint256 duration) public {
    duration = bound(duration, 1, 1 hours - 1);
    // ensure its extendable
    vm.warp(justAfterThreshold);
    // try to extend with an invalid season duration
    vm.prank(dao);
    vm.expectRevert(SeasonToggle_SeasonDurationTooShort.selector);
    instance.extend(duration, 0);
  }

  function test_extend_withNoChanges() public {
    // ensure its extendable
    vm.warp(justAfterThreshold);
    // extend
    vm.prank(dao);
    instance.extend(0, 0);
    // check that the season duration and extension delay are unchanged
    assertEq(instance.seasonDuration(), seasonDuration, "seasonDuration");
    assertEq(instance.extensionDelay(), extensionDelay, "extensionDelay");
    assertEq(instance.seasonEnd(), seasonStart + (2 * seasonDuration), "seasonEnd");
  }

  function test_extend_withDurationChange() public {
    // ensure its extendable
    vm.warp(justAfterThreshold);
    // extend
    newDuration = seasonDuration + 1;
    vm.prank(dao);
    instance.extend(newDuration, 0);
    // check that the season duration and extension delay are correct
    assertEq(instance.seasonDuration(), seasonDuration + 1, "seasonDuration");
    assertEq(instance.extensionDelay(), extensionDelay, "extensionDelay");
    assertEq(instance.seasonEnd(), seasonStart + seasonDuration + newDuration, "seasonEnd");
  }

  function test_extend_withDelayChange() public {
    // ensure its extendable
    vm.warp(justAfterThreshold);
    // extend
    newDelay = 5000;
    vm.prank(dao);
    instance.extend(0, 5000);
    // check that the season duration and extension delay are correct
    assertEq(instance.seasonDuration(), seasonDuration, "seasonDuration");
    assertEq(instance.extensionDelay(), newDelay, "extensionDelay");
    assertEq(instance.seasonEnd(), seasonStart + (2 * seasonDuration), "seasonEnd");
  }

  function test_extend_withBothChanges() public {
    // ensure its extendable
    vm.warp(justAfterThreshold);
    // extend
    newDuration = seasonDuration + 1;
    newDelay = 5000;
    vm.prank(dao);
    instance.extend(seasonDuration + 1, newDelay);
    // check that the season duration and extension delay are correct
    assertEq(instance.seasonDuration(), seasonDuration + 1, "seasonDuration");
    assertEq(instance.extensionDelay(), newDelay, "extensionDelay");
    assertEq(instance.seasonEnd(), seasonStart + seasonDuration + newDuration, "seasonEnd");
  }

  function test_extend_again_withNoChanges() public {
    // ensure its extendable
    vm.warp(justAfterThreshold);
    // extend
    vm.prank(dao);
    instance.extend(0, 0);
    // extend again
    vm.warp(
      seasonStart + (2 * seasonDuration) - (((DELAY_DIVISOR - extensionDelay) * seasonDuration) / DELAY_DIVISOR) + 1
    );
    vm.prank(dao);
    instance.extend(0, 0);
    // check that the season duration and extension delay are unchanged
    assertEq(instance.seasonDuration(), seasonDuration, "seasonDuration");
    assertEq(instance.extensionDelay(), extensionDelay, "extensionDelay");
    // and the seasonEnd is correct
    assertEq(instance.seasonEnd(), seasonStart + (3 * seasonDuration), "seasonEnd");
  }
}

contract ExtensionThreshold is SeasonToggleTest {
  function test_threshold() public {
    uint256 actual = instance.extensionThreshold();
    uint256 expected =
      seasonStart + seasonDuration - (((DELAY_DIVISOR - extensionDelay) * seasonDuration) / DELAY_DIVISOR);
    assertEq(actual, expected, "Threshold");
  }

  function test_afterExtension() public {
    // warp to just after the threshold
    vm.warp(justAfterThreshold);
    // extend another season
    vm.prank(dao);
    instance.extend(0, 0);

    uint256 actual = instance.extensionThreshold();
    uint256 expected =
      seasonStart + seasonDuration + (((DELAY_DIVISOR - extensionDelay) * seasonDuration) / DELAY_DIVISOR);
    assertEq(actual, expected, "Threshold");
  }
}

contract Extendable is SeasonToggleTest {
  function test_true_forAtSeasonEnd() public {
    vm.warp(seasonEnd);
    assertTrue(instance.extendable());
  }

  function test_true_forAfterSeasonEnd() public {
    vm.warp(justAfterSeason);
    assertTrue(instance.extendable());

    vm.warp(farAfterSeason);
    assertTrue(instance.extendable());
  }

  function test_true_forAtThreshold() public {
    vm.warp(atThreshold);
    assertTrue(instance.extendable());
  }

  function test_false_forBeforeThreshold() public {
    vm.warp(farBeforeThreshold);
    assertFalse(instance.extendable());

    vm.warp(justBeforeThreshold);
    assertFalse(instance.extendable());
  }
}
