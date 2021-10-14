pragma solidity ^0.8.0;
//SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
//import "@1001-digital/erc721-extensions/contracts/RandomlyAssigned.sol";
import "./RandomlyAssigned.sol";

contract Cryptopanda is ERC721Enumerable, Ownable, RandomlyAssigned {
  using Strings for uint256;
  // uint256 public requested;
  uint256 public currentSupply = 0;
      string baseURI;
  string public baseExtension = ".json";
            bool public revealed = false;
  string public notRevealedUri;
  

  constructor(    string memory _initBaseURI,
    string memory _initNotRevealedUri) 
    ERC721("Panda", "PAN")
    RandomlyAssigned(20,1) // Max. 10000 NFTs available; Start counting from 1 (instead of 0)
    {
       for (uint256 a = 1; a <= 1; a++) {
            buy();
        }
         setBaseURI(_initBaseURI);
    setNotRevealedURI(_initNotRevealedUri);
    }



    
  function buy ()
      public
      payable
  {
      require( tokenCount() + 1 <= totalSupply(), "YOU CAN'T MINT MORE THAN MAXIMUM SUPPLY");
      require( availableTokenCount() - 1 >= 0, "YOU CAN'T MINT MORE THAN AVALABLE TOKEN COUNT"); 
      require( tx.origin == msg.sender, "CANNOT MINT THROUGH A CUSTOM CONTRACT");

     if (msg.sender != owner()) {  
        require( msg.value >= 0.03 ether);
        require( balanceOf(msg.sender) <= 1);
    //    require( balanceOf(_to) <= 1);
      }
      
      uint256 id = nextToken();
        _safeMint(msg.sender, id);
        currentSupply++;
   }

  function _baseURI() internal view virtual override returns (string memory) {
    return baseURI;
  }
  
  function tokenURI(uint256 tokenId)
    public
    view
    virtual
    override
    returns (string memory)
  {
    require(
      _exists(tokenId),
      "ERC721Metadata: URI query for nonexistent token"
    );
    
    if(revealed == false) {
        return notRevealedUri;
    }

    string memory currentBaseURI = _baseURI();
    return bytes(currentBaseURI).length > 0
        ? string(abi.encodePacked(currentBaseURI, tokenId.toString(), baseExtension))
        : "";
  }

  //only owner
  function reveal() public onlyOwner() {
      revealed = true;
  }
  
  function setNotRevealedURI(string memory _notRevealedURI) public onlyOwner {
    notRevealedUri = _notRevealedURI;
  }

  function setBaseURI(string memory _newBaseURI) public onlyOwner {
    baseURI = _newBaseURI;
  }

  function setBaseExtension(string memory _newBaseExtension) public onlyOwner {
    baseExtension = _newBaseExtension;
  }

    function withdraw() public payable onlyOwner {
    require(payable(msg.sender).send(address(this).balance));
  }
  
  
}
