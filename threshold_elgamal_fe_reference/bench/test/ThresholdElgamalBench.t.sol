// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IThresholdElection} from "../src/IThresholdElection.sol";

interface Vm {
    function ffi(string[] calldata) external returns (bytes memory);
    function readFile(string calldata path) external returns (string memory);
    function pauseGasMetering() external;
    function resumeGasMetering() external;
    function envOr(string calldata name, uint256 defaultValue) external returns (uint256);
}

contract ThresholdElgamalBenchTest {
    // -------------------------------------------------------------------------
    // Test vectors (mirrors `ingots/threshold_elgamal_fe_tests/src/lib.fe`)
    // -------------------------------------------------------------------------

    uint256 private constant PUBLIC_KEY_X = 10300624219749368059713323037041369269067239741452710719700636823789733733154;
    uint256 private constant PUBLIC_KEY_Y = 17827553270106623771307957771827766897690156367955456415120897338355905013159;

    // ballot 1 vote=1 nonce=101
    uint256 private constant B1_C1_X = 101736474863018474486226188821757310196822904661437109985129121643628477843;
    uint256 private constant B1_C1_Y = 20809165444309486437598143500680353367168077151871577252054480771838214401340;
    uint256 private constant B1_C2_X = 12962917735978141221444368205266247483683847511298192923389131646601947578495;
    uint256 private constant B1_C2_Y = 13511671430952089340395405596387091423198727762290462286614491900744094320353;

    // ballot 2 vote=-1 nonce=202
    uint256 private constant B2_C1_X = 17824683701631220404790167295863547058164197332047694173140186357298477189027;
    uint256 private constant B2_C1_Y = 3097434001403605815138448380136495440524244032504546416970701306470368425560;
    uint256 private constant B2_C2_X = 92987952764381805479106405600674428203634538868185823452120739265792181903;
    uint256 private constant B2_C2_Y = 53022711887334421713593758480668320099728043176085275220323290016026430976;

    // ballot 3 vote=1 nonce=303
    uint256 private constant B3_C1_X = 18788921900215882028576331803050066650912825348279745351731017781865893991129;
    uint256 private constant B3_C1_Y = 20814377278669429206835538101018916238670560516677675250133520990818107708475;
    uint256 private constant B3_C2_X = 61437125467865537038641829258986279070513676837218299218577578148222252191;
    uint256 private constant B3_C2_Y = 18684938108794433691656587870215457405736474345011620771125666855515202760799;

    // ballot 4 vote=0 nonce=404
    uint256 private constant B4_C1_X = 13256385979709478041825407576283983783238279154098759374429323029806284937096;
    uint256 private constant B4_C1_Y = 21513102545268876961651414862126510904709719983608676746884501617698560681524;
    uint256 private constant B4_C2_X = 15693740690350101788647025923986963135110670086567359550756517522206769477839;
    uint256 private constant B4_C2_Y = 52569278308473687904715357417445726822408309503136783969846472142094042950;

    // ballot 5 vote=1 nonce=505
    uint256 private constant B5_C1_X = 18174603526803993658686942152143384402313116336828627275335369390747190095208;
    uint256 private constant B5_C1_Y = 19670326919000185315510907564113899766268039106509406435570657051621276703121;
    uint256 private constant B5_C2_X = 20330519925086639957082591346545531750070715601189046589362910951915186218873;
    uint256 private constant B5_C2_Y = 20743859361497709309955694236618608865509155234298968664635510007930902325659;

    // aggregate ciphertext
    uint256 private constant AGG_C1_X = 16404442663957185746263930515050125482033472485901130913021726498975982758907;
    uint256 private constant AGG_C1_Y = 13274530490267589212644233776423850103349736059235004318598498572925086435871;
    uint256 private constant AGG_C2_X = 9247987211804826595573629444076173043879837605879757743509119968087650564828;
    uint256 private constant AGG_C2_Y = 5393959636255382324049160108433203146296684020322750430401185645132912776962;

    // decrypted message point (tally=2)
    int256 private constant DECODED_TALLY = 2;
    uint256 private constant DECRYPTED_X = 1368015179489954701390400359078579693043519447331113978918064868415326638035;
    uint256 private constant DECRYPTED_Y = 9918110051302171585080402603319702774565515993150576347155970296011118125764;

    // -------------------------------------------------------------------------
    // Harness
    // -------------------------------------------------------------------------

    address private constant HEVM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm private constant vm = Vm(HEVM_ADDRESS);

    IThresholdElection private feSona;
    IThresholdElection private feYul;

    uint256 private constant THRESHOLD = 3;
    uint256 private constant VOTING_DEADLINE = type(uint256).max;

    function setUp() public {
        vm.pauseGasMetering();

        // Fe -> Sonatina (optimization level via `FE_SONA_OPT_LEVEL=0|1|2`).
        string[] memory cmdSona = new string[](11);
        uint256 sonaOptLevel = vm.envOr("FE_SONA_OPT_LEVEL", uint256(0));
        require(sonaOptLevel <= 2, "BAD_FE_SONA_OPT_LEVEL");
        cmdSona[0] = "fe";
        cmdSona[1] = "build";
        cmdSona[2] = "--backend";
        cmdSona[3] = "sonatina";
        cmdSona[4] = "--optimize";
        cmdSona[5] = sonaOptLevel == 0 ? "0" : (sonaOptLevel == 1 ? "1" : "2");
        cmdSona[6] = "--out-dir";
        cmdSona[7] = "out/fe/sonatina";
        cmdSona[8] = "--contract";
        cmdSona[9] = "ThresholdElection";
        cmdSona[10] = "../ingots/threshold_elgamal_fe";
        vm.ffi(cmdSona);

        bytes memory deployCodeSona = _hexStringToBytes(vm.readFile("out/fe/sonatina/ThresholdElection.bin"));
        address feSonaAddr = _deploy(bytes.concat(deployCodeSona, _ctorArgs()));
        feSona = IThresholdElection(feSonaAddr);
        _requireRuntimeMatches(feSonaAddr, "out/fe/sonatina/ThresholdElection.runtime.bin");

        // Fe -> Yul -> solc.
        string[] memory cmdYul = new string[](13);
        cmdYul[0] = "fe";
        cmdYul[1] = "build";
        cmdYul[2] = "--backend";
        cmdYul[3] = "yul";
        cmdYul[4] = "--optimize";
        cmdYul[5] = "2";
        cmdYul[6] = "--solc";
        cmdYul[7] = "/usr/bin/solc";
        cmdYul[8] = "--out-dir";
        cmdYul[9] = "out/fe/yul";
        cmdYul[10] = "--contract";
        cmdYul[11] = "ThresholdElection";
        cmdYul[12] = "../ingots/threshold_elgamal_fe";
        vm.ffi(cmdYul);

        bytes memory deployCodeYul = _hexStringToBytes(vm.readFile("out/fe/yul/ThresholdElection.bin"));
        address feYulAddr = _deploy(bytes.concat(deployCodeYul, _ctorArgs()));
        feYul = IThresholdElection(feYulAddr);
        _requireRuntimeMatches(feYulAddr, "out/fe/yul/ThresholdElection.runtime.bin");

        vm.resumeGasMetering();
    }

    function _ctorArgs() private view returns (bytes memory) {
        return abi.encode(PUBLIC_KEY_X, PUBLIC_KEY_Y, THRESHOLD, VOTING_DEADLINE, address(this));
    }

    // -------------------------------------------------------------------------
    // Correctness checks (deterministic vectors)
    // -------------------------------------------------------------------------

    function test_vectors_fe_sona_aggregate_matches_reference() public {
        feSona.castVote(B1_C1_X, B1_C1_Y, B1_C2_X, B1_C2_Y);
        feSona.castVote(B2_C1_X, B2_C1_Y, B2_C2_X, B2_C2_Y);
        feSona.castVote(B3_C1_X, B3_C1_Y, B3_C2_X, B3_C2_Y);
        feSona.castVote(B4_C1_X, B4_C1_Y, B4_C2_X, B4_C2_Y);
        feSona.castVote(B5_C1_X, B5_C1_Y, B5_C2_X, B5_C2_Y);

        (uint256 c1_x, uint256 c1_y, uint256 c2_x, uint256 c2_y) = feSona.getAggregate();
        assert(c1_x == AGG_C1_X);
        assert(c1_y == AGG_C1_Y);
        assert(c2_x == AGG_C2_X);
        assert(c2_y == AGG_C2_Y);
    }

    function test_vectors_fe_yul_aggregate_matches_reference() public {
        feYul.castVote(B1_C1_X, B1_C1_Y, B1_C2_X, B1_C2_Y);
        feYul.castVote(B2_C1_X, B2_C1_Y, B2_C2_X, B2_C2_Y);
        feYul.castVote(B3_C1_X, B3_C1_Y, B3_C2_X, B3_C2_Y);
        feYul.castVote(B4_C1_X, B4_C1_Y, B4_C2_X, B4_C2_Y);
        feYul.castVote(B5_C1_X, B5_C1_Y, B5_C2_X, B5_C2_Y);

        (uint256 c1_x, uint256 c1_y, uint256 c2_x, uint256 c2_y) = feYul.getAggregate();
        assert(c1_x == AGG_C1_X);
        assert(c1_y == AGG_C1_Y);
        assert(c2_x == AGG_C2_X);
        assert(c2_y == AGG_C2_Y);
    }

    function test_invalid_g1_point_is_rejected_fe_sona() public {
        (bool ok, ) = address(feSona).call(
            abi.encodeWithSelector(IThresholdElection.castVote.selector, uint256(0), uint256(1), B1_C2_X, B1_C2_Y)
        );
        assert(!ok);
    }

    function test_invalid_g1_point_is_rejected_fe_yul() public {
        (bool ok, ) = address(feYul).call(
            abi.encodeWithSelector(IThresholdElection.castVote.selector, uint256(0), uint256(1), B1_C2_X, B1_C2_Y)
        );
        assert(!ok);
    }

    // -------------------------------------------------------------------------
    // Gas benches
    // -------------------------------------------------------------------------

    function testGas_bench_fe_sona_castVote_first() public {
        vm.pauseGasMetering();
        bytes memory callData =
            abi.encodeWithSelector(IThresholdElection.castVote.selector, B1_C1_X, B1_C1_Y, B1_C2_X, B1_C2_Y);
        _warm(address(feSona));
        vm.resumeGasMetering();

        (bool ok, ) = address(feSona).call(callData);

        vm.pauseGasMetering();
        require(ok, "FE/sona: castVote first");
    }

    function testGas_bench_fe_yul_castVote_first() public {
        vm.pauseGasMetering();
        bytes memory callData =
            abi.encodeWithSelector(IThresholdElection.castVote.selector, B1_C1_X, B1_C1_Y, B1_C2_X, B1_C2_Y);
        _warm(address(feYul));
        vm.resumeGasMetering();

        (bool ok, ) = address(feYul).call(callData);

        vm.pauseGasMetering();
        require(ok, "FE/yul: castVote first");
    }

    function testGas_bench_fe_sona_castVote_after_1() public {
        vm.pauseGasMetering();
        // Bring aggregate away from the point at infinity.
        feSona.castVote(B1_C1_X, B1_C1_Y, B1_C2_X, B1_C2_Y);
        bytes memory callData =
            abi.encodeWithSelector(IThresholdElection.castVote.selector, B2_C1_X, B2_C1_Y, B2_C2_X, B2_C2_Y);
        _warm(address(feSona));
        vm.resumeGasMetering();

        (bool ok, ) = address(feSona).call(callData);

        vm.pauseGasMetering();
        require(ok, "FE/sona: castVote after 1");
    }

    function testGas_bench_fe_yul_castVote_after_1() public {
        vm.pauseGasMetering();
        feYul.castVote(B1_C1_X, B1_C1_Y, B1_C2_X, B1_C2_Y);
        bytes memory callData =
            abi.encodeWithSelector(IThresholdElection.castVote.selector, B2_C1_X, B2_C1_Y, B2_C2_X, B2_C2_Y);
        _warm(address(feYul));
        vm.resumeGasMetering();

        (bool ok, ) = address(feYul).call(callData);

        vm.pauseGasMetering();
        require(ok, "FE/yul: castVote after 1");
    }

    function testGas_bench_fe_sona_getAggregate() public {
        vm.pauseGasMetering();
        bytes memory callData = abi.encodeWithSelector(IThresholdElection.getAggregate.selector);
        _warm(address(feSona));
        vm.resumeGasMetering();

        (bool ok, bytes memory ret) = address(feSona).staticcall(callData);

        vm.pauseGasMetering();
        require(ok && ret.length == 128, "FE/sona: getAggregate");
    }

    function testGas_bench_fe_yul_getAggregate() public {
        vm.pauseGasMetering();
        bytes memory callData = abi.encodeWithSelector(IThresholdElection.getAggregate.selector);
        _warm(address(feYul));
        vm.resumeGasMetering();

        (bool ok, bytes memory ret) = address(feYul).staticcall(callData);

        vm.pauseGasMetering();
        require(ok && ret.length == 128, "FE/yul: getAggregate");
    }

    function testGas_bench_fe_sona_closeVoting() public {
        vm.pauseGasMetering();
        bytes memory callData = abi.encodeWithSelector(IThresholdElection.closeVoting.selector);
        _warm(address(feSona));
        vm.resumeGasMetering();

        (bool ok, ) = address(feSona).call(callData);

        vm.pauseGasMetering();
        require(ok, "FE/sona: closeVoting");
    }

    function testGas_bench_fe_yul_closeVoting() public {
        vm.pauseGasMetering();
        bytes memory callData = abi.encodeWithSelector(IThresholdElection.closeVoting.selector);
        _warm(address(feYul));
        vm.resumeGasMetering();

        (bool ok, ) = address(feYul).call(callData);

        vm.pauseGasMetering();
        require(ok, "FE/yul: closeVoting");
    }

    function testGas_bench_fe_sona_recordFinalResult() public {
        vm.pauseGasMetering();
        feSona.closeVoting();
        bytes memory callData = abi.encodeWithSelector(
            IThresholdElection.recordFinalResult.selector, DECODED_TALLY, DECRYPTED_X, DECRYPTED_Y
        );
        _warm(address(feSona));
        vm.resumeGasMetering();

        (bool ok, ) = address(feSona).call(callData);

        vm.pauseGasMetering();
        require(ok, "FE/sona: recordFinalResult");
    }

    function testGas_bench_fe_yul_recordFinalResult() public {
        vm.pauseGasMetering();
        feYul.closeVoting();
        bytes memory callData = abi.encodeWithSelector(
            IThresholdElection.recordFinalResult.selector, DECODED_TALLY, DECRYPTED_X, DECRYPTED_Y
        );
        _warm(address(feYul));
        vm.resumeGasMetering();

        (bool ok, ) = address(feYul).call(callData);

        vm.pauseGasMetering();
        require(ok, "FE/yul: recordFinalResult");
    }

    // -------------------------------------------------------------------------
    // Low-level helpers (copied from the adjacent zk-kit Foundry harness)
    // -------------------------------------------------------------------------

    function _warm(address target) private view {
        assembly ("memory-safe") {
            pop(extcodesize(target))
        }
    }

    function _deploy(bytes memory creationCode) private returns (address deployed) {
        assembly ("memory-safe") {
            deployed := create(0, add(creationCode, 0x20), mload(creationCode))
        }
        require(deployed != address(0), "DEPLOY_FAILED");
    }

    function _requireRuntimeMatches(address deployed, string memory runtimePath) private {
        bytes memory expected = _hexStringToBytes(vm.readFile(runtimePath));
        bytes memory actual = deployed.code;
        require(keccak256(actual) == keccak256(expected), "RUNTIME_MISMATCH");
    }

    function _hexStringToBytes(string memory s) private pure returns (bytes memory) {
        bytes memory strBytes = bytes(s);
        uint256 start = 0;
        uint256 end = strBytes.length;

        while (start < end && _isWhitespace(strBytes[start])) {
            start++;
        }
        while (end > start && _isWhitespace(strBytes[end - 1])) {
            end--;
        }

        if (start + 2 <= end && strBytes[start] == "0" && (strBytes[start + 1] == "x" || strBytes[start + 1] == "X"))
        {
            start += 2;
        }

        require(((end - start) % 2) == 0, "HEX_ODD_LENGTH");
        uint256 len = (end - start) / 2;
        bytes memory out = new bytes(len);

        for (uint256 i = 0; i < len; i++) {
            uint8 hi = _fromHexChar(uint8(strBytes[start + 2 * i]));
            uint8 lo = _fromHexChar(uint8(strBytes[start + 2 * i + 1]));
            out[i] = bytes1((hi << 4) | lo);
        }

        return out;
    }

    function _isWhitespace(bytes1 c) private pure returns (bool) {
        return c == 0x20 || c == 0x0a || c == 0x0d || c == 0x09;
    }

    function _fromHexChar(uint8 c) private pure returns (uint8) {
        if (c >= uint8(bytes1("0")) && c <= uint8(bytes1("9"))) return c - uint8(bytes1("0"));
        if (c >= uint8(bytes1("a")) && c <= uint8(bytes1("f"))) return 10 + (c - uint8(bytes1("a")));
        if (c >= uint8(bytes1("A")) && c <= uint8(bytes1("F"))) return 10 + (c - uint8(bytes1("A")));
        revert("HEX_BAD_CHAR");
    }
}
