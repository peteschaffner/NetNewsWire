//
//  TimelineCellAppearance.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 2/6/16.
//  Copyright © 2016 Ranchero Software, LLC. All rights reserved.
//

import AppKit

struct TimelineCellAppearance: Equatable {

	let showIcon: Bool

	let cellPadding: NSEdgeInsets
	
	let feedNameFont: NSFont

	let dateFont: NSFont
	let dateMarginLeft: CGFloat = 8.0

	let titleFont: NSFont
	let titleBottomMargin: CGFloat = 2.0
	let textBottomMargin: CGFloat = 7
	let titleNumberOfLines = 3
	
	let textFont: NSFont

	let textOnlyFont: NSFont

	let unreadCircleDimension: CGFloat = 8.0
	let unreadCircleMarginRight: CGFloat = 8.0

	let starDimension: CGFloat = 13.0

	let drawsGrid = true

	let iconSize = NSSize(width: 48, height: 48)
	let iconMarginLeft: CGFloat = 8.0
	let iconMarginRight: CGFloat = 8.0
	let iconAdjustmentTop: CGFloat = 4.0
	let iconCornerRadius: CGFloat = 4.0

	let boxLeftMargin: CGFloat

	init(showIcon: Bool, fontSize: FontSize) {
		self.feedNameFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
		self.dateFont = self.feedNameFont
		
		self.titleFont = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
		self.textFont =  NSFont.systemFont(ofSize: NSFont.systemFontSize)
		self.textOnlyFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)

		self.showIcon = showIcon
		
		cellPadding = NSEdgeInsets(top: 8.0, left: 4.0, bottom: 10.0, right: 4.0)

		let margin = self.cellPadding.left + self.unreadCircleDimension + self.unreadCircleMarginRight
		self.boxLeftMargin = margin
	}
}

extension NSEdgeInsets: Equatable {

	public static func ==(lhs: NSEdgeInsets, rhs: NSEdgeInsets) -> Bool {
		return lhs.left == rhs.left && lhs.top == rhs.top && lhs.right == rhs.right && lhs.bottom == rhs.bottom
	}
}
