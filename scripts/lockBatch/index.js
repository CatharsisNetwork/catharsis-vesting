const fs = require('fs')
const csv = require('csvtojson/v2')
const { isAddress, toChecksumAddress, isHexStrict } = require('web3-utils');
const rimraf = require('rimraf');

const initialData = 1626652800

/**
 * Returns an array with arrays of the given size.
 *
 * @param myArray {Array} array to split
 * @param chunk_size {Number} Size of every group
 */
function chunkArray(myArray, chunk_size) {
    let index = 0;
    let arrayLength = myArray.length;
    let tempArray = [];

    for (index = 0; index < arrayLength; index += chunk_size) {
        let myChunk = myArray.slice(index, index+chunk_size);
        // Do something if you want with the group
        tempArray.push(myChunk);
    }

    return tempArray;
}

async function rmTodeployDir() {
    const directory = './output/*'
    rimraf(directory, function () { console.log('done'); });
}

// {
//     account: 0xa73e5597e7df0c7300f4657165c0a67e0b8dcf9e,
//     unlockAt: 1000,
//     amounts: 1500
// }
async function main() {
    const csvFilePath = './data.csv'
    const jsonArray = await csv().fromFile(csvFilePath);
    let addresses = [];
    jsonArray.map(item => {
        let address = String(item['address']).trim()
        if (isAddress(address)) {
            if (!isHexStrict(address)) {
                address = `0x${address}`
                if (!isAddress(address)) {
                    return;
                }
            }
            address = toChecksumAddress(address)
            addresses.push({account: address, unlockAt: [String(initialData + Number(item['seconds']))], amounts: [item['weys']]})
        }
    })

    console.log('Valid addresses:');
    console.log(addresses.length)

    const result = addresses.reduce((x, y) => x.includes(y) ? x : [...x, y], []);

    console.log('Uniq addresses:');
    console.log(result.length);

    const chunkSize = 500
    let chunkResult = chunkArray(result, chunkSize)

    let chunkLen = chunkResult.length
    for (let index = 0; index < chunkLen; index++) {
        fs.writeFile(`./output/addresses_size-${chunkSize}.${index}.json`, JSON.stringify(chunkResult[index]), 'utf8', (data) => {
            console.log(data)
        })
    }
}

// ENTER TO THE PROGRAM
rmTodeployDir().then(() => {
    main().catch(console.error)
}).catch(console.error)