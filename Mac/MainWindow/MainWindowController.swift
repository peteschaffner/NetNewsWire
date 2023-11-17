//
//  MainWindowController.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 8/1/15.
//  Copyright © 2015 Ranchero Software, LLC. All rights reserved.
//

import AppKit
import UserNotifications
import Articles
import Account
import RSCore

enum TimelineSourceMode {
	case regular, search
}

@MainActor final class MainWindowController : NSWindowController, NSUserInterfaceValidations {

    @IBOutlet weak var articleThemePopUpButton: NSPopUpButton?
    
    private var activityManager = ActivityManager()

	private var isShowingExtractedArticle = false
	private var articleExtractor: ArticleExtractor? = nil
	private var sharingServicePickerDelegate: NSSharingServicePickerDelegate?

	private let windowAutosaveName = NSWindow.FrameAutosaveName("MainWindow")
	private static let mainWindowWidthsStateKey = "mainWindowWidthsStateKey"

	private var currentFeedOrFolder: AnyObject? {
		// Nil for none or multiple selection.
		guard let selectedObjects = selectedObjectsInSidebar(), selectedObjects.count == 1 else {
			return nil
		}
		return selectedObjects.first
	}
	
	private var shareToolbarItem: NSToolbarItem? {
		return window?.toolbar?.existingItem(withIdentifier: .share)
	}

	private static var detailViewMinimumThickness = 384
	private var sidebarViewController: SidebarViewController?
	private var timelineContainerViewController: TimelineContainerViewController?
	private var detailViewController: DetailViewController?
	private var currentSearchField: NSSearchField? = nil
	private let articleThemeMenuToolbarItem = NSMenuToolbarItem(itemIdentifier: .articleThemeMenu)
	private var searchString: String? = nil
	private var lastSentSearchString: String? = nil
	private var savedSearchArticles: ArticleArray? = nil
	private var savedSearchArticleIds: Set<String>? = nil
	private var timelineSourceMode: TimelineSourceMode = .regular {
		didSet {
			timelineContainerViewController?.showTimeline(for: timelineSourceMode)
			detailViewController?.showDetail(for: timelineSourceMode)
		}
	}
	private var searchSmartFeed: SmartFeed? = nil
	private var restoreArticleWindowScrollY: CGFloat?
	
	var shareMenu: NSMenu? {
		return currentTimelineViewController?.shareMenu
	}

	// MARK: - NSWindowController

	override func windowDidLoad() {
		super.windowDidLoad()

		sharingServicePickerDelegate = SharingServicePickerDelegate(self.window)
		
		updateArticleThemeMenu()

		let toolbar = NSToolbar(identifier: "MainWindowToolbar")
		toolbar.allowsUserCustomization = true
		toolbar.autosavesConfiguration = true
		toolbar.displayMode = .iconOnly
		toolbar.delegate = self
		self.window?.toolbar = toolbar
		
		if let window = window {
			let point = NSPoint(x: 128, y: 64)
			let size = NSSize(width: 1345, height: 900)
			let minSize = NSSize(width: 600, height: 600)
			window.setPointAndSizeAdjustingForScreen(point: point, size: size, minimumSize: minSize)
		}

		detailSplitViewItem?.minimumThickness = CGFloat(MainWindowController.detailViewMinimumThickness)

		let sidebarSplitViewItem = splitViewController?.splitViewItems[0]
		sidebarViewController = sidebarSplitViewItem?.viewController as? SidebarViewController
		sidebarViewController!.splitViewItem = sidebarSplitViewItem
		sidebarViewController!.delegate = self

		timelineContainerViewController = splitViewController?.splitViewItems[1].viewController as? TimelineContainerViewController
		timelineContainerViewController!.delegate = self

		detailViewController = splitViewController?.splitViewItems[2].viewController as? DetailViewController

		NotificationCenter.default.addObserver(self, selector: #selector(refreshProgressDidChange(_:)), name: .AccountRefreshDidBegin, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(refreshProgressDidChange(_:)), name: .AccountRefreshDidFinish, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(refreshProgressDidChange(_:)), name: .AccountRefreshProgressDidChange, object: nil)

		NotificationCenter.default.addObserver(self, selector: #selector(unreadCountDidChange(_:)), name: .UnreadCountDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(displayNameDidChange(_:)), name: .DisplayNameDidChange, object: nil)
		
		NotificationCenter.default.addObserver(self, selector: #selector(articleThemeNamesDidChangeNotification(_:)), name: .ArticleThemeNamesDidChangeNotification, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(currentArticleThemeDidChangeNotification(_:)), name: .CurrentArticleThemeDidChangeNotification, object: nil)

		Task { @MainActor in
			self.updateWindowTitle()
		}
	}

	// MARK: - API

	func selectedObjectsInSidebar() -> [AnyObject]? {
		return sidebarViewController?.selectedObjects
	}

	func handle(_ response: UNNotificationResponse) {
		let userInfo = response.notification.request.content.userInfo
		guard let articlePathUserInfo = userInfo[UserInfoKey.articlePath] as? [AnyHashable : Any] else { return }
		sidebarViewController?.deepLinkRevealAndSelect(for: articlePathUserInfo)
		currentTimelineViewController?.goToDeepLink(for: articlePathUserInfo)
	}

	func handle(_ activity: NSUserActivity) {
		guard let userInfo = activity.userInfo else { return }
		guard let articlePathUserInfo = userInfo[UserInfoKey.articlePath] as? [AnyHashable : Any] else { return }
		sidebarViewController?.deepLinkRevealAndSelect(for: articlePathUserInfo)
		currentTimelineViewController?.goToDeepLink(for: articlePathUserInfo)
	}

	func saveStateToUserDefaults() {
		AppDefaults.shared.windowState = savableState()
		window?.saveFrame(usingName: windowAutosaveName)
	}
	
	func restoreStateFromUserDefaults() {
		if let state = AppDefaults.shared.windowState {
			restoreState(from: state)
			window?.setFrameUsingName(windowAutosaveName, force: true)
		}
	}
	
	// MARK: - Notifications

	@objc func refreshProgressDidChange(_ note: Notification) {
		CoalescingQueue.standard.add(self, #selector(makeToolbarValidate))
	}

	@objc func unreadCountDidChange(_ note: Notification) {
		updateWindowTitleIfNecessary(note.object)
	}
	
	@objc func displayNameDidChange(_ note: Notification) {
		updateWindowTitleIfNecessary(note.object)
	}

	@objc func articleThemeNamesDidChangeNotification(_ note: Notification) {
		updateArticleThemeMenu()
	}

	@objc func currentArticleThemeDidChangeNotification(_ note: Notification) {
		updateArticleThemeMenu()
	}

	private func updateWindowTitleIfNecessary(_ noteObject: Any?) {
		
		if let folder = currentFeedOrFolder as? Folder, let noteObject = noteObject as? Folder {
			if folder == noteObject {
				updateWindowTitle()
				return
			}
		}
		
		if let feed = currentFeedOrFolder as? Feed, let noteObject = noteObject as? Feed {
			if feed == noteObject {
				updateWindowTitle()
				return
			}
		}
		
		// If we don't recognize the changed object, we will test it for identity instead
		// of equality.  This works well for us if the window title is displaying a
		// PsuedoFeed object.
		if let currentObject = currentFeedOrFolder, let noteObject = noteObject {
			if currentObject === noteObject as AnyObject {
				updateWindowTitle()
			}
		}
		
	}

	// MARK: - Toolbar
	
	@objc func makeToolbarValidate() {
		
		window?.toolbar?.validateVisibleItems()
	}

	// MARK: - NSUserInterfaceValidations
	
	public func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
		
		if item.action == #selector(copyArticleURL(_:)) {
			let canCopyArticleURL = canCopyArticleURL()

			if let item = item as? NSMenuItem {
				let format = NSLocalizedString("button.title.copy-article-url", comment: "Copy Article URL");

				item.title = String.localizedStringWithFormat(format, selectedArticles?.count ?? 0)
			}

			return canCopyArticleURL
		}
		
		if item.action == #selector(copyExternalURL(_:)) {
			return canCopyExternalURL()
		}
		
		if item.action == #selector(openArticleInBrowser(_:)) {
			if let item = item as? NSMenuItem, item.keyEquivalentModifierMask.contains(.shift) {
				item.title = Browser.titleForOpenInBrowserInverted
			}

			return currentLink != nil
		}
		
		if item.action == #selector(nextUnread(_:)) {
			return canGoToNextUnread(wrappingToTop: true)
		}
		
