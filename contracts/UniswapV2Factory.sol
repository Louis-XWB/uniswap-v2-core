pragma solidity =0.5.16;

import './interfaces/IUniswapV2Factory.sol';
import './UniswapV2Pair.sol';

// 创建流动性池的工厂合约
contract UniswapV2Factory is IUniswapV2Factory {
    address public feeTo; // 收取手续费的接收地址
    address public feeToSetter; // 拥有设置feeTo权限的地址
    // feeTo是开发者团队的地址。用于切换开发团队手续费开关，在uniswapV2中，会收取0.3%的手续费给LP，
    // 如果这里的feeTo地址是0，则表明不给开发者团队手续费，如果不为0，则开发者会收取0.05%手续费。


    // 前两个地址分别对应交易对中的两种代币地址，最后一个地址是交易对合约本身地址
    // 通过 token 地址可以获取 pair 地址
    mapping(address => mapping(address => address)) public getPair; 

    address[] public allPairs; // allPairs 是用于存放所有交易对（代币对）合约地址信息


    // 创建交易对事件
    // PairCreated 事件在createPair方法中触发，保存交易对的信息（两种代币地址，交易对本身地址，创建交易对的数量）
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    // 部署合约时对feeToSetter地址进行初始化
    constructor(address _feeToSetter) public {
        // 仅设置了 feeToSetter 没有设置 feeTo
        feeToSetter = _feeToSetter;
    }

    // 获取已经生成的 pair 数量
    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    // 创建一个新的交易对并返回其地址
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        // 两个代币地址不能相同
        require(tokenA != tokenB, 'UniswapV2: IDENTICAL_ADDRESSES');

        // 将地址进行排序：确保 token0 字面地址小于 token1
        // 这可以 A，B 两个地址无论什么顺序传入，得到的 token0 和 token1 结果都是一样的。
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        // token0 和 token1 不能为 0 地址
        require(token0 != address(0), 'UniswapV2: ZERO_ADDRESS');

        // 检查交易对是否已经存在
        require(getPair[token0][token1] == address(0), 'UniswapV2: PAIR_EXISTS'); // single check is sufficient

        // 使用 create2 创建交易对合约
        bytes memory bytecode = type(UniswapV2Pair).creationCode;

        // 为了确保 salt 的唯一性，将 token0 和 token1 作为 salt 生成的唯一方式
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));

        // 实际上在最新版的 EMV 中，已经直接支持给new方法传递 salt 参数，如下所示：pair = new UniswapV2Pair{salt: salt}();,
        // 因为 Uniswap v2 合约在开发时还没有这个功能，所以使用 assembly create2。
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        // 初始化交易对合约
        IUniswapV2Pair(pair).initialize(token0, token1);

        // 将交易对地址保存到 getPair 中
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);// 将交易对地址保存到 allPairs 中
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    // 设置收取手续费的接收地址
    function setFeeTo(address _feeTo) external {
        // 只有 feeToSetter 地址才能调用
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeTo = _feeTo;
    }
    
    // 设置拥有设置feeTo权限的地址
    function setFeeToSetter(address _feeToSetter) external {
        // 只有 feeToSetter 地址才能调用
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }
}
