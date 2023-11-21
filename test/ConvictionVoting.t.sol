// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;
import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";

import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";
import {AragonTest} from "./base/AragonTest.sol";
import {ConvictionVotingSetup} from "../src/ConvictionVotingSetup.sol";
import {ConvictionVoting} from "../src/ConvictionVoting.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {MockPriceOracle} from "./mocks/MockPriceOracle.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {Types} from "../src/Types.sol";

abstract contract ConvictionVotingTest is AragonTest {
    DAO internal dao;
    ConvictionVoting internal plugin;
    ConvictionVotingSetup internal setup;
    address internal proposer = account("proposer");

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

    function setUp() public virtual {
        setup = new ConvictionVotingSetup();
        stakeToken = IERC20(new MockToken("Stake Token", "STK", 1000, address(this)));
        usdc = IERC20(new MockToken("USDC", "USDC", 1000, address(this)));
        priceOracle = IPriceOracle((new MockPriceOracle(69)));

        stakeToken.transfer(proposer, 100 ** 18);

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

        (DAO _dao, address _plugin) = createMockDaoWithPlugin(setup, setupData);

        dao = _dao;
        plugin = ConvictionVoting(_plugin);

        vm.label(address(dao), "DAO");
        vm.label(address(plugin), "PLUGIN");
        vm.label(address(stakeToken), "STAKE_TOKEN");
        vm.label(address(usdc), "USDC");
        vm.label(address(priceOracle), "PRICE_ORACLE");
    }
}

contract ConvictionVotingInitializeTest is ConvictionVotingTest {
    function setUp() public override {
        super.setUp();
    }

    function test_initialize() public {
        assertEq(address(plugin.dao()), address(dao));
        assertEq(address(plugin.stakeToken()), address(stakeToken));
        assertEq(plugin.proposalCounter(), 2);
        assertEq(address(plugin.stakeToken()), address(stakeToken));
        assertEq(address(plugin.requestToken()), address(stakeToken));
        assertEq(address(plugin.stableToken()), address(usdc));
        assertEq(address(plugin.stableTokenOracle()), address(priceOracle));
        assertEq(plugin.decay(), DEFAULT_ALPHA);
        assertEq(plugin.maxRatio(), DEFAULT_BETA);
        assertEq(plugin.weight(), DEFAULT_RHO);
        assertEq(plugin.minThresholdStakePercentage(), MIN_THRESHOLD_STAKE_PERCENTAGE);
    }

    function test_reverts_if_reinitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        plugin.initialize({
            _dao: dao,
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
    }
}

contract ConvictionVotingPauseTest is ConvictionVotingTest {
    function setUp() public override {
        super.setUp();
    }

    function test_pause_contract() public {
        assertEq(plugin.contractPaused(), false);

        vm.prank(address(dao));
        plugin.pauseContract(true);
        assertEq(plugin.contractPaused(), true);

        vm.prank(address(dao));
        plugin.pauseContract(false);
        assertEq(plugin.contractPaused(), false);
    }

    function test_reverts_if_not_auth() public {
        // error DaoUnauthorized({dao: address(_dao),  where: _where,  who: _who,permissionId: _permissionId });
        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                dao,
                plugin,
                address(this),
                keccak256("PAUSE_CONTRACT")
            )
        );
        plugin.pauseContract(true);
    }
}

// GPT ============================================================================================

contract ConvictionVotingSetStableTokenOracleSettingsTest is ConvictionVotingTest {
    function setUp() public override {
        super.setUp();
    }

    function test_setStableTokenOracleSettings() public {
        IERC20 newStableToken = IERC20(
            new MockToken("New Stable Token", "NST", 1000, address(this))
        );
        IPriceOracle newPriceOracle = IPriceOracle((new MockPriceOracle(42)));

        vm.prank(address(dao));
        plugin.setStableTokenOracleSettings(newPriceOracle, newStableToken);

        assertEq(address(plugin.stableToken()), address(newStableToken));
        assertEq(address(plugin.stableTokenOracle()), address(newPriceOracle));
    }

    function test_reverts_if_not_auth_setStableTokenOracleSettings() public {
        IERC20 newStableToken = IERC20(
            new MockToken("New Stable Token", "NST", 1000, address(this))
        );
        IPriceOracle newPriceOracle = IPriceOracle((new MockPriceOracle(42)));

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                dao,
                plugin,
                address(this),
                keccak256("UPDATE_SETTINGS")
            )
        );
        plugin.setStableTokenOracleSettings(newPriceOracle, newStableToken);
    }
}

