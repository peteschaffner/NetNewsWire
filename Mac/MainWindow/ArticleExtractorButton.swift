//
//  ArticleExtractorButton.swift
//  NetNewsWire
//
//  Created by Maurice Parker on 8/10/20.
//  Copyright © 2020 Ranchero Software. All rights reserved.
//

import AppKit

enum ArticleExtractorButtonState {
	case error
	case animated
	case on
	case off
}

@MainActor final class ArticleExtractorButton: NSButton {
	
	public var rightClickAction: Selector?
	private var spinner: NSProgressIndicator!
	
	var buttonState: ArticleExtractorButtonState = .off {
			didSet {
				if buttonState != oldValue {
					switch buttonState {
					case .error:
						spinner.isHidden = true
						spinner.stopAnimation(nil)
						self.image = AppAssets.articleExtractorError
						self.state = .off
					case .animated:
						spinner.isHidden = false
						spinner.startAnimation(nil)
						self.image = nil
						self.state = .on
					case .on:
						spinner.isHidden = true
						spinner.stopAnimation(nil)
						self.image = AppAssets.articleExtractorOn
						self.state = .on
					case .off:
						spinner.isHidden = true
						spinner.stopAnimation(nil)
						self.image = AppAssets.articleExtractorOff
						self.state = .off
					}
				}
			}
		}
	
	override func accessibilityLabel() -> String? {
		switch buttonState {
		case .error:
			return NSLocalizedString("label.text.error-reader-view", comment: "Error - Reader View")
		case .animated:
			return NSLocalizedString("label.text.processing-reader-view", comment: "Processing - Reader View")
		case .on:
			return NSLocalizedString("label.text.selected-reader-view", comment: "Selected - Reader View")
		case .off:
			return NSLocalizedString("label.text.reader-view", comment: "Reader View")
		}
	}

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		commonInit()
	}
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
		commonInit()
	}
	
	private func commonInit() {
		spinner = NSProgressIndicator(frame: self.bounds)
		spinner.style = .spinning
		spinner.controlSize = .small
		self.addSubview(spinner)
		spinner.translatesAutoresizingMaskIntoConstraints = false
		spinner.centerXAnchor.constraint(equalTo: self.centerXAnchor).isActive = true
		spinner.centerYAnchor.constraint(equalTo: self.centerYAnchor).isActive = true
		spinner.isHidden = true
		
		self.bezelStyle = .texturedRounded
		self.setButtonType(.toggle)
		self.image = AppAssets.articleExtractorOff
		self.imageScaling = .scaleProportionallyDown
	}
	
}