		if item.action == #selector(markAllAsRead(_:)) {
			return canMarkAllAsRead()
		}

		if item.action == #selector(markAboveAsRead(_:)) {
			return canMarkAboveAsRead()
		}

		if item.action == #selector(markBelowAsRead(_:)) {
			return canMarkBelowAsRead()
		}

		if item.action == #selector(toggleRead(_:)) {
			return validateToggleRead(item)
		}

		if item.action == #selector(toggleStarred(_:)) {
			return validateToggleStarred(item)
		}

		if item.action == #selector(markAboveArticlesAsRead(_:)) {
			return canMarkAboveArticlesAsRead()
		}

		if item.action == #selector(markBelowArticlesAsRead(_:)) {
			return canMarkBelowArticlesAsRead()
		}

		if item.action == #selector(toggleArticleExtractor(_:)) {
			return validateToggleArticleExtractor(item)
		}
		
		if item.action == #selector(toolbarShowShareMenu(_:)) {
			return canShowShareMenu()
		}

		if item.action == #selector(moveFocusToSearchField(_:)) {
			return currentSearchField != nil
		}

		if item.action == #selector(cleanUp(_:)) {
			return validateCleanUp(item)
		}

		if item.action == #selector(toggleReadFeedsFilter(_:)) {
			return validateToggleReadFeeds(item)
		}

		if item.action == #selector(toggleReadArticlesFilter(_:)) {
			return validateToggleReadArticles(item)
		}

		if item.action == #selector(toggleTheSidebar(_:)) {
			guard let splitViewItem = sidebarSplitViewItem else {
				return false
			}

			let sidebarIsShowing = !splitViewItem.isCollapsed
			if let menuItem = item as? NSMenuItem {
				let title = sidebarIsShowing ? NSLocalizedString("button.title.hide-sidebar", comment: "Hide Sidebar") : NSLocalizedString("button.title.show-sidebar", comment: "Show Sidebar")
				menuItem.title = title
			}

			return true
		}
		if item.action == #selector(performFindPanelAction(_:)) {
			return self.detailViewController?.currentWebViewController.canFindInArticle ?? false
		}
		
		return true
	}

	// MARK: - Actions

	@IBAction func scrollOrGoToNextUnread(_ sender: Any?) {
		guard let detailViewController = detailViewController else {
			return
		}

		Task { @MainActor in
			let canScroll = await detailViewController.canScrollDown()
			NSCursor.setHiddenUntilMouseMoves(true)
			if canScroll {
				detailViewController.scrollPageDown(sender)
			} else {
				nextUnread(sender)
			}
		}
	}

	@IBAction func scrollUp(_ sender: Any?) {
		guard let detailViewController = detailViewController else {
			return
		}

		Task { @MainActor in
			let canScroll = await detailViewController.canScrollUp()
			if canScroll {
				NSCursor.setHiddenUntilMouseMoves(true)
				detailViewController.scrollPageUp(sender)
			}
		}
	}

	@IBAction func copyArticleURL(_ sender: Any?) {
		if let currentLinks {
			URLPasteboardWriter.write(urlStrings: currentLinks, alertingIn: window)
		}
	}

	@IBAction func copyExternalURL(_ sender: Any?) {
		if let links = selectedArticles?.compactMap({ $0.externalLink }) {
			URLPasteboardWriter.write(urlStrings: links, to: .general)
		}
	}

	@IBAction func openArticleInBrowser(_ sender: Any?) {
		guard let selectedArticles else { return }
		let urlStrings = selectedArticles.compactMap { $0.preferredLink }
		Browser.open(urlStrings, fromWindow: window, invertPreference: NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false)
	}

	@IBAction func openInBrowser(_ sender: Any?) {
		if AppDefaults.shared.openInBrowserInBackground {
			window?.makeKeyAndOrderFront(self)
		}
		openArticleInBrowser(sender)
	}

	@objc func openInAppBrowser(_ sender: Any?) {
		// There is no In-App Browser for mac - so we use safari
		openArticleInBrowser(sender)
	}

	@IBAction func openInBrowserUsingOppositeOfSettings(_ sender: Any?) {
		if !AppDefaults.shared.openInBrowserInBackground {
			window?.makeKeyAndOrderFront(self)
		}
		if let link = currentLink {
			Browser.open(link, inBackground: !AppDefaults.shared.openInBrowserInBackground)
		}
	}

	@IBAction func nextUnread(_ sender: Any?) {
		guard let timelineViewController = currentTimelineViewController, let sidebarViewController = sidebarViewController else {
			return
		}

		NSCursor.setHiddenUntilMouseMoves(true)

		// TODO: handle search mode
		if timelineViewController.canGoToNextUnread(wrappingToTop: false) {
			goToNextUnreadInTimeline(wrappingToTop: false)
		}
		else if sidebarViewController.canGoToNextUnread(wrappingToTop: true) {
			sidebarViewController.goToNextUnread(wrappingToTop: true)

			// If we ended up on the same timelineViewController, we may need to wrap
			// around to the top of its contents.
			if timelineViewController.canGoToNextUnread(wrappingToTop: true) {
				goToNextUnreadInTimeline(wrappingToTop: true)
			}
		}
	}

	@IBAction func markAllAsRead(_ sender: Any?) {
		currentTimelineViewController?.markAllAsRead()
	}

	@IBAction func markAboveAsRead(_ sender: Any?) {
		currentTimelineViewController?.markAboveArticlesRead()
	}

	@IBAction func markBelowAsRead(_ sender: Any?) {
		currentTimelineViewController?.markBelowArticlesRead()
	}

	@IBAction func toggleRead(_ sender: Any?) {
		currentTimelineViewController?.toggleReadStatusForSelectedArticles()
	}

	@IBAction func markRead(_ sender: Any?) {
		currentTimelineViewController?.markSelectedArticlesAsRead(sender)
	}

	@IBAction func markUnread(_ sender: Any?) {
		currentTimelineViewController?.markSelectedArticlesAsUnread(sender)
	}

	@IBAction func toggleStarred(_ sender: Any?) {
		currentTimelineViewController?.toggleStarredStatusForSelectedArticles()
	}

	@IBAction func toggleArticleExtractor(_ sender: Any?) {
		
		guard let currentLink = currentLink, let article = oneSelectedArticle else {
			return
		}

		defer {
			makeToolbarValidate()
		}
		
		if articleExtractor?.state == .failedToParse {
			startArticleExtractorForCurrentLink()
			return
		}
		
		guard articleExtractor?.state != .processing else {
			articleExtractor?.cancel()
			articleExtractor = nil
			isShowingExtractedArticle = false
			detailViewController?.setState(DetailState.article(article, nil), mode: timelineSourceMode)
			return
		}
		
		guard !isShowingExtractedArticle else {
			isShowingExtractedArticle = false
			detailViewController?.setState(DetailState.article(article, nil), mode: timelineSourceMode)
			return
		}
		
		if let articleExtractor = articleExtractor, let extractedArticle = articleExtractor.article {
			if currentLink == articleExtractor.articleLink {
				isShowingExtractedArticle = true
				let detailState = DetailState.extracted(article, extractedArticle, nil)
				detailViewController?.setState(detailState, mode: timelineSourceMode)
			}
		} else {
			startArticleExtractorForCurrentLink()
		}
		
	}

	@IBAction func markAllAsReadAndGoToNextUnread(_ sender: Any?) {
		currentTimelineViewController?.markAllAsRead() {
			self.nextUnread(sender)
		}
	}

	@IBAction func markUnreadAndGoToNextUnread(_ sender: Any?) {
		markUnread(sender)
		nextUnread(sender)
	}

	@IBAction func markReadAndGoToNextUnread(_ sender: Any?) {
		markUnread(sender)
		nextUnread(sender)
	}

	@IBAction func toggleTheSidebar(_ sender: Any?) {
		splitViewController!.toggleSidebar(sender)
		guard let splitViewItem = sidebarSplitViewItem else { return }
		if splitViewItem.isCollapsed {
			currentTimelineViewController?.focus()
		} else {
			sidebarViewController?.focus()
		}
	}
	
	@IBAction func markOlderArticlesAsRead(_ sender: Any?) {
		currentTimelineViewController?.markOlderArticlesRead()
	}
	
	@IBAction func markAboveArticlesAsRead(_ sender: Any?) {
		currentTimelineViewController?.markAboveArticlesRead()
	}

	@IBAction func markBelowArticlesAsRead(_ sender: Any?) {
		currentTimelineViewController?.markBelowArticlesRead()
	}

	@IBAction func navigateToTimeline(_ sender: Any?) {
		currentTimelineViewController?.focus()
	}

	@IBAction func navigateToSidebar(_ sender: Any?) {
		sidebarViewController?.focus()
	}

	@IBAction func navigateToDetail(_ sender: Any?) {
		detailViewController?.focus()
	}
	
	@IBAction func goToPreviousSubscription(_ sender: Any?) {
		sidebarViewController?.outlineView.selectPreviousRow(sender)
	}

	@IBAction func goToNextSubscription(_ sender: Any?) {
		sidebarViewController?.outlineView.selectNextRow(sender)
	}

	@IBAction func gotoToday(_ sender: Any?) {
		sidebarViewController?.gotoToday(sender)
	}

	@IBAction func gotoAllUnread(_ sender: Any?) {
		sidebarViewController?.gotoAllUnread(sender)
	}

	@IBAction func gotoStarred(_ sender: Any?) {
		sidebarViewController?.gotoStarred(sender)
	}

	@IBAction func toolbarShowShareMenu(_ sender: Any?) {
		guard let selectedArticles = selectedArticles, !selectedArticles.isEmpty else {
			assertionFailure("Expected toolbarShowShareMenu to be called only when there are selected articles.")
			return
		}
		guard let shareToolbarItem = shareToolbarItem else {
			assertionFailure("Expected toolbarShowShareMenu to be called only by the Share item in the toolbar.")
			return
		}

		let sortedArticles = selectedArticles.sortedByDate(.orderedAscending)
		let items = sortedArticles.map { ArticlePasteboardWriter(article: $0) }
		let sharingServicePicker = NSSharingServicePicker(items: items)
		sharingServicePicker.delegate = sharingServicePickerDelegate
		
		if let view = shareToolbarItem.view, view.window != nil {
			sharingServicePicker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
		} else if let view = window?.contentView {
			sharingServicePicker.show(relativeTo: CGRect(x: view.frame.width / 2.0, y: view.frame.height - 4, width: 1, height: 1), of: view, preferredEdge: .minY)
		}
	}

	@IBAction func moveFocusToSearchField(_ sender: Any?) {
		guard let searchField = currentSearchField else {
			return
		}
		window?.makeFirstResponder(searchField)
	}

	@IBAction func cleanUp(_ sender: Any?) {
		timelineContainerViewController?.cleanUp()
	}
	
	@IBAction func toggleReadFeedsFilter(_ sender: Any?) {
		sidebarViewController?.toggleReadFilter()
	}
	
	@IBAction func toggleReadArticlesFilter(_ sender: Any?) {
		timelineContainerViewController?.toggleReadFilter()
	}

	@IBAction  func performFindPanelAction(_ sender: Any?) {
		self.detailViewController?.performFindPanelAction(sender)
	}
	
	@objc func showArticleExtractorMenu(_ button: NSButton) {
		guard oneSelectedArticle?.feed != nil else {
			return
		}

		let menu = NSMenu()

		let alwaysUseReaderViewItem = NSMenuItem()
		alwaysUseReaderViewItem.title = NSLocalizedString("button.title.always-use-reader-view", comment: "Always Use Reader View")
		alwaysUseReaderViewItem.target = self
		alwaysUseReaderViewItem.action = #selector(alwaysUseReaderView)
		alwaysUseReaderViewItem.state = {
			if oneSelectedArticle?.feed?.isArticleExtractorAlwaysOn ?? false {
				return NSControl.StateValue.on
			} else {
				return NSControl.StateValue.off
			}
		}()
		
		menu.addItem(alwaysUseReaderViewItem)

		menu.popUp(positioning: alwaysUseReaderViewItem, at: button.frame.origin, in: button)
	}

	@objc func alwaysUseReaderView() {
		guard let feed = oneSelectedArticle?.feed else {
			return
		}
		
		if feed.isArticleExtractorAlwaysOn == nil { feed.isArticleExtractorAlwaysOn = false }
		feed.isArticleExtractorAlwaysOn?.toggle()
		NotificationCenter.default.post(Notification(name: .DidUpdateFeedPreferencesFromContextMenu))
	}
	
	@objc func selectArticleTheme(_ menuItem: NSMenuItem) {
		ArticleThemesManager.shared.currentThemeName = menuItem.title
	}
	
}

