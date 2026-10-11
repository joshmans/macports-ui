//
//  main.swift
//  MacPortsHelper
//
//  A privileged helper that runs a small allow-list of MacPorts commands for MacPorts UI.
//  It runs as root under launchd, accepts connections only from the app signed by the same team,
//  and re-validates every request, so it can never be used to run anything but those commands.
//

import Foundation
import PortHelperShared

private let portPath = "/opt/local/bin/port"

final class HelperService: NSObject, NSXPCListenerDelegate, PortHelperProtocol {
	
	/// MacPorts holds a lock while it works, so requests run one at a time.
	private let queue = DispatchQueue(label: "com.otstechs.macportsui.helper.port")
	
	// MARK: - Listener
	
	func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
		// Only the app, signed by the same team as this helper, may connect.
		guard let requirement = HelperConstants.requirement(identifier: HelperConstants.appIdentifier, teamIdentifier: CodeSigning.ownTeamIdentifier) else { return false }
		connection.setCodeSigningRequirement(requirement)
		connection.exportedInterface = makePortHelperInterface()
		connection.exportedObject = self
		connection.resume()
		return true
	}
	
	// MARK: - Protocol
	
	func protocolVersion(reply: @escaping (String) -> Void) {
		reply(HelperConstants.protocolVersion)
	}
	
	func runPort(arguments: [String], receiver: PortOutputReceiver, reply: @escaping (Int32, String) -> Void) {
		guard PortAction(arguments: arguments) != nil else {
			reply(-1, "Rejected: not an allowed port action.")
			return
		}
		
		queue.async {
			guard FileManager.default.isExecutableFile(atPath: portPath) else {
				reply(-1, "MacPorts was not found at \(portPath).")
				return
			}
			
			let process = Process()
			process.executableURL = URL(fileURLWithPath: portPath)
			process.arguments = arguments
			process.environment = ["PATH": "/opt/local/bin:/opt/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin", "HOME": "/var/root", "LANG": "en_US.UTF-8"]
			process.currentDirectoryURL = URL(fileURLWithPath: "/")
			
			let pipe = Pipe()
			process.standardOutput = pipe
			process.standardError = pipe
			
			do {
				try process.run()
			} catch {
				reply(-1, error.localizedDescription)
				return
			}
			
			// Send output to the app as it arrives and keep the complete text for the reply.
			let handle = pipe.fileHandleForReading
			let finished = DispatchSemaphore(value: 0)
			var collected = Data()
			handle.readabilityHandler = { handle in
				let data = handle.availableData
				if data.isEmpty {
					handle.readabilityHandler = nil
					finished.signal()
					return
				}
				collected.append(data)
				receiver.receive(output: String(decoding: data, as: UTF8.self))
			}
			process.waitUntilExit()
			finished.wait()
			reply(process.terminationStatus, String(decoding: collected, as: UTF8.self))
		}
	}
	
}

let service = HelperService()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = service
listener.resume()
RunLoop.main.run()
