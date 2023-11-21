// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";

import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";
import {PluginSetup, IPluginSetup} from "@aragon/osx/framework/plugin/setup/PluginSetup.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {ConvictionVoting} from "./ConvictionVoting.sol";

/// @title ConvictionVotingSetup build 1
contract ConvictionVotingSetup is PluginSetup {
    address private immutable IMPLEMEMTATION;
    address private constant ANY_ADDR = address(type(uint160).max);

    constructor() {
        IMPLEMEMTATION = address(new ConvictionVoting());
    }

    /// @inheritdoc IPluginSetup
    function prepareInstallation(
        address _dao,
        bytes memory _data
    ) external returns (address plugin, PreparedSetupData memory preparedSetupData) {
        (
            IERC20 _stakeToken,
            IERC20 _requestToken,
            IERC20 _stableToken,
            IPriceOracle _stableTokenOracle,
            uint256 _decay,
            uint256 _maxRatio,
            uint256 _weight,
            uint256 _minThresholdStakePercentage,
            uint256 _minProposalTokens
        ) = decodeInstallData(_data);

        plugin = createERC1967Proxy(
            IMPLEMEMTATION,
            abi.encodeCall(
                ConvictionVoting.initialize,
                (
                    IDAO(_dao),
                    _stakeToken,
                    _requestToken,
                    _stableToken,
                    _stableTokenOracle,
                    _decay,
                    _maxRatio,
                    _weight,
                    _minThresholdStakePercentage,
                    _minProposalTokens
                )
            )
        );

        PermissionLib.MultiTargetPermission[]
            memory permissions = new PermissionLib.MultiTargetPermission[](3);

        // permissions[3] = PermissionLib.MultiTargetPermission({
        //     operation: PermissionLib.Operation.Grant,
        //     where: plugin,
        //     who: address(type(uint160).max),
        //     condition: PermissionLib.NO_CONDITION,
        //     permissionId: keccak256("CREATE_PROPOSALS")
        // });

        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: keccak256("UPDATE_SETTINGS")
        });

        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: keccak256("PAUSE_CONTRACT")
        });

        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _dao,
            who: plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: keccak256("EXECUTE_PERMISSION")
        });
        preparedSetupData.permissions = permissions;
    }

    /// @inheritdoc IPluginSetup
    function prepareUninstallation(
        address _dao,
        SetupPayload calldata _payload
    ) external pure returns (PermissionLib.MultiTargetPermission[] memory permissions) {
        permissions = new PermissionLib.MultiTargetPermission[](1);

        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: keccak256("STORE_PERMISSION")
        });
    }

    /// @inheritdoc IPluginSetup
    function implementation() external view returns (address) {
        return IMPLEMEMTATION;
    }

    function encodeInstallData(
        IERC20 _stakeToken,
        IERC20 _requestToken,
        IERC20 _stableToken,
        IPriceOracle _stableTokenOracle,
        uint256 _decay,
        uint256 _maxRatio,
        uint256 _weight,
        uint256 _minThresholdStakePercentage,
        uint256 _minProposerTokens
    ) external pure returns (bytes memory) {
        return
            abi.encode(
                _stakeToken,
                _requestToken,
                _stableToken,
                _stableTokenOracle,
                _decay,
                _maxRatio,
                _weight,
                _minThresholdStakePercentage,
                _minProposerTokens
            );
    }

    function decodeInstallData(
        bytes memory _data
    )
        public
        pure
        returns (
            IERC20 _stakeToken,
            IERC20 _requestToken,
            IERC20 _stableToken,
            IPriceOracle _stableTokenOracle,
            uint256 _decay,
            uint256 _maxRatio,
            uint256 _weight,
            uint256 _minThresholdStakePercentage,
            uint256 _minProposalTokens
        )
    {
        return
            abi.decode(
                _data,
                (IERC20, IERC20, IERC20, IPriceOracle, uint256, uint256, uint256, uint256, uint256)
            );
    }
}