// MARK: NSWindowDelegate

extension MainWindowController: NSWindowDelegate {
	
	func window(_ window: NSWindow, willEncodeRestorableState coder: NSCoder) {
		coder.encode(savableState(), forKey: UserInfoKey.windowState)
	}

	func window(_ window: NSWindow, didDecodeRestorableState coder: NSCoder) {
		guard let state = try? coder.decodeTopLevelObject(forKey: UserInfoKey.windowState) as? [AnyHashable : Any] else { return }
		restoreState(from: state)
	}

	func windowWillClose(_ notification: Notification) {
		detailViewController?.stopMediaPlayback()
		appDelegate.removeMainWindow(self)
	}
	
}

// MARK: - SidebarDelegate

extension MainWindowController: SidebarDelegate {

	var directlyMarkedAsUnreadArticles: Set<Article>? {
		return timelineContainerViewController?.currentTimelineViewController?.directlyMarkedAsUnreadArticles
	}
	
	func sidebarSelectionDidChange(_: SidebarViewController, selectedObjects: [AnyObject]?) {
		// Don’t update the timeline if it already has those objects.
		let representedObjectsAreTheSame = timelineContainerViewController?.regularTimelineViewControllerHasRepresentedObjects(selectedObjects) ?? false
		if !representedObjectsAreTheSame {
			timelineContainerViewController?.setRepresentedObjects(selectedObjects, mode: .regular)
			forceSearchToEnd()
		}
		updateWindowTitle()
		NotificationCenter.default.post(name: .InspectableObjectsDidChange, object: nil)
	}

