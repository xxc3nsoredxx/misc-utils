// ==UserScript==
// @name        Mobile to Desktop
// @namespace   https://github.com/xxc3nsoredxx/misc-utils/
// @version     1
// @author      xxc3nsoredxx
// @description Changes from a mobile page to a desktop page
// @run-at      document-start
// ==/UserScript==

// How to change the url
const targets = [
  /(..\.)m\.(wikipedia\.org)/,
];

for (let cx = 0; cx < targets.length; cx++) {
  const cur = window.location;
  const matches = cur.hostname.match(targets[cx]);
  
  // Match found
  if (matches) {
    const prot = cur.protocol;
    const path = cur.pathname;
    cur.replace(prot + '//' + matches[1] + matches[2] + path);
  }
}