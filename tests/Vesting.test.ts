import BN from "bn.js";
import chai from "chai";

import { ethers } from "hardhat";
import { Signer } from "ethers";
import { assert, expect } from "chai";
import { solidity } from "ethereum-waffle";

const {
    expectRevert, // Assertions for transactions that should fail
} = require('@openzeppelin/test-helpers');

import * as times from './time'

chai.use(solidity);

function getDateNow() {
    return Math.floor(Date.now()/1000);
}

describe("Vesting", function () {
    let accounts: Signer[];

    let OWNER: any
    let BENEFICIARY: any
    let OTHER: any

    let OWNER_SIGNER: any
    let BENEFICIARY_SIGNER: any
    let OTHER_SIGNER: any

    let token: any
    let vesting: any

    before('Configuration',async function () {
        accounts = await ethers.getSigners();

        OWNER_SIGNER = accounts[0];
        BENEFICIARY_SIGNER = accounts[1];
        OTHER_SIGNER = accounts[2];

        OWNER = await OWNER_SIGNER.getAddress()
        BENEFICIARY = await BENEFICIARY_SIGNER.getAddress()
        OTHER = await OTHER_SIGNER.getAddress()
    });

    describe("Good user behavior", function () {

        beforeEach('success vesting call',async function () {
            const ERC20Mock = await ethers.getContractFactory("ERC20Mock");
            const Vesting = await ethers.getContractFactory("Vesting");

            token = await ERC20Mock.deploy('Mock Erc20 token', 'MOCK');
            vesting = await Vesting.deploy(token.address, getDateNow());

            const MINTER_ROLE = await token.MINTER_ROLE();
            await token.grantRole(MINTER_ROLE, OWNER)
        })

        it("should lock from owner", async function () {
            await token.mint(OWNER, 1000)
            await token.approve(vesting.address, 1000)

            let lockDate = getDateNow() + 1000
            await vesting.lock(BENEFICIARY, [lockDate], [1000])

            assert.equal(await vesting.getLocksLength(BENEFICIARY), 1, 'Empty locks')

            let lock = await vesting.getLocks(BENEFICIARY, 0);
            let { amounts, unlocks } = lock

            // assert.equal(balance.released, 0, 'Not zero')
            assert.equal(amounts[0], 1000, 'Wrong amount')
            assert.equal(unlocks[0], lockDate, 'Wrong unlock')

            let nextUnlock = await vesting.getNextUnlockByIndex(BENEFICIARY, 0);

            assert.equal(nextUnlock, lockDate, 'Wrong next unlock')

            let pendingReward = await vesting.pendingReward(BENEFICIARY);

            assert.equal(pendingReward, 0, 'Wrong pending reward')

            let pendingRewardInRange = await vesting.pendingRewardInRange(BENEFICIARY, 0, 1);

            assert.equal(pendingRewardInRange, 0, 'Wrong pending reward in range')
        });

        it("should lock batch from owner", async function () {
            await token.mint(OWNER, 10000)
            await token.approve(vesting.address, 10000)

            let dateNow = getDateNow()

            let BENEFICIARY_2 = accounts[3]
            let BENEFICIARY_3 = accounts[4]
            let BENEFICIARY_4 = accounts[5]

            let locks: Array<any> = [
                {
                    account: BENEFICIARY_2.getAddress(),
                    unlockAt: [
                        dateNow + 1000,
                        dateNow + 2000
                    ],
                    amounts: [
                        1500,
                        2500
                    ]
                },
                {
                    account: BENEFICIARY_2.getAddress(),
                    unlockAt: [
                        dateNow + 500,
                    ],
                    amounts: [
                        1000,
                    ]
                },
                {
                    account: BENEFICIARY_2.getAddress(),
                    unlockAt: [
                        dateNow,
                    ],
                    amounts: [
                        500,
                    ]
                },
                {
                    account: BENEFICIARY_3.getAddress(),
                    unlockAt: [
                        dateNow + 1500,
                        dateNow + 3000
                    ],
                    amounts: [
                        2000,
                        2000
                    ]
                },
                {
                    account: BENEFICIARY_4.getAddress(),
                    unlockAt: [
                        dateNow
                    ],
                    amounts: [
                        500
                    ]
                },
            ]

            await vesting.lockBatch(locks)

            let nextUnlock = await vesting.getNextUnlockByIndex(BENEFICIARY_2.getAddress(), 0);
            assert.equal(nextUnlock, dateNow + 1000, 'Wrong next unlock')

            nextUnlock = await vesting.getNextUnlockByIndex(BENEFICIARY_2.getAddress(), 1);
            assert.equal(nextUnlock, dateNow + 500, 'Wrong next unlock')

            nextUnlock = await vesting.getNextUnlockByIndex(BENEFICIARY_4.getAddress(), 0);
            assert.equal(nextUnlock, 0, 'Wrong next unlock')

            let pendingReward = await vesting.pendingReward(BENEFICIARY_2.getAddress());
            assert.equal(pendingReward, 500, 'Wrong pending reward')

            pendingReward = await vesting.pendingReward(BENEFICIARY_3.getAddress());
            assert.equal(pendingReward.toNumber(), 0, 'Wrong pending reward')

            pendingReward = await vesting.pendingReward(BENEFICIARY_4.getAddress());
            assert.equal(pendingReward, 500, 'Wrong pending reward')
        });

        it("should claim from beneficiary", async function () {
            await token.mint(OWNER, 10000)
            await token.approve(vesting.address, 10000)

            let dateNow = getDateNow()

            let locks: Array<any> = [
                {
                    account: BENEFICIARY,
                    unlockAt: [
                        dateNow,
                    ],
                    amounts: [
                        500,
                    ]
                },
                {
                    account: BENEFICIARY,
                    unlockAt: [
                        dateNow + 500,
                        dateNow + 1000
                    ],
                    amounts: [
                        1500,
                        2500
                    ]
                },
                {
                    account: BENEFICIARY,
                    unlockAt: [
                        dateNow + 1500,
                    ],
                    amounts: [
                        3000,
                    ]
                }
            ]

            await vesting.lockBatch(locks)
            await vesting.connect(BENEFICIARY_SIGNER).claim(BENEFICIARY)

            let balanceOfBeneficiary = await token.balanceOf(BENEFICIARY)
            assert.equal(balanceOfBeneficiary.toNumber(), 500, 'Wrong balance')

            // await vesting.connect(BENEFICIARY_SIGNER).claim(BENEFICIARY)
        });
    })

    describe("Bed user behavior", function () {

        beforeEach('success vesting call',async function () {
            const ERC20Mock = await ethers.getContractFactory("ERC20Mock");
            const Vesting = await ethers.getContractFactory("Vesting");

            token = await ERC20Mock.deploy('Mock Erc20 token', 'MOCK');
            vesting = await Vesting.deploy(token.address, getDateNow());

            const MINTER_ROLE = await token.MINTER_ROLE();
            await token.grantRole(MINTER_ROLE, OWNER)
        })

        it("should fail if pass wrong data batch from owner", async function () {
            await token.mint(OWNER, 10000)
            await token.approve(vesting.address, 10000)

            let dateNow = getDateNow()

            let BENEFICIARY_2 = accounts[3]

            let locks: Array<any> = [
                {
                    account: BENEFICIARY_2.getAddress(),
                    unlockAt: [
                        dateNow + 2000
                    ],
                    amounts: [
                        1500,
                        2500
                    ]
                }
            ]

            await expectRevert(
                vesting.lockBatch(locks),
                'Wrong array length'
            )

            locks = [
                {
                    account: BENEFICIARY_2.getAddress(),
                    unlockAt: [
                        dateNow + 2000,
                        dateNow + 1000
                    ],
                    amounts: [
                        1500,
                        2500
                    ]
                }
            ]

            await expectRevert(
                vesting.lockBatch(locks),
                'Timeline violation'
            )

            locks = [
                {
                    account: BENEFICIARY_2.getAddress(),
                    unlockAt: [
                        dateNow - 2000,
                        dateNow + 1000
                    ],
                    amounts: [
                        1500,
                        2500
                    ]
                }
            ]

            await expectRevert(
                vesting.lockBatch(locks),
                'Early unlock'
            )

            let { AddressZero } = ethers.constants
            locks = [
                {
                    account: AddressZero,
                    unlockAt: [
                        dateNow - 2000,
                        dateNow + 1000
                    ],
                    amounts: [
                        1500,
                        2500
                    ]
                }
            ]

            await expectRevert(
                vesting.lockBatch(locks),
                'Zero address'
            )

            locks = [
                {
                    account: BENEFICIARY_2.getAddress(),
                    unlockAt: [],
                    amounts: []
                }
            ]

            await expectRevert(
                vesting.lockBatch(locks),
                'Zero array length'
            )
        });

        it("should fail claim if claimed and available zero from beneficiary", async function () {
            await token.mint(OWNER, 10000)
            await token.approve(vesting.address, 10000)

            let dateNow = getDateNow()

            let locks: Array<any> = [
                {
                    account: BENEFICIARY,
                    unlockAt: [
                        dateNow,
                    ],
                    amounts: [
                        500,
                    ]
                },
                {
                    account: BENEFICIARY,
                    unlockAt: [
                        dateNow + 500,
                        dateNow + 1000
                    ],
                    amounts: [
                        1500,
                        2500
                    ]
                },
                {
                    account: BENEFICIARY,
                    unlockAt: [
                        dateNow + 1500,
                    ],
                    amounts: [
                        3000,
                    ]
                }
            ]

            await vesting.lockBatch(locks)
            await vesting.connect(BENEFICIARY_SIGNER).claim(BENEFICIARY)

            await expectRevert(
                vesting.connect(BENEFICIARY_SIGNER).claim(BENEFICIARY),
                'Zero claim'
            )
        });
    })
})