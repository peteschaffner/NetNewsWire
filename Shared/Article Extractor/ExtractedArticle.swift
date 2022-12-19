//
//  ExtractedArticle.swift
//  NetNewsWire
//
//  Created by Maurice Parker on 9/18/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import Foundation

struct ExtractedArticle: Codable, Equatable {

	let title: String?
	let content: String?
	let textContent: String?
	let length: Int?
	let excerpt: String?
	let byline: String?
	let dir: String?
	let siteName: String?
	
	enum CodingKeys: String, CodingKey {
		case title
		case content
		case textContent
		case length
		case excerpt
		case byline
		case dir
		case siteName
	}
	
}
