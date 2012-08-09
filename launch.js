var delay = 0;

if (process.argv.length > 2) {
	var delay = parseInt(process.argv[2], 10);
	if (isNaN(delay)) {
		console.log(process.argv[2] + " is not a proper number");
		process.exit();
	}
}

setTimeout(function() {
	require('coffee-script');
	require('./index');
}, delay * 1000);