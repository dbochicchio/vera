const http = require('http');
const url = require('url');
const Switchbot = require('node-switchbot');

const requestListener = function (req, res) {
	const queryObject = url.parse(req.url, true).query;
	res.writeHead(200);

	let device = null;

	if (queryObject == undefined || queryObject.id == undefined)
		return res.end('Please specify an id');

	const switchbot = new Switchbot();

	switchbot.discover({ id: queryObject.id, quick: true }).then((device_list) => {
		if (device_list == undefined || device_list.length == 0) {
			console.log('#device: notfound');
			res.end('no device');
		}
		device = device_list[0];

		console.log('#devicefound: ' + device.modelName + ' (' + device.address + ')');
		return true; //device.connect();
	}).then(() => {
		console.log('#device:press');
		return device.press();
	}).then(() => {
		console.log('#device:waiting');
		return switchbot.wait(1000);
	}).then(() => {
		console.log('#device:disconnecting');
		return device.disconnect();
	}).then(() => {
		console.log('Done.');
		res.end('OK!');
	}).catch((error) => {
		console.error(error);
		res.end('error: ' + error);
	});
};

const server = http.createServer(requestListener);
server.timeout = 5 * 1000;
server.listen(5002);

console.log('#http:started');