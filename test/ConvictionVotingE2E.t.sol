// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";

import {AragonE2E} from "./base/AragonE2E.sol";
import {ConvictionVotingSetup} from "../src/ConvictionVotingSetup.sol";
import {ConvictionVoting} from "../src/ConvictionVoting.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {MockPriceOracle} from "./mocks/MockPriceOracle.sol";
import {MockToken} from "./mocks/MockToken.sol";

contract ConvictionVotingE2E is AragonE2E {
    DAO internal dao;
    ConvictionVoting internal plugin;
    PluginRepo internal repo;
    ConvictionVotingSetup internal setup;

    //
    IERC20 internal stakeToken;
    IERC20 internal usdc;
    IPriceOracle internal priceOracle;

    //
    uint256 internal constant PERCENT_100 = 10 ** 18;
    uint256 internal constant D = 10 ** 7;
    uint256 internal constant DEFAULT_ALPHA = (9 * D) / 10; // DECAY
    uint256 internal constant DEFAULT_BETA = (2 * D) / 10; // WEIGHT
    uint256 internal constant DEFAULT_RHO = (2 * D) / 1000; // RATIO
    uint256 internal constant MIN_THRESHOLD_STAKE_PERCENTAGE = PERCENT_100 / 5; // 20%
    uint256 internal constant DEFAULT_MIN_PROPOSAL_TOKENS = 10 ** 18; // 1 token

    address internal unauthorised = account("unauthorised");

    function setUp() public virtual override {
        super.setUp();
        setup = new ConvictionVotingSetup();
    }

    function test_e2e() public {
        address _plugin;

        stakeToken = IERC20(new MockToken("Stake Token", "STK", 1000, address(this)));
        usdc = IERC20(new MockToken("USDC", "USDC", 1000, address(this)));
        priceOracle = IPriceOracle((new MockPriceOracle(69)));

        bytes memory setupData = setup.encodeInstallData({
            _stakeToken: stakeToken,
            _requestToken: stakeToken,
            _stableToken: usdc,
            _stableTokenOracle: priceOracle,
            _decay: DEFAULT_ALPHA,
            _maxRatio: DEFAULT_BETA,
            _weight: DEFAULT_RHO,
            _minThresholdStakePercentage: MIN_THRESHOLD_STAKE_PERCENTAGE,
            _minProposerTokens: DEFAULT_MIN_PROPOSAL_TOKENS
        });

        (dao, repo, _plugin) = deployRepoAndDao(
            "conviction-voting-42069",
            address(setup),
            setupData
        );

        plugin = ConvictionVoting(_plugin);

        // test repo
        PluginRepo.Version memory version = repo.getLatestVersion(repo.latestRelease());
        assertEq(version.pluginSetup, address(setup));
        assertEq(version.buildMetadata, NON_EMPTY_BYTES);

        // test dao
        assertEq(keccak256(bytes(dao.daoURI())), keccak256(bytes("https://mockDaoURL.com")));

        // test plugin init correctly
        assertEq(address(plugin.dao()), address(dao));
        assertEq(address(plugin.stakeToken()), address(stakeToken));

        // test dao pause plugin
        vm.prank(address(dao));
        plugin.pauseContract(true);
        assertEq(plugin.contractPaused(), true);

        // test unauthorised cannot store number
        vm.prank(unauthorised);
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                dao,
                plugin,
                unauthorised,
                keccak256("PAUSE_CONTRACT")
            )
        );
        plugin.pauseContract(true);
    }
}
