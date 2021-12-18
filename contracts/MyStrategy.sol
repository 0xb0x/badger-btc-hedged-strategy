// SPDX-License-Identifier: MIT

pragma solidity ^0.6.11;
pragma experimental ABIEncoderV2;

import "../deps/@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/math/MathUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "../deps/@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";

import "../interfaces/badger/IController.sol";

import {BaseStrategy} from "../deps/BaseStrategy.sol";

import {IRibbonVault} from "../interfaces/ribbon/IRibbonVault.sol";
import {VegaHedge} from "./VegaHedge.sol";

contract MyStrategy is BaseStrategy {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using SafeMathUpgradeable for uint256;

    // address public want // Inherited from BaseStrategy, the token the strategy wants, swaps into and tries to grow
    // address public reward; // Token we farm and swap to want

    VegaHedge public constant strategy =
        VegaHedge(); /** address(0)*/
    IRibbonVault public constant RIBBON_WBTC_COVERED_CALL =
        IRibbonVault(0x65a833afDc250D9d38f8CD9bC2B1E3132dB13B2F);
    bool public withdrawInitiated;
    uint256 PERCENT_HEDGE = 30;

    function initialize(
        address _governance,
        address _strategist,
        address _controller,
        address _keeper,
        address _guardian,
        address[3] memory _wantConfig,
        uint256[3] memory _feeConfig
    ) public initializer {
        __BaseStrategy_init(
            _governance,
            _strategist,
            _controller,
            _keeper,
            _guardian
        );
        /// @dev Add config here
        want = _wantConfig[0];

        performanceFeeGovernance = _feeConfig[0];
        performanceFeeStrategist = _feeConfig[1];
        withdrawalFee = _feeConfig[2];

        /// @dev do one off approvals here
        IERC20Upgradeable(want).safeApprove(
            address(RIBBON_WBTC_COVERED_CALL),
            type(uint256).max
        );

        IERC20Upgradeable(want).safeApprove(
            address(strategy),
            type(uint256).max
        );

        /// @dev uniswap approvals
        // IERC20Upgradeable(reward).safeApprove(ROUTER, type(uint256).max);
    }

    /// ===== View Functions =====

    // @dev Specify the name of the strategy
    function getName() external pure override returns (string memory) {
        return "StrategyName";
    }

    // @dev Specify the version of the Strategy, for upgrades
    function version() external pure returns (string memory) {
        return "1.0";
    }

    /// @dev Balance of want currently held in strategy positions
    function balanceOfPool() public view override returns (uint256) {
        return RIBBON_WBTC_COVERED_CALL.accountVaultBalance(address(this));
    }

    /// @dev Returns true if this strategy requires tending
    function isTendable() public view override returns (bool) {
        return balanceOfWant() > 0;
    }

    // @dev These are the tokens that cannot be moved except by the vault
    function getProtectedTokens()
        public
        view
        override
        returns (address[] memory)
    {
        address[] memory protectedTokens = new address[](1);
        protectedTokens[0] = want;

        return protectedTokens;
    }

    function getStrategyShares() internal view returns (uint256) {
        return IRibbonVault(RIBBON_WBTC_COVERED_CALL).shares(address(this));
    }

    /// ===== Internal Core Implementations =====

    /// @dev security check to avoid moving tokens that would cause a rugpull, edit based on strat
    function _onlyNotProtectedTokens(address _asset) internal override {
        address[] memory protectedTokens = getProtectedTokens();

        for (uint256 x = 0; x < protectedTokens.length; x++) {
            require(
                address(protectedTokens[x]) != _asset,
                "Asset is protected"
            );
        }
    }

    /// @dev invest the amount of want
    /// @notice When this function is called, the controller has already sent want to this
    /// @notice Just get the current balance and then invest accordingly
    function _deposit(uint256 _amount) internal override {
        RIBBON_WBTC_COVERED_CALL.deposit(_amount);
    }

    /// @dev utility function to withdraw everything for migration
    function _withdrawAll() internal override {
        if (withdrawInitiated) RIBBON_WBTC_COVERED_CALL.completeWithdraw();
        if (strategy.withdrawScheduled()) strategy.completeWithdraw();
    }

    /// @dev withdraw the specified amount of want
    function _withdrawSome(uint256 _amount)
        internal
        override
        returns (uint256)
    {
        uint256 maxAmount =
            RIBBON_WBTC_COVERED_CALL.pricePerShare().mul(getStrategyShares());
        if (_amount > maxAmount) {
            _amount = getStrategyShares();
            strategy.scheduleWithdraw();
        } else {
            _amount = _amount.div(RIBBON_WBTC_COVERED_CALL.pricePerShare());
        }

        RIBBON_WBTC_COVERED_CALL.initiateWithdraw(uint128(_amount));
        withdrawInitiated = true;

        return _amount;
    }

    /// @dev Harvest from strategy mechanics, realizing increase in underlying position
    function harvest() external whenNotPaused returns (uint256 harvested) {}

    // Alternative Harvest with Price received from harvester, used to avoid exessive front-running
    function harvest(uint256 price)
        external
        whenNotPaused
        returns (uint256 harvested)
    {}

    /// @dev Rebalance, Compound or Pay off debt here
    function tend() external whenNotPaused {
        _onlyAuthorizedActors();

        uint256 toDeposit = balanceOfWant();

        if (toDeposit > 0) {
            uint256 hedgeAmt = toDeposit.mul(PERCENT_HEDGE).div(100);

            RIBBON_WBTC_COVERED_CALL.deposit(toDeposit.sub(hedgeAmt));
            strategy.deposit(hedgeAmt);
        }
    }

    /// ===== Internal Helper Functions =====

    /// @dev used to manage the governance and strategist fee on earned rewards, make sure to use it to get paid!
    function _processRewardsFees(uint256 _amount, address _token)
        internal
        returns (uint256 governanceRewardsFee, uint256 strategistRewardsFee)
    {
        governanceRewardsFee = _processFee(
            _token,
            _amount,
            performanceFeeGovernance,
            IController(controller).rewards()
        );

        strategistRewardsFee = _processFee(
            _token,
            _amount,
            performanceFeeStrategist,
            strategist
        );
    }
}
