import { HardhatUserConfig } from 'hardhat/config';
import '@nomicfoundation/hardhat-toolbox';
import '@nomiclabs/hardhat-solhint';
import '@nomiclabs/hardhat-etherscan';
import 'hardhat-contract-sizer';
import 'hardhat-gas-reporter';
import '@openzeppelin/hardhat-upgrades';
import dotenv from 'dotenv';
dotenv.config();

const config: HardhatUserConfig = {
	solidity: '0.8.17',
	contractSizer: {
		alphaSort: true,
		disambiguatePaths: false,
		runOnCompile: false,
		strict: true,
	},
	networks: {
		hardhat: {
			forking: {
				url: process.env.ETHEREUM_RPC_ENDPOINT || '',
				enabled: process.env.FORK === 'true',
				blockNumber: 16891826,
			},
		},
	},
	etherscan: {
		apiKey: {
			mainnet: process.env.ETHERSCAN_API_MAINNET || '',
		},
	},
	gasReporter: {
		enabled: process.env.REPORT_GAS === 'true',
	},
};

export default config;
