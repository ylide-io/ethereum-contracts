import { HardhatUserConfig } from 'hardhat/config';
import '@nomicfoundation/hardhat-toolbox';
import '@nomiclabs/hardhat-solhint';
import 'hardhat-contract-sizer';

const config: HardhatUserConfig = {
	solidity: '0.8.17',
};

export default config;
