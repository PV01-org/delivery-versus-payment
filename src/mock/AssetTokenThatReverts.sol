// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts-v5-2-0/token/ERC20/ERC20.sol";

/// @title AssetTokenThatRevert
/// @dev Mock ERC20 token that does various flavours of revert on transferFrom based on the amount.
contract AssetTokenThatReverts is ERC20 {
  uint8 private _decimals;
  uint256 private dummy;
  // Error selector 0x0a59c53c

  error ThisIsACustomError();

  constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
    require(decimals_ <= 18, "Token cannot have more than 18 decimals");
    _decimals = decimals_;
  }

  /// @dev The `amount` parameter controls the behavior of the function as follows:
  /// - If `amount == 1`: The function will revert with a revert string: "AssetTokenThatReverts: transferFrom is disabled".
  /// - If `amount == 2`: The function will revert with a custom error: `ThisIsACustomError()`.
  /// - If `amount == 3`: The function will trigger a panic due to a divide-by-zero error, causing the transaction to fail unexpectedly.
  /// - If `amount >= 4`: The function will revert with no message, using inline assembly to revert the transaction.
  function transferFrom(address, address, uint256 amount) public override returns (bool) {
    dummy = 1;
    if (amount == 1) {
      // Revert with a revert string
      revert("AssetTokenThatReverts: transferFrom is disabled");
    } else if (amount == 2) {
      // Revert with a custom error
      revert ThisIsACustomError();
    } else if (amount == 3) {
      // Revert with panic divide by zero
      uint256 i = 10;
      dummy = i / (i - 10);
      return false;
    } else {
      // Revert with no message
      assembly {
        revert(0, 0)
      }
    }
  }

  function mint(address account, uint256 amount) external {
    _mint(account, amount);
  }

  function burn(address account, uint256 amount) external {
    _burn(account, amount);
  }

  function decimals() public view override returns (uint8) {
    return _decimals;
  }
}
