#[test_only]
module warpgate::test_utils {
    use std::signer;
    use test_coin::test_coins::{Self, TestWARP, TestBUSD, TestUSDC, TestBNB, TestAPT};
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::genesis;
    use aptos_framework::resource_account;
    use warpgate::swap::{Self, LPToken, initialize};
    use warpgate::router;
    use warpgate::math;
    use aptos_std::math64::pow;
    use warpgate::swap_utils;

    const MAX_U64: u64 = 18446744073709551615;
    const MINIMUM_LIQUIDITY: u128 = 1000;

    public fun setup_test_with_genesis(dev: &signer, admin: &signer, treasury: &signer, resource_account: &signer) {
        genesis::setup();
        setup_test(dev, admin, treasury, resource_account);
    }

    public fun setup_test(dev: &signer, admin: &signer, treasury: &signer, resource_account: &signer) {
        account::create_account_for_test(signer::address_of(dev));
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(treasury));
        resource_account::create_resource_account(dev, b"warpgate", x"");
        initialize(resource_account);
        swap::set_fee_to(admin, signer::address_of(treasury))
    }

    public fun get_token_reserves<X, Y>(): (u64, u64) {

        let is_x_to_y = swap_utils::sort_token_type<X, Y>();
        let reserve_x;
        let reserve_y;
        if(is_x_to_y){
            (reserve_x, reserve_y, _) = swap::token_reserves<X, Y>();
        }else{
            (reserve_y, reserve_x, _) = swap::token_reserves<Y, X>();
        };
        (reserve_x, reserve_y)

    }

    public fun calc_output_using_input(
        input_x: u64,
        reserve_x: u64,
        reserve_y: u64
    ): u128 {
        ((input_x as u128) * 9975u128 * (reserve_y as u128)) / (((reserve_x as u128) * 10000u128) + ((input_x as u128) * 9975u128))
    }

    public fun calc_input_using_output(
        output_y: u64,
        reserve_x: u64,
        reserve_y: u64
    ): u128 {
        ((output_y as u128) * 10000u128 * (reserve_x as u128)) / (9975u128 * ((reserve_y as u128) - (output_y as u128))) + 1u128
    }

    public fun calc_fee_lp(
        total_lp_supply: u128,
        k: u128,
        k_last: u128,
    ): u128 {
        let root_k = math::sqrt(k);
        let root_k_last = math::sqrt(k_last);

        let numerator = total_lp_supply * (root_k - root_k_last) * 8u128;
        let denominator = root_k_last * 17u128 + (root_k * 8u128);
        let liquidity = numerator / denominator;
        liquidity
    }
}