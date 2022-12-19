//
//  NSPopover+Background.swift
//  NSPopover+Background
//
//  Created by Peter Schaffner on 23/07/2021.
//  Copyright © 2021 Ranchero Software. All rights reserved.
//

import Cocoa

let backgroundViewTag = 999

extension NSPopover {
	public var backgroundColor: NSColor? {
		get {
			if let backgroundView = self.backgroundView(), let color = backgroundView.layer?.backgroundColor {
				return NSColor(cgColor: color)
			}
			return nil
		}
		set {
			if let backgroundView = self.backgroundView() {
				backgroundView.backgroundColor = newValue
			}
		}
	}

	func backgroundView() -> BackgroundView? {
		if let view = self.contentViewController?.view.superview?.viewWithTag(backgroundViewTag) as? BackgroundView {
			return view
		}

		if let frameView = self.contentViewController?.view.superview {
			let backgroundView = BackgroundView(frame: frameView.bounds)
			frameView.addSubview(backgroundView, positioned: NSWindow.OrderingMode.below, relativeTo: self.contentViewController?.view)
			return backgroundView
		}

		return nil
	}
}

class BackgroundView: NSView {
	var backgroundColor: NSColor? {
		didSet {
			needsDisplay = true
		}
	}

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)

		self.wantsLayer = true
		self.autoresizingMask = NSView.AutoresizingMask.width.union(NSView.AutoresizingMask.height)
	}

	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}

	override var tag: Int {
		return backgroundViewTag
	}

	override var wantsUpdateLayer: Bool { true }

	override func updateLayer() {
		layer?.backgroundColor = backgroundColor?.cgColor
	}
}

