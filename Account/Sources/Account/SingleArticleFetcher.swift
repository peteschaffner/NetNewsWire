//
//  SingleArticleFetcher.swift
//  Account
//
//  Created by Maurice Parker on 11/29/19.
//  Copyright © 2019 Ranchero Software, LLC. All rights reserved.
//

import Foundation
import Articles
import ArticlesDatabase

public struct SingleArticleFetcher: ArticleFetcher {
	
	private let account: Account
	private let articleID: String
	
	public init(account: Account, articleID: String) {
		self.account = account
		self.articleID = articleID
	}
	
    @MainActor public func fetchArticles() throws -> Set<Article> {
		return try account.fetchArticles(.articleIDs(Set([articleID])))
	}
	
	public func fetchArticlesAsync(_ completion: @escaping ArticleSetResultBlock) {
		return account.fetchArticlesAsync(.articleIDs(Set([articleID])), completion)
	}
	
    @MainActor public func fetchUnreadArticles() throws -> Set<Article> {
		return try account.fetchArticles(.articleIDs(Set([articleID])))
	}

	public func fetchUnreadArticlesBetween(before: Date? = nil, after: Date? = nil) throws -> Set<Article> {
		return try account.fetchArticlesBetween(articleIDs: Set([articleID]), before: before, after: after)
	}
	
	public func fetchUnreadArticlesAsync(_ completion: @escaping ArticleSetResultBlock) {
		return account.fetchArticlesAsync(.articleIDs(Set([articleID])), completion)
	}
	
}
