//
//  DetailStatusBarView.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 12/16/17.
//  Copyright © 2017 Ranchero Software. All rights reserved.
//

import AppKit
import Articles

final class DetailStatusBarView: NSVisualEffectView {

	@IBOutlet var urlLabel: NSTextField!

	override func awakeFromNib() {
		super.awakeFromNib()

		wantsLayer = true
		layer?.cornerRadius = 4
		layer?.cornerCurve = .continuous

		blendingMode = .withinWindow
		material = .menu
		state = .followsWindowActiveState
	}

	var mouseoverLink: String? {
		didSet {
			updateLinkForDisplay()
		}
	}

	private var linkForDisplay: String? {
		didSet {
			if let link = linkForDisplay {
				urlLabel.stringValue = link
				self.isHidden = false
			}
			else {
				urlLabel.stringValue = ""
				self.isHidden = true
			}
		}
	}
}

// MARK: - Private

private extension DetailStatusBarView {

	func updateLinkForDisplay() {
		if let mouseoverLink = mouseoverLink, !mouseoverLink.isEmpty {
			linkForDisplay = mouseoverLink.strippingHTTPOrHTTPSScheme
		}
		else {
			linkForDisplay = nil
		}
	}
}


