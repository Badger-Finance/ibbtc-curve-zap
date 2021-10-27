# @version 0.2.16
"""
@title "Zap" Depositer for wibbtc <> sbtc curve pool
@author tabish@badger.finance
"""

# using this deposit zap users will be able to deposit ibbtc + whatever tokens are there in the metapool

interface ERC20:
    def transfer(_receiver: address, _amount: uint256): nonpayable
    def transferFrom(_sender: address, _receiver: address, _amount: uint256): nonpayable
    def approve(_spender: address, _amount: uint256): nonpayable
    def decimals() -> uint256: view
    def balanceOf(_owner: address) -> uint256: view

interface CurveMeta:
    def add_liquidity(amounts: uint256[N_COINS], min_mint_amount: uint256, _receiver: address) -> uint256: nonpayable
    def remove_liquidity(_amount: uint256, min_amounts: uint256[N_COINS]) -> uint256[N_COINS]: nonpayable
    def remove_liquidity_one_coin(_token_amount: uint256, i: int128, min_amount: uint256, _receiver: address) -> uint256: nonpayable
    def remove_liquidity_imbalance(amounts: uint256[N_COINS], max_burn_amount: uint256) -> uint256: nonpayable
    def calc_withdraw_one_coin(_token_amount: uint256, i: int128) -> uint256: view
    def calc_token_amount(amounts: uint256[N_COINS], deposit: bool) -> uint256: view
    def coins(i: uint256) -> address: view

# interface CurveBase:
#     def add_liquidity(amounts: uint256[BASE_N_COINS], min_mint_amount: uint256): nonpayable
#     def remove_liquidity(_amount: uint256, min_amounts: uint256[BASE_N_COINS]): nonpayable
#     def remove_liquidity_one_coin(_token_amount: uint256, i: int128, min_amount: uint256): nonpayable
#     def remove_liquidity_imbalance(amounts: uint256[BASE_N_COINS], max_burn_amount: uint256): nonpayable
#     def calc_withdraw_one_coin(_token_amount: uint256, i: int128) -> uint256: view
#     def calc_token_amount(amounts: uint256[BASE_N_COINS], deposit: bool) -> uint256: view
#     def coins(i: int128) -> address: view
#     def fee() -> uint256: view

interface WrappedIbbtcEth:
    def mint(_shares: uint256): nonpayable
    def burn(_shares: uint256): nonpayable

N_COINS: constant(int128) = 2 # ibbtc and sbtc ... NOTE: change this accordingly
# MAX_COIN: constant(int128) = N_COINS-1
# BASE_N_COINS: constant(int128) = 3
# N_ALL_COINS: constant(int128) = N_COINS - 1

FEE_DENOMINATOR: constant(uint256) = 10 ** 10
FEE_IMPRECISION: constant(uint256) = 100 * 10 ** 8  # % of the fee

IBBTC_WRAPPER_PROXY: constant(address) = 0x7fC77b5c7614E1533320Ea6DDc2Eb61fa00A9714 # TODO: change this address to wrapper proxy deployed on mainnet
WIBBTC_TOKEN: constant(address) = 0x7fC77b5c7614E1533320Ea6DDc2Eb61fa00A9714 # TODO: change this to wibbtc token address
IBBTC_TOKEN: constant(address) = 0x7fC77b5c7614E1533320Ea6DDc2Eb61fa00A9714 # TODO: change this to ibbtc token address

# BASE_POOL: constant(address) = 0x7fC77b5c7614E1533320Ea6DDc2Eb61fa00A9714
# BASE_LP_TOKEN: constant(address) = 0x075b1bb99792c9E1041bA13afEf80C91a1e70fB3
# BASE_COINS: constant(address[3]) = [
#     0xEB4C2781e4ebA804CE9a9803C67d0893436bB27D,  # renBTC
#     0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,  # wBTC
#     0xfE18be6b3Bd88A2D2A7f928d00292E7a9963CfC6,  # sBTC
# ]

# coin -> pool -> is approved to transfer?
is_approved: HashMap[address, HashMap[address, bool]]


@external
def __init__():
    """
    @notice Contract constructor
    """
    # base_coins: address[3] = BASE_COINS
    # for coin in base_coins:
    #     ERC20(coin).approve(BASE_POOL, MAX_UINT256)


