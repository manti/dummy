#[test_only]
module warpgate::swap_test {
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
    use warpgate::test_utils;

    const MAX_U64: u64 = 18446744073709551615;
    const MINIMUM_LIQUIDITY: u128 = 1000;

    public fun setup_test_with_genesis(dev: &signer, admin: &signer, treasury: &signer, resource_account: &signer) {
        test_utils::setup_test_with_genesis(dev, admin, treasury, resource_account);
    }

    public fun setup_test(dev: &signer, admin: &signer, treasury: &signer, resource_account: &signer) {
        test_utils::setup_test(dev, admin, treasury, resource_account);
    }

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    fun test_swap_exact_input(
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) {
        account::create_account_for_test(signer::address_of(bob));
        account::create_account_for_test(signer::address_of(alice));


        setup_test_with_genesis(dev, admin, treasury, resource_account);

        let coin_owner = test_coins::init_coins();

        test_coins::register_and_mint<TestWARP>(&coin_owner, bob, 100 * pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 100 * pow(10, 8));
        test_coins::register_and_mint<TestWARP>(&coin_owner, alice, 100 * pow(10, 8));

        let initial_reserve_x = 5 * pow(10, 8);
        let initial_reserve_y = 10 * pow(10, 8);
        let input_x = 2 * pow(10, 8);
        // bob provider liquidity for 5:10 CAKE-BUSD
        router::add_liquidity<TestWARP, TestBUSD>(bob, initial_reserve_x, initial_reserve_y, 0, 0, 25);
        let bob_suppose_lp_balance = math::sqrt(((initial_reserve_x as u128) * (initial_reserve_y as u128))) - MINIMUM_LIQUIDITY;
        let suppose_total_supply = bob_suppose_lp_balance + MINIMUM_LIQUIDITY;

        // let bob_lp_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(bob));
        let alice_token_x_before_balance = coin::balance<TestWARP>(signer::address_of(alice));
        let fee_add = swap::fee_to();
        let fee_signer = account::create_account_for_test(fee_add);
        coin::register<TestWARP>(&fee_signer);
        let mm_fee_add = swap::mm_fee_to();

        let mm_fee_signer = account::create_account_for_test(mm_fee_add);
        coin::register<TestWARP>(&mm_fee_signer);

        
        router::swap_exact_input<TestWARP, TestBUSD>(alice, input_x, 0);

        let alice_token_x_after_balance = coin::balance<TestWARP>(signer::address_of(alice));
        let alice_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(alice));

         // Calculate fee
        let fee_amount = (input_x as u128) * 25 / 10000;
        let amount_after_fee = input_x - (fee_amount as u64);

        let output_y = test_utils::calc_output_using_input(amount_after_fee, initial_reserve_x, initial_reserve_y);
        let new_reserve_x = initial_reserve_x + amount_after_fee;
        let new_reserve_y = initial_reserve_y - (output_y as u64);

        let (reserve_y, reserve_x, _) = swap::token_reserves<TestBUSD, TestWARP>();
        assert!((alice_token_x_before_balance - alice_token_x_after_balance) == input_x, 99);
        assert!(alice_token_y_after_balance == (output_y as u64), 98);
        assert!(reserve_x == new_reserve_x, 97);
        assert!(reserve_y == new_reserve_y, 96);

        let bob_token_x_before_balance = coin::balance<TestWARP>(signer::address_of(bob));
        let bob_token_y_before_balance = coin::balance<TestBUSD>(signer::address_of(bob));

        router::remove_liquidity<TestWARP, TestBUSD>(bob, (bob_suppose_lp_balance as u64), 0, 0);

