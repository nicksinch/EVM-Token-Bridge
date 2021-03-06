// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./WrappedToken.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ERC20Permit.sol";

contract RouterRinkeby is Ownable {

  event TokensClaimed(address claimer, uint256 amount, address wrappedTokenAddr);

  ERC20Permit tokenContract; 

  /* Native token ropsten => deployed wrapped token on rinkeby */
  mapping(address => address) private nativeToWrapped;

  /* Wrapped Token => User Address => amount of claimed tokens */
  mapping(address => mapping(address => uint256)) private tokenHasBeenClaimed;

  function setERCContractAddress(address _address) private {
    tokenContract = ERC20Permit(_address);
  }

  function lockTokens(uint256 amount, address contractAddress, uint256 deadline, uint8 v, bytes32 r, bytes32 s) public payable {
    // require(msg.sender != address(0), "Lock tokens from the zero address");
    require(msg.value == 0.001 ether, "Contract should be paid 0.001 ETH to use the service");
    require(amount > 0, "Locking non-positive amount of tokens");
    
    setERCContractAddress(contractAddress);
    tokenContract.permit(msg.sender, address(this), amount, deadline, v, r, s);
    tokenContract.transferFrom(msg.sender, address(this), amount);
  }

  function deployToken(address nativeTokenAddr) private {
    address newWrappedERCAddress = address(new WrappedToken());
    nativeToWrapped[nativeTokenAddr] = newWrappedERCAddress;
  }

  function tokenExists(address nativeTokenAddr) private view returns (bool exists) {
    return nativeToWrapped[nativeTokenAddr] != address(0);
  }

  function recoverSigner(bytes32 hashedMessage, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
		bytes32 messageDigest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hashedMessage));
    	return ecrecover(messageDigest, v, r, s);
	}

  function claimTokens(bytes32 hashedMessage, bytes memory _signature, address nativeTokenAddr, uint256 amount) public {
    require(msg.sender != address(0), "ERC20: claim from the zero address");
    require(amount > 0, "ERC20: Claim tokens with non-positive amount");

    (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);

    require(recoverSigner(hashedMessage, v,r,s) == msg.sender, "Message sender didn't sign the claim transaction");
    
    bool tokenAlreadyExists = tokenExists(nativeTokenAddr);

    if(!tokenAlreadyExists) {
      deployToken(nativeTokenAddr);
    }

    address wrappedTokenAddress = nativeToWrapped[nativeTokenAddr];
    WrappedToken wToken = WrappedToken(wrappedTokenAddress);
    wToken.mint(msg.sender, amount);
    tokenHasBeenClaimed[wrappedTokenAddress][msg.sender] = amount;
    emit TokensClaimed(msg.sender, amount, wrappedTokenAddress);
  }

  function releaseTokens(address contractAddress, uint256 amount) public {
    require(amount > 0, "Release non-positive amount of tokens");
    require(contractAddress != address(0), "Release tokens in null address");
    setERCContractAddress(contractAddress);
    tokenContract.approve(msg.sender, amount);
  }

  function getTokensClaimedAmount(address wrappedTokenAddr, address userAddr) public view returns(uint256 amount) {
    return tokenHasBeenClaimed[wrappedTokenAddr][userAddr];
  }

  function getWrappedTokenAddress(address nativeToken) external view returns(address wrappedAddress) {
    return nativeToWrapped[nativeToken];
  }

  function splitSignature(bytes memory sig)
        public
        pure
        returns (
            bytes32 r,
            bytes32 s,
            uint8 v
        )
    {
        require(sig.length == 65, "invalid signature length");

        assembly {
            /*
            First 32 bytes stores the length of the signature

            add(sig, 32) = pointer of sig + 32
            effectively, skips first 32 bytes of signature

            mload(p) loads next 32 bytes starting at the memory address p into memory
            */

            // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // second 32 bytes
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }

        // implicitly return (r, s, v)
    }

  receive() external payable {}

  fallback() external payable {}

}