// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title TreasureHunt
 * @dev A contract, TreasureHunt where user can stake some ether to play game and win rewards.
 */

contract TreasureHunt is VRFConsumerBaseV2Plus {
    /**
     *  Enum representing possible directions where players can move
     */ 
    enum Directions {
        Left,
        Right,
        Top,
        Down
    }

    enum TreasureMovement {
        MultipleOfFive,
        PrimeNumber
    }

    struct GameData {
        uint8 treasurePosition;
        bool moveTreasure; 
        uint40 startTime;
        address winner;
        uint256 totalValueLocked;
        uint256 playerCount;
    }

    struct PlayerData {
        uint8 position;
        bool isActive;
    }

    struct RequestData {
        address player;
        uint8 newPosition;
        TreasureMovement condition;
        bool newGame;
        uint256 requestId;
    }

    
    /* Bitmask of prime numbers from 0 to 99
     Each bit represents a number, 1 if prime, 0 if not
    */
    /**
     * Private variables
     */
    uint256 private constant primeBitMask = 0x20208828828208a20a08a28ac;
    bytes private extraArgs;
    uint32 private constant callbackGasLimit = 100000;
    uint32 private constant numWords = 1;
    uint16 private immutable requestConfirmations;
    address private coordinatorId;
    uint256 private s_subscriptionId;
   

    /**
     * Public variables
     */
    uint256 public currentGameIndex; // Current game round index
    uint8 public constant GRID_SIZE = 100;
    bytes32 public keyHash;
    uint256 public immutable PARTICIPATION_FEE;
    uint256 public immutable GAME_DURATION;
    address public immutable DEPLOYER;
    mapping(uint256 gameIndex => GameData game) public games;
    mapping(uint256 gameIndex => mapping(address userAddress => PlayerData position)) public players;
    RequestData public request;

    /**
     * Events
     */
    event NewPlayerAdded(address indexed player, uint256 currentGameIndex);
    event PlayerRelocated(address player, uint256 currentGameIndex, uint8 newPosition);
    event TreasureRelocated(uint8 indexed newPosition, uint256 currentGameIndex);
    event Winner(address indexed winner, uint256 prize, uint256 currentGameIndex);
    event GameBegins(uint256 indexed currentGameIndex, uint256 initialTVL, uint8 initialTreasurePosition);
    event GameOver(uint256 indexed currentGameIndex);
    event WithdrawFunds(address indexed user);
    event RequestSent(uint256 requestId);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords);
    event Received(address indexed sender, uint256 amount);

    /**
     * Custom errors
     */
    error PlayerExists(address user);
    error PositionOutOfBounds(Directions direction, uint8 currentPosition);
    error GameInProgress(uint256 currentGameIndex);
    error GameNonExpirable(uint256 currentGameIndex);
    error InsufficientAmountToWithdraw();
    error InsufficientParticipationFee();
    error RequestNotFound(uint256 requestId);
    error NotEnoughGamesPlayedYetToWithdrawTVL(uint256 currentGameIndex);
    error ValueCannotExceedHundred();
    error RestrictedToDeployer();

    /**
     * @dev Constructor to initialize the contract with minimum turn duration and expiry duration.
     * @param _requestConfirmation The number of block confirmations the VRF service will wait to respond.
     * @param _gameDuration Duration till the game lasts
     * @param _s_subscriptionId SubscriptionId of VRF chainlink 
     * @param _participationFee The amount required to participate and play game
     */
    constructor(
        uint16 _requestConfirmation,
        uint256 _gameDuration,
        uint256 _s_subscriptionId,
        uint256 _participationFee,
        bytes32 _keyHash,
        address _coordinatorId
    ) VRFConsumerBaseV2Plus(_coordinatorId) {
        s_subscriptionId = _s_subscriptionId;
        keyHash = _keyHash;
        coordinatorId = _coordinatorId;
        requestConfirmations = _requestConfirmation;
        PARTICIPATION_FEE = _participationFee;
        GAME_DURATION = _gameDuration;
        DEPLOYER = msg.sender;
        currentGameIndex++;
        games[currentGameIndex].startTime = uint40(block.timestamp);
        uint8 initialTreasurePosition = _generateInitialRandomPosition();
        games[currentGameIndex].treasurePosition = initialTreasurePosition;

        emit GameBegins(currentGameIndex, games[currentGameIndex].totalValueLocked, initialTreasurePosition);
        extraArgs = VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}));
    }

    /**
     * Modifiers
     */

    /**
     * @dev Modifier to check whether the game has expired.
     */
    modifier gameExpired(uint256 gameIndex) {
        if (gameIndex >= currentGameIndex) {
            revert GameInProgress(currentGameIndex);
        }
        _;
    }

    /**
     * External Functions
     */

    /**
     * @dev Allows a user to participate in the current game by sending the required participation fee.
     * @notice The participant must send Ether to join the game.
     * @notice The participation fee must be equal to 'PARTICIPATION_FEE'.
     * @notice A player cannot participate in the same game more than once.
     * Emits a {NewPlayerAdded} event when a new player joins the game.
     */
    function participate() external payable {
        if (msg.value != PARTICIPATION_FEE) { 
            revert InsufficientParticipationFee();  
        }
        address participant = msg.sender;

        if (players[currentGameIndex][participant].isActive) {
            revert PlayerExists(participant);
        }

        games[currentGameIndex].playerCount++;
        games[currentGameIndex].totalValueLocked += PARTICIPATION_FEE;
        players[currentGameIndex][participant].isActive = true;

        emit NewPlayerAdded(participant, currentGameIndex);
    }

    /**
     * @dev Allows an active player to make a move in the specified direction.
     * The player must wait for their turn before making a move.
     * This function calculates the player's new position based on provided direction.
     * If the player lands on treasure's position, the game ends and funds are processed.
     * Otherwise, player's position is updated
     * If the new position is a prime number or a multiple of five, a request to generate random word is made.
     * Emits a {PlayerRelocated} event when the player successfully moves to a new position.
     * @param direction The direction in which the player wants to move. This should be one of the values from the `Directions` enum.
    */
    function makeMove(Directions direction) public payable {
        uint256 _currentGameIndex = currentGameIndex;
        PlayerData memory _player = players[_currentGameIndex][msg.sender];
        require(_player.isActive, "INACTIVE player");
        GameData memory _game = games[_currentGameIndex];
        require(!_game.moveTreasure, "Treasure is in movement");
        uint8 playerPosition = _player.position;
        uint8 treasurePosition = _game.treasurePosition;

        if (playerPosition == treasurePosition) {
            _endGameAndProcessFunds(_currentGameIndex, msg.sender);
        } else {
            uint8 newPosition = _newPlayerPosition(playerPosition, direction);

            if (_isPrime(newPosition)) {
                request.condition = TreasureMovement.PrimeNumber;
                request.player = msg.sender;
                request.newPosition = newPosition;

                _requestRandomWords(_currentGameIndex);
            } else if (newPosition % 5 == 0) {
                request.condition = TreasureMovement.MultipleOfFive;
                request.player = msg.sender;
                request.newPosition = newPosition;

                _requestRandomWords(_currentGameIndex);
            } else {
                players[_currentGameIndex][msg.sender].position = newPosition;
                emit PlayerRelocated(msg.sender, _currentGameIndex, newPosition);
                if (newPosition == treasurePosition) {
                    _endGameAndProcessFunds(_currentGameIndex, msg.sender);
                }
            }
        }
    }

    /**
     * @dev Expire the current game if game duration has elapsed.
     * The function checks if the current game is still within the limits, it is reverted with an error.
     * If the game has expired, it calculates the total value locked (TVL) for next game.
     * Emits a {GameOver} event when the current game is successfully expired and a new game is started.
     * Reverts with:
     * - `GameNonExpirable` if the current time is less than the game's expiry time.
     */
    function endCurrentGame() external {
        uint256 _currentGameIndex = currentGameIndex;
        GameData memory game = games[_currentGameIndex];
        if (block.timestamp <= (game.startTime + GAME_DURATION)) {
            revert GameNonExpirable(_currentGameIndex);
        }
        
        games[_currentGameIndex + 1].totalValueLocked = game.totalValueLocked - (game.playerCount * PARTICIPATION_FEE); // Remaining 10 percent is kept for next round

        _startNewGame(_currentGameIndex);
        emit GameOver(_currentGameIndex);
    }

    /**
     * @dev Allows an active player to withdraw their participation fee from a specific game.
     * Requirements:
     * - The current game must be expired.
     * - The caller must have a non-zero participation fee for the expired game.
     *
     * @param gameIndex The index of the game from which the player wishes to withdraw their funds.
     * Emits a {WithdrawFunds} event when funds are successfully withdrawn.
     */
    function withdrawFunds(uint256 gameIndex) external gameExpired(gameIndex) {
        PlayerData storage player = players[gameIndex][msg.sender];
        if (!player.isActive) {
            revert InsufficientAmountToWithdraw();
        }

        player.isActive = false;
        --games[gameIndex].playerCount;
        games[gameIndex].totalValueLocked -= PARTICIPATION_FEE;
        address payable receiver = payable(msg.sender);
        receiver.transfer(PARTICIPATION_FEE);
        emit WithdrawFunds(receiver);
    }

    /**
    * Internal Functions
    */

    /**
    * @dev Checks whether the current number is prime using a bitmask.
    * @notice This function uses a bitmask to check whether a number is prime or not. 
    * If the number is greater than or equal to 'GRID_SIZE' it reverts with an error.
    *
    * @param number The number to check for primality.
    * @return bool Returns true if the number is prime, false otherwise.
    */

    function _isPrime(uint8 number) internal pure returns (bool) {
        if (number >= GRID_SIZE) {
            revert ValueCannotExceedHundred();
        }
        return (primeBitMask & (1 << number)) != 0;
    }

    /**
     * @notice It handles the processing of random words received from VRF Cordinator.
     * @dev When the VRFCoordinator sends the response to a previous VRF request, this function is invoked.
            It marks the request as fulfilled, saves the provided random words, and triggers an event.
            The function's behavior varies based on whether the treasure's position needs to be reset or updated.
     * @param _requestId The unique identifier generated for each of the VRF request.
     * @param _randomWords An array containing the random words generated by the VRF Coordinator.
     * @notice Emits a {RequestFulfilled} event when the random words are successfully processed.
     */
    function fulfillRandomWords(uint256 _requestId, uint256[] calldata _randomWords) internal override {
        uint256 _currentGameIndex = currentGameIndex;
        games[_currentGameIndex].moveTreasure = false;
        if (request.requestId != _requestId) {
            revert RequestNotFound(_requestId);
        }
        if (request.newGame) {
            _resetTreasurePosition(_randomWords[0]);
        } else {
            _moveTreasure(_randomWords[0]);

            if (request.newPosition == games[_currentGameIndex].treasurePosition) {
                _endGameAndProcessFunds(_currentGameIndex, request.player);
            }
        }
        emit RequestFulfilled(_requestId, _randomWords);
    }

    /**
     * @dev Moves the treasure to a new position based on specified condition.
     * The treasure's movement is determined by specific conditions:
     * - If the player's current position is divisible by 5, the treasure will move to a random adjacent position.
     * - If the treasure's current position is a prime number, it will move to any random position on the grid.
     * @param randomWord The random word provided by the VRF Coordinator.
     * @notice Emits a {TreasureRelocated} event after the treasure has moved.
     */
    function _moveTreasure(uint256 randomWord) internal {
        if (request.condition == TreasureMovement.MultipleOfFive) {
            _moveTreasureToRandomAdjacentPosition(randomWord);
        } else if (request.condition == TreasureMovement.PrimeNumber) {
            _moveTreasureToRandomPosition(randomWord);
        }
    }

    /**
     * @dev Ends the current game and processes the funds for the winner.
     * This function updates the game state to reflect the winner, calculates the reward and
       transfers it to the winner.
     * It also prepares the total value locked (TVL) for the next game.
     * It also emits a Winner event and starts a new game.
     * @param _currentGameIndex The index of the current game being processed.
     * @param _winner The address of the player who won the game.
     * @notice Emits a {Winner} event when the funds are successfully processed and the winner is declared.
     */
    function _endGameAndProcessFunds(uint256 _currentGameIndex, address _winner) internal {
        games[_currentGameIndex].winner = _winner;
        uint256 reward = (games[_currentGameIndex].totalValueLocked * 9) / 10;
        payable(_winner).transfer(reward);
        games[_currentGameIndex + 1].totalValueLocked = address(this).balance; // Remaining 10% stays for the next round
        emit Winner(_winner, reward, _currentGameIndex);
        _startNewGame(_currentGameIndex);
    }

    /**
     * @dev Starts a new game.
     * This function increments the current game index, sets the start time for the new game,
       and make a request for random words to reset the treasure's position.
     * @param _currentGameIndex The index of the current game being processed.
     * @notice Emits a {GameBegins} event with the new game index.
     */
    function _startNewGame(uint256 _currentGameIndex) internal {
        currentGameIndex++;
        games[currentGameIndex].startTime = uint40(block.timestamp);

        request.newGame = true;
        _requestRandomWords(_currentGameIndex);
    }

    /**
     * @dev Moves the treasure to a new random position within the grid.
     * The new position is calculated by taking the modulus of randomWord with grid size.
     * @param randomWord The random word provided by the VRF Coordinator.
     * Emits a {TreasureRelocated} event when the treasure's position is successfully updated.
     */
    function _moveTreasureToRandomPosition(uint256 randomWord) internal {
        uint8 newTreasurePosition = uint8(randomWord % GRID_SIZE);
        games[currentGameIndex].treasurePosition = newTreasurePosition;
        emit TreasureRelocated(newTreasurePosition, currentGameIndex);
    }

    /**
     * @dev Moves the treasure to a random adjacent position on the board.
     * The allowed adjacent positions are - {LEFT, RIGHT, UP, DOWN}.
     * This function is internal and should only be called from within the contract.
     * @param randomWord RandomWord provided by VRF Coordinator.
     * Emits a {TreasureRelocated} event when the treasure's position is successfully updated.
     */
    function _moveTreasureToRandomAdjacentPosition(uint256 randomWord) internal {
        uint8 position = games[currentGameIndex].treasurePosition;
        uint8[4] memory possiblePositions;
        uint8 count = 0;
        uint8 x = position % 10; // x axis of the board
        uint8 y = position / 10; // y axis of the board
        
        // checks the possiblePosition to be within the boundary
        if (x != 0) {
            possiblePositions[count++] = position - 1; 
        }

        if (y != 0) {
            possiblePositions[count++] = position - 10; 
        }

        if (x != 9) {
            possiblePositions[count++] = position + 1; 
        }

        if (y != 9) {
            possiblePositions[count++] = position + 10;
        }

        require(count > 0, "No valid moves");
        uint8 newTreasurePosition = possiblePositions[randomWord % count];

        games[currentGameIndex].treasurePosition = newTreasurePosition;
        emit TreasureRelocated(newTreasurePosition, currentGameIndex);
    }

    /**
     * @notice Requests random words from the VRF (Verifiable Random Function) Coordinator for the current game.
     * @dev This function requests a specified number of random words from the VRF chainlink.
     * @param _currentGameIndex The index of the current game for which for which random words are requested.
     * @return requestId The unique ID of the randomness request, which can be used to track and manage the request status.
     * Emits a {RequestSent} event when the request for random words is successfully sent.
     */
    function _requestRandomWords(uint256 _currentGameIndex) internal returns (uint256 requestId) {
        games[_currentGameIndex].moveTreasure = true;
          requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: s_subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: numWords,
                extraArgs: extraArgs
            })
          );
        
        request.requestId = requestId;
        emit RequestSent(requestId);
    }

    /**
     * @dev Resets the treausure position in the current game.
     * @notice This function sets the treasure position based on a random word and reactivates the game.
     * @param randomWord A random uint256 value used to determine the new treasure position.
     * The treasure position is set as the modulo of this randomWord with GRID_SIZE.
     * Emits a {GameBegins} event when the treasure's position is successfully reset for the new game.
     */
    function _resetTreasurePosition(uint256 randomWord) internal {
        request.newGame = false;
        uint8 initialTreasurePosition = uint8(randomWord % GRID_SIZE);
        games[currentGameIndex].treasurePosition = initialTreasurePosition;

        emit GameBegins(currentGameIndex, games[currentGameIndex].totalValueLocked, initialTreasurePosition);
    }

    /**
     * @dev Calculates the new position of player based on specified direction.
     * It checks for the boundary of grid so that the player may not move out of boundary.
     * @param position current position of player in the game.
     * @param direction The direction where player has to move.
     * @return nextPosition The new position of the player.
     */
    function _newPlayerPosition(uint8 position, Directions direction) internal pure returns (uint8 nextPosition) {
        uint8 y = position / 10; // y axis of the board
        uint8 x = position % 10; // x axis of the board

        if (direction == Directions.Left) {
            nextPosition = (x == 0) ? 100 : position - 1;
        } else if (direction == Directions.Top) {
            nextPosition = (y == 0) ? 100 : position - 10;
        } else if (direction == Directions.Right) {
            nextPosition = (x == 9) ? 100 : position + 1;
        } else if (direction == Directions.Down) {
            nextPosition = (y == 9) ? 100 : position + 10;
        }

        // check if the position is hundred then throw error
        if (nextPosition == 100) {
            revert PositionOutOfBounds(direction, position);
        }
    }

    /**
     * @dev Generate a random position for the first time while deployment.
     * @return uint8 The generated random position.
     */
    function _generateInitialRandomPosition() internal view returns (uint8) {
        return uint8(uint256(keccak256(abi.encodePacked(block.timestamp, block.number))) % GRID_SIZE);
    }
}