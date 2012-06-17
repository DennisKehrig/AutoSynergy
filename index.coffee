require('ansinception') ->
	platform	= process.platform
	mac			= platform is 'darwin'
	win 		= platform is 'win32'
	unless mac or win
		throw new Error("Unsupported platform "+platform)

	fs			= require 'fs'
	os			= require 'os'
	dns			= require 'dns'
	portscanner	= require 'portscanner'
	ansi		= require 'ansi'
	if win
		windows	= require 'windows'
	spawn		= (require 'child_process').spawn
	cursor		= ansi process.stdout

	config		= null

	run = ->
		checkConfiguration()
		cycle()

	cycle = ->
		console.log "Starting over"
		console.log ""
		detectDevice (devicePresent) ->
			console.log ""
			if devicePresent
				launchServer cycle
			else
				findOwnIps (ownIps) ->
					resolveIps config.servers, (serverIps) ->
						findServer serverIps, ownIps, (serverIp) ->
							if serverIp
								console.log ""
								launchClient serverIp, cycle
							else
								delay config.interval, cycle

	requiredConfigurationKeys = ['client', 'server', 'config', 'vendorId', 'productId', 'servers']

	defaultConfiguration =
		port:		24800
		name:		os.hostname()
		interval:	5000
		timeout:	5000

	checkConfiguration = ->
		console.log "Checking the configuration file"
		
		configPath = require.resolve './config'
		findPathOrQuit configPath, -> "Config file #{configPath} missing\nUse config.coffee.sample as a template"
		config = require configPath
		
		missingRequired = false
		for key in requiredConfigurationKeys
			unless config[key]?
				missingRequired = true
				cursor.brightRed().write("Configuration: Missing key #{key}").reset().write("\n")
		process.exit() if missingRequired

		for key, value of defaultConfiguration
			unless config[key]?
				config[key] = value
				cursor.brightYellow().write("Configuration: Using #{key} #{value}").reset().write("\n")

		findPathOrQuit config.client, -> "Client executable #{config.client} not found"
		findPathOrQuit config.server, -> "Server executable #{config.server} not found"
		findPathOrQuit config.config, -> "Synergy configuration file #{config.config} not found"

	findPathOrQuit = (path, callback) ->
		try
			fs.statSync path
		catch err
			if err.code is 'ENOENT'
				cursor.brightRed().write(callback(path)).reset().write("\n")
				process.exit()
			throw err

	launchClient = (server, callback) ->
		console.log "Launching client, using server #{server}"
		
		console.log "Executing " + config.client
		client = spawn config.client, ['--no-daemon', '--no-restart', '--name', config.name, server+':'+config.port]
		
		manageChild client, 'client', callback

	launchServer = (callback) ->
		console.log "Launching server"
		
		console.log "Executing " + config.server
		server = spawn config.server, ['--no-daemon', '--no-restart', '--name', config.name, '--address', ':'+config.port, '--config', config.config]

		timeout = null
		do ->
			repeat = arguments.callee
			timeout = delay config.interval, ->
				detectDevice (devicePresent) ->
					if devicePresent
						repeat()
					else
						server.kill()
		
		stop = ->
			clearTimeout timeout
			callback()
		
		manageChild server, 'server', stop

	echoChild = (name, data, color) ->
		data = data.toString() if data.toString?
		data = data.replace(/^\s+|\s+$/g, '')
		
		for line in data.split("\n")
			cursor.grey().write('[' + name + '] ').reset()
			cursor[color]() if color
			cursor.write(data).reset().write("\n")

	manageChild = (child, name, callback) ->
		child.stderr.on 'data', (data) ->
			echoChild name, data, 'brightRed'
			child.kill()
		
		child.stdout.on 'data', (data) ->
			echoChild name, data
		
		child.on 'exit', (code) ->
			echoChild name, 'Exit code ' + (code ? 'n/a'), 'brightCyan'
			callback()

	resolveIps = (hostnames, callback) ->
		console.log "Resolving IP addresses of " + hostnames.join(", ")
		ips = [].concat hostnames

		remaining = 0
		ips.forEach (server, index) ->
			unless server.match(/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/)
				remaining++
				dns.resolve4 server, (err, addresses) ->
					remaining--
					if err
						console.log "Error while resolving #{server}: "
						console.log err
					else
						console.log "#{server} is at\t#{addresses[0]}"
						ips[index] = addresses[0]
					unless remaining
						filtered = []
						for ip in ips
							filtered.push ip unless ip is server or ip in filtered
						callback filtered

	findOwnIps = (callback) ->
		console.log "Finding own IP addresses"
		interfaces = os.networkInterfaces()
		
		empty = true
		for own key of interfaces
			empty = false
			break
		
		unless empty
			ownIps = []
			for device, addresses of interfaces
				for address in addresses
					ownIps.push address.address unless address.internal or address.family isnt 'IPv4'
			console.log "Own IP addresses: " + ownIps.join(", ")
			callback ownIps
		else
			first = true
			dns.lookup os.hostname(), (err, ip, family) ->
				if first and family is 4
					first = false
					console.log "Own IP address: " + ip
					callback [ip]

	findServer = (serverIps, ownIps, callback) ->
		console.log "Finding a server amongst " + serverIps.join(", ")
		do ->
			return callback null unless ip = serverIps.shift()
			
			next = arguments.callee
			return next() if ip in ownIps
			
			console.log "Probing " + ip
			portscanner.checkPortStatus config.port, ip, (err, status) ->
				throw err if err
				if status is 'open'
					console.log ip + " is active"
					callback ip
				else
					next()

	detectDevice = (callback) ->
		console.log "Detecting the device"
		
		report = (devicePresent) ->
			console.log 'Device ' + if devicePresent then 'found' else 'not found'
			callback devicePresent
		
		if mac
			detectDeviceMac report
		else if win
			detectDeviceWin report

	detectDeviceMac = (callback) ->
		console.log "Searching USB devices listed by the system profiler"
		profiler = spawn "system_profiler", ["SPUSBDataType", "-detailLevel", "mini"]
		
		buffer = ""
		profiler.stdout.on 'data', (data) ->
			buffer += data.toString()
		
		matcher = new RegExp('Product ID: 0x'+config.productId+'\\s*\\n\\s*Vendor ID:\\s*0x'+config.vendorId+'\\s')
		profiler.on 'exit', (code) ->
			callback if buffer.match(matcher) then true else false

	detectDeviceWin = (callback) ->
		console.log "Searching the device in the registry"
		data = windows.registry 'HKEY_LOCAL_MACHINE/SYSTEM/CurrentControlSet/Control/DeviceClasses/{378de44c-56ef-11d1-bc8c-00a0c91405dd}/'
		matcher = new RegExp('^#\\?#HID#Vid_'+config.vendorId+'&Pid_'+config.productId)
		for key, sub of data
			if matcher.test key
				sub = sub['#']
				if sub and sub.Control
					sub = sub.Control
					for name of sub
						if name is "Linked\tREG_DWORD\t0x1"
							return callback true
		callback false

	delay = (msec, fn) ->
		setTimeout fn, msec
	
	every = (msec, fn) ->
		setInterval fn, msec

	run()