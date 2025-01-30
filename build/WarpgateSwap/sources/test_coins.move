#[test_only]
module test_coin::test_coins {
    use aptos_framework::account;
    use aptos_framework::managed_coin;
    use std::signer;

    struct TestWARP {}
    struct TestMUSD {}
    struct TestUSDC {}
    struct TestMOVE {}
    struct TestAPT {}

    public entry fun init_coins(): signer {
        let account = account::create_account_for_test(@test_coin);

        // init coins
        managed_coin::initialize<TestWARP>(
            &account,
            b"Warp",
            b"WARP",
            9,
            false,
        );
        managed_coin::initialize<TestMUSD>(
            &account,
            b"Musd",
            b"MUSD",
            9,
            false,
        );

        managed_coin::initialize<TestUSDC>(
            &account,
            b"USDC",
            b"USDC",
            9,
            false,
        );

        managed_coin::initialize<TestMOVE>(
            &account,
            b"MOVE",
            b"MOVE",
            9,
            false,
        );

        managed_coin::initialize<TestAPT>(
            &account,
            b"Aptos",
            b"APT",
            9,
            false,
        );

        account
    }


    public entry fun register_and_mint<CoinType>(account: &signer, to: &signer, amount: u64) {
      managed_coin::register<CoinType>(to);
      managed_coin::mint<CoinType>(account, signer::address_of(to), amount)
    }

    public entry fun mint<CoinType>(account: &signer, to: &signer, amount: u64) {
        managed_coin::mint<CoinType>(account, signer::address_of(to), amount)
    }
}