	func unreadCount(for representedObject: AnyObject) -> Int {
		guard let timelineViewController = regularTimelineViewController else {
			return 0
		}
		guard timelineViewController.representsThisObjectOnly(representedObject) else {
			return 0
		}
		return timelineViewController.unreadCount
	}
	
	func sidebarInvalidatedRestorationState(_: SidebarViewController) {
		invalidateRestorableState()
	}
	
}

// MARK: - TimelineContainerViewControllerDelegate

extension MainWindowController: TimelineContainerViewControllerDelegate {

	func timelineSelectionDidChange(_: TimelineContainerViewController, articles: [Article]?, mode: TimelineSourceMode) {
		activityManager.invalidateReading()
		
		articleExtractor?.cancel()
		articleExtractor = nil
		isShowingExtractedArticle = false
		makeToolbarValidate()
		if #available(macOS 13.0, *) { } else {
			updateShareToolbarItemMenu()
		}
		
		let detailState: DetailState
		if let articles = articles {
			if articles.count == 1 {
				activityManager.reading(feed: nil, article: articles.first)
				if articles.first?.feed?.isArticleExtractorAlwaysOn ?? false {
					detailState = .loading
					startArticleExtractorForCurrentLink()
				} else {
					detailState = .article(articles.first!, restoreArticleWindowScrollY)
					restoreArticleWindowScrollY = nil
				}
			} else {
				detailState = .multipleSelection
			}
		} else {
			detailState = .noSelection
		}

		detailViewController?.setState(detailState, mode: mode)
	}

	func timelineRequestedFeedSelection(_: TimelineContainerViewController, feed: Feed) {
		sidebarViewController?.selectFeed(feed)
	}
	
	func timelineInvalidatedRestorationState(_: TimelineContainerViewController) {
		invalidateRestorableState()
	}
}

// MARK: - NSSearchFieldDelegate

extension MainWindowController: NSSearchFieldDelegate {

	func searchFieldDidStartSearching(_ sender: NSSearchField) {
		startSearchingIfNeeded()
	}

	func searchFieldDidEndSearching(_ sender: NSSearchField) {
		stopSearchingIfNeeded()
	}

	@IBAction func runSearch(_ sender: NSSearchField) {
		if sender.stringValue == "" {
			return
		}
		startSearchingIfNeeded()
		handleSearchFieldTextChange(sender)
	}

	private func handleSearchFieldTextChange(_ searchField: NSSearchField) {
		let s = searchField.stringValue
		if s == searchString {
			return
		}
		searchString = s
		updateSmartFeed()
	}

	func updateSmartFeed() {
		guard timelineSourceMode == .search, let searchString = searchString else {
			return
		}
		if searchString == lastSentSearchString {
			return
		}
		lastSentSearchString = searchString
		let smartFeed = SmartFeed(delegate: SearchTimelineFeedDelegate(searchString: searchString, articleIDs: savedSearchArticleIds!))
		timelineContainerViewController?.setRepresentedObjects([smartFeed], mode: .search)
		searchSmartFeed = smartFeed
		updateWindowTitle()
	}

	func forceSearchToEnd() {
		timelineSourceMode = .regular
		searchString = nil
		lastSentSearchString = nil
		if let searchField = currentSearchField {
			searchField.stringValue = ""
		}
		updateWindowTitle()
	}

	private func startSearchingIfNeeded() {
		if savedSearchArticles == nil {
			let articles = currentTimelineViewController!.articles
			savedSearchArticles = articles
			savedSearchArticleIds = Set(articles.map { $0.articleID })
		}
		timelineSourceMode = .search
		updateWindowTitle()
	}

	private func stopSearchingIfNeeded() {
		searchString = nil
		lastSentSearchString = nil
		savedSearchArticles = nil
		savedSearchArticleIds = nil
		timelineSourceMode = .regular
		timelineContainerViewController?.setRepresentedObjects(nil, mode: .search)
		updateWindowTitle()
	}
}

