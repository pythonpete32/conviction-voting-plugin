// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.19;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";

contract Types {
    error ProposalDoesNotExist();
    error StakingAlreadyStaked();
    error ProposalNotActive();
    error CannotExecuteAbstainProposal();
    error CannotExecuteZeroValueProposal();
    error InsufficientConviction();
    error SenderCannotCancel();
    error CannotCancelAbstainProposal();
    error AmountOverMaxRatio();
    error IncorrectTokenManagerHook();
    error AmountCannotBeZero();
    error StakingMoreThanAvailable();
    error MaxProposalsReached();
    error WithdrawMoreThanStaked();
    error ContractPaused();
    error IncorrectProposalStatus(ProposalStatus status);
    error ProposerNeedsMoreTokens(uint256 has, uint256 needs);
    error ZeroAddressCannotBeBeneficiary();

    event PauseContract(bool pauseEnabled);
    event OracleSettingsChanged(IPriceOracle stableTokenOracle, IERC20 stableToken);
    event ConvictionSettingsChanged(
        uint256 decay,
        uint256 maxRatio,
        uint256 weight,
        uint256 minThresholdStakePercentage
    );
    event ProposalAdded(
        address indexed entity,
        uint256 indexed id,
        string title,
        bytes link,
        uint256 amount,
        bool stable,
        address beneficiary
    );
    event StakeAdded(
        address indexed entity,
        uint256 indexed id,
        uint256 amount,
        uint256 tokensStaked,
        uint256 totalTokensStaked,
        uint256 conviction
    );
    event StakeWithdrawn(
        address entity,
        uint256 indexed id,
        uint256 amount,
        uint256 tokensStaked,
        uint256 totalTokensStaked,
        uint256 conviction
    );
    event ProposalExecuted(uint256 indexed id, uint256 conviction);
    event ProposalPaused(uint256 indexed proposalId, uint256 indexed challengeId);
    event ProposalResumed(uint256 indexed proposalId);
    event ProposalCancelled(uint256 indexed proposalId);
    event ProposalRejected(uint256 indexed proposalId);

    enum ProposalStatus {
        Active, // A vote that has been reported to Agreements
        Cancelled, // A vote that has been cancelled
        Executed // A vote that has been executed
    }

    struct Proposal {
        uint256 requestedAmount;
        bool stableRequestAmount;
        address beneficiary;
        uint256 stakedTokens;
        uint256 convictionLast;
        uint64 blockLast;
        ProposalStatus proposalStatus;
        address submitter;
    }
}
