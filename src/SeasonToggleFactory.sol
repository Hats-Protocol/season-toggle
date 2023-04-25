// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// import { console2 } from "forge-std/Test.sol"; // remove before deploy
import { SeasonToggle } from "src/SeasonToggle.sol";
import { LibClone } from "solady/utils/LibClone.sol";
import { IHats } from "hats-protocol/Interfaces/IHats.sol";

contract SeasonToggleFactory {
  /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
  //////////////////////////////////////////////////////////////*/

  /// @notice Emitted if attempting to deploy a SeasonToggle for a hat `branchRoot` that already has a SeasonToggle
  /// deployment
  error SeasonToggleFactory_AlreadyDeployed(uint256 branchRoot);

  /*//////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  /// @notice Emitted when a SeasonToggle for `branchRoot` is deployed to address `instance`
  event SeasonToggleDeployed(
    uint256 branchRoot, address instance, uint256 _seasonDuration, uint256 _extendabilityDelay
  );

  /*//////////////////////////////////////////////////////////////
                            CONSTANTS
  //////////////////////////////////////////////////////////////*/

  /// @notice The address of the SeasonToggle implementation
  SeasonToggle public immutable IMPLEMENTATION;
  /// @notice The address of the Hats Protocol
  IHats public immutable HATS;
  /// @notice The version of this SeasonToggleFactory
  string public version;

  /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
  //////////////////////////////////////////////////////////////*/

  /**
   * @param _implementation The address of the SeasonToggle implementation
   * @param _version The label for this version of SeasonToggle
   */
  constructor(SeasonToggle _implementation, IHats _hats, string memory _version) {
    IMPLEMENTATION = _implementation;
    HATS = _hats;
    version = _version;
  }

  /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Deploys a new SeasonToggle instance for a given `_branchRoot` to a deterministic address, if not already
   * deployed, and sets up the new instance with initial operational values.
   * @dev Will revert *after* the instance is deployed if their initial values are invalid.
   * @param _branchRoot The hat for which to deploy a SeasonToggle.
   * @param _seasonDuration The length of the season, in seconds. Must be >= 1 day (`86400` seconds).
   * @param _extendabilityDelay The proportion of the season that must elapse before the branch can be extended
   * for another season. Must be <= 10,000.
   * @return _instance The address of the deployed SeasonToggle instance
   */
  function createSeasonToggle(uint256 _branchRoot, uint256 _seasonDuration, uint256 _extendabilityDelay)
    public
    returns (SeasonToggle _instance)
  {
    // check if SeasonToggle has already been deployed for _branchRoot
    if (deployed(_branchRoot)) revert SeasonToggleFactory_AlreadyDeployed(_branchRoot);
    // deploy the clone to a deterministic address
    _instance = _createSeasonToggle(_branchRoot);
    // set up the toggle with initial operational values
    _instance.setUp(_seasonDuration, _extendabilityDelay);
    // log the deployment and setUp
    emit SeasonToggleDeployed(_branchRoot, address(_instance), _seasonDuration, _extendabilityDelay);
  }

  /**
   * @notice Predicts the address of a SeasonToggle instance for a given hat
   * @param _branchRoot The hat for which to predict the SeasonToggle instance address
   * @return The predicted address of the deployed instance
   */
  function getSeasonToggleAddress(uint256 _branchRoot) public view returns (address) {
    // prepare the unique inputs
    bytes memory args = _encodeArgs(_branchRoot);
    bytes32 _salt = _calculateSalt(args);
    // predict the address
    return _getSeasonToggleAddress(args, _salt);
  }

  /**
   * @notice Checks if a SeasonToggle instance has already been deployed for a given hat
   * @param _branchRoot The hat for which to check for an existing instance
   * @return True if an instance has already been deployed for the given hat
   */
  function deployed(uint256 _branchRoot) public view returns (bool) {
    bytes memory args = _encodeArgs(_branchRoot);
    // predict the address
    address instance = _getSeasonToggleAddress(args, _calculateSalt(args));
    // check for contract code at the predicted address
    return instance.code.length > 0;
  }

  /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
   * @notice Deployes a new SeasonToggle contract for a given hat, to a deterministic address
   * @param _branchRoot The hat for which to deploy a SeasonToggle
   * @return _instance The address of the deployed SeasonToggle
   */
  function _createSeasonToggle(uint256 _branchRoot) internal returns (SeasonToggle _instance) {
    // encode the Hats contract adddress and _branchRoot to pass as immutable args when deploying the clone
    bytes memory args = _encodeArgs(_branchRoot);
    // calculate the determinstic address salt as the hash of the _branchRoot and the Hats Protocol address
    bytes32 _salt = _calculateSalt(args);
    // deploy the clone to the deterministic address
    _instance = SeasonToggle(LibClone.cloneDeterministic(address(IMPLEMENTATION), args, _salt));
  }

  /**
   * @notice Predicts the address of a SeasonToggle contract given the encoded arguments and salt
   * @param _arg The encoded arguments to pass to the clone as immutable storage
   * @param _salt The salt to use when deploying the clone
   * @return The predicted address of the deployed SeasonToggle
   */
  function _getSeasonToggleAddress(bytes memory _arg, bytes32 _salt) internal view returns (address) {
    return LibClone.predictDeterministicAddress(address(IMPLEMENTATION), _arg, _salt, address(this));
  }

  /**
   * @notice Encodes the arguments to pass to the clone as immutable storage. The arguments are:
   *  - The address of this factory
   *  - The`_branchRoot`
   * @param _branchRoot The hat for which to deploy a SeasonToggle
   * @return The encoded arguments
   */
  function _encodeArgs(uint256 _branchRoot) internal view returns (bytes memory) {
    // find the local hat level of _branchRoot
    uint32 branchRootLevel = HATS.getLocalHatLevel(_branchRoot);
    return abi.encodePacked(address(this), HATS, _branchRoot, branchRootLevel);
  }

  /**
   * @notice Calculates the salt to use when deploying the clone. The (packed) inputs are:
   *  - The address of the this contract, `FACTORY` (passed as part of `_args`)
   *  - The`_branchRoot` (passed as part of `_args`)
   *  - The chain ID of the current network, to avoid confusion across networks since the same hat trees
   *    on different networks may have different wearers/admins
   * @dev
   * @param _args The encoded arguments to pass to the clone as immutable storage
   * @return The salt to use when deploying the clone
   */
  function _calculateSalt(bytes memory _args) internal view returns (bytes32) {
    return keccak256(abi.encodePacked(_args, block.chainid));
  }
}
