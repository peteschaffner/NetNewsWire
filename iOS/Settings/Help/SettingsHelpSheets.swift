//
//  SettingsHelpSheets.swift
//  NetNewsWire-iOS
//
//  Created by Stuart Breckenridge on 12/11/2022.
//  Copyright © 2022 Ranchero Software. All rights reserved.
//

import Foundation


public enum HelpSheet: CustomStringConvertible, CaseIterable {
	
	case help, website
	
	public var description: String {
		switch self {
		case .help:
			return NSLocalizedString("button.title.netnewswire-help", comment: "NetNewsWire Help")
		case .website:
			return NSLocalizedString("button.title.netnewswire-website", comment: "NetNewsWire Website")
		}
	}
	
	public var url: URL {
		switch self {
		case .help:
			return URL(string: "https://netnewswire.com/help/ios/6.1/en/")!
		case .website:
			return URL(string: "https://netnewswire.com/")!
		}
	}
	
	public var systemImage: String {
		switch self {
		case .help:
			return "questionmark.circle.fill"
		case .website:
			return "safari.fill"
		}
	}
}
