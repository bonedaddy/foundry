// Taken from:
// https://github.com/dapphub/dapptools/blob/e41b6cd9119bbd494aba1236838b859f2136696b/src/dapp-tests/pass/cheatCodes.sol
pragma solidity ^0.8.4;
pragma experimental ABIEncoderV2;

import "./DsTest.sol";

interface Hevm {
    // Set block.timestamp (newTimestamp)
    function warp(uint256) external;
    // Set block.height (newHeight)
    function roll(uint256) external;
    // Loads a storage slot from an address (who, slot)
    function load(address,bytes32) external returns (bytes32);
    // Stores a value to an address' storage slot, (who, slot, value)
    function store(address,bytes32,bytes32) external;
    // Signs data, (privateKey, digest) => (r, v, s)
    function sign(uint256,bytes32) external returns (uint8,bytes32,bytes32);
    // Gets address for a given private key, (privateKey) => (address)
    function addr(uint256) external returns (address);
    // Performs a foreign function call via terminal, (stringInputs) => (result)
    function ffi(string[] calldata) external returns (bytes memory);
    // Calls another contract with a specified `msg.sender`, (newSender, contract, input) => (success, returnData)
    function prank(address, address, bytes calldata) external payable returns (bool, bytes memory);
    // Sets an address' balance, (who, newBalance)
    function deal(address, uint256) external;
    // Sets an address' code, (who, newCode)
    function etch(address, bytes calldata) external;
    // Expects an error on next call
    function expectRevert(bytes calldata) external;
}

contract HasStorage {
    uint public slot0 = 10;
}