        let bob_token_x_after_balance = coin::balance<TestWARP>(signer::address_of(bob));
        let bob_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(bob));

        let suppose_k_last = ((initial_reserve_x * initial_reserve_y) as u128);
        let suppose_k = ((new_reserve_x * new_reserve_y) as u128);
        let suppose_fee_amount = test_utils::calc_fee_lp(suppose_total_supply, suppose_k, suppose_k_last);
        suppose_total_supply = suppose_total_supply + suppose_fee_amount;

        let bob_remove_liquidity_x = ((new_reserve_x) as u128) * bob_suppose_lp_balance / suppose_total_supply;
        let bob_remove_liquidity_y = ((new_reserve_y) as u128) * bob_suppose_lp_balance / suppose_total_supply;
        new_reserve_x = new_reserve_x - (bob_remove_liquidity_x as u64);
        new_reserve_y = new_reserve_y - (bob_remove_liquidity_y as u64);
        suppose_total_supply = suppose_total_supply - bob_suppose_lp_balance;

        assert!((bob_token_x_after_balance - bob_token_x_before_balance) == (bob_remove_liquidity_x as u64), 95);
        assert!((bob_token_y_after_balance - bob_token_y_before_balance) == (bob_remove_liquidity_y as u64), 94);

        swap::withdraw_fee<TestWARP, TestBUSD>(treasury);
        let treasury_lp_after_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(treasury));
        router::remove_liquidity<TestWARP, TestBUSD>(treasury, (suppose_fee_amount as u64), 0, 0);
        let treasury_token_x_after_balance = coin::balance<TestWARP>(signer::address_of(treasury));
        let treasury_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(treasury));

        let treasury_remove_liquidity_x = ((new_reserve_x) as u128) * suppose_fee_amount / suppose_total_supply;
        let treasury_remove_liquidity_y = ((new_reserve_y) as u128) * suppose_fee_amount / suppose_total_supply;
        assert!(treasury_lp_after_balance == (suppose_fee_amount as u64), 93);
        assert!(treasury_token_x_after_balance == (treasury_remove_liquidity_x as u64), 92);
        assert!(treasury_token_y_after_balance == (treasury_remove_liquidity_y as u64), 91);
        let mm_fee_collector_balance = coin::balance<TestWARP>(signer::address_of(&mm_fee_signer));
        assert!(mm_fee_collector_balance == (fee_amount as u64), 90);
    }

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    fun test_withdraw_fee_noauth(
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) {
        account::create_account_for_test(signer::address_of(bob));
        account::create_account_for_test(signer::address_of(alice));

        setup_test_with_genesis(dev, admin, treasury, resource_account);

        let coin_owner = test_coins::init_coins();

        test_coins::register_and_mint<TestWARP>(&coin_owner, bob, 100 * pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 100 * pow(10, 8));
        test_coins::register_and_mint<TestWARP>(&coin_owner, alice, 100 * pow(10, 8));

        let initial_reserve_x = 5 * pow(10, 8);
        let initial_reserve_y = 10 * pow(10, 8);
        let input_x = 2 * pow(10, 8);
        // bob provider liquidity for 5:10 CAKE-BUSD
        router::add_liquidity<TestWARP, TestBUSD>(bob, initial_reserve_x, initial_reserve_y, 0, 0, 25);
        if(swap_utils::sort_token_type<TestWARP, TestBUSD>()){
            swap::check_or_register_coin_store<LPToken<TestWARP, TestBUSD>>(treasury);
        }else{
            swap::check_or_register_coin_store<LPToken<TestBUSD, TestWARP>>(treasury);
        };
        let bob_suppose_lp_balance = math::sqrt(((initial_reserve_x as u128) * (initial_reserve_y as u128))) - MINIMUM_LIQUIDITY;
        let suppose_total_supply = bob_suppose_lp_balance + MINIMUM_LIQUIDITY;

        // let bob_lp_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(bob));
        let alice_token_x_before_balance = coin::balance<TestWARP>(signer::address_of(alice));

        let fee_add = swap::fee_to();
        let fee_signer = account::create_account_for_test(fee_add);
        coin::register<TestWARP>(&fee_signer);
        coin::register<TestBUSD>(&fee_signer);
        let mm_fee_add = swap::mm_fee_to();

        let mm_fee_signer = account::create_account_for_test(mm_fee_add);
        coin::register<TestWARP>(&mm_fee_signer);
        coin::register<TestBUSD>(&mm_fee_signer);

        router::swap_exact_input<TestWARP, TestBUSD>(alice, input_x, 0);

        let alice_token_x_after_balance = coin::balance<TestWARP>(signer::address_of(alice));
        let alice_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(alice));

        let fee_amount = (input_x as u128) * 25 / 10000;
        let amount_after_fee = input_x - (fee_amount as u64);

        let output_y = test_utils::calc_output_using_input(amount_after_fee, initial_reserve_x, initial_reserve_y);
        let new_reserve_x = initial_reserve_x + amount_after_fee;
        let new_reserve_y = initial_reserve_y - (output_y as u64);

        let (reserve_y, reserve_x, _) = swap::token_reserves<TestBUSD, TestWARP>();
        assert!((alice_token_x_before_balance - alice_token_x_after_balance) == input_x, 99);
        assert!(alice_token_y_after_balance == (output_y as u64), 98);
        assert!(reserve_x == new_reserve_x, 97);
        assert!(reserve_y == new_reserve_y, 96);

        let bob_token_x_before_balance = coin::balance<TestWARP>(signer::address_of(bob));
        let bob_token_y_before_balance = coin::balance<TestBUSD>(signer::address_of(bob));

        router::remove_liquidity<TestWARP, TestBUSD>(bob, (bob_suppose_lp_balance as u64), 0, 0);

        let bob_token_x_after_balance = coin::balance<TestWARP>(signer::address_of(bob));
        let bob_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(bob));

        let suppose_k_last = ((initial_reserve_x * initial_reserve_y) as u128);
        let suppose_k = ((new_reserve_x * new_reserve_y) as u128);
        let suppose_fee_amount = test_utils::calc_fee_lp(suppose_total_supply, suppose_k, suppose_k_last);
        suppose_total_supply = suppose_total_supply + suppose_fee_amount;

        let bob_remove_liquidity_x = ((new_reserve_x) as u128) * bob_suppose_lp_balance / suppose_total_supply;
        let bob_remove_liquidity_y = ((new_reserve_y) as u128) * bob_suppose_lp_balance / suppose_total_supply;
        new_reserve_x = new_reserve_x - (bob_remove_liquidity_x as u64);
        new_reserve_y = new_reserve_y - (bob_remove_liquidity_y as u64);
        suppose_total_supply = suppose_total_supply - bob_suppose_lp_balance;

        assert!((bob_token_x_after_balance - bob_token_x_before_balance) == (bob_remove_liquidity_x as u64), 95);
        assert!((bob_token_y_after_balance - bob_token_y_before_balance) == (bob_remove_liquidity_y as u64), 94);

        swap::withdraw_fee_noauth<TestWARP, TestBUSD>();
        let treasury_lp_after_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(treasury));
        router::remove_liquidity<TestWARP, TestBUSD>(treasury, (suppose_fee_amount as u64), 0, 0);
        let treasury_token_x_after_balance = coin::balance<TestWARP>(signer::address_of(treasury));
        let treasury_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(treasury));

        let treasury_remove_liquidity_x = ((new_reserve_x) as u128) * suppose_fee_amount / suppose_total_supply;
        let treasury_remove_liquidity_y = ((new_reserve_y) as u128) * suppose_fee_amount / suppose_total_supply;

        assert!(treasury_lp_after_balance == (suppose_fee_amount as u64), 93);
        assert!(treasury_token_x_after_balance == (treasury_remove_liquidity_x as u64), 92);
        assert!(treasury_token_y_after_balance == (treasury_remove_liquidity_y as u64), 91);
    }

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    fun test_swap_exact_input_overflow(
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) {
        account::create_account_for_test(signer::address_of(bob));
        account::create_account_for_test(signer::address_of(alice));

        setup_test_with_genesis(dev, admin, treasury, resource_account);

        let coin_owner = test_coins::init_coins();

        test_coins::register_and_mint<TestWARP>(&coin_owner, bob, MAX_U64);
        test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, MAX_U64);
        test_coins::register_and_mint<TestWARP>(&coin_owner, alice, MAX_U64);

        let initial_reserve_x = MAX_U64 / pow(10, 4);
        let initial_reserve_y = MAX_U64 / pow(10, 4);
        let input_x = pow(10, 9) * pow(10, 8);
        // bob provider liquidity for 5:10 CAKE-BUSD
        router::add_liquidity<TestWARP, TestBUSD>(bob, initial_reserve_x, initial_reserve_y, 0, 0, 25);


        let fee_add = swap::fee_to();
        let fee_signer = account::create_account_for_test(fee_add);
        coin::register<TestWARP>(&fee_signer);
        coin::register<TestBUSD>(&fee_signer);
        let mm_fee_add = swap::mm_fee_to();

        let mm_fee_signer = account::create_account_for_test(mm_fee_add);
        coin::register<TestWARP>(&mm_fee_signer);
        coin::register<TestBUSD>(&mm_fee_signer);

        router::swap_exact_input<TestWARP, TestBUSD>(alice, input_x, 0);
    }

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    #[expected_failure(abort_code = 65542, location = 0x1::coin)]
    fun test_swap_exact_input_with_not_enough_liquidity(
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) {
        account::create_account_for_test(signer::address_of(bob));
        account::create_account_for_test(signer::address_of(alice));

        setup_test_with_genesis(dev, admin, treasury, resource_account);

        let coin_owner = test_coins::init_coins();

        test_coins::register_and_mint<TestWARP>(&coin_owner, bob, 1000 * pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 1000 * pow(10, 8));
        test_coins::register_and_mint<TestWARP>(&coin_owner, alice, 1000 * pow(10, 8));

        let initial_reserve_x = 100 * pow(10, 8);
        let initial_reserve_y = 200 * pow(10, 8);
        let input_x = 10000 * pow(10, 8);
        // bob provider liquidity for 5:10 CAKE-BUSD
        router::add_liquidity<TestWARP, TestBUSD>(bob, initial_reserve_x, initial_reserve_y, 0, 0, 25);


        router::swap_exact_input<TestWARP, TestBUSD>(alice, input_x, 0);
    }

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    #[expected_failure(abort_code = 0, location = warpgate::router)]
    fun test_swap_exact_input_under_min_output(
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) {
        account::create_account_for_test(signer::address_of(bob));
        account::create_account_for_test(signer::address_of(alice));

        setup_test_with_genesis(dev, admin, treasury, resource_account);

        let coin_owner = test_coins::init_coins();

        test_coins::register_and_mint<TestWARP>(&coin_owner, bob, 100 * pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 100 * pow(10, 8));
        test_coins::register_and_mint<TestWARP>(&coin_owner, alice, 100 * pow(10, 8));

        let initial_reserve_x = 5 * pow(10, 8);
        let initial_reserve_y = 10 * pow(10, 8);
        let input_x = 2 * pow(10, 8);
        // bob provider liquidity for 5:10 CAKE-BUSD
        router::add_liquidity<TestWARP, TestBUSD>(bob, initial_reserve_x, initial_reserve_y, 0, 0, 25);

        let output_y = test_utils::calc_output_using_input(input_x, initial_reserve_x, initial_reserve_y);
        let fee_add = swap::fee_to();
        let fee_signer = account::create_account_for_test(fee_add);
        coin::register<TestWARP>(&fee_signer);
        coin::register<TestBUSD>(&fee_signer);
        let mm_fee_add = swap::mm_fee_to();

        let mm_fee_signer = account::create_account_for_test(mm_fee_add);
        coin::register<TestWARP>(&mm_fee_signer);
        coin::register<TestBUSD>(&mm_fee_signer);


        router::swap_exact_input<TestWARP, TestBUSD>(alice, input_x, ((output_y + 1) as u64));
    }

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    fun test_swap_exact_output(
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) {
        account::create_account_for_test(signer::address_of(bob));
        account::create_account_for_test(signer::address_of(alice));

        setup_test_with_genesis(dev, admin, treasury, resource_account);

        let coin_owner = test_coins::init_coins();

        test_coins::register_and_mint<TestWARP>(&coin_owner, bob, 100 * pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 100 * pow(10, 8));
        test_coins::register_and_mint<TestWARP>(&coin_owner, alice, 100 * pow(10, 8));

        let initial_reserve_x = 5 * pow(10, 8);
        let initial_reserve_y = 10 * pow(10, 8);
        let output_y = 166319299;
        let input_x_max = 1 * pow(10, 8);

        // bob provider liquidity for 5:10 CAKE-BUSD
        router::add_liquidity<TestWARP, TestBUSD>(bob, initial_reserve_x, initial_reserve_y, 0, 0, 25);
        let bob_suppose_lp_balance = math::sqrt(((initial_reserve_x as u128) * (initial_reserve_y as u128))) - MINIMUM_LIQUIDITY;
        let suppose_total_supply = bob_suppose_lp_balance + MINIMUM_LIQUIDITY;

        let alice_token_x_before_balance = coin::balance<TestWARP>(signer::address_of(alice));

        router::swap_exact_output<TestWARP, TestBUSD>(alice, output_y, input_x_max);

        let alice_token_x_after_balance = coin::balance<TestWARP>(signer::address_of(alice));
        let alice_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(alice));

        let input_x = test_utils::calc_input_using_output(output_y, initial_reserve_x, initial_reserve_y);
        let new_reserve_x = initial_reserve_x + (input_x as u64);
        let new_reserve_y = initial_reserve_y - output_y;

        let (reserve_y, reserve_x, _) = swap::token_reserves<TestBUSD, TestWARP>();
        assert!((alice_token_x_before_balance - alice_token_x_after_balance) == (input_x as u64), 99);
        assert!(alice_token_y_after_balance == output_y, 98);
        assert!(reserve_x == new_reserve_x, 97);
        assert!(reserve_y == new_reserve_y, 96);

        let bob_token_x_before_balance = coin::balance<TestWARP>(signer::address_of(bob));
        let bob_token_y_before_balance = coin::balance<TestBUSD>(signer::address_of(bob));

        router::remove_liquidity<TestWARP, TestBUSD>(bob, (bob_suppose_lp_balance as u64), 0, 0);

        let bob_token_x_after_balance = coin::balance<TestWARP>(signer::address_of(bob));
        let bob_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(bob));

        let suppose_k_last = ((initial_reserve_x * initial_reserve_y) as u128);
        let suppose_k = ((new_reserve_x * new_reserve_y) as u128);
        let suppose_fee_amount = test_utils::calc_fee_lp(suppose_total_supply, suppose_k, suppose_k_last);
        suppose_total_supply = suppose_total_supply + suppose_fee_amount;

        let bob_remove_liquidity_x = ((new_reserve_x) as u128) * bob_suppose_lp_balance / suppose_total_supply;
        let bob_remove_liquidity_y = ((new_reserve_y) as u128) * bob_suppose_lp_balance / suppose_total_supply;
        new_reserve_x = new_reserve_x - (bob_remove_liquidity_x as u64);
        new_reserve_y = new_reserve_y - (bob_remove_liquidity_y as u64);
        suppose_total_supply = suppose_total_supply - bob_suppose_lp_balance;

        assert!((bob_token_x_after_balance - bob_token_x_before_balance) == (bob_remove_liquidity_x as u64), 95);
        assert!((bob_token_y_after_balance - bob_token_y_before_balance) == (bob_remove_liquidity_y as u64), 94);

        swap::withdraw_fee<TestWARP, TestBUSD>(treasury);
        let treasury_lp_after_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(treasury));
        router::remove_liquidity<TestWARP, TestBUSD>(treasury, (suppose_fee_amount as u64), 0, 0);
        let treasury_token_x_after_balance = coin::balance<TestWARP>(signer::address_of(treasury));
        let treasury_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(treasury));

        let treasury_remove_liquidity_x = ((new_reserve_x) as u128) * suppose_fee_amount / suppose_total_supply;
        let treasury_remove_liquidity_y = ((new_reserve_y) as u128) * suppose_fee_amount / suppose_total_supply;

        assert!(treasury_lp_after_balance == (suppose_fee_amount as u64), 93);
        assert!(treasury_token_x_after_balance == (treasury_remove_liquidity_x as u64), 92);
        assert!(treasury_token_y_after_balance == (treasury_remove_liquidity_y as u64), 91);
    }

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    #[expected_failure]
    fun test_swap_exact_output_with_not_enough_liquidity(
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) {
        account::create_account_for_test(signer::address_of(bob));
        account::create_account_for_test(signer::address_of(alice));

        setup_test_with_genesis(dev, admin, treasury, resource_account);

        let coin_owner = test_coins::init_coins();

        test_coins::register_and_mint<TestWARP>(&coin_owner, bob, 1000 * pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 1000 * pow(10, 8));
        test_coins::register_and_mint<TestWARP>(&coin_owner, alice, 1000 * pow(10, 8));

        let initial_reserve_x = 100 * pow(10, 8);
        let initial_reserve_y = 200 * pow(10, 8);
        let output_y = 1000 * pow(10, 8);
        let input_x_max = 1000 * pow(10, 8);

        // bob provider liquidity for 5:10 CAKE-BUSD
        router::add_liquidity<TestWARP, TestBUSD>(bob, initial_reserve_x, initial_reserve_y, 0, 0, 25);

        router::swap_exact_output<TestWARP, TestBUSD>(alice, output_y, input_x_max);
    }

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    #[expected_failure(abort_code = 1, location = warpgate::router)]
    fun test_swap_exact_output_excceed_max_input(
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) {
        account::create_account_for_test(signer::address_of(bob));
        account::create_account_for_test(signer::address_of(alice));

        setup_test_with_genesis(dev, admin, treasury, resource_account);

        let coin_owner = test_coins::init_coins();

        test_coins::register_and_mint<TestWARP>(&coin_owner, bob, 1000 * pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 1000 * pow(10, 8));
        test_coins::register_and_mint<TestWARP>(&coin_owner, alice, 1000 * pow(10, 8));

        let initial_reserve_x = 50 * pow(10, 8);
        let initial_reserve_y = 100 * pow(10, 8);
        let output_y = 166319299;

        // bob provider liquidity for 5:10 CAKE-BUSD
        router::add_liquidity<TestWARP, TestBUSD>(bob, initial_reserve_x, initial_reserve_y, 0, 0, 25);

        let input_x = test_utils::calc_input_using_output(output_y, initial_reserve_x, initial_reserve_y);
        router::swap_exact_output<TestWARP, TestBUSD>(alice, output_y, ((input_x - 1) as u64));
    }

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    fun test_swap_x_to_exact_y_direct_external(
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) {
        account::create_account_for_test(signer::address_of(bob));
        account::create_account_for_test(signer::address_of(alice));

        setup_test_with_genesis(dev, admin, treasury, resource_account);

        let coin_owner = test_coins::init_coins();

        test_coins::register_and_mint<TestWARP>(&coin_owner, bob, 100 * pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 100 * pow(10, 8));
        test_coins::register_and_mint<TestWARP>(&coin_owner, alice, 100 * pow(10, 8));

        let initial_reserve_x = 5 * pow(10, 8);
        let initial_reserve_y = 10 * pow(10, 8);
        let output_y = 166319299;
        // let input_x_max = 1 * pow(10, 8);

        // bob provider liquidity for 5:10 CAKE-BUSD
        router::add_liquidity<TestWARP, TestBUSD>(bob, initial_reserve_x, initial_reserve_y, 0, 0, 25);
        let bob_suppose_lp_balance = math::sqrt(((initial_reserve_x as u128) * (initial_reserve_y as u128))) - MINIMUM_LIQUIDITY;
        let suppose_total_supply = bob_suppose_lp_balance + MINIMUM_LIQUIDITY;

        let alice_addr = signer::address_of(alice);

        let alice_token_x_before_balance = coin::balance<TestWARP>(alice_addr);

        let input_x = test_utils::calc_input_using_output(output_y, initial_reserve_x, initial_reserve_y); 

        let x_in_amount = router::get_amount_in<TestWARP, TestBUSD>(output_y);
        assert!(x_in_amount == (input_x as u64), 102);

        let input_x_coin = coin::withdraw(alice, (input_x as u64));

        let (x_out, y_out) =  router::swap_x_to_exact_y_direct_external<TestWARP, TestBUSD>(input_x_coin, output_y);

        assert!(coin::value(&x_out) == 0, 101);
        assert!(coin::value(&y_out) == output_y, 100);
        coin::register<TestBUSD>(alice);
        coin::deposit<TestWARP>(alice_addr, x_out);
        coin::deposit<TestBUSD>(alice_addr, y_out);

        let alice_token_x_after_balance = coin::balance<TestWARP>(alice_addr);
        let alice_token_y_after_balance = coin::balance<TestBUSD>(alice_addr);

        let new_reserve_x = initial_reserve_x + (input_x as u64);
        let new_reserve_y = initial_reserve_y - output_y;

        let (reserve_y, reserve_x, _) = swap::token_reserves<TestBUSD, TestWARP>();
        assert!((alice_token_x_before_balance - alice_token_x_after_balance) == (input_x as u64), 99);
        assert!(alice_token_y_after_balance == output_y, 98);
        assert!(reserve_x == new_reserve_x, 97);
        assert!(reserve_y == new_reserve_y, 96);

        let bob_token_x_before_balance = coin::balance<TestWARP>(signer::address_of(bob));
        let bob_token_y_before_balance = coin::balance<TestBUSD>(signer::address_of(bob));

        router::remove_liquidity<TestWARP, TestBUSD>(bob, (bob_suppose_lp_balance as u64), 0, 0);

        let bob_token_x_after_balance = coin::balance<TestWARP>(signer::address_of(bob));
        let bob_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(bob));

        let suppose_k_last = ((initial_reserve_x * initial_reserve_y) as u128);
        let suppose_k = ((new_reserve_x * new_reserve_y) as u128);
        let suppose_fee_amount = test_utils::calc_fee_lp(suppose_total_supply, suppose_k, suppose_k_last);
        suppose_total_supply = suppose_total_supply + suppose_fee_amount;

        let bob_remove_liquidity_x = ((new_reserve_x) as u128) * bob_suppose_lp_balance / suppose_total_supply;
        let bob_remove_liquidity_y = ((new_reserve_y) as u128) * bob_suppose_lp_balance / suppose_total_supply;
        new_reserve_x = new_reserve_x - (bob_remove_liquidity_x as u64);
        new_reserve_y = new_reserve_y - (bob_remove_liquidity_y as u64);
        suppose_total_supply = suppose_total_supply - bob_suppose_lp_balance;

        assert!((bob_token_x_after_balance - bob_token_x_before_balance) == (bob_remove_liquidity_x as u64), 95);
        assert!((bob_token_y_after_balance - bob_token_y_before_balance) == (bob_remove_liquidity_y as u64), 94);

        swap::withdraw_fee<TestWARP, TestBUSD>(treasury);
        let treasury_lp_after_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(treasury));
        router::remove_liquidity<TestWARP, TestBUSD>(treasury, (suppose_fee_amount as u64), 0, 0);
        let treasury_token_x_after_balance = coin::balance<TestWARP>(signer::address_of(treasury));
        let treasury_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(treasury));

        let treasury_remove_liquidity_x = ((new_reserve_x) as u128) * suppose_fee_amount / suppose_total_supply;
        let treasury_remove_liquidity_y = ((new_reserve_y) as u128) * suppose_fee_amount / suppose_total_supply;

        assert!(treasury_lp_after_balance == (suppose_fee_amount as u64), 93);
        assert!(treasury_token_x_after_balance == (treasury_remove_liquidity_x as u64), 92);
        assert!(treasury_token_y_after_balance == (treasury_remove_liquidity_y as u64), 91);
    }

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    fun test_swap_x_to_exact_y_direct_external_with_more_x_in(
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) {
        account::create_account_for_test(signer::address_of(bob));
        account::create_account_for_test(signer::address_of(alice));

        setup_test_with_genesis(dev, admin, treasury, resource_account);

        let coin_owner = test_coins::init_coins();

        test_coins::register_and_mint<TestWARP>(&coin_owner, bob, 100 * pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 100 * pow(10, 8));
        test_coins::register_and_mint<TestWARP>(&coin_owner, alice, 100 * pow(10, 8));

        let initial_reserve_x = 5 * pow(10, 8);
        let initial_reserve_y = 10 * pow(10, 8);
        let output_y = 166319299;
        // let input_x_max = 1 * pow(10, 8);

        // bob provider liquidity for 5:10 CAKE-BUSD
        router::add_liquidity<TestWARP, TestBUSD>(bob, initial_reserve_x, initial_reserve_y, 0, 0, 25);
        let bob_suppose_lp_balance = math::sqrt(((initial_reserve_x as u128) * (initial_reserve_y as u128))) - MINIMUM_LIQUIDITY;
        let suppose_total_supply = bob_suppose_lp_balance + MINIMUM_LIQUIDITY;

        let alice_addr = signer::address_of(alice);

        let alice_token_x_before_balance = coin::balance<TestWARP>(alice_addr);

        let input_x = test_utils::calc_input_using_output(output_y, initial_reserve_x, initial_reserve_y); 

        let x_in_more = 666666;

        let input_x_coin = coin::withdraw(alice, (input_x as u64) + x_in_more);

        let (x_out, y_out) =  router::swap_x_to_exact_y_direct_external<TestWARP, TestBUSD>(input_x_coin, output_y);

        assert!(coin::value(&x_out) == x_in_more, 101);
        assert!(coin::value(&y_out) == output_y, 100);
        coin::register<TestBUSD>(alice);
        coin::deposit<TestWARP>(alice_addr, x_out);
        coin::deposit<TestBUSD>(alice_addr, y_out);

        let alice_token_x_after_balance = coin::balance<TestWARP>(alice_addr);
        let alice_token_y_after_balance = coin::balance<TestBUSD>(alice_addr);

        let new_reserve_x = initial_reserve_x + (input_x as u64);
        let new_reserve_y = initial_reserve_y - output_y;

        let (reserve_y, reserve_x, _) = swap::token_reserves<TestBUSD, TestWARP>();
        assert!((alice_token_x_before_balance - alice_token_x_after_balance) == (input_x as u64), 99);
        assert!(alice_token_y_after_balance == output_y, 98);
        assert!(reserve_x == new_reserve_x, 97);
        assert!(reserve_y == new_reserve_y, 96);

        let bob_token_x_before_balance = coin::balance<TestWARP>(signer::address_of(bob));
        let bob_token_y_before_balance = coin::balance<TestBUSD>(signer::address_of(bob));

        router::remove_liquidity<TestWARP, TestBUSD>(bob, (bob_suppose_lp_balance as u64), 0, 0);

        let bob_token_x_after_balance = coin::balance<TestWARP>(signer::address_of(bob));
        let bob_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(bob));

        let suppose_k_last = ((initial_reserve_x * initial_reserve_y) as u128);
        let suppose_k = ((new_reserve_x * new_reserve_y) as u128);
        let suppose_fee_amount = test_utils::calc_fee_lp(suppose_total_supply, suppose_k, suppose_k_last);
        suppose_total_supply = suppose_total_supply + suppose_fee_amount;

        let bob_remove_liquidity_x = ((new_reserve_x) as u128) * bob_suppose_lp_balance / suppose_total_supply;
        let bob_remove_liquidity_y = ((new_reserve_y) as u128) * bob_suppose_lp_balance / suppose_total_supply;
        new_reserve_x = new_reserve_x - (bob_remove_liquidity_x as u64);
        new_reserve_y = new_reserve_y - (bob_remove_liquidity_y as u64);
        suppose_total_supply = suppose_total_supply - bob_suppose_lp_balance;

        assert!((bob_token_x_after_balance - bob_token_x_before_balance) == (bob_remove_liquidity_x as u64), 95);
        assert!((bob_token_y_after_balance - bob_token_y_before_balance) == (bob_remove_liquidity_y as u64), 94);

        swap::withdraw_fee<TestWARP, TestBUSD>(treasury);
        let treasury_lp_after_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(treasury));
        router::remove_liquidity<TestWARP, TestBUSD>(treasury, (suppose_fee_amount as u64), 0, 0);
        let treasury_token_x_after_balance = coin::balance<TestWARP>(signer::address_of(treasury));
        let treasury_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(treasury));

        let treasury_remove_liquidity_x = ((new_reserve_x) as u128) * suppose_fee_amount / suppose_total_supply;
        let treasury_remove_liquidity_y = ((new_reserve_y) as u128) * suppose_fee_amount / suppose_total_supply;

        assert!(treasury_lp_after_balance == (suppose_fee_amount as u64), 93);
        assert!(treasury_token_x_after_balance == (treasury_remove_liquidity_x as u64), 92);
        assert!(treasury_token_y_after_balance == (treasury_remove_liquidity_y as u64), 91);
    }

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    #[expected_failure(abort_code = 2, location = warpgate::router)]
    fun test_swap_x_to_exact_y_direct_external_with_less_x_in(
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) {
        account::create_account_for_test(signer::address_of(bob));
        account::create_account_for_test(signer::address_of(alice));

        setup_test_with_genesis(dev, admin, treasury, resource_account);

        let coin_owner = test_coins::init_coins();

        test_coins::register_and_mint<TestWARP>(&coin_owner, bob, 100 * pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 100 * pow(10, 8));
        test_coins::register_and_mint<TestWARP>(&coin_owner, alice, 100 * pow(10, 8));

        let initial_reserve_x = 5 * pow(10, 8);
        let initial_reserve_y = 10 * pow(10, 8);
        let output_y = 166319299;
        // let input_x_max = 1 * pow(10, 8);

        // bob provider liquidity for 5:10 CAKE-BUSD
        router::add_liquidity<TestWARP, TestBUSD>(bob, initial_reserve_x, initial_reserve_y, 0, 0, 25);

        let alice_addr = signer::address_of(alice);

        let input_x = test_utils::calc_input_using_output(output_y, initial_reserve_x, initial_reserve_y); 

        let x_in_less = 66;

        let input_x_coin = coin::withdraw(alice, (input_x as u64) - x_in_less);

        let (x_out, y_out) =  router::swap_x_to_exact_y_direct_external<TestWARP, TestBUSD>(input_x_coin, output_y);

        coin::register<TestBUSD>(alice);
        coin::deposit<TestWARP>(alice_addr, x_out);
        coin::deposit<TestBUSD>(alice_addr, y_out);
    }

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    fun test_get_amount_in(
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) {
        account::create_account_for_test(signer::address_of(bob));
        account::create_account_for_test(signer::address_of(alice));

        setup_test_with_genesis(dev, admin, treasury, resource_account);

        let coin_owner = test_coins::init_coins();

        test_coins::register_and_mint<TestWARP>(&coin_owner, bob, 100 * pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 100 * pow(10, 8));
        test_coins::register_and_mint<TestWARP>(&coin_owner, alice, 100 * pow(10, 8));

        let initial_reserve_x = 5 * pow(10, 8);
        let initial_reserve_y = 10 * pow(10, 8);
        let output_y = 166319299;
        let output_x = 166319299;
        // let input_x_max = 1 * pow(10, 8);

        // bob provider liquidity for 5:10 CAKE-BUSD
        router::add_liquidity<TestWARP, TestBUSD>(bob, initial_reserve_x, initial_reserve_y, 0, 0, 25);

        let input_x = test_utils::calc_input_using_output(output_y, initial_reserve_x, initial_reserve_y); 

        let x_in_amount = router::get_amount_in<TestWARP, TestBUSD>(output_y);
        assert!(x_in_amount == (input_x as u64), 102);

        let input_y = test_utils::calc_input_using_output(output_x, initial_reserve_y, initial_reserve_x); 

        let y_in_amount = router::get_amount_in<TestBUSD, TestWARP>(output_x);
        assert!(y_in_amount == (input_y as u64), 101);
    }
}