pragma solidity ^0.8.0;
//SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@1001-digital/erc721-extensions/contracts/RandomlyAssigned.sol";


contract Cryptopanda is ERC721, Ownable, RandomlyAssigned {
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
    RandomlyAssigned(10,1) // Max. 10000 NFTs available; Start counting from 1 (instead of 0) 
    //keep max amount & reserved amount for team
    {
       for (uint256 a = 1; a <= 1; a++) {
            mint(msg.sender);
        }
         setBaseURI(_initBaseURI);//Set base URI of your image
    setNotRevealedURI(_initNotRevealedUri);//Set generic images for contract 
    }

  function mint (address _to) public payable
      {
      require( tokenCount() + 1 <= totalSupply(), "YOU CAN'T MINT MORE THAN MAXIMUM SUPPLY");
      require( availableTokenCount() - 1 >= 0, "YOU CAN'T MINT MORE THAN AVALABLE TOKEN COUNT"); 
      require( tx.origin == msg.sender, "CANNOT MINT THROUGH A CUSTOM CONTRACT");

      if (msg.sender != owner()) {  
        require( msg.value >= 1 ether);
        require( balanceOf(msg.sender) <= 1);
        require( balanceOf(_to) <= 1);
      }
      
      uint256 id = nextToken();
        _safeMint(_to, id);
        currentSupply++;
  }

  function _baseURI() internal view virtual override returns (string memory) {
    return baseURI;
  }
  
  function tokenURI(uint256 tokenId) public view virtual override returns (string memory)  {
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
      revealed = true;// This functional will change image URL from revel to actal once called
  }
  
  function setNotRevealedURI(string memory _notRevealedURI) public onlyOwner {
    notRevealedUri = _notRevealedURI;
  } //this function to change the URI in NON reveled mode

  function setBaseURI(string memory _newBaseURI) public onlyOwner {
    baseURI = _newBaseURI; //This function to change URI
  }

  function setBaseExtension(string memory _newBaseExtension) public onlyOwner {
    baseExtension = _newBaseExtension; // this function to change the extension format
  }

   function withdraw() public payable onlyOwner {
    require(payable(msg.sender).send(address(this).balance));
  }// to withddraw any amount
}