@external
def add_liquidity(
    _pool: address,
    _deposit_amounts: uint256[N_COINS],
    _min_mint_amount: uint256,
    _receiver: address = msg.sender,
) -> uint256:
    """
    @notice Wrap underlying coins and deposit them into `_pool`
    @param _pool Address of the pool to deposit into
    @param _deposit_amounts List of amounts of underlying coins to deposit
    @param _min_mint_amount Minimum amount of LP tokens to mint from the deposit
    @param _receiver Address that receives the LP tokens
    @return Amount of LP tokens received by depositing
    """
    meta_amounts: uint256[N_COINS] = empty(uint256[N_COINS])
    # base_amounts: uint256[BASE_N_COINS] = empty(uint256[BASE_N_COINS])
    # deposit_base: bool = False
    # base_coins: address[3] = BASE_COINS

    # for ibbtc deposit
    if _deposit_amounts[0] != 0:
        coin: address = IBBTC_TOKEN
        if not self.is_approved[coin][IBBTC_WRAPPER_PROXY]:
            ERC20(coin).approve(IBBTC_WRAPPER_PROXY, MAX_UINT256)
            self.is_approved[coin][IBBTC_WRAPPER_PROXY] = True
        ERC20(coin).transferFrom(msg.sender, self, _deposit_amounts[0])
        
        before_balance_wibbtc: uint256 = ERC20(WIBBTC_TOKEN).balanceOf(self)
        WrappedIbbtcEth(IBBTC_WRAPPER_PROXY).mint(_deposit_amounts[0])
        after_balance_wibbtc: uint256 = ERC20(WIBBTC_TOKEN).balanceOf(self)
        
        # assert(after_balance_wibbtc - before_balance_wibbtc * (MAX_BPS - FEES) / MAX_BPS >= , ) TODO: add an assert for tighter slippage checks

        meta_amounts[0] = after_balance_wibbtc - before_balance_wibbtc

        wibbtc_coin: address = WIBBTC_TOKEN
        if not self.is_approved[wibbtc_coin][_pool]:
            ERC20(wibbtc_coin).approve(_pool, MAX_UINT256)
            self.is_approved[wibbtc_coin][_pool] = True

    # for all coins(other than ibbtc/ wibbtc) do nothing, just approve them and transfer them
    for i in range(1, N_COINS):
        coin: address = CurveMeta(_pool).coins(i)
        amount: uint256 = _deposit_amounts[i]
        if amount == 0:
            continue
        if not self.is_approved[coin][_pool]:
            ERC20(coin).approve(_pool, MAX_UINT256)
            self.is_approved[coin][_pool] = True
        ERC20(coin).transferFrom(msg.sender, self, amount)
        meta_amounts[i] = amount

    # Deposit to the meta pool
    return CurveMeta(_pool).add_liquidity(meta_amounts, _min_mint_amount, _receiver)


@external
def remove_liquidity(
    _pool: address,
    _burn_amount: uint256,
    _min_amounts: uint256[N_COINS],
    _receiver: address = msg.sender
) -> uint256[N_COINS]:
    """
    @notice Withdraw and unwrap coins from the pool
    @dev Withdrawal amounts are based on current deposit ratios
    @param _pool Address of the pool to deposit into
    @param _burn_amount Quantity of LP tokens to burn in the withdrawal
    @param _min_amounts Minimum amounts of underlying coins to receive
    @param _receiver Address that receives the LP tokens
    @return List of amounts of underlying coins that were withdrawn
    """
    ERC20(_pool).transferFrom(msg.sender, self, _burn_amount)

    amounts: uint256[N_COINS] = empty(uint256[N_COINS])

    # Withdraw from meta
    meta_received: uint256[N_COINS] = CurveMeta(_pool).remove_liquidity(
        _burn_amount,
        _min_amounts
    )

    # convert wibbtc to ibbtc
    coin: address = CurveMeta(_pool).coins(0)
    
    before_ibbtc_balance: uint256 = ERC20(IBBTC_TOKEN).balanceOf(self)
    WrappedIbbtcEth(IBBTC_WRAPPER_PROXY).burn(meta_received[0])
    after_ibbtc_balance: uint256 = ERC20(IBBTC_TOKEN).balanceOf(self)
    
    amounts[0] = after_ibbtc_balance - before_ibbtc_balance
    ERC20(IBBTC_TOKEN).transfer(_receiver, amounts[0])
    
    for i in range(1, N_COINS):
        coin = CurveMeta(_pool).coins(i)
        amounts[i] = ERC20(coin).balanceOf(self)
        ERC20(coin).transfer(_receiver, amounts[i])

    return amounts


@external
def remove_liquidity_one_coin(
    _pool: address,
    _burn_amount: uint256,
    i: int128,
    _min_amount: uint256,
    _receiver: address=msg.sender
) -> uint256:
    """
    @notice Withdraw and unwrap a single coin from the pool
    @param _pool Address of the pool to deposit into
    @param _burn_amount Amount of LP tokens to burn in the withdrawal
    @param i Index value of the coin to withdraw
    @param _min_amount Minimum amount of underlying coin to receive
    @param _receiver Address that receives the LP tokens
    @return Amount of underlying coin received
    """
    ERC20(_pool).transferFrom(msg.sender, self, _burn_amount)
    coin: address = CurveMeta(_pool).coins(convert(i, uint256))
    coin_amount: uint256 = 0
    coin_amount = CurveMeta(_pool).remove_liquidity_one_coin(_burn_amount, i, _min_amount, _receiver)

    if i == 0:
        before_ibbtc_balance: uint256 = ERC20(IBBTC_TOKEN).balanceOf(self)
        WrappedIbbtcEth(IBBTC_WRAPPER_PROXY).burn(coin_amount)
        after_ibbtc_balance: uint256 = ERC20(IBBTC_TOKEN).balanceOf(self)
        ERC20(IBBTC_TOKEN).transfer(_receiver, after_ibbtc_balance - before_ibbtc_balance)
    else:
        ERC20(coin).transfer(_receiver, coin_amount)

    return coin_amount

