// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import { console2 } from "forge-std/Test.sol"; // remove before deploy
import { SeasonToggleFactory } from "./SeasonToggleFactory.sol";
import { IHatsToggle } from "hats-protocol/Interfaces/IHatsToggle.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";
import { Clone } from "solady/utils/Clone.sol";

/**
 * TODO
 *  [x] - refactor into clone factory
 *  [x] - simplify logic
 *  [x] - add events
 *  [x] - add custom errors
 *  [x] - write deploy script
 *  [ ] - write tests
 *  [x] - install solady dep
 */

contract SeasonToggle is Clone, IHatsToggle {
  /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
  //////////////////////////////////////////////////////////////*/

  /// @notice Thrown when a non-admin attempts to extend a branch to a new season
  error SeasonToggle_NotBranchAdmin();
  /// @notice Thrown when attempting to extend a branch to a new season before its extendable
  error SeasonToggle_NotExtendable();
  /// @notice Valid extendability delays are <= 10,000
  error SeasonToggle_InvalidExtendabilityDelay();
  /// @notice Season durations must be at least `MIN_SEASON_DURATION` long
  error SeasonToggle_SeasonDurationTooShort();
  /// @notice Emitted when a non-factory address attempts to call an onlyFactory function
  error SeasonToggle_NotFactory();

  /*//////////////////////////////////////////////////////////////
                                EVENTS
  //////////////////////////////////////////////////////////////*/

  /// @notice Emitted when `_branchRoot` has been extended to a new season
  event Extended(uint256 _branchRoot, uint256 _duration, uint256 _extendabilityDelay);

  /*//////////////////////////////////////////////////////////////
                              CONSTANTS
  //////////////////////////////////////////////////////////////*/

  /**
   * This contract is a clone with immutable args, which means that it is deployed with a set of
   * immutable storage variables (ie constants). Accessing these constants is cheaper than accessing
   * regular storage variables (such as those set on initialization of a typical EIP-1167 clone),
   * but requires a slightly different approach since they are read from calldata instead of storage.
   *
   * Below is a table of constants and their location.
   *
   * For more, see here: https://github.com/Saw-mon-and-Natalie/clones-with-immutable-args
   *
   * --------------------------------------------------------------------+
   * CLONE IMMUTABLE "STORAGE"                                           |
   * --------------------------------------------------------------------|
   * Offset  | Constant        | Type    | Length  |                     |
   * --------------------------------------------------------------------|
   * 0       | FACTORY         | address | 20      |                     |
   * 20      | HATS            | address | 20      |                     |
   * 40      | branchRoot      | uint256 | 32      |                     |
   * 72      | branchRootLevel | uint32  | 4       |                     |
   * --------------------------------------------------------------------+
   */

  /// @notice The address of the SeasonToggleFactory that deployed this contract
  function FACTORY() public pure returns (SeasonToggleFactory) {
    return SeasonToggleFactory(_getArgAddress(0));
  }

  /// @notice Hats Protocol address
  function HATS() public pure returns (IHats) {
    return IHats(_getArgAddress(20));
  }

  /// @notice The hat id of the root of the branch to which this instance applies
  function branchRoot() public pure returns (uint256) {
    return _getArgUint256(40);
  }

  /// @notice The level of the branch root within its local hat tree
  /// @dev Used to determine whether a given hat is within the `branchRoot`
  function branchRootLevel() public pure returns (uint32) {
    return _getArgUint32(72);
  }

  /// @notice The minimum length of a season
  uint256 public constant MIN_SEASON_DURATION = 86_400; // 1 day = 86,400 seconds

  /// @notice The version of this SeasonToggle implementation
  /// @dev This value is not set in clones
  string internal _version;

  /// @notice The version of this SeasonToggle
  function version() public view returns (string memory version_) {
    // If the factory is set (ie this is a clone), use its version
    if (address(FACTORY()) != address(0)) return FACTORY().version();
    // Otherwise (ie this is the implementation contract), use the version from storage
    else return _version;
  }

  /*//////////////////////////////////////////////////////////////
                            MUTABLE STATE
  //////////////////////////////////////////////////////////////*/

  /// @notice The timestamp after which the current season ends, i.e. after which hats in this instance's branch will no
  /// longer be active
  uint256 public seasonEnd;
  /// @notice The length of the current season, in seconds
  uint256 public seasonDuration;

  /**
   * @notice The proportion of the current season that must elapse before the branch can be extended to another season.
   * @dev Stored in the form of `x` in the expression `x / 10,000`. Here are some sample values:
   *   - 0      ⇒ none of the current season must have passed before another season can be added
   *   - 5,000  ⇒ 50% of the current season must have passed before another season can be added
   *   - 10,000 ⇒ 100% of the current season must have passed before another season can be added
   */
  uint256 public extendabilityDelay;

  /*//////////////////////////////////////////////////////////////
                            INITIALIZER
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Sets up this instance with initial operational values
   * @dev Only callable by the factory. Since the factory only calls this function during a new deployment, this ensures
   * it can only be called once per instance, and that the implementation contract is never initialized.
   * @param _seasonDuration The length of the season, in seconds. Must be >= 1 day (`86400` seconds).
   * @param _extendabilityDelay The proportion of the season that must elapse before the branch can be extended
   * for another season. The value is treated as the numerator `x` in the expression `x / 10,000`, and therefore must be
   * <= 10,000.
   */
  function setUp(uint256 _seasonDuration, uint256 _extendabilityDelay) public onlyFactory {
    // prevent invalid extendability delays
    if (_extendabilityDelay > 10_000) revert SeasonToggle_InvalidExtendabilityDelay();
    // season duration must be non-zero, otherwise
    if (_seasonDuration < MIN_SEASON_DURATION) revert SeasonToggle_SeasonDurationTooShort();
    // initialize the mutable state vars
    seasonDuration = _seasonDuration;
    extendabilityDelay = _extendabilityDelay;
    seasonEnd = block.timestamp + _seasonDuration;
  }

  /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  /// @notice Deploy the SeasonToggle implementation contract and set its `_version`
  /// @dev This is only used to deploy the implementation contract, and should not be used to deploy clones
  constructor(string memory __version) {
    _version = __version;
  }

  /*//////////////////////////////////////////////////////////////
                          HATS TOGGLE FUNCTION
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Check if a hat is active (not expired, in this case).
   * @dev Does not revert if `_hatId` is not within this instance's branch, in order to not break the Hats wearer
   * checks. Instead, it returns true.
   * @param _hatId The id of the hat to check.
   * @return _active False if `_hatId` has expired; true otherwise.
   */
  function getHatStatus(uint256 _hatId) external view override returns (bool _active) {
    // return true if the hat is not in this instance's branch; ensures this contract only affects hats within this
    // instance's branch
    if (!inBranch(_hatId)) return true;
    // otherwise, the hat is active if the season has not yet ended
    return block.timestamp <= seasonEnd;
  }

  /*//////////////////////////////////////////////////////////////
                           ADMIN FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Extend the branch for a new season, optionally with a new season duration. This function is typically
   * called once the toggle has already been set up, but it can also be used to set it up for the first time.
   * @dev Requires admin privileges for the branchRoot hat.
   * @param _duration [OPTIONAL] A new custom season duration, in seconds. Set to 0 to re-use the previous
   * duration.
   * @param _extendabilityDelay [OPTIONAL] A new delay
   */
  function extend(uint256 _duration, uint256 _extendabilityDelay) external {
    // prevent non-admins from extending
    if (!HATS().isAdminOfHat(msg.sender, branchRoot())) revert SeasonToggle_NotBranchAdmin();
    // prevent extending before half of current season has elapsed
    if (!extendable()) revert SeasonToggle_NotExtendable();
    // prevent invalid extendability delays
    if (_extendabilityDelay > 10_000) revert SeasonToggle_InvalidExtendabilityDelay();

    // process the optional _duration value
    uint256 duration;
    // if new, store the new value and prepare to use it
    if (_duration > 0) {
      // prevent too short derations
      if (_duration < MIN_SEASON_DURATION) revert SeasonToggle_SeasonDurationTooShort();
      // store the new value; will be used to check extendability for next season
      seasonDuration = _duration;
      // prepare to use it
      duration = _duration;
    } else {
      // otherwise, just prepare to use the existing value from storage
      duration = seasonDuration;
    }

    // process the optional _extendabilityDelay value. We know a set value is valid because of the earlier check.
    if (_extendabilityDelay > 0) extendabilityDelay = _extendabilityDelay;

    // extend the expiry by duration
    seasonEnd += duration;
    // log the extension
    emit Extended(branchRoot(), _duration, _extendabilityDelay);
  }

  /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Whether the expiry for this branch can be extended to another season, which is allowed if more than
   * half of the current season has elapsed
   */
  function extendable() public view returns (bool) {
    return block.timestamp >= _extendabilityThreshold(seasonEnd, extendabilityDelay, seasonDuration);
  }

  /**
   * @notice The timestamp at which the branch can be extended to another season, i.e. when it becomes {extendable}
   *
   */
  function extendabilityThreshold() public view returns (uint256) {
    return _extendabilityThreshold(seasonEnd, extendabilityDelay, seasonDuration);
  }

  /**
   * @notice Whether the given hat is within the hat branch tied to this instance of SeasonToggle
   * @param _hatId The id of the hat to check
   * @return bool True if `_hatId` is within this instance's branch; false otherwise
   */
  function inBranch(uint256 _hatId) public pure returns (bool) {
    // clear all bits in _hatId after the branchRootLevel
    uint256 bitsToShift = (14 - branchRootLevel()) * 16;
    uint256 truncatedHatId = _hatId >> bitsToShift << bitsToShift;
    // return true if the truncated hatId matches the branch root
    return branchRoot() == truncatedHatId;
  }

  /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice The timestamp at which the branch can be extended to another season, i.e. when it becomes {extendable}
   * @param _seasonEnd The timestamp at which the current season ends
   * @param _extendabilityDelay The proportion of the season that must elapse before the branch can be extended
   * for another season. The value is treated as the numerator `x` in the expression `x / 10,000`, and therefore must be
   * <= 10,000.
   * @param _seasonDuration The length of the season, in seconds. Must be >= 1 day (`86400` seconds).
   */
  function _extendabilityThreshold(uint256 _seasonEnd, uint256 _extendabilityDelay, uint256 _seasonDuration)
    internal
    pure
    returns (uint256)
  {
    return (_seasonEnd - (((10_000 - _extendabilityDelay) * _seasonDuration) / 10_000));
  }

  /*//////////////////////////////////////////////////////////////
                            MODIFIERS
  //////////////////////////////////////////////////////////////*/

  modifier onlyFactory() {
    if (msg.sender != address(FACTORY())) revert SeasonToggle_NotFactory();
    _;
  }
}
