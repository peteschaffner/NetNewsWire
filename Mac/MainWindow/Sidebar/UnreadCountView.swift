//
//  UnreadCountView.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 11/22/15.
//  Copyright © 2015 Ranchero Software, LLC. All rights reserved.
//

import AppKit

class UnreadCountView : NSImageView {
	
	struct Appearance {
		static let padding = NSEdgeInsets(top: 1.0, left: 7.0, bottom: 1.0, right: 7.0)
		static let cornerRadius: CGFloat = 8.0
		static let backgroundColor = NSColor.secondaryLabelColor
		static let textSize: CGFloat = 11.0
		static let textFont = NSFont.systemFont(ofSize: textSize, weight: NSFont.Weight.semibold)
		static let textAttributes: [NSAttributedString.Key: AnyObject] = [NSAttributedString.Key.foregroundColor: NSColor.black, NSAttributedString.Key.font: textFont, NSAttributedString.Key.kern: NSNull()]
	}
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}
	
	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		contentTintColor = Appearance.backgroundColor
	}
	
	var unreadCount = 0 {
		didSet {
			invalidateIntrinsicContentSize()
			needsDisplay = true
		}
	}
	var unreadCountString: String {
		return unreadCount < 1 ? "" : "\(unreadCount)"
	}
	
	private var intrinsicContentSizeIsValid = false
	private var _intrinsicContentSize = NSZeroSize
	
	override var intrinsicContentSize: NSSize {
		if !intrinsicContentSizeIsValid {
			var size = NSZeroSize
			if unreadCount > 0 {
				size = textSize()
				size.width += (Appearance.padding.left + Appearance.padding.right)
				size.height += (Appearance.padding.top + Appearance.padding.bottom)
			}
			_intrinsicContentSize = size
			intrinsicContentSizeIsValid = true
		}
		return _intrinsicContentSize
	}
	
	override var isFlipped: Bool {
		return true
	}
	
	override func invalidateIntrinsicContentSize() {
		intrinsicContentSizeIsValid = false
	}
	
	private static var textSizeCache = [Int: NSSize]()
	
	private func textSize() -> NSSize {
		if unreadCount < 1 {
			return NSZeroSize
		}
		
		if let cachedSize = UnreadCountView.textSizeCache[unreadCount] {
			return cachedSize
		}
		
		var size = unreadCountString.size(withAttributes: Appearance.textAttributes)
		size.height = ceil(size.height)
		size.width = ceil(size.width)
		
		UnreadCountView.textSizeCache[unreadCount] = size
		return size
	}
	
	private func textRect() -> NSRect {
		let size = textSize()
		var r = NSZeroRect
		r.size = size
		r.origin.x = (NSMaxX(bounds) - Appearance.padding.right) - r.size.width
		r.origin.y = Appearance.padding.top
		return r
	}
	
	override func viewWillDraw() {
		super.viewWillDraw()
		
		image = NSImage(size: bounds.size, flipped: true) { rect in
			if let context = NSGraphicsContext.current {
				let path = NSBezierPath(roundedRect: self.bounds, xRadius: Appearance.cornerRadius, yRadius: Appearance.cornerRadius)
				NSColor.black.setFill()
				path.fill()
				
				context.saveGraphicsState()
				
				NSGraphicsContext.current?.compositingOperation = .sourceOut
				if self.unreadCount > 0 {
					self.unreadCountString.draw(at: self.textRect().origin, withAttributes: Appearance.textAttributes)
				}
				
				context.restoreGraphicsState()
				return true
			}
			
			return false
		}
		
		image?.isTemplate = true
	}
}