# not sure we need this 
# @external
# def remove_liquidity_imbalance(
#     _pool: address,
#     _amounts: uint256[N_ALL_COINS],
#     _max_burn_amount: uint256,
#     _receiver: address=msg.sender
# ) -> uint256:
#     """
#     @notice Withdraw coins from the pool in an imbalanced amount
#     @param _pool Address of the pool to deposit into
#     @param _amounts List of amounts of underlying coins to withdraw
#     @param _max_burn_amount Maximum amount of LP token to burn in the withdrawal
#     @param _receiver Address that receives the LP tokens
#     @return Actual amount of the LP token burned in the withdrawal
#     """
#     fee: uint256 = CurveBase(BASE_POOL).fee() * BASE_N_COINS / (4 * (BASE_N_COINS - 1))
#     fee += fee * FEE_IMPRECISION / FEE_DENOMINATOR  # Overcharge to account for imprecision

#     # Transfer the LP token in
#     ERC20(_pool).transferFrom(msg.sender, self, _max_burn_amount)

#     withdraw_base: bool = False
#     amounts_base: uint256[BASE_N_COINS] = empty(uint256[BASE_N_COINS])
#     amounts_meta: uint256[N_COINS] = empty(uint256[N_COINS])

#     # determine amounts to withdraw from base pool
#     for i in range(BASE_N_COINS):
#         amount: uint256 = _amounts[MAX_COIN + i]
#         if amount != 0:
#             amounts_base[i] = amount
#             withdraw_base = True

#     # determine amounts to withdraw from metapool
#     amounts_meta[0] = _amounts[0]
#     if withdraw_base:
#         amounts_meta[MAX_COIN] = CurveBase(BASE_POOL).calc_token_amount(amounts_base, False)
#         amounts_meta[MAX_COIN] += amounts_meta[MAX_COIN] * fee / FEE_DENOMINATOR + 1

#     # withdraw from metapool and return the remaining LP tokens
#     burn_amount: uint256 = CurveMeta(_pool).remove_liquidity_imbalance(amounts_meta, _max_burn_amount)
#     ERC20(_pool).transfer(msg.sender, _max_burn_amount - burn_amount)

#     # withdraw from base pool
#     if withdraw_base:
#         CurveBase(BASE_POOL).remove_liquidity_imbalance(amounts_base, amounts_meta[MAX_COIN])
#         coin: address = BASE_LP_TOKEN
#         leftover: uint256 = ERC20(coin).balanceOf(self)

#         if leftover > 0:
#             # if some base pool LP tokens remain, re-deposit them for the caller
#             if not self.is_approved[coin][_pool]:
#                 ERC20(coin).approve(_pool, MAX_UINT256)
#                 self.is_approved[coin][_pool] = True
#             burn_amount -= CurveMeta(_pool).add_liquidity([convert(0, uint256), leftover], 0, msg.sender)

#         # transfer withdrawn base pool tokens to caller
#         base_coins: address[BASE_N_COINS] = BASE_COINS
#         for i in range(BASE_N_COINS):
#             ERC20(base_coins[i]).transfer(_receiver, amounts_base[i])

#     # transfer withdrawn metapool tokens to caller
#     if _amounts[0] > 0:
#         coin: address = CurveMeta(_pool).coins(0)
#         ERC20(coin).transfer(_receiver, _amounts[0])

#     return burn_amount


@view
@external
def calc_withdraw_one_coin(_pool: address, _token_amount: uint256, i: int128) -> uint256:
    """
    @notice Calculate the amount received when withdrawing and unwrapping a single coin
    @param _pool Address of the pool to deposit into
    @param _token_amount Amount of LP tokens to burn in the withdrawal
    @param i Index value of the underlying coin to withdraw
    @return Amount of coin received
    """
    
    return CurveMeta(_pool).calc_withdraw_one_coin(_token_amount, i) # NOTE: as ibbtc to wibbtc is 1:1 this becomes a simple return


@view
@external
def calc_token_amount(_pool: address, _amounts: uint256[N_COINS], _is_deposit: bool) -> uint256:
    """
    @notice Calculate addition or reduction in token supply from a deposit or withdrawal
    @dev This calculation accounts for slippage, but not fees.
         Needed to prevent front-running, not for precise calculations!
    @param _pool Address of the pool to deposit into
    @param _amounts Amount of each underlying coin being deposited
    @param _is_deposit set True for deposits, False for withdrawals
    @return Expected amount of LP tokens received
    """

    return CurveMeta(_pool).calc_token_amount(_amounts, _is_deposit)