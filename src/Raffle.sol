// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Lottery contract
 * @author Martin BARRAL (with the help of Patrick COLLINS)
 * @notice This contract is for creating a sample raffle
 * @dev Implements Chainlink VRFv2.5
 * */

//IMPORTS
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

//CONTRACT
contract Raffle is VRFConsumerBaseV2Plus {
    //ERRORS
    error Raffle__NotSendEnoughETH();
    error Raffle__UpkeepNotNeeded(
        uint256 balance,
        uint256 playerLenght,
        uint256 isOpen
    );
    error Raffle__TransferFailed();
    error Raffle__NotOpen();

    //TYPES DECLARATIONS
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    //STATE VARIABLES
    uint16 private constant REQUEST_CONFIRMATIONS = 4;
    uint32 private constant NUM_WORDS = 1;
    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subId;
    uint32 private immutable i_callBackGasLimit;
    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    //EVENTS
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    //CONSTRUCTOR
    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subId,
        uint32 callBackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_keyHash = gasLane;
        i_subId = subId;
        i_callBackGasLimit = callBackGasLimit;
        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
    }

    //FUNCTIONS
    //Enter the lottery
    function enterRaffle() public payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__NotSendEnoughETH();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__NotOpen();
        }
        s_players.push(payable(msg.sender));
        emit RaffleEntered(msg.sender);
    }

    //When should the winner be picked ?
    /**
     * @dev This is the function the chainkink node will call to see if the lottery is ready to have a winner picked
     * The following should be true in order for upkeepNeeded to be true :
     * 1. The time interval has passed since the last winner picked
     * 2. The lottery is OPEN
     * 3. The contract has ETH
     * 4. Your subscription has LINK
     * @param - ignored
     * @return upkeepNeeded as true if it's time to restart the lottery
     * @return - ignored
     */
    function checkUpkeep(
        bytes memory /*checkdata*/
    ) public view returns (bool upkeepNeeded, bytes memory /*performdata*/) {
        bool timePassed = (block.timestamp - s_lastTimeStamp) > i_interval;
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = timePassed && isOpen && hasPlayers && hasBalance;
        return (upkeepNeeded, "0x0");
    }

    //Get a random number
    //Pick a random player with this random number
    //Do that pick every T lapse of time
    function performUpkeep(bytes calldata /*performData*/) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }

        s_raffleState = RaffleState.CALCULATING;

        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callBackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );

        emit RequestedRaffleWinner(requestId);
    }

    //Checks --> Effects --> Interactions
    function fulfillRandomWords(
        uint256 /*requestId*/,
        uint256[] calldata randomWords
    ) internal virtual override {
        //Checks
        //Effects (Internal contract state)
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;

        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;

        emit WinnerPicked(s_recentWinner);

        //Interactions (with external contracts)
        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    //GETTER FUNCTIONS
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }
}
