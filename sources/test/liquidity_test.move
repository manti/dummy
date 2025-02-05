#[test_only]
module warpgate::liquidity_test {
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
    fun test_add_liquidity(
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
        test_coins::register_and_mint<TestBUSD>(&coin_owner, alice, 100 * pow(10, 8));

        let bob_liquidity_x = 5 * pow(10, 8);
        let bob_liquidity_y = 10 * pow(10, 8);
        let alice_liquidity_x = 2 * pow(10, 8);
        let alice_liquidity_y = 4 * pow(10, 8);

        let mm_fee_add = swap::mm_fee_to();
        let mm_fee_signer = account::create_account_for_test(mm_fee_add);
        coin::register<TestWARP>(&mm_fee_signer);
        coin::register<TestBUSD>(&mm_fee_signer);


        // bob provider liquidity for 5:10 CAKE-BUSD
        router::add_liquidity<TestWARP, TestBUSD>(bob, bob_liquidity_x, bob_liquidity_y, 0, 0, 25);
        router::add_liquidity<TestWARP, TestBUSD>(alice, alice_liquidity_x, alice_liquidity_y, 0, 0, 25);

        let (balance_y, balance_x) = swap::token_balances<TestBUSD, TestWARP>();
        let (reserve_y, reserve_x, _) = swap::token_reserves<TestBUSD, TestWARP>();
        let resource_account_lp_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(resource_account));
        let bob_lp_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(bob));
        let alice_lp_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(alice));

        let resource_account_suppose_lp_balance = MINIMUM_LIQUIDITY;
        let bob_suppose_lp_balance = math::sqrt(((bob_liquidity_x as u128) * (bob_liquidity_y as u128))) - MINIMUM_LIQUIDITY;
        let total_supply = bob_suppose_lp_balance + MINIMUM_LIQUIDITY;
        let alice_suppose_lp_balance = math::min((alice_liquidity_x as u128) * total_supply / (bob_liquidity_x as u128), (alice_liquidity_y as u128) * total_supply / (bob_liquidity_y as u128));

        assert!(balance_x == bob_liquidity_x + alice_liquidity_x, 99);
        assert!(reserve_x == bob_liquidity_x + alice_liquidity_x, 98);
        assert!(balance_y == bob_liquidity_y + alice_liquidity_y, 97);
        assert!(reserve_y == bob_liquidity_y + alice_liquidity_y, 96);

        assert!(bob_lp_balance == (bob_suppose_lp_balance as u64), 95);
        assert!(alice_lp_balance == (alice_suppose_lp_balance as u64), 94);
        assert!(resource_account_lp_balance == (resource_account_suppose_lp_balance as u64), 93);
    }

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    fun test_add_liquidity_with_less_x_ratio(
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

        test_coins::register_and_mint<TestWARP>(&coin_owner, bob, 200 * pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 200 * pow(10, 8));

        let bob_liquidity_x = 5 * pow(10, 8);
        let bob_liquidity_y = 10 * pow(10, 8);
        let mm_fee_add = swap::mm_fee_to();
        let mm_fee_signer = account::create_account_for_test(mm_fee_add);
        coin::register<TestWARP>(&mm_fee_signer);
        coin::register<TestBUSD>(&mm_fee_signer);

        // bob provider liquidity for 5:10 CAKE-BUSD
        router::add_liquidity<TestWARP, TestBUSD>(bob, bob_liquidity_x, bob_liquidity_y, 0, 0, 25);

        let bob_token_x_before_balance = coin::balance<TestWARP>(signer::address_of(bob));
        let bob_token_y_before_balance = coin::balance<TestBUSD>(signer::address_of(bob));

        let bob_add_liquidity_x = 1 * pow(10, 8);
        let bob_add_liquidity_y = 5 * pow(10, 8);
        router::add_liquidity<TestWARP, TestBUSD>(bob, bob_add_liquidity_x, bob_add_liquidity_y, 0, 0, 25);

        let bob_added_liquidity_x = bob_add_liquidity_x;
        let bob_added_liquidity_y = (bob_add_liquidity_x as u128) * (bob_liquidity_y as u128) / (bob_liquidity_x as u128);

        let bob_token_x_after_balance = coin::balance<TestWARP>(signer::address_of(bob));
        let bob_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(bob));
        let bob_lp_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(bob));
        let resource_account_lp_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(resource_account));

        let resource_account_suppose_lp_balance = MINIMUM_LIQUIDITY;
        let bob_suppose_lp_balance = math::sqrt(((bob_liquidity_x as u128) * (bob_liquidity_y as u128))) - MINIMUM_LIQUIDITY;
        let total_supply = bob_suppose_lp_balance + MINIMUM_LIQUIDITY;
        bob_suppose_lp_balance = bob_suppose_lp_balance + math::min((bob_add_liquidity_x as u128) * total_supply / (bob_liquidity_x as u128), (bob_add_liquidity_y as u128) * total_supply / (bob_liquidity_y as u128));

        assert!((bob_token_x_before_balance - bob_token_x_after_balance) == (bob_added_liquidity_x as u64), 99);
        assert!((bob_token_y_before_balance - bob_token_y_after_balance) == (bob_added_liquidity_y as u64), 98);
        assert!(bob_lp_balance == (bob_suppose_lp_balance as u64), 97);
        assert!(resource_account_lp_balance == (resource_account_suppose_lp_balance as u64), 96);
    }

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    #[expected_failure(abort_code = 3, location = warpgate::router)]
    fun test_add_liquidity_with_less_x_ratio_and_less_than_y_min(
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

        test_coins::register_and_mint<TestWARP>(&coin_owner, bob, 200 * pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 200 * pow(10, 8));

        let initial_reserve_x = 5 * pow(10, 8);
        let initial_reserve_y = 10 * pow(10, 8);

        let mm_fee_add = swap::mm_fee_to();
        let mm_fee_signer = account::create_account_for_test(mm_fee_add);
        coin::register<TestWARP>(&mm_fee_signer);
        coin::register<TestBUSD>(&mm_fee_signer);

        // bob provider liquidity for 5:10 CAKE-BUSD
        router::add_liquidity<TestWARP, TestBUSD>(bob, initial_reserve_x, initial_reserve_y, 0, 0, 25);

        let bob_add_liquidity_x = 1 * pow(10, 8);
        let bob_add_liquidity_y = 5 * pow(10, 8);
        router::add_liquidity<TestWARP, TestBUSD>(bob, bob_add_liquidity_x, bob_add_liquidity_y, 0, 4 * pow(10, 8), 25);
    }

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    fun test_add_liquidity_with_less_y_ratio(
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

        test_coins::register_and_mint<TestWARP>(&coin_owner, bob, 200 * pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 200 * pow(10, 8));

        let bob_liquidity_x = 5 * pow(10, 8);
        let bob_liquidity_y = 10 * pow(10, 8);

        let mm_fee_add = swap::mm_fee_to();
        let mm_fee_signer = account::create_account_for_test(mm_fee_add);
        coin::register<TestWARP>(&mm_fee_signer);
        coin::register<TestBUSD>(&mm_fee_signer);

        // bob provider liquidity for 5:10 CAKE-BUSD
        router::add_liquidity<TestWARP, TestBUSD>(bob, bob_liquidity_x, bob_liquidity_y, 0, 0, 25);

        let bob_token_x_before_balance = coin::balance<TestWARP>(signer::address_of(bob));
        let bob_token_y_before_balance = coin::balance<TestBUSD>(signer::address_of(bob));

        let bob_add_liquidity_x = 5 * pow(10, 8);
        let bob_add_liquidity_y = 4 * pow(10, 8);
        router::add_liquidity<TestWARP, TestBUSD>(bob, bob_add_liquidity_x, bob_add_liquidity_y, 0, 0, 25);

        let bob_added_liquidity_x = (bob_add_liquidity_y as u128) * (bob_liquidity_x as u128) / (bob_liquidity_y as u128);
        let bob_added_liquidity_y = bob_add_liquidity_y;

        let bob_token_x_after_balance = coin::balance<TestWARP>(signer::address_of(bob));
        let bob_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(bob));
        let bob_lp_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(bob));
        let resource_account_lp_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(resource_account));

        let resource_account_suppose_lp_balance = MINIMUM_LIQUIDITY;
        let bob_suppose_lp_balance = math::sqrt(((bob_liquidity_x as u128) * (bob_liquidity_y as u128))) - MINIMUM_LIQUIDITY;
        let total_supply = bob_suppose_lp_balance + MINIMUM_LIQUIDITY;
        bob_suppose_lp_balance = bob_suppose_lp_balance + math::min((bob_add_liquidity_x as u128) * total_supply / (bob_liquidity_x as u128), (bob_add_liquidity_y as u128) * total_supply / (bob_liquidity_y as u128));


        assert!((bob_token_x_before_balance - bob_token_x_after_balance) == (bob_added_liquidity_x as u64), 99);
        assert!((bob_token_y_before_balance - bob_token_y_after_balance) == (bob_added_liquidity_y as u64), 98);
        assert!(bob_lp_balance == (bob_suppose_lp_balance as u64), 97);
        assert!(resource_account_lp_balance == (resource_account_suppose_lp_balance as u64), 96);
    }

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12345, alice = @0x12346)]
    #[expected_failure(abort_code = 2, location = warpgate::router)]
    fun test_add_liquidity_with_less_y_ratio_and_less_than_x_min(
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

        test_coins::register_and_mint<TestWARP>(&coin_owner, bob, 200 * pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 200 * pow(10, 8));

        let initial_reserve_x = 5 * pow(10, 8);
        let initial_reserve_y = 10 * pow(10, 8);

        let mm_fee_add = swap::mm_fee_to();
        let mm_fee_signer = account::create_account_for_test(mm_fee_add);
        coin::register<TestWARP>(&mm_fee_signer);
        coin::register<TestBUSD>(&mm_fee_signer);

        // bob provider liquidity for 5:10 CAKE-BUSD
        router::add_liquidity<TestWARP, TestBUSD>(bob, initial_reserve_x, initial_reserve_y, 0, 0, 25);

        let bob_add_liquidity_x = 5 * pow(10, 8);
        let bob_add_liquidity_y = 4 * pow(10, 8);
        router::add_liquidity<TestWARP, TestBUSD>(bob, bob_add_liquidity_x, bob_add_liquidity_y, 5 * pow(10, 8), 0, 25);
    }

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12341, alice = @0x12342)]
    fun test_remove_liquidity(
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
        test_coins::register_and_mint<TestWARP>(&coin_owner, alice, 100 * pow(10, 8));

        test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 100 * pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, alice, 100 * pow(10, 8));

        let bob_add_liquidity_x = 5 * pow(10, 8);
        let bob_add_liquidity_y = 10 * pow(10, 8);

        let alice_add_liquidity_x = 2 * pow(10, 8);
        let alice_add_liquidity_y = 4 * pow(10, 8);
        let mm_fee_add = swap::mm_fee_to();
        let mm_fee_signer = account::create_account_for_test(mm_fee_add);
        coin::register<TestWARP>(&mm_fee_signer);
        coin::register<TestBUSD>(&mm_fee_signer);
        // bob provider liquidity for 5:10 CAKE-BUSD
        router::add_liquidity<TestWARP, TestBUSD>(bob, bob_add_liquidity_x, bob_add_liquidity_y, 0, 0, 25);
        router::add_liquidity<TestWARP, TestBUSD>(alice, alice_add_liquidity_x, alice_add_liquidity_y, 0, 0, 25);

        let bob_suppose_lp_balance = math::sqrt(((bob_add_liquidity_x as u128) * (bob_add_liquidity_y as u128))) - MINIMUM_LIQUIDITY;
        let suppose_total_supply = bob_suppose_lp_balance + MINIMUM_LIQUIDITY;
        let alice_suppose_lp_balance = math::min((alice_add_liquidity_x as u128) * suppose_total_supply / (bob_add_liquidity_x as u128), (alice_add_liquidity_y as u128) * suppose_total_supply / (bob_add_liquidity_y as u128));
        suppose_total_supply = suppose_total_supply + alice_suppose_lp_balance;
        let suppose_reserve_x = bob_add_liquidity_x + alice_add_liquidity_x;
        let suppose_reserve_y = bob_add_liquidity_y + alice_add_liquidity_y;

        let bob_lp_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(bob));
        let alice_lp_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(alice));

        assert!((bob_suppose_lp_balance as u64) == bob_lp_balance, 99);
        assert!((alice_suppose_lp_balance as u64) == alice_lp_balance, 98);

        let alice_token_x_before_balance = coin::balance<TestWARP>(signer::address_of(alice));
        let alice_token_y_before_balance = coin::balance<TestBUSD>(signer::address_of(alice));
        let bob_token_x_before_balance = coin::balance<TestWARP>(signer::address_of(bob));
        let bob_token_y_before_balance = coin::balance<TestBUSD>(signer::address_of(bob));

        router::remove_liquidity<TestWARP, TestBUSD>(bob, (bob_suppose_lp_balance as u64), 0, 0);
        let bob_remove_liquidity_x = ((suppose_reserve_x) as u128) * bob_suppose_lp_balance / suppose_total_supply;
        let bob_remove_liquidity_y = ((suppose_reserve_y) as u128) * bob_suppose_lp_balance / suppose_total_supply;
        suppose_total_supply = suppose_total_supply - bob_suppose_lp_balance;
        suppose_reserve_x = suppose_reserve_x - (bob_remove_liquidity_x as u64);
        suppose_reserve_y = suppose_reserve_y - (bob_remove_liquidity_y as u64);

        router::remove_liquidity<TestWARP, TestBUSD>(alice, (alice_suppose_lp_balance as u64), 0, 0);
        let alice_remove_liquidity_x = ((suppose_reserve_x) as u128) * alice_suppose_lp_balance / suppose_total_supply;
        let alice_remove_liquidity_y = ((suppose_reserve_y) as u128) * alice_suppose_lp_balance / suppose_total_supply;
        suppose_reserve_x = suppose_reserve_x - (alice_remove_liquidity_x as u64);
        suppose_reserve_y = suppose_reserve_y - (alice_remove_liquidity_y as u64);

        let alice_lp_after_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(alice));
        let bob_lp_after_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(bob));
        let alice_token_x_after_balance = coin::balance<TestWARP>(signer::address_of(alice));
        let alice_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(alice));
        let bob_token_x_after_balance = coin::balance<TestWARP>(signer::address_of(bob));
        let bob_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(bob));
        let (balance_y, balance_x) = swap::token_balances<TestBUSD, TestWARP>();
        let (reserve_y, reserve_x, _) = swap::token_reserves<TestBUSD, TestWARP>();
        let total_supply = std::option::get_with_default(
            &coin::supply<LPToken<TestBUSD, TestWARP>>(),
            0u128
        );

        assert!((alice_token_x_after_balance - alice_token_x_before_balance) == (alice_remove_liquidity_x as u64), 97);
        assert!((alice_token_y_after_balance - alice_token_y_before_balance) == (alice_remove_liquidity_y as u64), 96);
        assert!((bob_token_x_after_balance - bob_token_x_before_balance) == (bob_remove_liquidity_x as u64), 95);
        assert!((bob_token_y_after_balance - bob_token_y_before_balance) == (bob_remove_liquidity_y as u64), 94);
        assert!(alice_lp_after_balance == 0, 93);
        assert!(bob_lp_after_balance == 0, 92);
        assert!(balance_x == suppose_reserve_x, 91);
        assert!(balance_y == suppose_reserve_y, 90);
        assert!(reserve_x == suppose_reserve_x, 89);
        assert!(reserve_y == suppose_reserve_y, 88);
        assert!(total_supply == MINIMUM_LIQUIDITY, 87);
    }

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, user1 = @0x12341, user2 = @0x12342, user3 = @0x12343, user4 = @0x12344)]
    fun test_remove_liquidity_with_more_user(
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        user1: &signer,
        user2: &signer,
        user3: &signer,
        user4: &signer,
    ) {
        account::create_account_for_test(signer::address_of(user1));
        account::create_account_for_test(signer::address_of(user2));
        account::create_account_for_test(signer::address_of(user3));
        account::create_account_for_test(signer::address_of(user4));
        setup_test_with_genesis(dev, admin, treasury, resource_account);

        let coin_owner = test_coins::init_coins();

        test_coins::register_and_mint<TestWARP>(&coin_owner, user1, 100 * pow(10, 8));
        test_coins::register_and_mint<TestWARP>(&coin_owner, user2, 100 * pow(10, 8));
        test_coins::register_and_mint<TestWARP>(&coin_owner, user3, 100 * pow(10, 8));
        test_coins::register_and_mint<TestWARP>(&coin_owner, user4, 100 * pow(10, 8));

        test_coins::register_and_mint<TestBUSD>(&coin_owner, user1, 100 * pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, user2, 100 * pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, user3, 100 * pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, user4, 100 * pow(10, 8));

        let user1_add_liquidity_x = 5 * pow(10, 8);
        let user1_add_liquidity_y = 10 * pow(10, 8);

        let user2_add_liquidity_x = 2 * pow(10, 8);
        let user2_add_liquidity_y = 4 * pow(10, 8);

        let user3_add_liquidity_x = 25 * pow(10, 8);
        let user3_add_liquidity_y = 50 * pow(10, 8);

        let user4_add_liquidity_x = 45 * pow(10, 8);
        let user4_add_liquidity_y = 90 * pow(10, 8);

        let mm_fee_add = swap::mm_fee_to();
        let mm_fee_signer = account::create_account_for_test(mm_fee_add);
        coin::register<TestWARP>(&mm_fee_signer);
        coin::register<TestBUSD>(&mm_fee_signer);


        // bob provider liquidity for 5:10 CAKE-BUSD
        router::add_liquidity<TestWARP, TestBUSD>(user1, user1_add_liquidity_x, user1_add_liquidity_y, 0, 0, 25);
        router::add_liquidity<TestWARP, TestBUSD>(user2, user2_add_liquidity_x, user2_add_liquidity_y, 0, 0, 25);
        router::add_liquidity<TestWARP, TestBUSD>(user3, user3_add_liquidity_x, user3_add_liquidity_y, 0, 0, 25);
        router::add_liquidity<TestWARP, TestBUSD>(user4, user4_add_liquidity_x, user4_add_liquidity_y, 0, 0, 25);

        let user1_suppose_lp_balance = math::sqrt(((user1_add_liquidity_x as u128) * (user1_add_liquidity_y as u128))) - MINIMUM_LIQUIDITY;
        let suppose_total_supply = user1_suppose_lp_balance + MINIMUM_LIQUIDITY;
        let suppose_reserve_x = user1_add_liquidity_x;
        let suppose_reserve_y = user1_add_liquidity_y;
        let user2_suppose_lp_balance = math::min((user2_add_liquidity_x as u128) * suppose_total_supply / (suppose_reserve_x as u128), (user2_add_liquidity_y as u128) * suppose_total_supply / (suppose_reserve_y as u128));
        suppose_total_supply = suppose_total_supply + user2_suppose_lp_balance;
        suppose_reserve_x = suppose_reserve_x + user2_add_liquidity_x;
        suppose_reserve_y = suppose_reserve_y + user2_add_liquidity_y;
        let user3_suppose_lp_balance = math::min((user3_add_liquidity_x as u128) * suppose_total_supply / (suppose_reserve_x as u128), (user3_add_liquidity_y as u128) * suppose_total_supply / (suppose_reserve_y as u128));
        suppose_total_supply = suppose_total_supply + user3_suppose_lp_balance;
        suppose_reserve_x = suppose_reserve_x + user3_add_liquidity_x;
        suppose_reserve_y = suppose_reserve_y + user3_add_liquidity_y;
        let user4_suppose_lp_balance = math::min((user4_add_liquidity_x as u128) * suppose_total_supply / (suppose_reserve_x as u128), (user4_add_liquidity_y as u128) * suppose_total_supply / (suppose_reserve_y as u128));
        suppose_total_supply = suppose_total_supply + user4_suppose_lp_balance;
        suppose_reserve_x = suppose_reserve_x + user4_add_liquidity_x;
        suppose_reserve_y = suppose_reserve_y + user4_add_liquidity_y;

        let user1_lp_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(user1));
        let user2_lp_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(user2));
        let user3_lp_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(user3));
        let user4_lp_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(user4));

        assert!((user1_suppose_lp_balance as u64) == user1_lp_balance, 99);
        assert!((user2_suppose_lp_balance as u64) == user2_lp_balance, 98);
        assert!((user3_suppose_lp_balance as u64) == user3_lp_balance, 97);
        assert!((user4_suppose_lp_balance as u64) == user4_lp_balance, 96);

        let user1_token_x_before_balance = coin::balance<TestWARP>(signer::address_of(user1));
        let user1_token_y_before_balance = coin::balance<TestBUSD>(signer::address_of(user1));
        let user2_token_x_before_balance = coin::balance<TestWARP>(signer::address_of(user2));
        let user2_token_y_before_balance = coin::balance<TestBUSD>(signer::address_of(user2));
        let user3_token_x_before_balance = coin::balance<TestWARP>(signer::address_of(user3));
        let user3_token_y_before_balance = coin::balance<TestBUSD>(signer::address_of(user3));
        let user4_token_x_before_balance = coin::balance<TestWARP>(signer::address_of(user4));
        let user4_token_y_before_balance = coin::balance<TestBUSD>(signer::address_of(user4));

        router::remove_liquidity<TestWARP, TestBUSD>(user1, (user1_suppose_lp_balance as u64), 0, 0);
        let user1_remove_liquidity_x = ((suppose_reserve_x) as u128) * user1_suppose_lp_balance / suppose_total_supply;
        let user1_remove_liquidity_y = ((suppose_reserve_y) as u128) * user1_suppose_lp_balance / suppose_total_supply;
        suppose_total_supply = suppose_total_supply - user1_suppose_lp_balance;
        suppose_reserve_x = suppose_reserve_x - (user1_remove_liquidity_x as u64);
        suppose_reserve_y = suppose_reserve_y - (user1_remove_liquidity_y as u64);

        router::remove_liquidity<TestWARP, TestBUSD>(user2, (user2_suppose_lp_balance as u64), 0, 0);
        let user2_remove_liquidity_x = ((suppose_reserve_x) as u128) * user2_suppose_lp_balance / suppose_total_supply;
        let user2_remove_liquidity_y = ((suppose_reserve_y) as u128) * user2_suppose_lp_balance / suppose_total_supply;
        suppose_total_supply = suppose_total_supply - user2_suppose_lp_balance;
        suppose_reserve_x = suppose_reserve_x - (user2_remove_liquidity_x as u64);
        suppose_reserve_y = suppose_reserve_y - (user2_remove_liquidity_y as u64);

        router::remove_liquidity<TestWARP, TestBUSD>(user3, (user3_suppose_lp_balance as u64), 0, 0);
        let user3_remove_liquidity_x = ((suppose_reserve_x) as u128) * user3_suppose_lp_balance / suppose_total_supply;
        let user3_remove_liquidity_y = ((suppose_reserve_y) as u128) * user3_suppose_lp_balance / suppose_total_supply;
        suppose_total_supply = suppose_total_supply - user3_suppose_lp_balance;
        suppose_reserve_x = suppose_reserve_x - (user3_remove_liquidity_x as u64);
        suppose_reserve_y = suppose_reserve_y - (user3_remove_liquidity_y as u64);

        router::remove_liquidity<TestWARP, TestBUSD>(user4, (user4_suppose_lp_balance as u64), 0, 0);
        let user4_remove_liquidity_x = ((suppose_reserve_x) as u128) * user4_suppose_lp_balance / suppose_total_supply;
        let user4_remove_liquidity_y = ((suppose_reserve_y) as u128) * user4_suppose_lp_balance / suppose_total_supply;
        suppose_reserve_x = suppose_reserve_x - (user4_remove_liquidity_x as u64);
        suppose_reserve_y = suppose_reserve_y - (user4_remove_liquidity_y as u64);

        let user1_lp_after_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(user1));
        let user2_lp_after_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(user2));
        let user3_lp_after_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(user3));
        let user4_lp_after_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(user4));

        let user1_token_x_after_balance = coin::balance<TestWARP>(signer::address_of(user1));
        let user1_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(user1));
        let user2_token_x_after_balance = coin::balance<TestWARP>(signer::address_of(user2));
        let user2_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(user2));
        let user3_token_x_after_balance = coin::balance<TestWARP>(signer::address_of(user3));
        let user3_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(user3));
        let user4_token_x_after_balance = coin::balance<TestWARP>(signer::address_of(user4));
        let user4_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(user4));

        let (balance_y, balance_x) = swap::token_balances<TestBUSD, TestWARP>();
        let (reserve_y, reserve_x, _) = swap::token_reserves<TestBUSD, TestWARP>();
        let total_supply = swap::total_lp_supply<TestBUSD, TestWARP>();

        assert!((user1_token_x_after_balance - user1_token_x_before_balance) == (user1_remove_liquidity_x as u64), 95);
        assert!((user1_token_y_after_balance - user1_token_y_before_balance) == (user1_remove_liquidity_y as u64), 94);
        assert!((user2_token_x_after_balance - user2_token_x_before_balance) == (user2_remove_liquidity_x as u64), 93);
        assert!((user2_token_y_after_balance - user2_token_y_before_balance) == (user2_remove_liquidity_y as u64), 92);
        assert!((user3_token_x_after_balance - user3_token_x_before_balance) == (user3_remove_liquidity_x as u64), 91);
        assert!((user3_token_y_after_balance - user3_token_y_before_balance) == (user3_remove_liquidity_y as u64), 90);
        assert!((user4_token_x_after_balance - user4_token_x_before_balance) == (user4_remove_liquidity_x as u64), 89);
        assert!((user4_token_y_after_balance - user4_token_y_before_balance) == (user4_remove_liquidity_y as u64), 88);
        assert!(user1_lp_after_balance == 0, 87);
        assert!(user2_lp_after_balance == 0, 86);
        assert!(user3_lp_after_balance == 0, 85);
        assert!(user4_lp_after_balance == 0, 84);
        assert!(balance_x == suppose_reserve_x, 83);
        assert!(balance_y == suppose_reserve_y, 82);
        assert!(reserve_x == suppose_reserve_x, 81);
        assert!(reserve_y == suppose_reserve_y, 80);
        assert!(total_supply == MINIMUM_LIQUIDITY, 79);
    }

    #[test(dev = @dev, admin = @default_admin, resource_account = @warpgate, treasury = @0x23456, bob = @0x12341, alice = @0x12342)]
    #[expected_failure(abort_code = 10, location = warpgate::swap)]
    fun test_remove_liquidity_imbalance(
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
        test_coins::register_and_mint<TestWARP>(&coin_owner, alice, 100 * pow(10, 8));

        test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 100 * pow(10, 8));
        test_coins::register_and_mint<TestBUSD>(&coin_owner, alice, 100 * pow(10, 8));

        let bob_liquidity_x = 5 * pow(10, 8);
        let bob_liquidity_y = 10 * pow(10, 8);

        let alice_liquidity_x = 1;
        let alice_liquidity_y = 2;

        let mm_fee_add = swap::mm_fee_to();
        let mm_fee_signer = account::create_account_for_test(mm_fee_add);
        coin::register<TestWARP>(&mm_fee_signer);
        coin::register<TestBUSD>(&mm_fee_signer);
        // bob provider liquidity for 5:10 CAKE-BUSD
        router::add_liquidity<TestWARP, TestBUSD>(bob, bob_liquidity_x, bob_liquidity_y, 0, 0, 25);
        router::add_liquidity<TestWARP, TestBUSD>(alice, alice_liquidity_x, alice_liquidity_y, 0, 0, 25);

        let bob_lp_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(bob));
        let alice_lp_balance = coin::balance<LPToken<TestBUSD, TestWARP>>(signer::address_of(alice));

        router::remove_liquidity<TestWARP, TestBUSD>(bob, bob_lp_balance, 0, 0);
        // expect the small amount will result one of the amount to be zero and unable to remove liquidity
        router::remove_liquidity<TestWARP, TestBUSD>(alice, alice_lp_balance, 0, 0);
    }

}