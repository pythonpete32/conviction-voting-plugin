// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.19;

import {PluginUUPSUpgradeable, IDAO} from "@aragon/osx/core/plugin/PluginUUPSUpgradeable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Types} from "./Types.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ArrayUtils} from "./lib/ArrayUtils.sol";

/**
 * @title ConvictionVoting
 * @author PythonPete32 (Security@DAOBox.app)
 * @notice ...
 * to delegate spending authority
 */
contract ConvictionVoting is PluginUUPSUpgradeable, Types {
    using Math for uint256;
    using ArrayUtils for uint256[];

    bytes32 public constant UPDATE_SETTINGS_ROLE = keccak256("UPDATE_SETTINGS");
    bytes32 public constant CREATE_PROPOSALS_ROLE = keccak256("CREATE_PROPOSALS");
    bytes32 public constant PAUSE_CONTRACT_ROLE = keccak256("PAUSE_CONTRACT");

    uint256 public constant D = 10000000;
    uint256 public constant ONE_HUNDRED_PERCENT = 1e18;
    uint256 private constant TWO_128 = 0x100000000000000000000000000000000; // 2^128
    uint256 private constant TWO_127 = 0x80000000000000000000000000000000; // 2^127
    uint256 private constant TWO_64 = 0x10000000000000000; // 2^64
    uint256 public constant ABSTAIN_PROPOSAL_ID = 1;
    uint64 public constant MAX_STAKED_PROPOSALS = 10;

    IERC20 public stakeToken;
    IERC20 public requestToken;
    IERC20 public stableToken;
    IPriceOracle public stableTokenOracle;
    uint256 public decay;
    uint256 public maxRatio;
    uint256 public weight;
    uint256 public minThresholdStakePercentage;
    uint256 public proposalCounter;
    uint256 public totalStaked;
    uint256 public minProposerTokens;

    mapping(uint256 proposalCounter => Proposal proposal) internal proposals;
    mapping(address => uint256) internal totalVoterStake;
    mapping(address => uint256[]) internal voterStakedProposals;
    mapping(uint256 proposalCounter => mapping(address voter => uint256 stake)) internal voterStake;
    bool public contractPaused;

    modifier proposalExists(uint256 _proposalId) {
        if (_proposalId != 1 && proposals[_proposalId].submitter == address(0)) {
            revert ProposalDoesNotExist();
        }
        _;
    }

    modifier isPaused() {
        if (contractPaused) revert ContractPaused();
        _;
    }

    function initialize(
        IDAO _dao,
        IERC20 _stakeToken,
        IERC20 _requestToken,
        IERC20 _stableToken,
        IPriceOracle _stableTokenOracle,
        uint256 _decay,
        uint256 _maxRatio,
        uint256 _weight,
        uint256 _minThresholdStakePercentage,
        uint256 _minProposerTokens
    ) external initializer {
        __PluginUUPSUpgradeable_init(_dao);
        proposalCounter = 2; // First proposal should be #2, #1 is reserved for abstain proposal, #0 is not used for better UX.
        stakeToken = _stakeToken;
        stableToken = _stableToken;
        stableTokenOracle = _stableTokenOracle;

        requestToken = _requestToken;
        decay = _decay;
        maxRatio = _maxRatio;
        weight = _weight;
        minThresholdStakePercentage = _minThresholdStakePercentage;
        minProposerTokens = _minProposerTokens;

        proposals[ABSTAIN_PROPOSAL_ID].requestedAmount = 0;
        proposals[ABSTAIN_PROPOSAL_ID].stableRequestAmount = false;
        proposals[ABSTAIN_PROPOSAL_ID].beneficiary = address(0);
        proposals[ABSTAIN_PROPOSAL_ID].stakedTokens = 0;
        proposals[ABSTAIN_PROPOSAL_ID].convictionLast = 0;
        proposals[ABSTAIN_PROPOSAL_ID].blockLast = 0;
        proposals[ABSTAIN_PROPOSAL_ID].proposalStatus = ProposalStatus.Active;
        proposals[ABSTAIN_PROPOSAL_ID].submitter = address(0);

        emit ProposalAdded({
            entity: address(0),
            id: ABSTAIN_PROPOSAL_ID,
            title: "Abstain proposal",
            link: "",
            amount: 0,
            stable: false,
            beneficiary: address(0)
        });
    }

    /**
     * @notice Pause / unpause the contract preventing / allowing general interaction
     * @param _pauseEnabled Whether to enable or disable pause
     */
    function pauseContract(bool _pauseEnabled) external auth(PAUSE_CONTRACT_ROLE) {
        contractPaused = _pauseEnabled;
        emit PauseContract(contractPaused);
    }

    function setMinProposerTokens(uint256 _minProposerTokens) external auth(UPDATE_SETTINGS_ROLE) {
        minProposerTokens = _minProposerTokens;
    }

    /**
     * @notice Update the stable token oracle settings
     * @param _stableTokenOracle The new stable token oracle
     * @param _stableToken The new stable token
     */
    function setStableTokenOracleSettings(
        IPriceOracle _stableTokenOracle,
        IERC20 _stableToken
    ) external auth(UPDATE_SETTINGS_ROLE) {
        stableTokenOracle = _stableTokenOracle;
        stableToken = _stableToken;

        emit OracleSettingsChanged(_stableTokenOracle, _stableToken);
    }

    /**
     * @notice Update the conviction voting parameters
     * @param _decay The rate at which conviction is accrued or lost from a proposal
     * @param _maxRatio Proposal threshold parameter
     * @param _weight Proposal threshold parameter
     * @param _minThresholdStakePercentage The minimum percent of stake token max supply that is used for calculating
        conviction
     */
    function setConvictionCalculationSettings(
        uint256 _decay,
        uint256 _maxRatio,
        uint256 _weight,
        uint256 _minThresholdStakePercentage
    ) external auth(UPDATE_SETTINGS_ROLE) {
        decay = _decay;
        maxRatio = _maxRatio;
        weight = _weight;
        minThresholdStakePercentage = _minThresholdStakePercentage;

        emit ConvictionSettingsChanged(_decay, _maxRatio, _weight, _minThresholdStakePercentage);
    }

    /**
     * @notice Create signaling proposal `_title`
     * @param _title Title of the proposal
     * @param _link IPFS or HTTP link with proposal's description
     */
    function addSignalingProposal(string memory _title, bytes memory _link) external {
        // TODO: auth(CREATE_PROPOSALS_ROLE)
        if (stakeToken.balanceOf(msg.sender) < minProposerTokens) {
            revert ProposerNeedsMoreTokens({
                has: stakeToken.balanceOf(msg.sender),
                needs: minProposerTokens
            });
        }
        _addProposal(_title, _link, 0, false, address(0));
    }

    /**
     * @notice Create proposal `_title` for `@tokenAmount((self.requestToken(): address), _requestedAmount)` to `_beneficiary`
     * @param _title Title of the proposal
     * @param _link IPFS or HTTP link with proposal's description
     * @param _requestedAmount Tokens requested
     * @param _stableRequestAmount Whether the requested amount is in the request token or the stable token, converted to the request token upon execution
     * @param _beneficiary Address that will receive payment
     */
    function addProposal(
        string memory _title,
        bytes memory _link,
        uint256 _requestedAmount,
        bool _stableRequestAmount,
        address _beneficiary
    ) external {
        // TODO: auth(CREATE_PROPOSALS_ROLE)
        if (_requestedAmount == 0) revert AmountCannotBeZero();
        if (_beneficiary == address(0)) revert ZeroAddressCannotBeBeneficiary();

        _addProposal(_title, _link, _requestedAmount, _stableRequestAmount, _beneficiary);
    }

    /**
     * @notice Stake `@tokenAmount((self.stakeToken(): address), _amount)` on proposal #`_proposalId`
     * @param _proposalId Proposal id
     * @param _amount Amount of tokens staked
     */
    function stakeToProposal(uint256 _proposalId, uint256 _amount) external {
        _stake(_proposalId, _amount, msg.sender);
    }

    /**
     * @notice Stake all my `(self.stakeToken(): address).symbol(): string` tokens on proposal #`_proposalId`
     * @param _proposalId Proposal id
     */
    function stakeAllToProposal(uint256 _proposalId) external {
        if (totalVoterStake[msg.sender] != 0) revert StakingAlreadyStaked();
        _stake(_proposalId, stakeToken.balanceOf(msg.sender), msg.sender);
    }

    /**
     * @notice Withdraw `@tokenAmount((self.stakeToken(): address), _amount)` previously staked on proposal #`_proposalId`
     * @param _proposalId Proposal id
     * @param _amount Amount of tokens withdrawn
     */
    function withdrawFromProposal(
        uint256 _proposalId,
        uint256 _amount
    ) external proposalExists(_proposalId) {
        _withdrawFromProposal(_proposalId, _amount, msg.sender);
    }

    /**
     * @notice Withdraw all `(self.stakeToken(): address).symbol(): string` tokens previously staked on proposal #`_proposalId`
     * @param _proposalId Proposal id
     */
    function withdrawAllFromProposal(uint256 _proposalId) external proposalExists(_proposalId) {
        _withdrawFromProposal(_proposalId, voterStake[_proposalId][msg.sender], msg.sender);
    }

    /**
     * @notice Withdraw all callers stake from inactive proposals
     */
    function withdrawFromInactiveProposals() external {
        _withdrawInactiveStakedTokens(type(uint256).max, msg.sender);
    }

    //=-=-=-=-=-=-=-=-=-=-==-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

    function getProposal(
        uint256 _proposalId
    )
        external
        view
        returns (
            uint256 requestedAmount,
            bool stableRequestAmount,
            address beneficiary,
            uint256 stakedTokens,
            uint256 convictionLast,
            uint64 blockLast,
            ProposalStatus proposalStatus,
            address submitter,
            uint256 threshold
        )
    {
        Proposal storage proposal = proposals[_proposalId];
        threshold = proposal.requestedAmount == 0
            ? 0
            : calculateThreshold(_getRequestAmount(proposal));
        return (
            proposal.requestedAmount,
            proposal.stableRequestAmount,
            proposal.beneficiary,
            proposal.stakedTokens,
            proposal.convictionLast,
            proposal.blockLast,
            proposal.proposalStatus,
            proposal.submitter,
            threshold
        );
    }

    /**
     * @notice Get stake of voter `_voter` on proposal #`_proposalId`
     * @param _proposalId Proposal id
     * @param _voter Voter address
     * @return Proposal voter stake
     */
    function getProposalVoterStake(
        uint256 _proposalId,
        address _voter
    ) external view returns (uint256) {
        return voterStake[_proposalId][_voter];
    }

    /**
     * @notice Get the total stake of voter `_voter` on all proposals
     * @param _voter Voter address
     * @return Total voter stake
     */
    function getTotalVoterStake(address _voter) external view returns (uint256) {
        return totalVoterStake[_voter];
    }

    /**
     * @notice Get all proposal ID's voter `_voter` has currently staked to
     * @param _voter Voter address
     * @return Voter proposals
     */
    function getVoterStakedProposals(address _voter) external view returns (uint256[] memory) {
        return voterStakedProposals[_voter];
    }

    /**
     * @dev IDisputable interface conformance
     */
    function canChallenge(uint256 _proposalId) external view returns (bool) {
        return proposals[_proposalId].proposalStatus == ProposalStatus.Active && !contractPaused;
    }

    /**
     * @dev IDisputable interface conformance
     */
    function canClose(uint256 _proposalId) external view returns (bool) {
        Proposal storage proposal = proposals[_proposalId];

        return
            proposal.proposalStatus == ProposalStatus.Executed ||
            proposal.proposalStatus == ProposalStatus.Cancelled;
    }

    //-=-=-=-=-=-==-=-=-=-=-=-=-=-=-=-=-=-

    /**
     * @dev Conviction formula: a^t * y(0) + x * (1 - a^t) / (1 - a)
     * Solidity implementation: y = (2^128 * a^t * y0 + x * D * (2^128 - 2^128 * a^t) / (D - aD) + 2^127) / 2^128
     * @param _timePassed Number of blocks since last conviction record
     * @param _lastConv Last conviction record
     * @param _oldAmount Amount of tokens staked until now
     * @return Current conviction
     */
    function calculateConviction(
        uint64 _timePassed,
        uint256 _lastConv,
        uint256 _oldAmount
    ) public view returns (uint256) {
        uint256 t = uint256(_timePassed);
        // atTWO_128 = 2^128 * a^t
        // uint256 atTWO_128 = _pow((decay << 128)/(D), t);
        uint256 decayShifted = (decay << 128) / D;
        uint256 atTWO_128 = _pow(decayShifted, t);

        // solium-disable-previous-line
        // conviction = (atTWO_128 * _lastConv + _oldAmount * D * (2^128 - atTWO_128) / (D - aD) + 2^127) / 2^128
        return
            ((atTWO_128 *
                (_lastConv) +
                ((_oldAmount * (D) * (TWO_128 - (atTWO_128))) / (D - decay))) + (TWO_127)) >> 128;
    }

    /**
     * @dev Formula: ρ * totalStaked / (1 - a) / (β - requestedAmount / total)**2
     * For the Solidity implementation we amplify ρ and β and simplify the formula:
     * weight = ρ * D
     * maxRatio = β * D
     * decay = a * D
     * threshold = weight * totalStaked * D ** 2 * funds ** 2 / (D - decay) / (maxRatio * funds - requestedAmount * D) ** 2
     * @param _requestedAmount Requested amount of tokens on certain proposal
     * @return _threshold Threshold a proposal's conviction should surpass in order to be able to
     * executed it.
     */
    function calculateThreshold(uint256 _requestedAmount) public view returns (uint256 _threshold) {
        // uint256 funds = fundsManager.balance(requestToken);
        uint256 funds = IERC20(requestToken).balanceOf(address(dao()));
        if (!(maxRatio * (funds) > _requestedAmount * (D))) {
            revert AmountOverMaxRatio();
        }
        // denom = maxRatio * 2 ** 64 / D  - requestedAmount * 2 ** 64 / funds
        uint256 denom = (maxRatio << 64) / (D) - ((_requestedAmount << 64) / (funds));
        // _threshold = (weight * 2 ** 128 / D) / (denom ** 2 / 2 ** 64) * totalStaked * D / 2 ** 128
        _threshold =
            (((((weight << 128) / (D) / ((denom * (denom)) >> 64)) * (D)) / (D - (decay))) *
                (_totalStaked())) >>
            64;
    }

    /**
     * @notice Execute proposal #`_proposalId`
     * @dev ...by sending `@tokenAmount((self.requestToken(): address), self.getPropoal(_proposalId): ([uint256], address, uint256, uint256, uint64, bool))` to `self.getPropoal(_proposalId): (uint256, [address], uint256, uint256, uint64, bool)`
     * @param _proposalId Proposal id
     */
    function executeProposal(uint256 _proposalId) external isPaused proposalExists(_proposalId) {
        Proposal storage proposal = proposals[_proposalId];

        if (_proposalId == ABSTAIN_PROPOSAL_ID) revert CannotExecuteAbstainProposal();
        if (proposal.requestedAmount == 0) revert CannotExecuteZeroValueProposal();
        if (proposal.proposalStatus != ProposalStatus.Active) revert ProposalNotActive();

        _calculateAndSetConviction(proposal, proposal.stakedTokens);
        uint256 requestedAmount = _getRequestAmount(proposal);
        if (!(proposal.convictionLast > calculateThreshold(requestedAmount))) {
            revert InsufficientConviction();
        }

        proposal.proposalStatus = ProposalStatus.Executed;

        IDAO.Action[] memory _actions = new IDAO.Action[](1);
        _actions[0] = IDAO.Action({
            to: address(requestToken),
            value: 0,
            data: abi.encodeCall(IERC20.transfer, (proposal.beneficiary, requestedAmount))
        });

        dao().execute(bytes32(_proposalId), _actions, 0);

        emit ProposalExecuted(_proposalId, proposal.convictionLast);
    }

    // ----------------------------------------------------------------------------

    function _getRequestAmount(Proposal storage proposal) internal view returns (uint256) {
        return
            proposal.stableRequestAmount
                ? stableTokenOracle.consult(
                    address(stableToken),
                    proposal.requestedAmount,
                    address(requestToken)
                )
                : proposal.requestedAmount;
    }

    function _addProposal(
        string memory _title,
        bytes memory _link,
        uint256 _requestedAmount,
        bool _stableRequestAmount,
        address _beneficiary
    ) internal isPaused {
        proposals[proposalCounter] = Proposal({
            requestedAmount: _requestedAmount,
            stableRequestAmount: _stableRequestAmount,
            beneficiary: _beneficiary,
            stakedTokens: 0,
            convictionLast: 0,
            blockLast: 0,
            proposalStatus: ProposalStatus.Active,
            submitter: msg.sender
        });

        emit ProposalAdded(
            msg.sender,
            proposalCounter,
            _title,
            _link,
            _requestedAmount,
            _stableRequestAmount,
            _beneficiary
        );
        proposalCounter++;
    }

    /**
     * @dev Stake an amount of tokens on a proposal
     * @param _proposalId Proposal id
     * @param _amount Amount of staked tokens
     * @param _from Account from which we stake
     */
    function _stake(
        uint256 _proposalId,
        uint256 _amount,
        address _from
    ) internal isPaused proposalExists(_proposalId) {
        Proposal storage proposal = proposals[_proposalId];
        if (_amount <= 0) revert AmountCannotBeZero();
        if (proposal.proposalStatus != ProposalStatus.Active)
            revert IncorrectProposalStatus(proposal.proposalStatus);

        uint256 unstakedAmount = stakeToken.balanceOf(_from) - (totalVoterStake[_from]);
        if (_amount > unstakedAmount) {
            _withdrawInactiveStakedTokens(_amount - (unstakedAmount), _from);
        }

        if (totalVoterStake[_from] + (_amount) > stakeToken.balanceOf(_from)) {
            revert StakingMoreThanAvailable();
        }

        uint256 previousStake = proposal.stakedTokens;
        proposal.stakedTokens = proposal.stakedTokens + (_amount);
        voterStake[_proposalId][_from] = voterStake[_proposalId][_from] + _amount;
        totalVoterStake[_from] = totalVoterStake[_from] + (_amount);
        totalStaked = totalStaked + (_amount);

        if (proposal.blockLast == 0) {
            proposal.blockLast = uint64(block.number);
        } else {
            _calculateAndSetConviction(proposal, previousStake);
        }

        _updateVoterStakedProposals(_proposalId, _from);

        emit StakeAdded(
            _from,
            _proposalId,
            _amount,
            voterStake[_proposalId][_from],
            proposal.stakedTokens,
            proposal.convictionLast
        );
    }

    /**
     * @dev Withdraw staked tokens from executed proposals until a target amount is reached.
     * @param _targetAmount Target at which to stop withdrawing tokens
     * @param _from Account to withdraw from
     */
    function _withdrawInactiveStakedTokens(uint256 _targetAmount, address _from) internal {
        uint256 i = 0;
        uint256 toWithdraw;
        uint256 withdrawnAmount = 0;
        uint256[] memory voterStakedProposalsCopy = voterStakedProposals[_from];

        while (i < voterStakedProposalsCopy.length && withdrawnAmount < _targetAmount) {
            uint256 proposalId = voterStakedProposalsCopy[i];
            Proposal storage proposal = proposals[proposalId];

            if (
                proposal.proposalStatus == ProposalStatus.Executed ||
                proposal.proposalStatus == ProposalStatus.Cancelled
            ) {
                toWithdraw = voterStake[proposalId][_from];
                if (toWithdraw > 0) {
                    _withdrawFromProposal(proposalId, toWithdraw, _from);
                    withdrawnAmount = withdrawnAmount + (toWithdraw);
                }
            }
            i++;
        }
    }

    /**
     * @dev Withdraw an amount of tokens from a proposal
     * @param _proposalId Proposal id
     * @param _amount Amount of withdrawn tokens
     * @param _from Account to withdraw from
     */
    function _withdrawFromProposal(uint256 _proposalId, uint256 _amount, address _from) internal {
        Proposal storage proposal = proposals[_proposalId];
        if (voterStake[_proposalId][_from] < _amount) {
            revert WithdrawMoreThanStaked();
        }
        if (_amount == 0) {
            revert AmountCannotBeZero();
        }

        uint256 previousStake = proposal.stakedTokens;
        proposal.stakedTokens = proposal.stakedTokens - (_amount);
        voterStake[_proposalId][_from] = voterStake[_proposalId][_from] - (_amount);
        totalVoterStake[_from] = totalVoterStake[_from] - (_amount);
        totalStaked = totalStaked - (_amount);

        if (voterStake[_proposalId][_from] == 0) {
            voterStakedProposals[_from].deleteItem(_proposalId);
        }

        if (proposal.proposalStatus == ProposalStatus.Active) {
            _calculateAndSetConviction(proposal, previousStake);
        }

        emit StakeWithdrawn(
            _from,
            _proposalId,
            _amount,
            voterStake[_proposalId][_from],
            proposal.stakedTokens,
            proposal.convictionLast
        );
    }

    /**
     * @dev Calculate conviction and store it on the proposal
     * @param _proposal Proposal
     * @param _oldStaked Amount of tokens staked on a proposal until now
     */
    function _calculateAndSetConviction(Proposal storage _proposal, uint256 _oldStaked) internal {
        uint64 blockNumber = uint64(block.number);
        assert(_proposal.blockLast <= blockNumber);
        if (_proposal.blockLast == blockNumber) {
            return; // Conviction already stored
        }
        // calculateConviction and store it
        uint256 conviction = calculateConviction(
            blockNumber - _proposal.blockLast, // we assert it doesn't overflow above
            _proposal.convictionLast,
            _oldStaked
        );
        _proposal.blockLast = blockNumber;
        _proposal.convictionLast = conviction;
    }

    function _updateVoterStakedProposals(uint256 _proposalId, address _submitter) internal {
        uint256[] storage voterStakedProposalsArray = voterStakedProposals[_submitter];

        if (!voterStakedProposalsArray.contains(_proposalId)) {
            if (voterStakedProposalsArray.length >= MAX_STAKED_PROPOSALS) {
                revert Types.MaxProposalsReached();
            }
            voterStakedProposalsArray.push(_proposalId);
        }
    }

    function _totalStaked() internal view returns (uint256) {
        uint256 minTotalStake = (stakeToken.totalSupply() * (minThresholdStakePercentage)) /
            (ONE_HUNDRED_PERCENT);
        return totalStaked < minTotalStake ? minTotalStake : totalStaked;
    }

    /**
     * Calculate (_a / 2^128)^_b * 2^128.  Parameter _a should be less than 2^128.
     *
     * @param _a left argument
     * @param _b right argument
     * @return _result (_a / 2^128)^_b * 2^128
     */
    function _pow(uint256 _a, uint256 _b) internal pure returns (uint256 _result) {
        require(_a < TWO_128, "_a should be less than 2^128");
        uint256 a = _a;
        uint256 b = _b;
        _result = TWO_128;
        while (b > 0) {
            if (b & 1 == 0) {
                a *= a;
                b >>= 1;
            } else {
                _result *= a;
                b -= 1;
            }
        }
    }
}

// 0xd9c78e0200000000000000000000000000000000000000000000000000000000