contract ConvictionVotingSetConvictionCalculationSettingsTest is ConvictionVotingTest {
    function setUp() public override {
        super.setUp();
    }

    function test_setConvictionCalculationSettings() public {
        uint256 newDecay = DEFAULT_ALPHA - 1;
        uint256 newMaxRatio = DEFAULT_BETA + 1;
        uint256 newWeight = DEFAULT_RHO + 1;
        uint256 newMinThresholdStakePercentage = MIN_THRESHOLD_STAKE_PERCENTAGE - 1;

        vm.prank(address(dao));
        plugin.setConvictionCalculationSettings(
            newDecay,
            newMaxRatio,
            newWeight,
            newMinThresholdStakePercentage
        );

        assertEq(plugin.decay(), newDecay);
        assertEq(plugin.maxRatio(), newMaxRatio);
        assertEq(plugin.weight(), newWeight);
        assertEq(plugin.minThresholdStakePercentage(), newMinThresholdStakePercentage);
    }

    function test_reverts_if_not_auth_setConvictionCalculationSettings() public {
        uint256 newDecay = DEFAULT_ALPHA - 1;
        uint256 newMaxRatio = DEFAULT_BETA + 1;
        uint256 newWeight = DEFAULT_RHO + 1;
        uint256 newMinThresholdStakePercentage = MIN_THRESHOLD_STAKE_PERCENTAGE - 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                dao,
                plugin,
                address(this),
                keccak256("UPDATE_SETTINGS")
            )
        );
        plugin.setConvictionCalculationSettings(
            newDecay,
            newMaxRatio,
            newWeight,
            newMinThresholdStakePercentage
        );
    }
}

contract ConvictionVotingAddSignalingProposalTest is ConvictionVotingTest {
    function setUp() public override {
        super.setUp();
    }

    function test_addSignalingProposal() public {
        string memory title = "New Proposal";
        bytes memory link = "http://example.com";

        uint256 proposalCounterBefore = plugin.proposalCounter();

        vm.prank(proposer);
        plugin.addSignalingProposal(title, link);

        assertEq(plugin.proposalCounter(), proposalCounterBefore + 1);
    }

    // function test_reverts_if_not_auth_addSignalingProposal() public {
    //     string memory title = "New Proposal";
    //     bytes memory link = "http://example.com";

    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             DaoUnauthorized.selector,
    //             dao,
    //             plugin,
    //             address(this),
    //             keccak256("CREATE_PROPOSALS")
    //         )
    //     );
    //     plugin.addSignalingProposal(title, link);
    // }
}

contract ConvictionVotingStakeToProposalTest is ConvictionVotingTest {
    function setUp() public override {
        super.setUp();
        // Additional setup if required
    }

    function test_stakeToProposal() public {
        string memory title = "New Proposal";
        bytes memory link = "http://example.com";
        vm.startPrank(proposer);

        uint256 proposalId = plugin.proposalCounter();
        plugin.addSignalingProposal(title, link);

        console2.log("proposalId: ", proposalId);

        uint256 amountToStake = 10 ** 18; // Replace with an appropriate amount

        uint256 initialStake = plugin.getProposalVoterStake(proposalId, address(this));
        (, , , , , , , address proposerAddress, ) = plugin.getProposal(proposalId);
        console2.log("address: ", proposerAddress);

        plugin.stakeToProposal(proposalId, amountToStake);

        uint256 newStake = plugin.getProposalVoterStake(proposalId, address(this));
        assertEq(newStake, initialStake + amountToStake);
        vm.stopPrank();
        // Additional assertions can be added to check totalStaked, etc.
    }

    function test_reverts_if_stakeToNonExistentProposal() public {
        uint256 nonExistentProposalId = 999;
        uint256 amountToStake = 10 * 10 ** 18;

        vm.expectRevert(Types.ProposalDoesNotExist.selector);

        plugin.stakeToProposal(nonExistentProposalId, amountToStake);
    }
}
