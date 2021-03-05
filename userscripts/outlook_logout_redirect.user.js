// ==UserScript==
// @name        Outlook Logout Redirect
// @namespace   https://github.com/xxc3nsoredxx/misc-utils/
// @version     2.0
// @description Redirect to login page after logout message appears
// @match       *://login.microsoftonline.com/common/oauth2/logout
// @run-at      document-end
// ==/UserScript==

const redirect = 'https://outlook.office.com';
const test_phrase = 'signed out of your account';

function check_page () {
    if (document.body.innerText.includes(test_phrase)) {
        window.location.replace(redirect);
    }
}

let timer = setInterval(check_page, 1000);
