const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("TreasureHunt Multiple Win Conditions and Error Cases", function () {
  let deployer, player1, player2;
  let treasureHunt;
  const PARTICIPATION_FEE = ethers.parseEther("0.1");
  const REQUEST_CONFIRMATIONS_BLOCKS = 1;
  const GAME_DURATION = 60 * 60; // 1-hour
  const SUBSCRIPTION_ID =
    "64746452690481906522574034740770945330467998183793674977142993865018905336125";
  const KEY_HASH =
    "0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae";
  const COORDINATOR_ID = "0x9ddfaca8183c41ad55329bdeed9f6a8d53168b1b";

  beforeEach(async function () {
    [deployer, player1, player2] = await ethers.getSigners();

    treasureHunt = await ethers.deployContract(
      "TreasureHuntMock",
      [
        REQUEST_CONFIRMATIONS_BLOCKS,
        GAME_DURATION,
        SUBSCRIPTION_ID,
        PARTICIPATION_FEE,
        KEY_HASH,
        COORDINATOR_ID,
        80, // Initial treasure position
      ],
      deployer
    );

    // Participate in the game
    await treasureHunt
      .connect(player1)
      .participate({ value: PARTICIPATION_FEE });
    await treasureHunt
      .connect(player2)
      .participate({ value: PARTICIPATION_FEE });
  });

  it("Should enable a player to win by landing directly on the treasure's location", async function () {
    const currentGameIndex = await treasureHunt.currentGameIndex();
    const gameDetails = await treasureHunt.games(currentGameIndex);

    let playerPosition = 80; // same as the treasure location

    await treasureHunt.setPlayerPosition(player1.address, playerPosition);

    const totalValueLocked = gameDetails.totalValueLocked;
    const prizeAmount = (totalValueLocked * BigInt(9)) / BigInt(10);

    // Verify player1's position
    const playerState = await treasureHunt.players(
      currentGameIndex,
      player1.address
    );
    expect(playerState.position).to.be.equal(playerPosition);

    let moveToDirection = 1; // Right direction

    const transaction = await (
      await treasureHunt.connect(player1).makeMove(moveToDirection)
    ).wait();
    await expect(transaction)
      .to.emit(treasureHunt, "Winner")
      .withArgs(player1.address, prizeAmount, currentGameIndex);
  });

  it("should allow a player to win when the treasure moves to their position (prime_Number)", async function () {
    const currentGameIndex = await treasureHunt.currentGameIndex();
    const gameDetails = await treasureHunt.games(currentGameIndex);

    const treasureLocation = Number(gameDetails.treasurePosition); // 80

    let playerPosition = 3; // Prime position

    await treasureHunt.setPlayerPosition(player1.address, playerPosition);

    const totalValueLocked = gameDetails.totalValueLocked;
    const prizeAmount = (totalValueLocked * BigInt(9)) / BigInt(10);

    // Verify player1's position
    const playerState = await treasureHunt.players(
      currentGameIndex,
      player1.address
    );
    expect(playerState.position).to.be.equal(playerPosition);

    let directionToMove = 3; // Right direction

    const transaction = await (
      await treasureHunt.connect(player1).makeMove(directionToMove)
    ).wait();

    let request = await treasureHunt.request();
    let updatedTreasurePosition = request.newPosition;
    await treasureHunt.setTreasurePosition(updatedTreasurePosition);
    const transaction1 = await (
      await treasureHunt.feedRandomWords(request.requestId, [13])
    ).wait();
    await expect(transaction1)
      .to.emit(treasureHunt, "Winner")
      .withArgs(player1.address, prizeAmount, currentGameIndex);
  });

  it("should allow a player to win when the treasure moves to their position (Multiple of Five)", async function () {
    const currentGameIndex = await treasureHunt.currentGameIndex();
    const gameDetails = await treasureHunt.games(currentGameIndex);

    const treasureLocation = Number(gameDetails.treasurePosition); // 50

    let playerPosition = 10; // Multiple of 5 position

    await treasureHunt.setPlayerPosition(player1.address, playerPosition);

    const totalValueLocked = gameDetails.totalValueLocked;
    const prizeAmount = (totalValueLocked * BigInt(9)) / BigInt(10);

    // Verify player1's position
    const playerState = await treasureHunt.players(
      currentGameIndex,
      player1.address
    );
    expect(playerState.position).to.be.equal(playerPosition);

    let directionToMove = 1; // Right direction
    const transaction = await (
      await treasureHunt.connect(player1).makeMove(directionToMove)
    ).wait();

    let request = await treasureHunt.request();
    let updatedTreasurePosition = request.newPosition;
    await treasureHunt.setTreasurePosition(updatedTreasurePosition);
    const transaction1 = await (
      await treasureHunt.feedRandomWords(request.requestId, [11])
    ).wait();
    await expect(transaction1)
      .to.emit(treasureHunt, "Winner")
      .withArgs(player1.address, prizeAmount, currentGameIndex);
  });

  it("should allow a player to win when treasure moves to their position (multiple of 5 and a Prime number)", async function () {
    const currentGameIndex = await treasureHunt.currentGameIndex();
    const gameDetails = await treasureHunt.games(currentGameIndex);

    const treasureLocation = Number(gameDetails.treasurePosition); // 80

    let playerPosition = 5; // Multiple of 5 and a prime number also

    await treasureHunt.setPlayerPosition(player1.address, playerPosition);

    const totalValueLocked = gameDetails.totalValueLocked;
    const prizeAmount = (totalValueLocked * BigInt(9)) / BigInt(10);

    // Verify player1's position
    const playerState = await treasureHunt.players(
      currentGameIndex,
      player1.address
    );

    expect(playerState.position).to.be.equal(playerPosition);

    let directionToMove = 3; // Right direction

    const transaction = await (
      await treasureHunt.connect(player1).makeMove(directionToMove)
    ).wait();

    let request = await treasureHunt.request();

    let updatedTreasurePosition = request.newPosition;

    await treasureHunt.setTreasurePosition(updatedTreasurePosition);

    let newUserPositionInRequest = 25;
    await treasureHunt.setRequestInExecution(
      request.requestId,
      newUserPositionInRequest
    );

    const transaction1 = await (
      await treasureHunt.feedRandomWords(request.requestId, [15])
    ).wait();

    await expect(transaction1)
      .to.emit(treasureHunt, "Winner")
      .withArgs(player1.address, prizeAmount, currentGameIndex);
  });

  it("should revert with PlayerExists when a user tries to participate twice", async function () {
    await expect(
      treasureHunt.connect(player1).participate({ value: PARTICIPATION_FEE })
    )
      .to.be.revertedWithCustomError(treasureHunt, "PlayerExists")
      .withArgs(player1.address);
  });

  it("should revert with GameNonExpirable when trying to expire a game too early", async function () {
    const gameIndex = await treasureHunt.currentGameIndex();
    await expect(treasureHunt.endCurrentGame())
      .to.be.revertedWithCustomError(treasureHunt, "GameNonExpirable")
      .withArgs(gameIndex);
  });

  it("should revert with InsufficientAmountToWithdraw when a non-participant tries to withdraw", async function () {
    const gameIndex = await treasureHunt.currentGameIndex();

    // Fast-forward time to make the game expirable
    await ethers.provider.send("evm_increaseTime", [GAME_DURATION + 1]);
    await ethers.provider.send("evm_mine");

    await treasureHunt.endCurrentGame();

    await expect(
      treasureHunt.connect(deployer).withdrawFunds(gameIndex)
    ).to.be.revertedWithCustomError(
      treasureHunt,
      "InsufficientAmountToWithdraw"
    );
  });
});
