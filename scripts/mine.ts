import { currentTimestamp, mine } from './utils';

(async () => {
	await currentTimestamp().then(console.log);
	await mine(500);
	await currentTimestamp().then(console.log);
})();
