//
//  HelperProtocol.swift
//  MacPortsKit
//
//  Shared by the app and the privileged helper.
//

import Foundation
import Security

public enum HelperConstants {
	
	/// The launchd label and Mach service name of the helper.
	public static let machServiceName = "com.otstechs.macportsui.helper"
	
	/// The launch daemon property list embedded in the app at `Contents/Library/LaunchDaemons`.
	public static let daemonPlistName = "com.otstechs.macportsui.helper.plist"
	
	/// The bundle identifier of the app that is allowed to talk to the helper.
	public static let appIdentifier = "com.otstechs.macportsui"
	
	/// The code signing identifier of the helper executable.
	public static let helperIdentifier = "com.otstechs.macportsui.helper"
	
	/// Bump when the protocol changes, so the app can tell an outdated helper from a current one.
	public static let protocolVersion = "1"
	
	/// The code signing requirement a peer must satisfy: signed by the given team with the given identifier.
	///
	/// Returns `nil` without a team identifier, which means ad-hoc signed builds never get privileged access.
	public static func requirement(identifier: String, teamIdentifier: String?) -> String? {
		guard let team = teamIdentifier, team.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil else { return nil }
		return "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
	}
	
}

/// What the app can ask the helper to do.
@objc public protocol PortHelperProtocol {
	
	/// The protocol version the helper implements.
	func protocolVersion(reply: @escaping (String) -> Void)
	
	/// Runs `port` with the given arguments, if they are one of the allowed `PortAction` shapes, and returns the exit status and combined output.
	func runPort(arguments: [String], reply: @escaping (Int32, String) -> Void)
	
}

public enum CodeSigning {
	
	/// The team identifier the running executable was signed with, if any.
	public static var ownTeamIdentifier: String? {
		var code: SecCode?
		var staticCode: SecStaticCode?
		var information: CFDictionary?
		guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
			  SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
			  SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
			  let dictionary = information as? [String: Any] else { return nil }
		return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
	}
	
}
