import { HardhatUserConfig } from 'hardhat/config';
import '@nomicfoundation/hardhat-toolbox';
import '@nomiclabs/hardhat-solhint';
import 'hardhat-contract-sizer';
import 'hardhat-gas-reporter';

const config: HardhatUserConfig = {
	solidity: '0.8.17',
	gasReporter: {
		enabled: process.env.REPORT_GAS ? true : false,
	},
};

export default config;
