// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

import './interfaces/IBooster.sol';
import './interfaces/IBaseRewardPool.sol';
import './interfaces/ICVX.sol';
import './interfaces/ICurveSwap.sol';
import './interfaces/ISwapRouter.sol';
import './interfaces/IWETH.sol';
import 'hardhat/console.sol';

contract Vault is Ownable {

    using SafeERC20 for IERC20;
    
    event DepositLp(address indexed user, address indexed lptoken, uint amount);
    event DepositSingle(address indexed user, address indexed token, uint amount);
    
    event WithdrawLp(address indexed user, address indexed lptoken, uint amount);
    event WithdrawSingle(address indexed user, address indexed token, uint amount);

    event Claim(address indexed user, uint crvReward, uint cvxReward);
    event WhitelistAdded(address indexed token);
    event WhitelistRemoved(address indexed token);

    uint private constant MULTIPLIER = 1e18;

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address private constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    /// @notice Convex main deposit
    address private constant BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    /// @notice Uniswap V3 swap router
    address private constant router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    /// @notice Curve swap contract for selected pid
    address private immutable curveSwap;

    uint public immutable pid;
    address public immutable lptoken;
    address public immutable rewardContract;

    /// @dev reward token ->  reward index
    mapping(address => uint) private rewardIndex;
    /// @dev user -> reward token -> reward index
    mapping(address => mapping(address => uint)) private rewardIndexOf;
    /// @dev user -> reward token -> earned reward
    mapping(address => mapping(address => uint)) private earned;
    
    mapping(address => uint) public balanceOf;
    uint public totalSupply;

    mapping(address => bool) public isWhitelisted;

    constructor(uint _pid, address _curveSwap) Ownable(msg.sender) {
        pid = _pid;
        curveSwap = _curveSwap;

        (address _lptoken, , , address _crvRewards, , bool _shutdown) = IBooster(BOOSTER).poolInfo(_pid);
        require(_lptoken != address(0), "Invalid pid");
        require(!_shutdown, "shutdown");

        lptoken = _lptoken;
        rewardContract = _crvRewards;
    }

    function addWhitelist(address _token) external onlyOwner {
        require(!isWhitelisted[_token], "already whitelisted");
        isWhitelisted[_token] = true;

        emit WhitelistAdded(_token);
    }

    function removeWhitelist(address _token) external onlyOwner {
        require(isWhitelisted[_token], "not whitelisted");
        delete isWhitelisted[_token];

        emit WhitelistRemoved(_token);
    }

    function updateRewardIndex(address _rewardToken, uint reward) internal {
        rewardIndex[_rewardToken] += (reward * MULTIPLIER) / totalSupply;
    }

    function _calculateRewards(address _account, address _rewardToken) private view returns (uint) {
        uint shares = balanceOf[_account];
        return (shares * (rewardIndex[_rewardToken] - rewardIndexOf[_account][_rewardToken])) / MULTIPLIER;
    }

    function calculateRewardsEarned(address _account, address _rewardToken) public view returns (uint) {
        return earned[_account][_rewardToken] + _calculateRewards(_account, _rewardToken);
    }

    function _updateRewards(address _account, address _rewardToken) internal {
        unchecked {
            if (rewardIndex[_rewardToken] > rewardIndexOf[_account][_rewardToken]) {
                earned[_account][_rewardToken] += _calculateRewards(_account, _rewardToken);
                rewardIndexOf[_account][_rewardToken] = rewardIndex[_rewardToken];
            }
        }
    }

    /// @notice Deposit ETH
    function depositETH() public payable {
        // LP balance before
        uint lpBalanceBefore = IERC20(lptoken).balanceOf(address(this));

        // Swap ETH into the first underlying token using Uniswap V3 router
        address token0 = ICurveSwap(curveSwap).coins(0);
        uint amountOut = _swapExactInputSingle(address(0), token0, msg.value, 3000);

        _addLiquidity(token0, 0, amountOut);

        // LP balance after
        uint lpBalanceAfter = IERC20(lptoken).balanceOf(address(this));
        uint updatedAmt = lpBalanceAfter - lpBalanceBefore;
        _deposit(updatedAmt, address(this));

        emit DepositSingle(msg.sender, address(0), msg.value);
    }

    /// @notice Deposit only whitelisted tokens
    function depositSingle(address _token, uint256 _amount) public {
        require(isWhitelisted[_token], "Not whitelisted");
        require(_amount > 0, "Invalid amount");

        // LP balance before
        uint lpBalanceBefore = IERC20(lptoken).balanceOf(address(this));

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        // Check token is underlying token
        uint tokenIdx;
        for (uint256 i = 0; i < 3; i++) {
            address coin = ICurveSwap(curveSwap).coins(i);

            if (_token == coin) {
                tokenIdx = i + 1;
                break;
            }
        }

        // Deposit directly into LP Pool
        if (tokenIdx > 0) {
            _addLiquidity(_token, tokenIdx - 1, _amount);
        } else {
            // Swap token into underlying token using uniswap router
            address token0 = ICurveSwap(curveSwap).coins(0);
            uint amountOut = _swapExactInputSingle(_token, token0, _amount, 3000);
            _addLiquidity(token0, 0, amountOut);
        }

        // LP balance after
        uint lpBalanceAfter = IERC20(lptoken).balanceOf(address(this));
        uint updatedAmt = lpBalanceAfter - lpBalanceBefore;

        _deposit(updatedAmt, address(this));

        emit DepositSingle(msg.sender, _token, _amount);
    }

    function depositLp(uint _amount) public {
        require(_amount > 0, "Invalid amount");
        _deposit(_amount, msg.sender);

        // Emit event
        emit DepositLp(msg.sender, lptoken, _amount);
    }

    function _deposit(uint _amount, address _user) internal {

        if (totalSupply > 0) {
            _getConvexRewards();

            _updateRewards(msg.sender, CRV);
            _updateRewards(msg.sender, CVX);
        }

        if (_user != address(this)) {
            IERC20(lptoken).safeTransferFrom(
                _user,
                address(this),
                _amount
            );
        }

        balanceOf[msg.sender] += _amount;
        totalSupply += _amount;

        IERC20(lptoken).approve(BOOSTER, _amount);
        IBooster(BOOSTER).deposit(pid, _amount, true);
    }

    /// @notice Withdraw LP tokens directly
    function withdrawLp(uint256 _amount) public {
        require(_amount > 0, "Invalid amount");
        _withdraw(_amount, msg.sender);

        // Emit event
        emit WithdrawLp(msg.sender, lptoken, _amount);
    }

    /// @notice Withdraw only whitelisted tokens
    function withdrawSingle(address _token, uint256 _amount) public payable {
        require(isWhitelisted[_token], "Not whitelisted");
        require(_amount > 0, "Invalid amount");

        // Withdraw liquidity
        _withdraw(_amount, address(this));

        // Remove liquidity
        uint256[3] memory amounts;
        ICurveSwap(curveSwap).remove_liquidity(_amount, amounts);

        // Swap rewards into token
        uint256 amount = 0;
        for (uint256 i = 0; i < 3; i++) {
            // get returned token balance
            address coin = ICurveSwap(curveSwap).coins(i);
            uint256 balance = IERC20(coin).balanceOf(address(this));
            if (balance == 0) {
                continue;
            }

            if (coin == _token) {
                amount += balance;
            } else {
                // swap into requested token
                uint amountOut = _swapExactInputMultiHop(
                    coin,
                    _token,
                    balance,
                    3000
                );
                amount += amountOut;
            }
        }

        // Swap CRV, CVX
        if (earned[msg.sender][CRV] > 0) {
            uint amountOut = _swapExactInputMultiHop(
                CRV,
                _token,
                earned[msg.sender][CRV],
                3000
            );
            amount += amountOut;
            earned[msg.sender][CRV] = 0;
        }

        if (earned[msg.sender][CVX] > 0) {
            uint amountOut = _swapExactInputMultiHop(
                CVX,
                _token,
                earned[msg.sender][CVX],
                10000
            );
            amount += amountOut;
            earned[msg.sender][CVX] = 0;
        }

        if (amount > 0) {
            if (_token == address(0)) {
                // Unwrap WETH
                IWETH(WETH).withdraw(amount);

                // Transfer ETH to user
                (bool sent, ) = msg.sender.call{value: amount}("");
                require(sent, "Failed to send Ether");

            } else {
                // Transfer requested token from vault to user
                IERC20(_token).safeTransfer(msg.sender, amount);
            }
        }

        // Emit event
        emit WithdrawSingle(msg.sender, _token, amount);
    }

    function _withdraw(uint _amount, address _user) internal {
        require(balanceOf[msg.sender] >= _amount, "Exceeded amount");

        if (_user == address(this)) {
            _getConvexRewards();

            _updateRewards(msg.sender, CRV);
            _updateRewards(msg.sender, CVX);
        } else {
            claimRewards();
        }

        IBaseRewardPool(rewardContract).withdrawAndUnwrap(_amount, true);
        
        balanceOf[msg.sender] -= _amount;
        totalSupply -= _amount;
        
        if (_user != address(this)) {
            IERC20(lptoken).safeTransfer(msg.sender, _amount);
        }
    }

    function claimRewards() public {
        _getConvexRewards();

        _updateRewards(msg.sender, CRV);
        _updateRewards(msg.sender, CVX);

        uint crvReward = calculateRewardsEarned(msg.sender, CRV);
        uint cvxReward = calculateRewardsEarned(msg.sender, CVX);

        if (crvReward > 0) {
            earned[msg.sender][CRV] = 0;
            IERC20(CRV).transfer(msg.sender, crvReward);
        }

        if (cvxReward > 0) {
            earned[msg.sender][CVX] = 0;
            IERC20(CVX).transfer(msg.sender, cvxReward);
        }

        emit Claim(msg.sender, crvReward, cvxReward);
    }

    function pendingRewards(
        address _user
    ) external view returns (uint crvRewards, uint cvxRewards) {
        if (totalSupply == 0) return (0, 0);

        uint totalCrvRewards = IBaseRewardPool(rewardContract).earned(address(this));
        uint crvRewardIndex = rewardIndex[CRV] + (totalCrvRewards * MULTIPLIER) / totalSupply;

        uint totalCVXRewards = _calculateCvxReward(totalCrvRewards);
        uint cvxRewardIndex = rewardIndex[CVX] + (totalCVXRewards * MULTIPLIER) / totalSupply;

        crvRewards = (balanceOf[_user] * (crvRewardIndex - rewardIndexOf[_user][CRV])) / MULTIPLIER;
        cvxRewards = (balanceOf[_user] * (cvxRewardIndex - rewardIndexOf[_user][CVX])) / MULTIPLIER;
        crvRewards += earned[_user][CRV];
        cvxRewards += earned[_user][CVX];
    }

    function _getConvexRewards() internal {
        if (totalSupply == 0) return;

        uint256 crvBalBefore = IERC20(CRV).balanceOf(address(this));
        uint256 cvxBalBefore = IERC20(CVX).balanceOf(address(this));

        IBaseRewardPool(rewardContract).getReward();

        uint256 crvBalDelta = IERC20(CRV).balanceOf(address(this)) - crvBalBefore;
        uint256 cvxBalDelta = IERC20(CVX).balanceOf(address(this)) - cvxBalBefore;

        if (crvBalDelta > 0) {
            updateRewardIndex(CRV, crvBalDelta);
        }

        if (cvxBalDelta > 0) {
            updateRewardIndex(CVX, cvxBalDelta);
        }
    }

    function _calculateCvxReward(uint _crvRewards) internal view returns (uint cvxRewards){
        uint256 supply = ICVX(CVX).totalSupply();
        if(supply == 0){
            cvxRewards = _crvRewards;
        }
        uint256 reductionPerCliff = ICVX(CVX).reductionPerCliff();
        uint256 totalCliffs = ICVX(CVX).totalCliffs();
        uint256 maxSupply = ICVX(CVX).maxSupply();

        uint256 cliff = supply / reductionPerCliff;
        if (cliff < totalCliffs) {
            // for reduction% take inverse of current cliff
            uint256 reduction = totalCliffs - cliff;
            // reduce
            cvxRewards = _crvRewards * reduction / totalCliffs;
            // supply cap check
            uint256 amtTillMax = maxSupply - supply;
            if(cvxRewards > amtTillMax){
                cvxRewards = amtTillMax;
            }
        }
    }

    function _addLiquidity(
        address _token,
        uint256 _idx,
        uint256 _amount
    ) internal {
        // Approve token transfer to curve
        IERC20(_token).approve(curveSwap, _amount);

        // Add single liquidity
        uint256[3] memory amounts;
        amounts[_idx] = _amount;
        ICurveSwap(curveSwap).add_liquidity(amounts, 0);
    }

    function _swapExactInputSingle(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint24 _fee
    ) internal returns (uint256 amountOut) {
        if (_tokenIn != address(0)) {
            IERC20(_tokenIn).approve(router, 0);
            IERC20(_tokenIn).approve(router, _amountIn);
        }

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: _tokenIn == address(0) ? WETH : _tokenIn,
                tokenOut: _tokenOut,
                fee: _fee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: _amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        if (_tokenIn == address(0)) {
            amountOut = ISwapRouter(router).exactInputSingle{value: _amountIn}(params);
        } else {
            amountOut = ISwapRouter(router).exactInputSingle(params);
        }
    }

    function _swapExactInputMultiHop(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint24 _feeTier
    ) internal returns (uint256 amountOut) {
        if (_tokenIn != address(0)) {
            IERC20(_tokenIn).approve(router, 0);
            IERC20(_tokenIn).approve(router, _amountIn);
        }

        if (
            _tokenIn == address(0) || _tokenIn == WETH ||
            _tokenOut == address(0) || _tokenOut == WETH
        ) {
            amountOut = _swapExactInputSingle(_tokenIn, _tokenOut, _amountIn, _feeTier);
        } else {
            bytes memory path = abi.encodePacked(
                _tokenIn,
                uint24(_feeTier),
                WETH,
                uint24(_feeTier),
                _tokenOut
            );

            ISwapRouter.ExactInputParams memory params = ISwapRouter
                .ExactInputParams({
                    path: path,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: _amountIn,
                    amountOutMinimum: 0
                });

            amountOut = ISwapRouter(router).exactInput(params);
        }
    }
}
