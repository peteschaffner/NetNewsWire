//
//  DeleteFromSidebarCommand.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 11/4/17.
//  Copyright © 2017 Ranchero Software. All rights reserved.
//

import Foundation
import RSCore
import RSTree
import Account
import Articles

@MainActor final class DeleteCommand: UndoableCommand {

	let treeController: TreeController?
	let undoManager: UndoManager
	let undoActionName: String
	var redoActionName: String {
		return undoActionName
	}
	let errorHandler: (Error) -> ()

	private let itemSpecifiers: [SidebarItemSpecifier]

	init?(nodesToDelete: [Node], treeController: TreeController? = nil, undoManager: UndoManager, errorHandler: @escaping (Error) -> ()) {

		guard DeleteCommand.canDelete(nodesToDelete) else {
			return nil
		}
		guard let actionName = DeleteActionName.name(for: nodesToDelete) else {
			return nil
		}

		self.treeController = treeController
		self.undoActionName = actionName
		self.undoManager = undoManager
		self.errorHandler = errorHandler

		let itemSpecifiers = nodesToDelete.compactMap{ SidebarItemSpecifier(node: $0, errorHandler: errorHandler) }
		guard !itemSpecifiers.isEmpty else {
			return nil
		}
		self.itemSpecifiers = itemSpecifiers
	}

	func perform() {
		
		let group = DispatchGroup()
		for itemSpecifier in itemSpecifiers {
			group.enter()
			itemSpecifier.delete() {
				group.leave()
			}
		}
	
		group.notify(queue: DispatchQueue.main) {
			self.treeController?.rebuild()
			self.registerUndo()
		}
		
	}
	
	func undo() {
		for itemSpecifier in itemSpecifiers {
			itemSpecifier.restore()
		}
		registerRedo()
	}

	static func canDelete(_ nodes: [Node]) -> Bool {

		// Return true if all nodes are feeds and folders.
		// Any other type: return false.

		if nodes.isEmpty {
			return false
		}

		for node in nodes {
			if let _ = node.representedObject as? Feed {
				continue
			}
			if let _ = node.representedObject as? Folder {
				continue
			}
			return false
		}

		return true
	}
}

// Remember as much as we can now about the items being deleted,
// so they can be restored to the correct place.

private struct SidebarItemSpecifier {

	private weak var account: Account?
	private let parentFolder: Folder?
	private let folder: Folder?
	private let feed: Feed?
	private let path: ContainerPath
	private let errorHandler: (Error) -> ()

	private var container: Container? {
		if let parentFolder = parentFolder {
			return parentFolder
		}
		if let account = account {
			return account
		}
		return nil
	}

	@MainActor init?(node: Node, errorHandler: @escaping (Error) -> ()) {

		var account: Account?

		self.parentFolder = node.parentFolder()

		if let feed = node.representedObject as? Feed {
			self.feed = feed
			self.folder = nil
			account = feed.account
		}
		else if let folder = node.representedObject as? Folder {
			self.feed = nil
			self.folder = folder
			account = folder.account
		}
		else {
			return nil
		}
		if account == nil {
			return nil
		}

		self.account = account!
		self.path = ContainerPath(account: account!, folders: node.containingFolders())
		
		self.errorHandler = errorHandler
		
	}

	@MainActor func delete(completion: @escaping () -> Void) {

		if let feed {
			
			guard let container = path.resolveContainer() else {
				completion()
				return
			}
			
			BatchUpdate.shared.start()
			account?.removeFeed(feed, from: container) { result in
				BatchUpdate.shared.end()
				completion()
				self.checkResult(result)
			}
			
		} else if let folder = folder {
			
			BatchUpdate.shared.start()
			account?.removeFolder(folder) { result in
				BatchUpdate.shared.end()
				completion()
				self.checkResult(result)
			}
			
		}
	}

	@MainActor func restore() {

		if let _ = feed {
			restoreFeed()
		}
		else if let _ = folder {
			restoreFolder()
		}
	}

	@MainActor private func restoreFeed() {

		guard let account = account, let feed = feed, let container = path.resolveContainer() else {
			return
		}
		
		BatchUpdate.shared.start()
		account.restoreFeed(feed, container: container) { result in
			BatchUpdate.shared.end()
			self.checkResult(result)
		}
		
	}

	@MainActor private func restoreFolder() {

		guard let account = account, let folder = folder else {
			return
		}
		
		BatchUpdate.shared.start()
		account.restoreFolder(folder) { result in
			BatchUpdate.shared.end()
			self.checkResult(result)
		}
		
	}

	private func checkResult(_ result: Result<Void, Error>) {
		
		switch result {
		case .success:
			break
		case .failure(let error):
			errorHandler(error)
		}

	}
	
}

private extension Node {
	
	func parentFolder() -> Folder? {

		guard let parentNode = self.parent else {
			return nil
		}
		if parentNode.isRoot {
			return nil
		}
		if let folder = parentNode.representedObject as? Folder {
			return folder
		}
		return nil
	}

	func containingFolders() -> [Folder] {

		var nomad = self.parent
		var folders = [Folder]()

		while nomad != nil {
			if let folder = nomad!.representedObject as? Folder {
				folders += [folder]
			}
			else {
				break
			}
			nomad = nomad!.parent
		}

		return folders.reversed()
	}

}

private struct DeleteActionName {

	private static let deleteFeed = NSLocalizedString("button.title.delete-feed", comment: "Delete Feed")
	private static let deleteFeeds = NSLocalizedString("button.title.delete-feeds", comment: "Delete Feeds")
	private static let deleteFolder = NSLocalizedString("button.title.delete-folder", comment: "Delete Folder")
	private static let deleteFolders = NSLocalizedString("button.title.delete-folders", comment: "Delete Folders")
	private static let deleteFeedsAndFolders = NSLocalizedString("button.title.delete-feeds-and-folders", comment: "Delete Feeds and Folders")

	static func name(for nodes: [Node]) -> String? {

		var numberOfFeeds = 0
		var numberOfFolders = 0

		for node in nodes {
			if let _ = node.representedObject as? Feed {
				numberOfFeeds += 1
			}
			else if let _ = node.representedObject as? Folder {
				numberOfFolders += 1
			}
			else {
				return nil // Delete only Feeds and Folders.
			}
		}

		if numberOfFolders < 1 {
			return numberOfFeeds == 1 ? deleteFeed : deleteFeeds
		}
		if numberOfFeeds < 1 {
			return numberOfFolders == 1 ? deleteFolder : deleteFolders
		}

		return deleteFeedsAndFolders
	}
}
