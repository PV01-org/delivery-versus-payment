// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ERC721} from "@openzeppelin/contracts-v5-2-0/token/ERC721/ERC721.sol";

contract NFT is ERC721 {
  constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) {}

  function mint(address to, uint256 tokenId) external {
    _mint(to, tokenId);
  }

  function burn(uint256 tokenId) external {
    _burn(tokenId);
  }
}
