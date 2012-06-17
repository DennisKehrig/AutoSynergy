platform	= process.platform
mac			= platform is 'darwin'
win 		= platform is 'win32'
unless mac or win
	throw new Error("Unsupported platform "+platform)

os			= require 'os'
dns			= require 'dns'
portscanner	= require 'portscanner'
if win
	windows	= require 'windows'

spawn		= (require 'child_process').spawn

config		= require './config'

run = ->
	detectDevice (devicePresent) ->
		if devicePresent
			console.log "Device found"
			launchServer()
		else
			console.log "Device not found"
			findServer (server) ->
				if server
					launchClient server
				else
					console.log "No server found"

launchServer = ->
	console.log "Launching server"

launchClient = (server) ->
	console.log "Launching client, using server #{server}"
	if mac
		launchMacClient server
	else if win
		launchWinClient server

launchMacClient = (server) ->

launchWinClient = (server) ->

resolveHostnames = (callback) ->
	ips = [].concat config.servers

	remaining = 0
	ips.forEach (server, index) ->
		unless server.match(/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/)
			remaining++
			dns.resolve4 server, (err, addresses) ->
				throw err if err
				ips[index] = addresses[0]
				unless --remaining
					filtered = []
					for ip in ips
						filtered.push ip unless ip in filtered
					callback filtered

findOwnIps = (callback) ->
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
		callback ownIps
	else
		first = true
		dns.lookup os.hostname(), (err, address, family) ->
			if first and family is 4
				first = false
				callback [address]

findServer = (callback) ->
	findOwnIps (ownIps) ->
		resolveHostnames (ips) ->
			do ->
				return callback null unless ip = ips.shift()
				
				next = arguments.callee
				return next() if ip in ownIps
				portscanner.checkPortStatus config.port, ip, (err, status) ->
					throw err if err
					if status is 'open'
						callback ip
					else
						next()

detectDevice = (callback) ->
	if mac
		detectDeviceMac callback
	else if win
		detectDeviceWin callback

detectDeviceMac = (callback) ->
	console.log "Detecting the device by searching USB devices listed by the system profiler"
	profiler = spawn "system_profiler", ["SPUSBDataType", "-detailLevel", "mini"]
	
	buffer = ""
	profiler.stdout.on 'data', (data) ->
		buffer += data.toString()
	
	matcher = new RegExp('Product ID: 0x'+config.productId+'\\s*\\n\\s*Vendor ID:\\s*0x'+config.vendorId+'\\s')
	profiler.on 'exit', (code) ->
		callback if buffer.match(matcher) then true else false

detectDeviceWin = (callback) ->
	return callback false
	console.log "Detecting the device by searching the registry"
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

run()