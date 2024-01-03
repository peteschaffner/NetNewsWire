//
//  ArticleExtractor.swift
//  NetNewsWire
//
//  Created by Maurice Parker on 9/18/19.
//  Copyright © 2019 Ranchero Software. All rights reserved.
//

import Foundation
import Account
import Secrets
import WebKit

public enum ArticleExtractorState {
	case ready
	case processing
	case failedToParse
	case complete
	case cancelled
}

protocol ArticleExtractorDelegate {
	func articleExtractionDidFail(with: Error)
	func articleExtractionDidComplete(extractedArticle: ExtractedArticle)
}

class ArticleExtractor: NSObject, WKNavigationDelegate {
	
	private var dataTask: URLSessionDataTask? = nil
	
	var state: ArticleExtractorState!
	var article: ExtractedArticle?
	var delegate: ArticleExtractorDelegate?
	var articleLink: String!
	
	private var url: URL!
	private var webView: WKWebView!
	private var readabilityScript: String!
	
	public init?(_ articleLink: String) {
		super.init()
		
		self.articleLink = articleLink
		self.readabilityScript = try! String(contentsOfFile: Bundle.main.path(forResource: "Readability", ofType: "js")!)
		self.webView = WKWebView()
		self.webView.navigationDelegate = self
	}
	
	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		let jsFilePath = Bundle.main.path(forResource: "Readability", ofType: "js")!
		var readabilityJsString = try! String(contentsOfFile: jsFilePath)
		
		readabilityJsString.append(contentsOf: "JSON.stringify(new Readability(document).parse())")
		
		webView.evaluateJavaScript(readabilityJsString) { result, error in
			if let error = error {
				self.state = .failedToParse
				DispatchQueue.main.async {
					self.delegate?.articleExtractionDidFail(with: error)
				}
				return
			}
			
			guard let result = (result as? String)?.data(using: .utf8) else {
				self.state = .failedToParse
				DispatchQueue.main.async {
					self.delegate?.articleExtractionDidFail(with: URLError(.cannotDecodeContentData)) // TODO: find appropriate error to use here
				}
				return
			}
			
			do {
				let decoder = JSONDecoder()
				self.article = try decoder.decode(ExtractedArticle.self, from: result)
				
				DispatchQueue.main.async {
					if self.article?.content == nil {
						self.state = .failedToParse
						self.delegate?.articleExtractionDidFail(with: URLError(.cannotDecodeContentData))
					} else {
						self.state = .complete
						self.delegate?.articleExtractionDidComplete(extractedArticle: self.article!)
					}
				}
			} catch {
				self.state = .failedToParse
				DispatchQueue.main.async {
					self.delegate?.articleExtractionDidFail(with: error)
				}
			}
			
		}
	}
	
	public func process() {
		state = .processing
		self.webView.load(URLRequest(url: URL(string: articleLink)!))
	}
	
	public func cancel() {
		state = .cancelled
	}
	
}
