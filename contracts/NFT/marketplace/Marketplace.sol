// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


import "https://github.com/roadtobitcoin/solidity_smart_contracts/blob/main/contracts/NFT/marketplace/IERC721Verifiable.sol";
import "https://github.com/roadtobitcoin/solidity_smart_contracts/blob/main/contracts/NFT/marketplace/IMarketplace.sol";
import "https://github.com/roadtobitcoin/solidity_smart_contracts/blob/main/contracts/NFT/marketplace/FeeManager.sol";


contract Marketplace is Ownable, Pausable, FeeManager, IMarketplace, ERC721Holder {

    using Address for address;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public acceptedToken;

    // From ERC721 registry assetId to Order (to avoid asset collision)
    mapping(address => mapping(uint256 => Order)) public orderByAssetId;

    // From ERC721 registry assetId to Bid (to avoid asset collision)
    mapping(address => mapping(uint256 => Bid)) public bidByOrderId;

    // 721 Interfaces
    bytes4 public constant _INTERFACE_ID_ERC721 = 0x80ac58cd;

    /**
     * @dev Initialize this contract. Acts as a constructor
     * @param _acceptedToken - currency for payments
     */
    constructor(address _acceptedToken) public Ownable() {
        require(
            _acceptedToken.isContract(),
            "The accepted token address must be a deployed contract"
        );
        acceptedToken = IERC20(_acceptedToken);
    }

    /**
     * @dev Sets the paused failsafe. Can only be called by owner
     * @param _setPaused - paused state
     */
    function setPaused(bool _setPaused) public onlyOwner {
        return (_setPaused) ? _pause() : _unpause();
    }

    /**
     * @dev Creates a new order
     * @param _nftAddress - Non fungible registry address
     * @param _assetId - ID of the published NFT
     * @param _priceInWei - Price in Wei for the supported coin
     * @param _expiresAt - Duration of the order (in hours)
     */
    function createOrder(
        address _nftAddress,
        uint256 _assetId,
        uint256 _priceInWei,
        uint256 _expiresAt
    )
        public whenNotPaused
    {
        _createOrder(_nftAddress, _assetId, _priceInWei, _expiresAt);
    }


    /**
     * @dev Cancel an already published order
     *  can only be canceled by seller or the contract owner
     * @param _nftAddress - Address of the NFT registry
     * @param _assetId - ID of the published NFT
     */
    function cancelOrder(
        address _nftAddress,
        uint256 _assetId
    )
        public whenNotPaused
    {
        Order memory order = orderByAssetId[_nftAddress][_assetId];

        require(
            order.seller == msg.sender || msg.sender == owner(),
            "Marketplace: unauthorized sender"
        );

        // Remove pending bid if any
        Bid memory bid = bidByOrderId[_nftAddress][_assetId];

        if (bid.id != 0) {
            _cancelBid(
                bid.id,
                _nftAddress,
                _assetId,
                bid.bidder,
                bid.price
            );
        }

        // Cancel order.
        _cancelOrder(
            order.id,
            _nftAddress,
            _assetId,
            msg.sender
        );
    }


    /**
     * @dev Update an already published order
     *  can only be updated by seller
     * @param _nftAddress - Address of the NFT registry
     * @param _assetId - ID of the published NFT
     */
    function updateOrder(
        address _nftAddress,
        uint256 _assetId,
        uint256 _priceInWei,
        uint256 _expiresAt
    )
        public whenNotPaused
    {
        Order memory order = orderByAssetId[_nftAddress][_assetId];

        // Check valid order to update
        require(order.id != 0, "Marketplace: asset not published");
        require(order.seller == msg.sender, "Marketplace: sender not allowed");
        require(order.expiresAt >= block.timestamp, "Marketplace: order expired");

        // check order updated params
        require(_priceInWei > 0, "Marketplace: Price should be bigger than 0");
        require(
            _expiresAt > block.timestamp.add(1 minutes),
            "Marketplace: Expire time should be more than 1 minute in the future"
        );

        order.price = _priceInWei;
        order.expiresAt = _expiresAt;

        emit OrderUpdated(order.id, _priceInWei, _expiresAt);
    }


    /**
     * @dev Executes the sale for a published NFT and checks for the asset fingerprint
     * @param _nftAddress - Address of the NFT registry
     * @param _assetId - ID of the published NFT
     * @param _priceInWei - Order price
     * @param _fingerprint - Verification info for the asset
     */
    function safeExecuteOrder(
        address _nftAddress,
        uint256 _assetId,
        uint256 _priceInWei,
        bytes32 _fingerprint
    )
        public whenNotPaused
    {
        // Get the current valid order for the asset or fail
        Order memory order = _getValidOrder(
            _nftAddress,
            _assetId
        );

        /// Check the execution price matches the order price
        require(order.price == _priceInWei, "Marketplace: invalid price");
        require(order.seller != msg.sender, "Marketplace: unauthorized sender");

        // Check the asset fingerprint
        _verifyAssetFingerprint(
            IERC721Verifiable(_nftAddress),
            _assetId,
            _fingerprint
        );

        // market fee to cut
        uint256 saleShareAmount = 0;

        // Send market fees to owner
        if (FeeManager.cutPerMillion > 0) {
            // Calculate sale share
            saleShareAmount = _priceInWei
                .mul(FeeManager.cutPerMillion)
                .div(1e6);

            // Transfer share amount for marketplace Owner
            acceptedToken.safeTransferFrom(
                msg.sender, //buyer
                owner(),
                saleShareAmount
            );
        }

        // Transfer accepted token amount minus market fee to seller
        acceptedToken.safeTransferFrom(
            msg.sender, // buyer
            order.seller, // seller
            order.price.sub(saleShareAmount)
        );

        // Remove pending bid if any
        Bid memory bid = bidByOrderId[_nftAddress][_assetId];

        if (bid.id != 0) {
            _cancelBid(
                bid.id,
                _nftAddress,
                _assetId,
                bid.bidder,
                bid.price
            );
        }

        _executeOrder(
            order.id,
            msg.sender, // buyer
            _nftAddress,
            _assetId,
            _priceInWei
        );
    }


    /**
     * @dev Places a bid for a published NFT and checks for the asset fingerprint
     * @param _nftAddress - Address of the NFT registry
     * @param _assetId - ID of the published NFT
     * @param _priceInWei - Bid price in acceptedToken currency
     * @param _expiresAt - Bid expiration time
     * @param _fingerprint - Verification info for the asset
     */
    function safePlaceBid(
        address _nftAddress,
        uint256 _assetId,
        uint256 _priceInWei,
        uint256 _expiresAt,
        bytes32 _fingerprint
    )
        public whenNotPaused
    {
        _verifyAssetFingerprint(
            IERC721Verifiable(_nftAddress),
            _assetId,
            _fingerprint
        );

        _createBid(
            _nftAddress,
            _assetId,
            _priceInWei,
            _expiresAt
        );
    }


    /**
     * @dev Cancel an already published bid
     *  can only be canceled by seller or the contract owner
     * @param _nftAddress - Address of the NFT registry
     * @param _assetId - ID of the published NFT
     */
    function cancelBid(
        address _nftAddress,
        uint256 _assetId
    )
        public whenNotPaused
    {
        Bid memory bid = bidByOrderId[_nftAddress][_assetId];

        require(
            bid.bidder == msg.sender || msg.sender == owner(),
            "Marketplace: Unauthorized sender"
        );

        _cancelBid(
            bid.id,
            _nftAddress,
            _assetId,
            bid.bidder,
            bid.price
        );
    }


    /**
     * @dev Executes the sale for a published NFT by accepting a current bid
     * @param _nftAddress - Address of the NFT registry
     * @param _assetId - ID of the published NFT
     * @param _priceInWei - Bid price in wei in acceptedTokens currency
     */
    function acceptBid(
        address _nftAddress,
        uint256 _assetId,
        uint256 _priceInWei
    )
        public whenNotPaused
    {
        // check order validity
        Order memory order = _getValidOrder(_nftAddress, _assetId);

        // item seller is the only allowed to accept a bid
        require(order.seller == msg.sender, "Marketplace: unauthorized sender");

        Bid memory bid = bidByOrderId[_nftAddress][_assetId];

        require(bid.price == _priceInWei, "Marketplace: invalid bid price");
        require(bid.expiresAt >= block.timestamp, "Marketplace: the bid expired");

        // remove bid
        delete bidByOrderId[_nftAddress][_assetId];

        emit BidAccepted(bid.id);

        // calc market fees
        uint256 saleShareAmount = bid.price
            .mul(FeeManager.cutPerMillion)
            .div(1e6);

        // transfer escrowed bid amount minus market fee to seller
        acceptedToken.safeTransfer(
            bid.bidder,
            bid.price.sub(saleShareAmount)
        );

        _executeOrder(
            order.id,
            bid.bidder,
            _nftAddress,
            _assetId,
            _priceInWei
        );
    }


    /**
     * @dev Internal function gets Order by nftRegistry and assetId. Checks for the order validity
     * @param _nftAddress - Address of the NFT registry
     * @param _assetId - ID of the published NFT
     */
    function _getValidOrder(
        address _nftAddress,
        uint256 _assetId
    )
        internal view returns (Order memory order)
    {
        order = orderByAssetId[_nftAddress][_assetId];

        require(order.id != 0, "Marketplace: asset not published");
        require(order.expiresAt >= block.timestamp, "Marketplace: order expired");
    }


    /**
     * @dev Executes the sale for a published NFT
     * @param _orderId - Order Id to execute
     * @param _buyer - address
     * @param _nftAddress - Address of the NFT registry
     * @param _assetId - NFT id
     * @param _priceInWei - Order price
     */
    function _executeOrder(
        bytes32 _orderId,
        address _buyer,
        address _nftAddress,
        uint256 _assetId,
        uint256 _priceInWei
    )
        internal
    {
        // remove order
        delete orderByAssetId[_nftAddress][_assetId];

        // Transfer NFT asset
        IERC721(_nftAddress).safeTransferFrom(
            address(this),
            _buyer,
            _assetId
        );

        // Notify ..
        emit OrderSuccessful(
            _orderId,
            _buyer,
            _priceInWei
        );
    }


    /**
     * @dev Creates a new order
     * @param _nftAddress - Non fungible registry address
     * @param _assetId - ID of the published NFT
     * @param _priceInWei - Price in Wei for the supported coin
     * @param _expiresAt - Expiration time for the order
     */
    function _createOrder(
        address _nftAddress,
        uint256 _assetId,
        uint256 _priceInWei,
        uint256 _expiresAt
    )
        internal
    {
        // Check nft registry
        IERC721 nftRegistry = _requireERC721(_nftAddress);

        // Check order creator is the asset owner
        address assetOwner = nftRegistry.ownerOf(_assetId);

        require(
            assetOwner == msg.sender,
            "Marketplace: Only the asset owner can create orders"
        );

        require(_priceInWei > 0, "Marketplace: Price should be bigger than 0");

        require(
            _expiresAt > block.timestamp.add(1 minutes),
            "Marketplace: Publication should be more than 1 minute in the future"
        );

        // get NFT asset from seller
        nftRegistry.safeTransferFrom(
            assetOwner,
            address(this),
            _assetId
        );

        // create the orderId
        bytes32 orderId = keccak256(
            abi.encodePacked(
                block.timestamp,
                assetOwner,
                _nftAddress,
                _assetId,
                _priceInWei
            )
        );

        // save order
        orderByAssetId[_nftAddress][_assetId] = Order({
            id: orderId,
            seller: assetOwner,
            nftAddress: _nftAddress,
            price: _priceInWei,
            expiresAt: _expiresAt
        });

        emit OrderCreated(
            orderId,
            assetOwner,
            _nftAddress,
            _assetId,
            _priceInWei,
            _expiresAt
        );
    }


    /**
     * @dev Creates a new bid on a existing order
     * @param _nftAddress - Non fungible registry address
     * @param _assetId - ID of the published NFT
     * @param _priceInWei - Price in Wei for the supported coin
     * @param _expiresAt - expires time
     */
    function _createBid(
        address _nftAddress,
        uint256 _assetId,
        uint256 _priceInWei,
        uint256 _expiresAt
    )
        internal
    {
        // Checks order validity
        Order memory order = _getValidOrder(_nftAddress, _assetId);

        // check on expire time
        if (_expiresAt > order.expiresAt) {
            _expiresAt = order.expiresAt;
        }

        // Check price if theres previous a bid
        Bid memory bid = bidByOrderId[_nftAddress][_assetId];

        // if theres no previous bid, just check price > 0
        if (bid.id != 0) {
            if (bid.expiresAt >= block.timestamp) {
                require(
                    _priceInWei > bid.price,
                    "Marketplace: bid price should be higher than last bid"
                );

            } else {
                require(_priceInWei > 0, "Marketplace: bid should be > 0");
            }

            _cancelBid(
                bid.id,
                _nftAddress,
                _assetId,
                bid.bidder,
                bid.price
            );

        } else {
            require(_priceInWei > 0, "Marketplace: bid should be > 0");
        }

        // Transfer sale amount from bidder to escrow
        acceptedToken.safeTransferFrom(
            msg.sender, // bidder
            address(this),
            _priceInWei
        );

        // Create bid
        bytes32 bidId = keccak256(
            abi.encodePacked(
                block.timestamp,
                msg.sender,
                order.id,
                _priceInWei,
                _expiresAt
            )
        );

        // Save Bid for this order
        bidByOrderId[_nftAddress][_assetId] = Bid({
            id: bidId,
            bidder: msg.sender,
            price: _priceInWei,
            expiresAt: _expiresAt
        });

        emit BidCreated(
            bidId,
            _nftAddress,
            _assetId,
            msg.sender, // bidder
            _priceInWei,
            _expiresAt
        );
    }


    /**
     * @dev Cancel an already published order
     *  can only be canceled by seller or the contract owner
     * @param _orderId - Bid identifier
     * @param _nftAddress - Address of the NFT registry
     * @param _assetId - ID of the published NFT
     * @param _seller - Address
     */
    function _cancelOrder(
        bytes32 _orderId,
        address _nftAddress,
        uint256 _assetId,
        address _seller
    )
        internal
    {
        delete orderByAssetId[_nftAddress][_assetId];

        /// send asset back to seller
        IERC721(_nftAddress).safeTransferFrom(
            address(this),
            _seller,
            _assetId
        );

        emit OrderCancelled(_orderId);
    }


    /**
     * @dev Cancel bid from an already published order
     *  can only be canceled by seller or the contract owner
     * @param _bidId - Bid identifier
     * @param _nftAddress - registry address
     * @param _assetId - ID of the published NFT
     * @param _bidder - Address
     * @param _escrowAmount - in acceptenToken currency
     */
    function _cancelBid(
        bytes32 _bidId,
        address _nftAddress,
        uint256 _assetId,
        address _bidder,
        uint256 _escrowAmount
    )
        internal
    {
        delete bidByOrderId[_nftAddress][_assetId];

        // return escrow to canceled bidder
        acceptedToken.safeTransfer(
            _bidder,
            _escrowAmount
        );

        emit BidCancelled(_bidId);
    }


    function _requireERC721(address _nftAddress) internal view returns (IERC721) {
        require(
            _nftAddress.isContract(),
            "The NFT Address should be a contract"
        );
        require(
            IERC721(_nftAddress).supportsInterface(_INTERFACE_ID_ERC721),
            "The NFT contract has an invalid ERC721 implementation"
        );
        return IERC721(_nftAddress);
    }


    function _verifyAssetFingerprint(
        IERC721Verifiable _nftRegistry,
        uint256 _assetId,
        bytes32 _fingerprint
    )
        internal view
    {
        require(
            _nftRegistry.verifyFingerprint(_assetId, _fingerprint),
            "Marketplace: asset fingerprint is not valid"
        );
    }
}
