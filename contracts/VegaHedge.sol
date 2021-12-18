// SPDX-License-Identifier: MIT
pragma solidity ^0.6.11;
pragma experimental ABIEncoderV2;

import "../deps/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRibbonVault} from "../interfaces/ribbon/IRibbonVault.sol";
import {IOpynController} from "../interfaces/IOpynController.sol";
import {IOToken} from "../interfaces/IOToken.sol";
import {IZeroXV4} from "../interfaces/IZeroXV4.sol";
import {ISwapRouter} from "../interfaces/uniswap/ISwapRouter.sol";

contract VegaHedge {
    IOToken oToken;

    IOpynController controller;
    IRibbonVault RIBBON_WBTC_COVERED_CALL =
        IRibbonVault(0x65a833afDc250D9d38f8CD9bC2B1E3132dB13B2F);
    IZeroXV4 public exchange;

    address public wBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant WETH_TOKEN =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public ROUTER;
    address owner;
    address strategy;

    bool _withdrawScheduled;

    constructor(address _opynController, address _exchange) public {
        controller = IOpynController(_opynController);
        exchange = IZeroXV4(_exchange);
        owner = msg.sender;
    }

    function setOtoken(IOToken _oToken) public {
        require(msg.sender == owner, "NOT_AUTHORIZED");
        checkOtoken(_oToken);
        oToken = _oToken;
    }

    function deposit(uint256 amount) public {
        IERC20(wBTC).transferFrom(msg.sender, address(this), amount);
    }

    function checkOtoken(IOToken _oToken) public view {
        require(address(oToken) == address(0));

        address rOToken = RIBBON_WBTC_COVERED_CALL.currentOption();
        IOToken ribbon_oToken = IOToken(rOToken);

        require(_oToken.strikePrice() < ribbon_oToken.strikePrice());
        require(
            _oToken.expiryTimestamp() <= ribbon_oToken.expiryTimestamp() &&
                _oToken.expiryTimestamp() < block.timestamp
        );
        require(!_oToken.isPut());
        require(_oToken.underlyingAsset() == wBTC);
    }

    function purchaseOTokenVia0x(
        IZeroXV4.LimitOrder memory _order,
        IZeroXV4.Signature memory _signature,
        uint128 takerTokenFillAmount
    ) public payable {
        require(msg.sender == owner);
        IERC20(_order.takerToken).approve(
            address(exchange),
            takerTokenFillAmount
        );
        exchange.fillLimitOrder{value: msg.value}(
            _order,
            _signature,
            takerTokenFillAmount
        );
    }

    function reedem() external {
        require(msg.sender == strategy);
        if (address(oToken) != address(0)) {
            if (oToken.expiryTimestamp() > now) {
                IOpynController.ActionArgs[] memory actions =
                    new IOpynController.ActionArgs[](1);
                // this action will always use vault id 1
                actions[0] = IOpynController.ActionArgs(
                    IOpynController.ActionType.Redeem,
                    address(0), // owner
                    address(this), // secondAddress: recipient
                    address(oToken), // asset
                    0, // vaultId
                    IOToken(address(oToken)).balanceOf(address(this)), // amount
                    0, // index
                    "" // data
                );
                controller.operate(actions);
            }

            oToken = IOToken(address(0));
        }
    }

    function swap(
        address _from,
        address _to,
        uint256 _amt
    ) public {
        require(msg.sender == owner);
        require(_from == wBTC || _from == USDC);
        require(_to == wBTC || _to == USDC);

        bytes memory path =
            abi.encodePacked(
                _from,
                uint24(10000),
                WETH_TOKEN,
                uint24(10000),
                _to
            );

        ISwapRouter.ExactInputParams memory fromToParams =
            ISwapRouter.ExactInputParams(
                path,
                address(this),
                now,
                IERC20(_from).balanceOf(address(this)),
                0
            );
        ISwapRouter(ROUTER).exactInput(fromToParams);
    }

    function setStrategy(address _strategy) public {
        require(msg.sender == owner);
        strategy = _strategy;
    }

    function scheduleWithdraw() external {
        require(msg.sender == strategy);

        if (address(oToken) != address(0)) {
            _withdrawScheduled = true;
        } else {
            uint256 usdcBalance = IERC20(USDC).balanceOf(address(this));

            if (usdcBalance > 0) swap(USDC, wBTC, usdcBalance);
            withdrawBTCBalance();
        }
    }

    function withdrawScheduled() public view returns (bool) {
        return _withdrawScheduled;
    }

    function withdrawBTCBalance() internal {
        uint256 btcBalance = IERC20(USDC).balanceOf(address(this));
        IERC20(wBTC).transferFrom(address(this), strategy, btcBalance);
    }

    function completeWithdraw() public {
        if (_withdrawScheduled) withdrawBTCBalance();
        _withdrawScheduled = false;
    }
}
