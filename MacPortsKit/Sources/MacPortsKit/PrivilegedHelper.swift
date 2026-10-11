//
//  PrivilegedHelper.swift
//  MacPortsKit
//

import Foundation
import ServiceManagement
import Security
@_exported import PortHelperShared

/// Manages the optional privileged helper that lets the app run MacPorts changes without asking for the administrator password each time.
///
/// The helper is a launch daemon embedded in the app. The user approves it once in System Settings > General > Login Items & Extensions.
/// It only exists in builds signed with a developer team (see scripts/make-app.sh); everything else falls back to the password prompt.
enum PrivilegedHelper {
	
	enum Status: Equatable {
		/// The helper cannot be used in this build. The reason can be shown to the user.
		case unavailable(reason: String)
		
		/// The helper is bundled but not registered.
		case notRegistered
		
		/// Registered; waiting for the user to approve it in System Settings.
		case requiresApproval
		
		/// Registered and approved.
		case enabled
	}
	
	/// User defaults key recording that the user turned the helper on.
	static let optInKey = "UsePrivilegedHelper"
	
	static var isOptedIn: Bool {
		UserDefaults.standard.bool(forKey: optInKey)
	}
	
	
	// MARK: - Status
	
	static var ownTeamIdentifier: String? { CodeSigning.ownTeamIdentifier }
	
	static var status: Status {
		guard #available(macOS 13.0, *) else {
			return .unavailable(reason: "Requires macOS 13 or later.")
		}
		let plist = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LaunchDaemons/\(HelperConstants.daemonPlistName)")
		guard FileManager.default.fileExists(atPath: plist.path) else {
			return .unavailable(reason: "This build does not include the helper. Build with the release script and a signing identity.")
		}
		guard HelperConstants.requirement(identifier: HelperConstants.helperIdentifier, teamIdentifier: ownTeamIdentifier) != nil else {
			return .unavailable(reason: "This build is not signed with a developer team.")
		}
		
		switch SMAppService.daemon(plistName: HelperConstants.daemonPlistName).status {
		case .enabled: return .enabled
		case .requiresApproval: return .requiresApproval
		// `.notFound` is also what a valid daemon reports before it has ever been registered. Let the user try; `register()` reports the real error.
		default: return .notRegistered
		}
	}
	
	
	// MARK: - Enabling
	
	/// Registers the helper. If macOS needs the user's approval, the status becomes `requiresApproval`.
	static func enable() throws {
		guard #available(macOS 13.0, *) else { return }
		UserDefaults.standard.set(true, forKey: optInKey)
		let service = SMAppService.daemon(plistName: HelperConstants.daemonPlistName)
		do {
			try service.register()
		} catch {
			// When the user still has to approve the helper, `register()` throws "Operation not permitted" although registration worked. That is not a failure.
			if service.status == .requiresApproval { return }
			throw error
		}
	}
	
	static func disable() {
		UserDefaults.standard.set(false, forKey: optInKey)
		guard #available(macOS 13.0, *) else { return }
		try? SMAppService.daemon(plistName: HelperConstants.daemonPlistName).unregister()
	}
	
	/// Opens System Settings on the Login Items page, where the helper can be approved.
	static func openSystemSettings() {
		if #available(macOS 13.0, *) { SMAppService.openSystemSettingsLoginItems() }
	}
	
	
	// MARK: - Running
	
	/// Runs the actions through the helper. Returns `nil` if the helper cannot be reached, so the caller can fall back to the password prompt.
	static func run(_ actions: [PortAction], onOutput: ((String) -> Void)? = nil) -> [CommandRunner.Result]? {
		guard #available(macOS 13.0, *),
			  let requirement = HelperConstants.requirement(identifier: HelperConstants.helperIdentifier, teamIdentifier: ownTeamIdentifier) else { return nil }
		
		let connection = NSXPCConnection(machServiceName: HelperConstants.machServiceName, options: .privileged)
		connection.remoteObjectInterface = makePortHelperInterface()
		connection.setCodeSigningRequirement(requirement)
		connection.resume()
		defer { connection.invalidate() }
		
		// A helper left over from an older build cannot stream; the caller falls back to the password prompt until it is re-enabled.
		let versionSemaphore = DispatchSemaphore(value: 0)
		var helperVersion: String?
		let versionProxy = connection.remoteObjectProxyWithErrorHandler { _ in versionSemaphore.signal() } as? PortHelperProtocol
		versionProxy?.protocolVersion { helperVersion = $0; versionSemaphore.signal() }
		versionSemaphore.wait()
		guard helperVersion == HelperConstants.protocolVersion else { return nil }
		
		let receiver = OutputReceiver(handler: onOutput)
		var results = [CommandRunner.Result]()
		for action in actions {
			guard let arguments = action.arguments else { return results.isEmpty ? nil : results + [.init(status: -1, output: "Invalid port action.")] }
			
			let semaphore = DispatchSemaphore(value: 0)
			var result: CommandRunner.Result?
			let proxy = connection.remoteObjectProxyWithErrorHandler { _ in semaphore.signal() } as? PortHelperProtocol
			proxy?.runPort(arguments: arguments, receiver: receiver) { status, output in
				result = CommandRunner.Result(status: status, output: output)
				semaphore.signal()
			}
			semaphore.wait()
			
			guard let result else { return results.isEmpty ? nil : results }
			results.append(result)
		}
		return results
	}
	
}

/// Runs actions through the helper, falling back to the password prompt if the helper is not reachable.
struct HelperPortRunner: PrivilegedPortRunner {
	
	func run(_ actions: [PortAction], onOutput: ((String) -> Void)?) -> [CommandRunner.Result] {
		PrivilegedHelper.run(actions, onOutput: onOutput) ?? PromptingPortRunner().run(actions, onOutput: onOutput)
	}
	
}

/// Forwards output from the helper to a closure.
private final class OutputReceiver: NSObject, PortOutputReceiver {
	
	private let handler: ((String) -> Void)?
	
	init(handler: ((String) -> Void)?) { self.handler = handler }
	
	func receive(output: String) { handler?(output) }
	
}
