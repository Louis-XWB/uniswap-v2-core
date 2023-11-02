pragma solidity =0.5.16;

import './interfaces/IUniswapV2Pair.sol';
import './UniswapV2ERC20.sol';
import './libraries/Math.sol';
import './libraries/UQ112x112.sol';
import './interfaces/IERC20.sol';
import './interfaces/IUniswapV2Factory.sol';
import './interfaces/IUniswapV2Callee.sol';

// Uniswap V2Pair 继承自IUniswap V2Pair, Uniswap V2ERC20，其中IUniswap V2Pair中定义了必须要实现的接口
contract UniswapV2Pair is IUniswapV2Pair, UniswapV2ERC20 {
    using SafeMath for uint; // 使用SafeMath库来防止uint256溢出
    using UQ112x112 for uint224; // 使用UQ112x112库来处理uint224

    uint public constant MINIMUM_LIQUIDITY = 10 ** 3; // 定义了最小流动性，在提供初始流动性时会被燃烧掉

    // 用于计算ERC-20合约中转移资产的transfer对应的函数选择器
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    // 存储factory合约地址，token0，token1分别表示两种代币的地址
    address public factory;
    address public token0;
    address public token1;

    // reserve0，reserve1 分别表示最新恒定乘积中两种代币的数量
    uint112 private reserve0; // uses single storage slot, accessible via getReserves
    uint112 private reserve1; // uses single storage slot, accessible via getReserves
    // 记录交易时的区块创建时间
    uint32 private blockTimestampLast; // uses single storage slot, accessible via getReserves

    // 变量用于记录交易对中两种价格的累计值
    // 每个交易对都有一个 `price0CumulativeLast` 和 `price1CumulativeLast`，
    // 分别记录了两个代币的价格累积值。每次交易完成后，这两个值都会被更新。
    // 这样，其他智能合约就可以通过这两个值来计算出一个代币对的平均价格。
    uint public price0CumulativeLast;
    uint public price1CumulativeLast;
    // 用于表示某一时刻恒定乘积中的积的值，主要用于开发团队手续费的计算
    uint public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    // 表示未被锁上的状态，用于下面的修饰器
    uint private unlocked = 1;

    // 该modifier的流程为：在调用该lock修饰器的函数首先检查unlocked 是否为1，
    // 如果不是则报错被锁上，如果是为1，则将unlocked赋值为0（锁上），之后执行被修饰的函数体，
    // 此时unlocked已成为0，之后等函数执行完之后再恢复unlocked为1：
    modifier lock() {
        require(unlocked == 1, 'UniswapV2: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    // 用于获取交易对的资产数量和最近一次交易的区块时间
    // 获取两种代币的缓存余额。在白皮书中提到，保存缓存余额是为了防止攻击者操控价格预言机。
    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    // 函数用于发送代币
    function _safeTransfer(address token, address to, uint value) private {
        // 使用代币的call函数去调用代币合约transfer来发送代币
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        // 检查call调用是否成功以及返回值是否为true：
        // 在ERC20代币中，一个成功的transfer调用通常会返回一个布尔值true。
        // 但是，并不是所有的ERC20实现都遵循这一标准；有些可能根本不返回任何值。
        // data.length == 0 || abi.decode(data, (bool) ： 允许调用不符合ERC20标准（即不返回任何值）or 确保了那些返回值的代币确实返回了true
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'UniswapV2: TRANSFER_FAILED');
    }

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    // UniswapV2Pair合约是由factory创建的，
    // msg.sender也就是UniswapV2Factory合约的地址。
    constructor() public {
        factory = msg.sender;
    }

    // called once by the factory at time of deployment
    // 该函数只能被工厂合约调用，用于初始化交易对合约中的两种代币地址
    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, 'UniswapV2: FORBIDDEN'); // sufficient check
        token0 = _token0;
        token1 = _token1;
    }

    // update reserves and, on the first call per block, price accumulators
    // 更新reserves并进行价格累计的计算
    function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {
        // 用于验证 balance0 和 blanace1 是否 uint112 的上限
        require(balance0 <= uint112(-1) && balance1 <= uint112(-1), 'UniswapV2: OVERFLOW');

        // 获取当前区块时间, 只取后32位
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);

        // 如果当前区块时间大于最近一次交易的区块时间 和 两种代币的储备数量不为0
        // 则更新价格累计值
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            // 用于计算两种代币的价格累计值
            price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }

        // 更新储备量和最近一次交易的区块时间
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    // if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
    // 用于在添加流动性和移除流动性时，计算开发团队手续费
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = IUniswapV2Factory(factory).feeTo(); // 获取收取手续费的地址
        feeOn = feeTo != address(0); // 如果收取手续费的地址不为0，则表示开启了收取手续费的功能
        uint _kLast = kLast; // gas savings
        // 获取恒定乘积值

        if (feeOn) {
            if (_kLast != 0) {
                // // 计算手续费的值
                uint rootK = Math.sqrt(uint(_reserve0).mul(_reserve1));
                uint rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint numerator = totalSupply.mul(rootK.sub(rootKLast));
                    uint denominator = rootK.mul(5).add(rootKLast);
                    uint liquidity = numerator / denominator;
                    // 调用uniswap V2ERC20中的_mint(),传入开发者团队地址和收益
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    // this low-level function should be called from a contract which performs important safety checks
    // 用于用户提供流动性时(提供一定比例的两种ERC-20代币)增加流动性代币给流动性提供者
    // to：接收流动性代币的地址
    // liquidity：增加流动性的数值
    function mint(address to) external lock returns (uint liquidity) {
        // getReserves()获取两种代币的缓存余额。在白皮书中提到，保存缓存余额是为了防止攻击者操控价格预言机。
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves(); // gas savings

        // 计算协议手续费，并通过当前余额与缓存余额相减获得转账的代币数量。
        // 在调用 mint 函数之前，在 addLiquidity 函数已经完成了转账，所以，从这个函数的角度，两种代币数量的计算方式如下：
        // balance0和balance1是流动性池中当前交易对的资产数量
        // amount0和amount1是计算用户新注入的两种ERC20代币的数量
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        uint amount0 = balance0.sub(_reserve0);
        uint amount1 = balance1.sub(_reserve1);

        // 发送开发团队的手续费
        bool feeOn = _mintFee(_reserve0, _reserve1);
        // 存储当前已发行的流动性代币的总量（之所以写在feeOn后面，是因为在_mintFee()中会更新一次totalSupply值）
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            // 如果_totalSupply为0，则说明是初次提供流动性，会根据恒定乘积公式的平方根来计算，
            // 同时要减去已经燃烧掉的初始流动性值，具体为MINIMUM_LIQUIDITY；
            liquidity = Math.sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            // 如果_totalSupply不为0，则会根据已有流动性按比例增发，由于注入了两种代币，
            // 所以会有两个计算公式，每种代币按注入比例计算流动性值，取两个中的最小值。
            liquidity = Math.min(amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1);
        }

        //
        require(liquidity > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED');
        // 增发新的流动性给接收者
        _mint(to, liquidity);
        // 更新流动性池中两种资产的值
        _update(balance0, balance1, _reserve0, _reserve1);

        // 如果开启了手续费，则更新恒定乘积值
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    // 用于燃烧流动性代币来提取相应的两种资产，并减少交易对的流动性
    function burn(address to) external lock returns (uint amount0, uint amount1) {
        // 获取库存交易对的资产数量
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves(); // gas savings
        // 获取代币地址
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings

        // 获取当前合约中的流动性代币数量
        uint balance0 = IERC20(_token0).balanceOf(address(this));
        uint balance1 = IERC20(_token1).balanceOf(address(this));
        uint liquidity = balanceOf[address(this)];

        // 计算手续费给开发团队
        bool feeOn = _mintFee(_reserve0, _reserve1);
        // 存储当前已发行的流动性代币的总量
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee

        // 按比例计算提取资产
        amount0 = liquidity.mul(balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity.mul(balance1) / _totalSupply; // using balances ensures pro-rata distribution

        require(amount0 > 0 && amount1 > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED');
        // 将用户转入的流动性代币燃烧（通过燃烧代币得到方式来提取两种资产）
        _burn(address(this), liquidity);
        // 将两种资产token转到对应的地址
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);

        // 更新两种资产的余额
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        // 更新流动性池中两种资产的值
        _update(balance0, balance1, _reserve0, _reserve1);

        // 如果开启了手续费，则更新恒定乘积值
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // this low-level function should be called from a contract which performs important safety checks
    // swap 函数实现两种代币的兑换。
    // amount0Out 购买的token0的数量
    // amount1Out 购买的token1的数量
    // to 接收者的地址
    // data 接收后执行回调传递数据
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {
        // 确保amount0Out和amount1Out至少有一个不为0
        // 先判断要购买的token数量是否大于0
        // 为了兼容闪电贷功能，以及不依赖特定代币的 transfer 方法，
        // 整个 swap 方法并没有类似 amountIn 的参数，而是通过比较当前余额与缓存余额的差值来得出转入的代币数量。
        require(amount0Out > 0 || amount1Out > 0, 'UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT');
        //使用getReserves()获取当前库存的交易对资产数量，并判断购买的token是否小于reserve的值。
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves(); // gas savings
        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'UniswapV2: INSUFFICIENT_LIQUIDITY');

        uint balance0;
        uint balance1;
        {
            // scope for _token{0,1}, avoids stack too deep errors
            address _token0 = token0;
            address _token1 = token1;
            require(to != _token0 && to != _token1, 'UniswapV2: INVALID_TO');

            // 如果amount0Out大于0，说明要购买token0，则将token0转给 to；
            // 如果amount1Out大于0，则说明要购买token1，则将token1转给to
            if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
            if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens

            // 调用合约的uniswapV2Call回调函数将data传递过去，普通交易调用这个data为空
            // 由于在 swap 方法最后会检查余额（扣掉手续费后）符合 k 常值函数约束（参考白皮书公式），
            // 因此合约可以先将用户希望获得的代币转出，如果用户之前并没有向合约转入用于交易的代币，则相当于借币（即闪电贷）；
            // 如果使用闪电贷，则需要在自定义的 uniswapV2Call 方法中将借出的代币归还。
            if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
            // 获取此时交易对资产的余额
            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
        }
        //通过当前余额和库存余额比较可得出汇入流动性池的资产数量
        uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;

        // 确保amount0In和amount1In至少有一个不为0
        require(amount0In > 0 || amount1In > 0, 'UniswapV2: INSUFFICIENT_INPUT_AMOUNT');
        {
            // scope for reserve{0,1}Adjusted, avoids stack too deep errors
            // 获取当前交易对的资产数量
            uint balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3));
            uint balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(3));

            // 确保当前交易对的资产数量乘积大于等于恒定乘积
            // 安全检查，确保在交易执行后，资产的数量乘积（也就是流动性池中两种资产数量的乘积）至少要保持在交易执行前的水平。
            // 交易必须保证不会降低k的值，这样可以保护池子免受某些操纵手段的影响，如价格滑点和套利者的攻击。
            // balance0Adjusted和balance1Adjusted是调整后的余额，考虑了交易完成后的状态。它们可能包括交易费用或其他因素的影响。
            // uint(_reserve0)和uint(_reserve1)是交易之前的资产储备量，将它们转换为无符号整型确保了数学操作的正确性。
            // .mul(1000 ** 2)表示调整因子，这通常与协议收取的费用有关。在Uniswap v2中，默认情况下，交易费用是0.3%，所以这里可能是为了把费用纳入计算。
            // 如果这个条件不满足，交易将会被回滚，并且提示一个错误信息 'UniswapV2: K'。这样可以防止在交易过程中因为异常或者操纵造成的流动性池损失。
            require(
                balance0Adjusted.mul(balance1Adjusted) >= uint(_reserve0).mul(_reserve1).mul(1000 ** 2),
                'UniswapV2: K'
            );
        }

        // 更新恒定乘积公式，并且新的值要大于等于原来的值。
        // 使用缓存余额更新价格预言机所需的累计价格，最后更新缓存余额为当前余额。
        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // force balances to match reserves
    function skim(address to) external lock {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)).sub(reserve0));
        _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)).sub(reserve1));
    }

    // force reserves to match balances
    function sync() external lock {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }
}
