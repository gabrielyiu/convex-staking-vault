const { time } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { expect } = require("chai");

describe("Vault", () => {
    const pid = 4;
    // Accounts
    const user1Addr = "0x9E51BE7071F086d3A1fD5Dc0016177473619b237";
    const user2Addr = "0xD2e10CfC63d1e48850849B4EE6977Ca359cAa7ce";
    // Contracts
    let vault, lpToken, baseRewardPool;
    // Signers
    let owner, user1, user2;

    const TEN_HOURS = 10 * 3600;

    before(async() => {
        // Contracts are deployed using the first signer/account by default
        [owner] = await ethers.getSigners();

        const Vault = await ethers.getContractFactory("Vault");
        vault = await Vault.deploy(pid);

        const lpTokenAddr = await vault.lptoken();

        lpToken = await ethers.getContractAt("IERC20", lpTokenAddr);
        const rewardContractAddr = await vault.rewardContract();
 
        baseRewardPool = await ethers.getContractAt("IBaseRewardPool", rewardContractAddr);

        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [user1Addr],
        });

        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [user2Addr],
        });

        user1 = await ethers.getSigner(user1Addr);
        user2 = await ethers.getSigner(user2Addr);
    });
        
    describe("Deposit", () => {
        it("Validation", async() => {
            const amount = ethers.parseEther("0");
            // Approve lp token
            await lpToken.connect(user1).approve(vault.target, amount);

            await expect(
                vault.connect(user1).deposit(ethers.parseEther("0"))
            ).to.be.revertedWith("Invalid amount");
        });

        it("User1 deposits 100 lp tokens", async() => {
            const amount = ethers.parseEther("100");

            // Approve lp token
            await lpToken.connect(user1).approve(vault.target, amount);

            // Deposit
            await expect(
                vault.connect(user1).deposit(amount)
            ).to.emit(vault, "Deposit").withArgs(user1Addr, pid, amount);

            expect(await vault.balanceOf(user1Addr)).to.equal(amount);
            expect(await vault.totalSupply()).to.equal(amount);
        });

        it("User2 deposits 200 lp tokens", async() => {
            const amount = ethers.parseEther("200");

            // Approve lp token
            await lpToken.connect(user2).approve(vault.target, amount);

            // Deposit
            await expect(
                vault.connect(user2).deposit(amount)
            ).to.emit(vault, "Deposit").withArgs(user2Addr, pid, amount);
            
            expect(await vault.balanceOf(user2Addr)).to.equal(amount);
            expect(await vault.totalSupply()).to.equal(ethers.parseEther("300"));
        });
    });

    describe("Claim rewards", () => {
        // Todo
        it("Get pending rewards 10 hours later", async() => {
            await time.increase(TEN_HOURS);

            const [crvRewards1, cvxRewards1] = await vault.pendingRewards(user1Addr);
            const [crvRewards2, cvxRewards2] = await vault.pendingRewards(user2Addr);

            console.log(crvRewards1.toString(), cvxRewards1.toString());
        });
    });

    describe("Withdraw", () => {
        it("Validation", async() => {
            await expect(
                vault.connect(user1).withdraw(ethers.parseEther("0"))
            ).to.be.revertedWith("Invalid amount");

            await expect(
                vault.connect(user1).withdraw(ethers.parseEther("1000"))
            ).to.be.revertedWith("Exceeded amount");
        });

        it("User1 withdraws 50 lp tokens", async() => {
            const amount = ethers.parseEther("50");
    
            await expect(
                vault.connect(user1).withdraw(amount)
            ).to.emit(vault, "Withdraw").withArgs(user1Addr, pid, amount);
    
            expect(await vault.balanceOf(user1Addr)).to.equal(amount);
            // 300 - 50 = 250
            expect(await vault.totalSupply()).to.equal(ethers.parseEther("250"));
        });
    
        it("User2 withdraws 100 lp tokens", async() => {
            const amount = ethers.parseEther("100");
    
            await expect(
                vault.connect(user2).withdraw(amount)
            ).to.emit(vault, "Withdraw").withArgs(user2Addr, pid, amount);
    
            expect(await vault.balanceOf(user2Addr)).to.equal(amount);
            // 250 - 100 = 150
            expect(await vault.totalSupply()).to.equal(ethers.parseEther("150"));
        });
    });
});
