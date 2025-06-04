// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {ERC20} from "solady/tokens/ERC20.sol";

/// @title BasicAsset
/// @notice A standard immutable ERC20 token created by Eulaunch.
contract BasicAsset is ERC20 {
    string public _name;
    string public _symbol;

    constructor(string memory name_, string memory symbol_, address to_, uint256 totalSupply_) {
        _name = name_;
        _symbol = symbol_;
        _mint(to_, totalSupply_);
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }
}
