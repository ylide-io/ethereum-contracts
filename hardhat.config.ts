import { HardhatUserConfig } from 'hardhat/config';
import '@nomicfoundation/hardhat-toolbox';
import '@nomiclabs/hardhat-solhint';
import '@nomiclabs/hardhat-etherscan';
import 'hardhat-contract-sizer';
import 'hardhat-gas-reporter';

const config: HardhatUserConfig = {
	solidity: '0.8.17',
	contractSizer: {
		alphaSort: true,
		disambiguatePaths: false,
		runOnCompile: false,
		strict: true,
	},
	etherscan: {
		apiKey: {
			mainnet: process.env.ETHERSCAN_API_MAINNET || '',
		},
	},
	gasReporter: {
		enabled: process.env.REPORT_GAS ? true : false,
	},
};

export default config;
