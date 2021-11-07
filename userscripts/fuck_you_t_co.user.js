// ==UserScript==
// @name        Fuck You t.co
// @namespace   https://github.com/xxc3nsoredxx/misc-utils/
// @version     1.1
// @author      xxc3nsoredxx
// @description Re-injects the original link into the tweet
// @match       *://twitter.com/*
// @run-at      document-start
// ==/UserScript==

// Only replace links that have the actual URL in the tweet. Relevant child nodes:
// [0]: https://
// [1]: example.com/path_to
// [2]: actual_page
// [3]: ...
// 0 and 2 are hidden


// Possible initial values of prev:
//   "" (empty string) if the URL already contains "https://"
//   "https://" if the URL doesn't already contain "https://"
function url_reducer (prev, cur) {
    return prev + cur.textContent;
}

function collapse_url (children) {
    let children_array = Array.from(children).slice(0, 3);

    if (children_array[0].textContent == "https://") {
        return children_array.reduce(url_reducer, "");
    } else {
        return children_array.reduce(url_reducer, "https://");
    }
}

function replace_url (node) {
    if (node.childNodes.length == 4 || node.childNodes.length == 2) {
        console.log("Replacing t.co URL: " + node);
        console.log(node);
        node.attributes.href.nodeValue = collapse_url(node.childNodes);
    }
}

function filter_urls () {
    let t_co_links = document.querySelectorAll("a[href^='https://t.co']");

    t_co_links.forEach(replace_url);
}

document.addEventListener("scroll", filter_urls);
