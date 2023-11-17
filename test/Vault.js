const { time } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { expect } = require("chai");

describe("Vault", () => {
    const pid = 9;
    const curveSwapAddr = "0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7";
    // underlying tokens
    const DAIAddr = "0x6B175474E89094C44Da98b954EedeAC495271d0F";

    // Accounts
    const user1Addr = "0xb838c8A085D71F560698D1D5d60Aa46509735cd6";
    const user2Addr = "0x3C5348c8981f2d9759f4219a6F14c87274675AB8";
    // Contracts
    let vault, lpToken, dai, baseRewardPool;
    // Signers
    let owner, user1, user2;

    const TEN_HOURS = 10 * 3600;

    before(async() => {
        // Contracts are deployed using the first signer/account by default
        [owner] = await ethers.getSigners();

        const Vault = await ethers.getContractFactory("Vault");
        vault = await Vault.deploy(pid, curveSwapAddr);

        const lpTokenAddr = await vault.lptoken();

        lpToken = await ethers.getContractAt("IERC20", lpTokenAddr);
        dai = await ethers.getContractAt("IERC20", DAIAddr);

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
        it("Not whitelisted", async() => {
            await expect(
                vault.connect(user1).depositSingle(DAIAddr, ethers.parseEther("100"))
            ).to.be.revertedWith("Not whitelisted");
        });

        it("Invalid amount", async() => {
            await expect(
                vault.connect(owner).addWhitelist(DAIAddr)
            ).to.emit(vault, "WhitelistAdded").withArgs(DAIAddr);

            await expect(
                vault.connect(user1).depositSingle(DAIAddr, ethers.parseEther("0"))
            ).to.be.revertedWith("Invalid amount");
        });

        it("User1 deposits 100 3CRV tokens", async() => {
            const amount = ethers.parseEther("100");

            // Approve lp token
            await lpToken.connect(user1).approve(vault.target, amount);

            // Deposit
            await expect(
                vault.connect(user1).depositLp(amount)
            ).to.emit(vault, "DepositLp").withArgs(user1Addr, lpToken.target, amount);

            expect(await vault.balanceOf(user1Addr)).to.equal(amount);
            expect(await vault.totalSupply()).to.equal(amount);
        });

        it("User1 deposits 1000 DAI tokens", async() => {
            const amount = ethers.parseEther("1000");

            // Approve DAI token
            await dai.connect(user1).approve(vault.target, amount);
            
            // Deposit
            await expect(
                vault.connect(user1).depositSingle(DAIAddr, amount)
            ).to.emit(vault, "DepositSingle")
            .withArgs(user1Addr, DAIAddr, amount);
        });

        it("User1 deposits 1 ETH", async() => {
            const amount = ethers.parseEther("1");

            await expect(
                vault.connect(user1).depositETH({ 
                    value: amount
                })
            ).to.emit(vault, "DepositSingle")
            .withArgs(user1Addr, ethers.ZeroAddress, amount);
        });
    })

    /* describe("Claim rewards", () => {
        // Todo
        it("Get pending rewards 10 hours later", async() => {
            await time.increase(TEN_HOURS);

            const [crvRewards1, cvxRewards1] = await vault.pendingRewards(user1Addr);
            const [crvRewards2, cvxRewards2] = await vault.pendingRewards(user2Addr);

            console.log(crvRewards1.toString(), cvxRewards1.toString());
        });
    }); */

    describe("Withdraw", () => {
        it("Validation", async() => {
            await expect(
                vault.connect(user1).withdrawLp(ethers.parseEther("0"))
            ).to.be.revertedWith("Invalid amount");

            await expect(
                vault.connect(user1).withdrawLp(ethers.parseEther("3000"))
            ).to.be.revertedWith("Exceeded amount");
        });

        it("User1 withdraws 100 lp tokens", async() => {
            const amount = ethers.parseEther("100");
    
            await expect(
                vault.connect(user1).withdrawLp(amount)
            ).to.emit(vault, "WithdrawLp")
            .withArgs(user1Addr, lpToken.target, amount);
        });
    
        /* it("User1 withdraws DAI tokens for 100 lp tokens", async() => {
            const amount = ethers.parseEther("100");
    
            await expect(
                vault.connect(user1).withdrawSingle(DAIAddr, amount)
            ).to.emit(vault, "WithdrawSingle")
            .withArgs(user1Addr, DAIAddr, amount);
        }); */
    });
});