// MARK: - ArticleExtractorDelegate

extension MainWindowController: ArticleExtractorDelegate {
	
	func articleExtractionDidFail(with: Error) {
		makeToolbarValidate()
	}
	
	func articleExtractionDidComplete(extractedArticle: ExtractedArticle) {
		if let article = oneSelectedArticle, articleExtractor?.state != .cancelled {
			isShowingExtractedArticle = true
			let detailState = DetailState.extracted(article, extractedArticle, restoreArticleWindowScrollY)
			restoreArticleWindowScrollY = nil
			detailViewController?.setState(detailState, mode: timelineSourceMode)
			makeToolbarValidate()
		}
	}
	
}

// MARK: - Scripting Access

/*
    the ScriptingMainWindowController protocol exposes a narrow set of accessors with
    internal visibility which are very similar to some private vars.
    
    These would be unnecessary if the similar accessors were marked internal rather than private,
    but for now, we'll keep the stratification of visibility
*/

extension MainWindowController : ScriptingMainWindowController {

    internal var scriptingCurrentArticle: Article? {
        return self.oneSelectedArticle
    }

    internal var scriptingSelectedArticles: [Article] {
        return self.selectedArticles ?? []
    }
}

// MARK: - NSToolbarDelegate

extension NSToolbarItem.Identifier {
	static let sidebarToggle = NSToolbarItem.Identifier("sidebarToggle")
	static let newFeed = NSToolbarItem.Identifier("newFeed")
	static let newFolder = NSToolbarItem.Identifier("newFolder")
	static let refresh = NSToolbarItem.Identifier("refresh")
	static let newSidebarItemMenu = NSToolbarItem.Identifier("newSidebarItemMenu")
	static let timelineTrackingSeparator = NSToolbarItem.Identifier("timelineTrackingSeparator")
	static let search = NSToolbarItem.Identifier("search")
	static let markAllAsRead = NSToolbarItem.Identifier("markAllAsRead")
	static let markAboveAsRead = NSToolbarItem.Identifier("markAboveAsRead")
	static let markBelowAsRead = NSToolbarItem.Identifier("markBelowAsRead")
	static let toggleReadArticlesFilter = NSToolbarItem.Identifier("toggleReadArticlesFilter")
	static let nextUnread = NSToolbarItem.Identifier("nextUnread")
	static let markRead = NSToolbarItem.Identifier("markRead")
	static let markStar = NSToolbarItem.Identifier("markStar")
	static let readerView = NSToolbarItem.Identifier("readerView")
	static let openInBrowser = NSToolbarItem.Identifier("openInBrowser")
	static let share = NSToolbarItem.Identifier("share")
	static let articleThemeMenu = NSToolbarItem.Identifier("articleThemeMenu")
	static let cleanUp = NSToolbarItem.Identifier("cleanUp")
}

extension MainWindowController: NSToolbarDelegate {

