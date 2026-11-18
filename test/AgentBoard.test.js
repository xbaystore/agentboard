const { expect } = require("chai");
const { ethers } = require("hardhat");

const DAY = 24 * 60 * 60;

async function increaseTime(seconds) {
  await ethers.provider.send("evm_increaseTime", [seconds]);
  await ethers.provider.send("evm_mine", []);
}

describe("AgentBoard", function () {
  let mock, board, owner, alice, bob, carol;

  beforeEach(async function () {
    [owner, alice, bob, carol] = await ethers.getSigners();

    const Mock = await ethers.getContractFactory("MockAgentID");
    mock = await Mock.deploy();

    const Board = await ethers.getContractFactory("AgentBoard");
    board = await Board.deploy(await mock.getAddress());

    // alice & bob hold an Agent ID; carol does not.
    await mock.setBalance(alice.address, 1);
    await mock.setBalance(bob.address, 1);
  });

  it("reports holder status from the Agent ID collection", async function () {
    expect(await board.isAgentHolder(alice.address)).to.equal(true);
    expect(await board.isAgentHolder(carol.address)).to.equal(false);
  });

  it("blocks registration without an Agent ID", async function () {
    await expect(board.connect(carol).register("carol.ai", "chat", ""))
      .to.be.revertedWithCustomError(board, "NotAgentHolder");
  });

  it("registers a holder and stores the profile", async function () {
    await board.connect(alice).register("alice.ai", "research", "https://example.com/a");
    const p = await board.getProfile(alice.address);
    expect(p.agentName).to.equal("alice.ai");
    expect(p.capability).to.equal("research");
    expect(p.exists).to.equal(true);
    expect(await board.agentCount()).to.equal(1);
    expect(await board.isRegistered(alice.address)).to.equal(true);
  });

  it("rejects double registration and empty names", async function () {
    await board.connect(alice).register("alice.ai", "research", "");
    await expect(board.connect(alice).register("alice2.ai", "x", ""))
      .to.be.revertedWithCustomError(board, "AlreadyRegistered");
    await expect(board.connect(bob).register("", "x", ""))
      .to.be.revertedWithCustomError(board, "EmptyName");
  });

  it("lets a registered holder update their profile", async function () {
    await board.connect(alice).register("alice.ai", "research", "");
    await board.connect(alice).updateProfile("alice.ai", "trading", "ipfs://card");
    const p = await board.getProfile(alice.address);
    expect(p.capability).to.equal("trading");
    expect(p.profileURI).to.equal("ipfs://card");
  });

  it("check-in works once per day and builds a streak", async function () {
    await board.connect(alice).register("alice.ai", "research", "");
    await board.connect(alice).checkIn();
    let p = await board.getProfile(alice.address);
    expect(p.checkInCount).to.equal(1);
    expect(p.streak).to.equal(1);

    await expect(board.connect(alice).checkIn())
      .to.be.revertedWithCustomError(board, "AlreadyCheckedInToday");

    await increaseTime(DAY + 60);
    await board.connect(alice).checkIn();
    p = await board.getProfile(alice.address);
    expect(p.checkInCount).to.equal(2);
    expect(p.streak).to.equal(2);

    // skip a day -> streak resets
    await increaseTime(2 * DAY + 60);
    await board.connect(alice).checkIn();
    p = await board.getProfile(alice.address);
    expect(p.streak).to.equal(1);
    expect(p.checkInCount).to.equal(3);
  });

  it("check-in requires registration", async function () {
    await expect(board.connect(bob).checkIn())
      .to.be.revertedWithCustomError(board, "NotRegistered");
  });

  it("endorsements follow the rules and can be revoked", async function () {
    await board.connect(alice).register("alice.ai", "research", "");
    await board.connect(bob).register("bob.ai", "trading", "");

    await expect(board.connect(alice).endorse(alice.address))
      .to.be.revertedWithCustomError(board, "CannotEndorseSelf");
    await expect(board.connect(alice).endorse(carol.address))
      .to.be.revertedWithCustomError(board, "NotRegistered");

    await board.connect(alice).endorse(bob.address);
    expect((await board.getProfile(bob.address)).endorsements).to.equal(1);
    expect(await board.hasEndorsed(alice.address, bob.address)).to.equal(true);

    await expect(board.connect(alice).endorse(bob.address))
      .to.be.revertedWithCustomError(board, "AlreadyEndorsed");

    await board.connect(alice).revokeEndorsement(bob.address);
    expect((await board.getProfile(bob.address)).endorsements).to.equal(0);
  });

  it("board posts are gated, counted and length-limited", async function () {
    await board.connect(alice).register("alice.ai", "research", "");
    await expect(board.connect(alice).post("hello agents"))
      .to.emit(board, "Posted")
      .withArgs(alice.address, 1, "hello agents");
    expect(await board.totalPosts()).to.equal(1);

    await expect(board.connect(alice).post(""))
      .to.be.revertedWithCustomError(board, "EmptyPost");
    await expect(board.connect(alice).post("x".repeat(281)))
      .to.be.revertedWithCustomError(board, "PostTooLong");
    await expect(board.connect(carol).post("hi"))
      .to.be.revertedWithCustomError(board, "NotAgentHolder");
  });

  it("losing the Agent ID locks writes again", async function () {
    await board.connect(alice).register("alice.ai", "research", "");
    await mock.setBalance(alice.address, 0);
    await expect(board.connect(alice).checkIn())
      .to.be.revertedWithCustomError(board, "NotAgentHolder");
  });

  it("paginates the agent list and reports stats", async function () {
    await board.connect(alice).register("alice.ai", "research", "");
    await board.connect(bob).register("bob.ai", "trading", "");
    const page = await board.getAgents(0, 1);
    expect(page.length).to.equal(1);
    expect(page[0]).to.equal(alice.address);
    const [agents, posts] = await board.stats();
    expect(agents).to.equal(2);
    expect(posts).to.equal(0);
  });
});
