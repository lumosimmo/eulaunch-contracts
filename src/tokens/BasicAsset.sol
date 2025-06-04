// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {ERC20} from "solady/tokens/ERC20.sol";
import {LibString} from "solady/utils/LibString.sol";

/// @title BasicAsset
/// @notice A standard immutable ERC20 token created by Eulaunch.
contract BasicAsset is ERC20 {
    using LibString for string;

    bytes32 private immutable _name;
    bytes32 private immutable _symbol;

    constructor(string memory name_, string memory symbol_, address to_, uint256 totalSupply_) {
        // No length check here. We expect the caller to provide valid values.
        _name = LibString.packOne(name_);
        _symbol = LibString.packOne(symbol_);
        _mint(to_, totalSupply_);
    }

    function name() public view virtual override returns (string memory) {
        return LibString.unpackOne(_name);
    }

    function symbol() public view virtual override returns (string memory) {
        return LibString.unpackOne(_symbol);
    }
}