	func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
		switch itemIdentifier {

		case .sidebarToggle:
			let title = NSLocalizedString("button.title.toggle-sidebar", comment: "Toggle Sidebar")
			return buildToolbarButton(.toggleSidebar, title, AppAssets.sidebarToggleImage, "toggleTheSidebar:")

		case .refresh:
			let title = NSLocalizedString("button.title.refresh", comment: "Refresh")
			return buildToolbarButton(.refresh, title, AppAssets.refreshImage, "refreshAll:")
		
		case .newSidebarItemMenu:
			let toolbarItem = NSMenuToolbarItem(itemIdentifier: .newSidebarItemMenu)
			toolbarItem.image = AppAssets.addNewSidebarItemImage
			let description = NSLocalizedString("button.title.add-item", comment: "Add Item")
			toolbarItem.toolTip = description
			toolbarItem.label = description
			toolbarItem.menu = buildNewSidebarItemMenu()
			return toolbarItem

		case .markAllAsRead:
			let title = NSLocalizedString("button.title.mark-all-as-read.titlecase", comment: "Mark All as Read")
			return buildToolbarButton(.markAllAsRead, title, AppAssets.markAllAsReadImage, "markAllAsRead:")
		
		case .markAboveAsRead:
			let title = NSLocalizedString("button.title.mark-above-as-read.titlecase", comment: "Mark Above as Read")
			return buildToolbarButton(.markAboveAsRead, title, AppAssets.markAboveAsReadImage, "markAboveAsRead:")
		
		case .markBelowAsRead:
			let title = NSLocalizedString("button.title.mark-below-as-read.titlecase", comment: "Mark Below as Read")
			return buildToolbarButton(.markBelowAsRead, title, AppAssets.markBelowAsReadImage, "markBelowAsRead:")
		
		case .toggleReadArticlesFilter:
			let title = NSLocalizedString("button.title.read-articles-filter", comment: "Read Articles Filter")
			let toolbarItem = RSToolbarItem(itemIdentifier: .toggleReadArticlesFilter)
			toolbarItem.autovalidates = true

			let button = NSButton()
			button.bezelStyle = .texturedRounded
			button.setButtonType(.toggle)
			button.image = AppAssets.filterInactive
			button.imageScaling = .scaleProportionallyDown
			button.action = #selector(toggleReadArticlesFilter(_:))

			toolbarItem.view = button
			toolbarItem.toolTip = title
			toolbarItem.label = title
			return toolbarItem
		
		case .timelineTrackingSeparator:
			return NSTrackingSeparatorToolbarItem(identifier: .timelineTrackingSeparator, splitView: splitViewController!.splitView, dividerIndex: 1)

		case .markRead:
			let title = NSLocalizedString("button.title.mark-read", comment: "Mark Read")
			return buildToolbarButton(.markRead, title, AppAssets.readClosedImage, "toggleRead:")
		
		case .markStar:
			let title = NSLocalizedString("button.title.mark-star", comment: "Star")
			return buildToolbarButton(.markStar, title, AppAssets.starOpenImage, "toggleStarred:")
		
		case .nextUnread:
			let title = NSLocalizedString("button.title.next-read", comment: "Next Unread")
			return buildToolbarButton(.nextUnread, title, AppAssets.nextUnreadImage, "nextUnread:")
		
		case .readerView:
			let toolbarItem = RSToolbarItem(itemIdentifier: .readerView)
			toolbarItem.autovalidates = true
			let description = NSLocalizedString("button.title.reader-view", comment: "Reader View")
			toolbarItem.toolTip = description
			toolbarItem.label = description
			let button = ArticleExtractorButton()
			button.target = self
			button.action = #selector(toggleArticleExtractor(_:))
			button.rightClickAction = #selector(showArticleExtractorMenu(_:))
			toolbarItem.view = button
			toolbarItem.menuFormRepresentation = NSMenuItem(title: description, action: #selector(toggleArticleExtractor(_:)), keyEquivalent: "")
			return toolbarItem

		case .share:
			let title = NSLocalizedString("button.title.share", comment: "Share")
			let image = AppAssets.shareImage
			if #available(macOS 13.0, *) {
				// `item.view` is required for properly positioning the sharing picker.
				return buildToolbarButton(.share, title, image, "toolbarShowShareMenu:", usesCustomButtonView: true)
			} else {
				let item = NSMenuToolbarItem(itemIdentifier: .share)
				item.image = image
				item.toolTip = title
				item.label = title
				item.showsIndicator = false
				return item
			}
		
		case .openInBrowser:
			let title = NSLocalizedString("button.title.open-in-browser", comment: "Open in Browser")
			return buildToolbarButton(.openInBrowser, title, AppAssets.openInBrowserImage, "openArticleInBrowser:")
		
		case .articleThemeMenu:
			articleThemeMenuToolbarItem.image = AppAssets.articleTheme
			let description = NSLocalizedString("button.title.article-theme", comment: "Article Theme")
			articleThemeMenuToolbarItem.toolTip = description
			articleThemeMenuToolbarItem.label = description
			return articleThemeMenuToolbarItem

		case .search:
			let toolbarItem = NSSearchToolbarItem(itemIdentifier: .search)
			let description = NSLocalizedString("button.title.search", comment: "Search")
			toolbarItem.toolTip = description
			toolbarItem.label = description
			return toolbarItem

		case .cleanUp:
			let title = NSLocalizedString("button.title.clean-up", comment: "Clean Up")
			return buildToolbarButton(.cleanUp, title, AppAssets.cleanUpImage, "cleanUp:")
		
		default:
			return nil
		}
	}
	
	func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		return [
			.sidebarToggle,
			.refresh,
			.newSidebarItemMenu,
			.sidebarTrackingSeparator,
			.markAllAsRead,
			.markAboveAsRead,
			.markBelowAsRead,
			.toggleReadArticlesFilter,
			.timelineTrackingSeparator,
			.flexibleSpace,
			.space,
			.nextUnread,
			.markRead,
			.markStar,
			.readerView,
			.openInBrowser,
			.share,
			.articleThemeMenu,
			.search,
			.cleanUp
		]
	}
	
	func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
		return [
			.flexibleSpace,
			.refresh,
			.newSidebarItemMenu,
			.sidebarTrackingSeparator,
			.markAllAsRead,
			.toggleReadArticlesFilter,
			.timelineTrackingSeparator,
			.markRead,
			.markStar,
			.nextUnread,
			.readerView,
			.share,
			.openInBrowser,
			.flexibleSpace,
			.search
		]
	}
	
	func toolbarWillAddItem(_ notification: Notification) {
		guard let item = notification.userInfo?["item"] as? NSToolbarItem else {
			return
		}

		if item.itemIdentifier == .share, let button = item.view as? NSButton {
			// The share button should send its action on mouse down, not mouse up.
			button.sendAction(on: .leftMouseDown)
		}

		if item.itemIdentifier == .search, let searchItem = item as? NSSearchToolbarItem {
			searchItem.searchField.delegate = self
			searchItem.searchField.target = self
			searchItem.searchField.action = #selector(runSearch(_:))
			currentSearchField = searchItem.searchField
		}
	}

	func toolbarDidRemoveItem(_ notification: Notification) {
		guard let item = notification.userInfo?["item"] as? NSToolbarItem else {
			return
		}

		if item.itemIdentifier == .search, let searchItem = item as? NSSearchToolbarItem {
			searchItem.searchField.delegate = nil
			searchItem.searchField.target = nil
			searchItem.searchField.action = nil
			currentSearchField = nil
		}
	}
	
}

// MARK: - Private

private extension MainWindowController {

	var splitViewController: NSSplitViewController? {
		guard let viewController = contentViewController else {
			return nil
		}
		return viewController.children.first as? NSSplitViewController
	}

	var currentTimelineViewController: TimelineViewController? {
		return timelineContainerViewController?.currentTimelineViewController
	}

	var regularTimelineViewController: TimelineViewController? {
		return timelineContainerViewController?.regularTimelineViewController
	}

	var sidebarSplitViewItem: NSSplitViewItem? {
		return splitViewController?.splitViewItems[0]
	}

	var detailSplitViewItem: NSSplitViewItem? {
		return splitViewController?.splitViewItems[2]
	}
	
	var selectedArticles: [Article]? {
		return currentTimelineViewController?.selectedArticles
	}

	var oneSelectedArticle: Article? {
		if let articles = selectedArticles {
			return articles.count == 1 ? articles[0] : nil
		}
		return nil
	}

	var currentLink: String? {
		return selectedArticles?.first { $0.preferredLink != nil }?.preferredLink
	}

	var currentLinks: [String?]? {
		return selectedArticles?.map { $0.preferredLink }
	}

	// MARK: - State Restoration
	
	func savableState() -> [AnyHashable : Any] {
		var state = [AnyHashable : Any]()
		state[UserInfoKey.windowFullScreenState] = window?.styleMask.contains(.fullScreen) ?? false
		saveSplitViewState(to: &state)
		sidebarViewController?.saveState(to: &state)
		timelineContainerViewController?.saveState(to: &state)
		detailViewController?.saveState(to: &state)
		return state
	}

	func restoreState(from state: [AnyHashable : Any]) {
		if let fullScreen = state[UserInfoKey.windowFullScreenState] as? Bool, fullScreen {
			window?.toggleFullScreen(self)
		}
		restoreSplitViewState(from: state)
		
		sidebarViewController?.restoreState(from: state)
		
		let articleWindowScrollY = state[UserInfoKey.articleWindowScrollY] as? CGFloat
		restoreArticleWindowScrollY = articleWindowScrollY
		timelineContainerViewController?.restoreState(from: state)
		
		let isShowingExtractedArticle = state[UserInfoKey.isShowingExtractedArticle] as? Bool ?? false
		if isShowingExtractedArticle {
			restoreArticleWindowScrollY = articleWindowScrollY
			startArticleExtractorForCurrentLink()
		}
		
	}

	// MARK: - Command Validation
	
	func canCopyArticleURL() -> Bool {
		if let currentLinks, currentLinks.count != 0 {
			return true
		}

		return false
	}
	
	func canCopyExternalURL() -> Bool {
		return oneSelectedArticle?.externalLink != nil && oneSelectedArticle?.externalLink != currentLink
	}