// We add `assertEq` tests as well to ensure that our test runner checks the
// `failed` variable.
contract CheatCodes is DSTest {
    address public store = address(new HasStorage());
    Hevm constant hevm = Hevm(HEVM_ADDRESS);
    address public who = hevm.addr(1);

    // Warp

    function testWarp(uint128 jump) public {
        uint pre = block.timestamp;
        hevm.warp(block.timestamp + jump);
        require(block.timestamp == pre + jump, "warp failed");
    }

    function testWarpAssertEq(uint128 jump) public {
        uint pre = block.timestamp;
        hevm.warp(block.timestamp + jump);
        assertEq(block.timestamp, pre + jump);
    }

    function testFailWarp(uint128 jump) public {
        uint pre = block.timestamp;
        hevm.warp(block.timestamp + jump);
        require(block.timestamp == pre + jump + 1, "warp failed");
    }

    function testFailWarpAssert(uint128 jump) public {
        uint pre = block.timestamp;
        hevm.warp(block.timestamp + jump);
        assertEq(block.timestamp, pre + jump + 1);
    }

    // Roll

    // Underscore does not run the fuzz test?!
    function testRoll(uint256 jump) public {
        uint pre = block.number;
        hevm.roll(block.number + jump);
        require(block.number == pre + jump, "roll failed");
    }

    function testFailRoll(uint32 jump) public {
        uint pre = block.number;
        hevm.roll(block.number + jump);
        assertEq(block.number, pre + jump + 1);
    }

    // function prove_warp_symbolic(uint128 jump) public {
    //     test_warp_concrete(jump);
    // }


    function test_store_load_concrete(uint x) public {
        uint ten = uint(hevm.load(store, bytes32(0)));
        assertEq(ten, 10);

        hevm.store(store, bytes32(0), bytes32(x));
        uint val = uint(hevm.load(store, bytes32(0)));
        assertEq(val, x);
    }

    // function prove_store_load_symbolic(uint x) public {
    //     test_store_load_concrete(x);
    // }

    function test_sign_addr_digest(uint sk, bytes32 digest) public {
        if (sk == 0) return; // invalid key

        (uint8 v, bytes32 r, bytes32 s) = hevm.sign(sk, digest);
        address expected = hevm.addr(sk);
        address actual = ecrecover(digest, v, r, s);

        assertEq(actual, expected);
    }

    function test_sign_addr_message(uint sk, bytes memory message) public {
        test_sign_addr_digest(sk, keccak256(message));
    }

    function testFail_sign_addr(uint sk, bytes32 digest) public {
        uint badKey = sk + 1;

        (uint8 v, bytes32 r, bytes32 s) = hevm.sign(badKey, digest);
        address expected = hevm.addr(sk);
        address actual = ecrecover(digest, v, r, s);

        assertEq(actual, expected);
    }

    function testFail_addr_zero_sk() public {
        hevm.addr(0);
    }

    function test_addr() public {
        uint sk = 77814517325470205911140941194401928579557062014761831930645393041380819009408;
        address expected = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

        assertEq(hevm.addr(sk), expected);
    }

    function testFFI() public {
        string[] memory inputs = new string[](3);
        inputs[0] = "echo";
        inputs[1] = "-n";
        inputs[2] = "0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000046163616200000000000000000000000000000000000000000000000000000000";

        bytes memory res = hevm.ffi(inputs);
        (string memory output) = abi.decode(res, (string));
        assertEq(output, "acab");
    }

    function testDeal() public {
        address addr = address(1337);
        hevm.deal(addr, 1337);
        assertEq(addr.balance, 1337);
    }

    function testPrank() public {
        Prank prank = new Prank();
        address new_sender = address(1337);
        bytes4 sig = prank.checksOriginAndSender.selector;
        string memory input = "And his name is JOHN CENA!";
        bytes memory calld = abi.encodePacked(sig, abi.encode(input));
        address origin = tx.origin;
        address sender = msg.sender;
        (bool success, bytes memory ret) = hevm.prank(new_sender, address(prank), calld);
        assertTrue(success);
        string memory expectedRetString = "SUPER SLAM!";
        string memory actualRet = abi.decode(ret, (string));
        assertEq(actualRet, expectedRetString);

        // make sure we returned back to normal
        assertEq(origin, tx.origin);
        assertEq(sender, msg.sender);
    }

    function testPrankValue() public {
        Prank prank = new Prank();
        // setup the call
        address new_sender = address(1337);
        bytes4 sig = prank.checksOriginAndSender.selector;
        string memory input = "And his name is JOHN CENA!";
        bytes memory calld = abi.encodePacked(sig, abi.encode(input));
        address origin = tx.origin;
        address sender = msg.sender;

        // give the sender some monies
        hevm.deal(new_sender, 1337);

        // call the function passing in a value. the eth is pulled from the new sender
        sig = hevm.prank.selector;
        calld = abi.encodePacked(sig, abi.encode(new_sender, address(prank), calld));

        // this is nested low level calls effectively
        (bool high_level_success, bytes memory outerRet) = address(hevm).call{value: 1}(calld);
        assertTrue(high_level_success);
        (bool success, bytes memory ret) = abi.decode(outerRet, (bool,bytes));
        assertTrue(success);
        string memory expectedRetString = "SUPER SLAM!";
        string memory actualRet = abi.decode(ret, (string));
        assertEq(actualRet, expectedRetString);

        // make sure we returned back to normal
        assertEq(origin, tx.origin);
        assertEq(sender, msg.sender);
    }

    function testEtch() public {
        address rewriteCode = address(1337);
        
        bytes memory newCode = hex"1337";
        hevm.etch(rewriteCode, newCode);
        bytes memory n_code = getCode(rewriteCode);
        assertEq(string(newCode), string(n_code));
    }

    function testExpectRevert() public {
        ExpectRevert target = new ExpectRevert();
        hevm.expectRevert("Value too large");
        target.stringErr(101);
        target.stringErr(99); 
    }

    function testExpectCustomRevert() public {
        ExpectRevert target = new ExpectRevert();
        bytes memory data = abi.encodePacked(bytes4(keccak256("InputTooLarge()")));
        hevm.expectRevert(data);
        target.customErr(101);
        target.customErr(99); 
    }

    function testCalleeExpectRevert() public {
        ExpectRevert target = new ExpectRevert();
        hevm.expectRevert("Value too largeCallee");
        target.stringErrCall(101);
        target.stringErrCall(99);
    }

    function testFailExpectRevert() public {
        ExpectRevert target = new ExpectRevert();
        hevm.expectRevert("Value too large");
        target.stringErr2(101);
    }

    function testFailExpectRevert2() public {
        ExpectRevert target = new ExpectRevert();
        hevm.expectRevert("Value too large");
        target.stringErr(99);
    }

    function getCode(address who) internal returns (bytes memory o_code) {
        assembly {
            // retrieve the size of the code, this needs assembly
            let size := extcodesize(who)
            // allocate output byte array - this could also be done without assembly
            // by using o_code = new bytes(size)
            o_code := mload(0x40)
            // new "memory end" including padding
            mstore(0x40, add(o_code, and(add(add(size, 0x20), 0x1f), not(0x1f))))
            // store length in memory
            mstore(o_code, size)
            // actually retrieve the code, this needs assembly
            extcodecopy(who, add(o_code, 0x20), 0, size)
        }
    }
}


error InputTooLarge();
contract ExpectRevert {
    function stringErrCall(uint256 a) public returns (uint256) {
        ExpectRevertCallee callee = new ExpectRevertCallee();
        uint256 amount = callee.stringErr(a);
        return amount;
    }

    function stringErr(uint256 a) public returns (uint256) {
        require(a < 100, "Value too large");
        return a;
    }

    function stringErr2(uint256 a) public returns (uint256) {
        require(a < 100, "Value too large2");
        return a;
    }

    function customErr(uint256 a) public returns (uint256) {
        if (a > 99) {
            revert InputTooLarge();
        }
        return a;
    }
}

contract ExpectRevertCallee {
    function stringErr(uint256 a) public returns (uint256) {
        require(a < 100, "Value too largeCallee");
        return a;
    }

    function stringErr2(uint256 a) public returns (uint256) {
        require(a < 100, "Value too large2Callee");
        return a;
    }
}

contract Prank is DSTest {
    function checksOriginAndSender(string calldata input) external payable returns (string memory) {
        string memory expectedInput = "And his name is JOHN CENA!";
        assertEq(input, expectedInput);
        assertEq(address(1337), msg.sender);
        string memory expectedRetString = "SUPER SLAM!";
        return expectedRetString;
    }
}
