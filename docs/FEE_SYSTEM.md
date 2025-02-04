# Warpgate Fee System Documentation

## Overview
Warpgate implements a dual-fee system consisting of swap fees and market maker fees. This document outlines the fee collection, accumulation, and distribution mechanisms.

## Fee Structure

### Fee Types and Rates
1. **Swap Fee**: Configurable per token pair
   - Set in basis points (e.g., 25 = 0.25%)
   - Stored in `TokenPairMetadata.swap_fee`
   - Applied to all swap transactions
   - Collected through k-value changes
   - Converted to LP tokens during mint operations

2. **Market Maker Fee**: 1% (100 basis points)
   - Applied to swap input amounts
   - Accumulated in original tokens (X/Y)
   - Converted to LP tokens during fee minting

## Fee Collection Process

### During Swaps

1. **Market Maker Fee Collection**
```move
let mm_fee_x = ((amount_x_in as u128) * MARKET_MAKER_FEE / 10000u128) as u64;
metadata.market_maker_fee_x = metadata.market_maker_fee_x + mm_fee_x;
```
- Market maker fees are accumulated in their original token form
- Stored in `market_maker_fee_x` and `market_maker_fee_y` in pool metadata
- Accumulation continues until fees are converted to LP tokens

2. **Swap Fee Collection**
- Collected implicitly through k-value changes
- No direct accumulation, tracked via `k_last`
- Converted to LP tokens during `mint_fee` operations

### During Liquidity Operations

1. **Fee Calculation**
```move
// Calculate swap fees based on k-value change
let swap_fee_liquidity = (total_lp_supply * (root_k - root_k_last) * 8) / (root_k_last * 17 + root_k * 8);

// Calculate market maker fees in LP tokens
let mm_fee_liquidity = min(
    (mm_fee_x * total_supply) / reserve_x,
    (mm_fee_y * total_supply) / reserve_y
);
```

2. **Fee Conversion**
- Both fee types are converted to LP tokens
- Market maker fees are reset only after successful conversion
- Combined fees are stored in `metadata.fee_amount`

## Fee Distribution

### Fee Storage
- All fees are stored as LP tokens in `metadata.fee_amount`
- LP token storage ensures fees maintain value relative to pool
- Fees accumulate until withdrawn by admin

### Fee Withdrawal
```move
// Only admin can withdraw fees
if (metadata.fee_amount.value > 0) {
    coin::deposit(swap_info.fee_to, coin::extract_all(&mut metadata.fee_amount));
}
```
- Admin-only operation
- Withdraws all accumulated fees as LP tokens
- Admin can burn LP tokens for underlying assets

## Protection Mechanisms

### 1. Market Maker Fee Protection
- Excluded from burn calculations
- Only reset after successful LP token conversion
- Accumulated separately from swap fees

### 2. K-Value Protection
- Ensures pool balance is maintained
- Prevents manipulation through large swaps
- Validates fee calculations

### 3. Access Control
- Only admin can withdraw fees
- Protected fee-to address setting
- Secure fee accumulation

## Important Considerations

### 1. Fee Accumulation
- Market maker fees accumulate in original tokens
- Conversion to LP tokens happens during mint operations
- Both fee types combine in final LP token form

### 2. Liquidity Provider Impact
- Fees increase the value of LP tokens
- Fair distribution through LP token mechanism
- Protected from fee-related value loss

### 3. Admin Operations
- Can withdraw accumulated fees
- Must handle LP tokens appropriately
- Responsible for fee distribution

## Technical Details

### Constants
```move
const PRECISION: u64 = 10000;
const MARKET_MAKER_FEE: u128 = 100; // 1% market maker fee
```

### Key Functions

1. **mint_fee**
- Converts accumulated fees to LP tokens
- Handles both swap and market maker fees
- Updates fee storage and resets counters

2. **withdraw_fee**
- Admin function for fee withdrawal
- Transfers accumulated LP tokens
- Resets fee storage

## Example Scenarios

### 1. Basic Swap
1. User swaps token X for Y
2. Market maker fee calculated and accumulated
3. Swap fee tracked via k-value
4. Fees await conversion to LP tokens

### 2. Fee Conversion
1. K-value change triggers fee calculation
2. Market maker fees converted to LP tokens
3. Combined fees stored in metadata
4. Market maker fee counters reset

### 3. Fee Withdrawal
1. Admin initiates withdrawal
2. All LP token fees transferred
3. Fee storage reset to zero
4. Admin can manage received LP tokens

## Best Practices

1. **Regular Fee Withdrawal**
   - Prevent excessive fee accumulation
   - Maintain efficient pool operation
   - Regular distribution to stakeholders

2. **Monitoring**
   - Track fee accumulation rates
   - Monitor conversion efficiency
   - Verify fee distribution

3. **Security**
   - Validate admin operations
   - Ensure secure fee handling
   - Maintain access controls