	func canGoToNextUnread(wrappingToTop wrapping: Bool = false) -> Bool {
		guard let timelineViewController = currentTimelineViewController, let sidebarViewController = sidebarViewController else {
			return false
		}
		// TODO: handle search mode
		return timelineViewController.canGoToNextUnread(wrappingToTop: wrapping) || sidebarViewController.canGoToNextUnread(wrappingToTop: wrapping)
	}
	
	func canMarkAllAsRead() -> Bool {
		return currentTimelineViewController?.canMarkAllAsRead() ?? false
	}
	
	func canMarkAboveAsRead() -> Bool {
		return currentTimelineViewController?.canMarkAboveArticlesAsRead() ?? false
	}
	
	func canMarkBelowAsRead() -> Bool {
		return currentTimelineViewController?.canMarkBelowArticlesAsRead() ?? false
	}
	
	func validateToggleRead(_ item: NSValidatedUserInterfaceItem) -> Bool {

		let validationStatus = currentTimelineViewController?.markReadCommandStatus() ?? .canDoNothing
		let markingRead: Bool
		let result: Bool
		
		switch validationStatus {
		case .canMark:
			markingRead = true
			result = true
		case .canUnmark:
			markingRead = false
			result = true
		case .canDoNothing:
			markingRead = true
			result = false
		}
		
		let commandName = markingRead ? NSLocalizedString("button.title.mark-as-read", comment: "Mark as Read") : NSLocalizedString("button.title.mark-as-unread", comment: "Mark as Unread")
		
		if let toolbarItem = item as? NSToolbarItem {
			toolbarItem.toolTip = commandName
			toolbarItem.image = markingRead ? AppAssets.readClosedImage : AppAssets.readOpenImage
		}
		
		if let menuItem = item as? NSMenuItem {
			menuItem.title = commandName
		}
		
		return result
	}

	func validateToggleArticleExtractor(_ item: NSValidatedUserInterfaceItem) -> Bool {
		guard let toolbarItem = item as? NSToolbarItem, let toolbarButton = toolbarItem.view as? ArticleExtractorButton else {
			if let menuItem = item as? NSMenuItem {
				menuItem.state = isShowingExtractedArticle ? .on : .off
			}
			return currentLink != nil
		}
		
		if currentTimelineViewController?.selectedArticles.first?.feed != nil {
			toolbarButton.isEnabled = true
		}

		guard let state = articleExtractor?.state else {
			toolbarButton.buttonState = .off
			return currentLink != nil
		}

		switch state {
		case .processing:
			toolbarButton.buttonState = .animated
		case .failedToParse:
			toolbarButton.buttonState = .error
		case .ready, .cancelled, .complete:
			toolbarButton.buttonState = isShowingExtractedArticle ? .on : .off
		}

		return true
	}

	func canMarkAboveArticlesAsRead() -> Bool {
		return currentTimelineViewController?.canMarkAboveArticlesAsRead() ?? false
	}

	func canMarkBelowArticlesAsRead() -> Bool {
		return currentTimelineViewController?.canMarkBelowArticlesAsRead() ?? false
	}
	
	func canShowShareMenu() -> Bool {

		guard let selectedArticles = selectedArticles else {
			return false
		}
		return !selectedArticles.isEmpty
	}

	func validateToggleStarred(_ item: NSValidatedUserInterfaceItem) -> Bool {

		let validationStatus = currentTimelineViewController?.markStarredCommandStatus() ?? .canDoNothing
		let starring: Bool
		let result: Bool

		switch validationStatus {
		case .canMark:
			starring = true
			result = true
		case .canUnmark:
			starring = false
			result = true
		case .canDoNothing:
			starring = true
			result = false
		}

		let commandName = starring ? NSLocalizedString("button.title.mark-as-starred", comment: "Mark as Starred") : NSLocalizedString("button.title.mark-as-unstarred", comment: "Mark as Unstarred")

		if let toolbarItem = item as? NSToolbarItem {
			toolbarItem.toolTip = commandName
			toolbarItem.image = starring ? AppAssets.starOpenImage : AppAssets.starClosedImage
		}

		if let menuItem = item as? NSMenuItem {
			menuItem.title = commandName
		}

		return result
	}
	
	func validateCleanUp(_ item: NSValidatedUserInterfaceItem) -> Bool {
		return timelineContainerViewController?.isCleanUpAvailable ?? false
	}

	func validateToggleReadFeeds(_ item: NSValidatedUserInterfaceItem) -> Bool {
		guard let menuItem = item as? NSMenuItem else { return false }

		let showCommand = NSLocalizedString("button.title.show-read-feeds", comment: "Show Read Feeds")
		let hideCommand = NSLocalizedString("button.title.hide-read-feeds", comment: "Hide Read Feeds")
		menuItem.title = sidebarViewController?.isReadFiltered ?? false ? showCommand : hideCommand
		return true
	}

	func validateToggleReadArticles(_ item: NSValidatedUserInterfaceItem) -> Bool {
		let showCommand = NSLocalizedString("button.title.show-read-articles", comment: "Show Read Articles")
		let hideCommand = NSLocalizedString("button.title.hide-read-articles", comment: "Hide Read Articles")

		guard let isReadFiltered = timelineContainerViewController?.isReadFiltered else {
			(item as? NSMenuItem)?.title = hideCommand
			if let toolbarItem = item as? NSToolbarItem, let button = toolbarItem.view as? NSButton {
				toolbarItem.toolTip = hideCommand
				button.image = AppAssets.filterInactive
				button.state = .off
			}
			return false
		}

		if isReadFiltered {
			(item as? NSMenuItem)?.title = showCommand
			if let toolbarItem = item as? NSToolbarItem, let button = toolbarItem.view as? NSButton {
				toolbarItem.toolTip = showCommand
				button.image = AppAssets.filterActive
				button.state = .on
			}
		} else {
			(item as? NSMenuItem)?.title = hideCommand
			if let toolbarItem = item as? NSToolbarItem, let button = toolbarItem.view as? NSButton {
				toolbarItem.toolTip = hideCommand
				button.image = AppAssets.filterInactive
				button.state = .off
			}
		}
		
		return true
	}

	// MARK: - Misc.

	func goToNextUnreadInTimeline(wrappingToTop wrapping: Bool) {

		guard let timelineViewController = currentTimelineViewController else {
			return
		}

		if timelineViewController.canGoToNextUnread(wrappingToTop: wrapping) {
			timelineViewController.goToNextUnread(wrappingToTop: wrapping)
			makeTimelineViewFirstResponder()
		}
	}

	func makeTimelineViewFirstResponder() {

		guard let window = window, let timelineViewController = currentTimelineViewController else {
			return
		}
		window.makeFirstResponderUnlessDescendantIsFirstResponder(timelineViewController.tableView)
	}

