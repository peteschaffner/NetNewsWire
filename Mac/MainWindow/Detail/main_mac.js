function linkHover() {
	window.onmouseover = function(event) {
		var closestAnchor = event.target.closest('a')
		if (closestAnchor) {
			window.webkit.messageHandlers.mouseDidEnter.postMessage(closestAnchor.href);
		}
	}
	window.onmouseout = function(event) {
		var closestAnchor = event.target.closest('a')
		if (closestAnchor) {
			window.webkit.messageHandlers.mouseDidExit.postMessage(closestAnchor.href);
		}
	}
}

function popover() {
	window.onclick = function(event) {
		var closestAnchor = event.target.closest('a')
		if (closestAnchor && closestAnchor.matches('.footnote')) {
			if (!closestAnchor.hash) return;
			
			let targetId = decodeURIComponent(closestAnchor.hash.substring(1));
			const targetElement = document.getElementById(targetId);
			
			if (targetElement === null) return;
			
			event.preventDefault();
			
			var data = closestAnchor.getBoundingClientRect().toJSON()
			data.text = targetElement.innerText
			
			window.webkit.messageHandlers.mouseDidClick.postMessage(data);
		}
	}
}

function scrollDetection() {
	window.addEventListener("scroll", function() {
		var top;
		
		if(window.scrollY <= 0) {
			top = 1;
		} else {
			top = 0;
		}
		
		window.webkit.messageHandlers.windowDidScroll.postMessage({
			"isTop": top,
			"scrollY": window.scrollY
		});
	});
}

function postRenderProcessing() {
	linkHover()
	popover()
	scrollDetection()
}
