/*

  Copyright 2019 ZeroEx Intl.

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

*/

pragma solidity ^0.5.9;
pragma experimental ABIEncoderV2;

import "@0x/contracts-utils/contracts/src/LibEIP1271.sol";
import "@0x/contracts-utils/contracts/src/Ownable.sol";
import "@0x/contracts-utils/contracts/src/LibBytes.sol";
import "@0x/contracts-exchange-libs/contracts/src/LibOrder.sol";
import "./IENS.sol";
import "./IResolver.sol";
import "../interfaces/IEIP1271Data.sol";


contract ENSValidator is
    LibEIP1271,
    Ownable
{
    using LibBytes for bytes;
    using LibOrder for LibOrder.Order;

    bytes32 constant internal EIP712_EXCHANGE_DOMAIN_HASH = 0xaa81d881b1adbbf115e15b849cb9cdc643cad3c6a90f30eb505954af943247e6;
    address constant internal EXCHANGE_ADDRESS = 0x61935CbDd02287B511119DDb11Aeb42F1593b7Ef;
    address constant internal ENS_ADDRESS = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e;

    mapping (bytes32 => address) public resolvedAddressByNode;

    constructor()
        public
        Ownable()
    {}

    /// @dev Verifies that a signature is valid.
    /// @param data Arbitrary signed data.
    /// @param signature Proof that data has been signed.
    /// @return magicValue bytes4(0x20c13b0b) if the signature check succeeds.
    function isValidSignature(
        bytes calldata data,
        bytes calldata signature
    )
        external
        view
        returns (bytes4)
    {
        // Ensure caller is the ExchangeV3 contract. This allows us to trust the passed in data.
        require(
            msg.sender == EXCHANGE_ADDRESS,
            "ENSValidator/INVALID_CALLER"
        );

        // Ensure that the data passed in by the Exchange contract encodes an order
        bytes4 dataId = data.readBytes4(0);
        require(
            dataId == IEIP1271Data(address(0)).OrderWithHash.selector,
            "ENSValidator/INVALID_DATA_ENCODING"
        );

        // Decode the order
        (LibOrder.Order memory order) = abi.decode(
            data.sliceDestructive(4, data.length),
            (LibOrder.Order)
        );

        // Signature is encoded as:
        // | Offset | Length | Contents            |
        // | ------ | ------ | ------------------- |
        // | 0      | 32     | ensNode             |
        // | 32     | 1      | v (always 27 or 28) |
        // | 33     | 32     | r                   |
        // | 65     | 32     | s                   |

        // Find the address that the ENS node resolves to
        bytes32 nodeHash = signature.readBytes32(0);
        address tokenAddress = resolvedAddressByNode[nodeHash];

        // We assume that `takerAssetData` uses ERC20Proxy encoding
        address takerTokenAddress = order.takerAssetData.readAddress(16);

        // Ensure that node resolved to same token address that is specified in `takerAssetData`
        require(
            tokenAddress == takerTokenAddress,
            "ENSValidator/TAKER_TOKEN_ADDRESS_MISMATCH"
        );

        // Replace the token address in the `takerAssetData` with the ENS node hash, since that is how the order was originally signed
        order.takerAssetData.writeBytes32(4, nodeHash);

        // Calculate the hash of the original order
        bytes32 orderHash = order.getTypedDataHash(EIP712_EXCHANGE_DOMAIN_HASH);
        address recoveredAddress = ecrecover(
            orderHash,
            uint8(signature[32]),
            signature.readBytes32(33),
            signature.readBytes32(65)
        );

        // Ensure that the recovered address is the same as the maker
        require(
            order.makerAddress == recoveredAddress,
            "ENSValidator/INVALID_SIGNATURE"
        );

        return EIP1271_MAGIC_VALUE;
    }

    /// @dev Allows the owner to update the address that an ENS node resolves to.
    ///      This can only be called by this contract's owner in order to prevent
    ///      the ENS name owner from changing the underlying asset in the order.
    /// @param nodeHash Node hash of ENS name. See: https://docs.ens.domains/contract-developer-guide/resolving-names-on-chain
    /// @param target Expected address that nodeHash will resolve to.
    function storeResolvedEnsNode(
        bytes32 nodeHash,
        address target
    )
        external
        onlyOwner
    {
        IResolver resolver = IENS(ENS_ADDRESS).resolver(nodeHash);
        address resolved = resolver.addr(nodeHash);
        require(
            resolved == target,
            "ENSValidator/RESOLVED_NODE_MISMATCH"
        );
        resolvedAddressByNode[nodeHash] = target;
    }
}