	func updateWindowTitle() {
		guard timelineSourceMode != .search else {
			let localizedLabel = NSLocalizedString("window.title.search.%@", comment: "Search: %@")
			window?.title = NSString.localizedStringWithFormat(localizedLabel as NSString, searchString ?? "") as String
			var searchCount = 0
			if let smartFeed = searchSmartFeed, let count = try? smartFeed.fetchArticles().count {
				searchCount = count
			}
			window?.subtitle = String(searchCount) + " articles"
			return
		}
		
		func setSubtitle(_ count: Int) {
			let localizedLabel = NSLocalizedString("window.subtitle.unread-count.%d", comment: "%d unread")
			let formattedLabel = NSString.localizedStringWithFormat(localizedLabel as NSString, count)
			window?.subtitle = formattedLabel as String
		}
		
		guard let selectedObjects = selectedObjectsInSidebar(), selectedObjects.count > 0 else {
			window?.title = appDelegate.appName!
			setSubtitle(appDelegate.unreadCount)
			return
		}
		
		guard selectedObjects.count == 1 else {
			window?.title = NSLocalizedString("window.title.multiple", comment: "Multiple")
			let unreadCount = selectedObjects.reduce(0, { result, selectedObject in
				if let unreadCountProvider = selectedObject as? UnreadCountProvider {
					return result + unreadCountProvider.unreadCount
				} else {
					return result
				}
			})
			setSubtitle(unreadCount)
			return
		}
		
		if let displayNameProvider = currentFeedOrFolder as? DisplayNameProvider {
			window?.title = displayNameProvider.nameForDisplay
			if let unreadCountProvider = currentFeedOrFolder as? UnreadCountProvider {
				setSubtitle(unreadCountProvider.unreadCount)
			}
		}
	}
	
	func startArticleExtractorForCurrentLink() {
		if let link = currentLink, let extractor = ArticleExtractor(link) {
			extractor.delegate = self
			extractor.process()
			articleExtractor = extractor
			detailViewController?.setState(.loading, mode: timelineSourceMode)
		}
	}

	func saveSplitViewState(to state: inout [AnyHashable : Any]) {
		guard let splitView = splitViewController?.splitView else {
			return
		}

		let widths = splitView.arrangedSubviews.map{ Int(floor($0.frame.width)) }
		state[MainWindowController.mainWindowWidthsStateKey] = widths
		
		state[UserInfoKey.isSidebarHidden] = sidebarSplitViewItem?.isCollapsed
	}

	func restoreSplitViewState(from state: [AnyHashable : Any]) {
		guard let splitView = splitViewController?.splitView,
			let widths = state[MainWindowController.mainWindowWidthsStateKey] as? [Int],
			widths.count == 3,
			let window = window else {
				return
		}

		let windowWidth = Int(floor(window.frame.width))
		let dividerThickness: Int = Int(splitView.dividerThickness)
		let sidebarWidth: Int = widths[0]
		let timelineWidth: Int = widths[1]

		// Make sure the detail view has its minimum thickness, at least.
		if windowWidth < sidebarWidth + dividerThickness + timelineWidth + dividerThickness + MainWindowController.detailViewMinimumThickness {
			return
		}

		splitView.setPosition(CGFloat(sidebarWidth), ofDividerAt: 0)
		splitView.setPosition(CGFloat(sidebarWidth + dividerThickness + timelineWidth), ofDividerAt: 1)
		
		let isSidebarHidden = state[UserInfoKey.isSidebarHidden] as? Bool ?? false
		
		if !(sidebarSplitViewItem?.isCollapsed ?? false) && isSidebarHidden {
			sidebarSplitViewItem?.isCollapsed = true
		}
	}

	func buildToolbarButton(_ itemIdentifier: NSToolbarItem.Identifier, _ title: String, _ image: NSImage, _ selector: String, usesCustomButtonView: Bool = false) -> NSToolbarItem {
		let toolbarItem = RSToolbarItem(itemIdentifier: itemIdentifier)
		toolbarItem.autovalidates = true
		
		toolbarItem.toolTip = title
		toolbarItem.label = title
		
		if usesCustomButtonView {
			let button = NSButton()
			button.bezelStyle = .texturedRounded
			button.image = image
			button.imageScaling = .scaleProportionallyDown
			button.action = Selector((selector))
			toolbarItem.view = button
			toolbarItem.menuFormRepresentation = NSMenuItem(title: title, action: Selector((selector)), keyEquivalent: "")
		} else {
			toolbarItem.image = image
			toolbarItem.isBordered = true
			toolbarItem.action = Selector((selector))
		}
		return toolbarItem
	}

	func buildNewSidebarItemMenu() -> NSMenu {
		let menu = NSMenu()
		
		let newFeedItem = NSMenuItem()
		newFeedItem.title = NSLocalizedString("button.title.new-feed", comment: "New Feed...")
		newFeedItem.action = Selector(("showAddFeedWindow:"))
		menu.addItem(newFeedItem)
		
		let newFolderFeedItem = NSMenuItem()
		newFolderFeedItem.title = NSLocalizedString("button.title.open-new-folder", comment: "New Folder...")
		newFolderFeedItem.action = Selector(("showAddFolderWindow:"))
		menu.addItem(newFolderFeedItem)
		
		return menu
	}

	func updateArticleThemeMenu() {
		let articleThemeMenu = NSMenu()
		
		let defaultThemeItem = NSMenuItem()
		defaultThemeItem.title = ArticleTheme.defaultTheme.name
		defaultThemeItem.action = #selector(selectArticleTheme(_:))
		defaultThemeItem.state = defaultThemeItem.title == ArticleThemesManager.shared.currentTheme.name ? .on : .off
		articleThemeMenu.addItem(defaultThemeItem)

		articleThemeMenu.addItem(NSMenuItem.separator())

		for themeName in ArticleThemesManager.shared.themeNames {
			let themeItem = NSMenuItem()
			themeItem.title = themeName
			themeItem.action = #selector(selectArticleTheme(_:))
			themeItem.state = themeItem.title == ArticleThemesManager.shared.currentTheme.name ? .on : .off
			articleThemeMenu.addItem(themeItem)
		}

		articleThemeMenuToolbarItem.menu = articleThemeMenu
		articleThemePopUpButton?.menu = articleThemeMenu
	}

	func updateShareToolbarItemMenu() {
		guard let shareToolbarItem = shareToolbarItem as? NSMenuToolbarItem else {
			return
		}
		if let shareMenu = shareMenu {
			shareToolbarItem.isEnabled = true
			shareToolbarItem.menu = shareMenu
		} else {
			shareToolbarItem.isEnabled = false
		}
	}

}

