//
//  FootnotePopoverViewController.swift
//  NetNewsWire
//
//  Created by Peter Schaffner on 15/07/2021.
//  Copyright © 2021 Ranchero Software. All rights reserved.
//

import Cocoa

class FootnotePopoverViewController: NSViewController, NSPopoverDelegate {

	@IBOutlet private var footnoteLabel: NSTextField!

	var footnoteText: String? {
		didSet {
			if let footnoteText = footnoteText {
				let sanitizedFootnote = footnoteText.replacingOccurrences(of: "(?s)↩.*", with: "", options: .regularExpression)
				footnoteLabel.stringValue = sanitizedFootnote
			} else {
				footnoteLabel.stringValue = "No footnote found."
			}
		}
	}

	init() {
		super.init(nibName: "FootnotePopover", bundle: nil)
		// force the view hierarchy to load so we have access to the label outlet
		loadView()
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}


	func popoverWillShow(_ notification: Notification) {
		if let popover = notification.object as? NSPopover {
			popover.backgroundColor = .textBackgroundColor
		}
	}

	func popoverWillClose(_ notification: Notification) {
		if let popover = notification.object as? NSPopover {
			popover.animates = false
		}
	}
    
}
