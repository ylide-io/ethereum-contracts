import { HardhatUserConfig } from 'hardhat/config';
import '@nomicfoundation/hardhat-toolbox';
import '@nomiclabs/hardhat-solhint';
import 'hardhat-contract-sizer';

const config: HardhatUserConfig = {
	solidity: '0.8.17',
	networks: {
		hardhat: {
			forking: {
				url: 'https://mainnet.infura.io/v3/8304d93f528f45569f6841b06a56e703',
				enabled: true,
				blockNumber: 17019807,
			},
		},
	},
};

export default config;
