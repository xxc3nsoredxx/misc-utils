// ==UserScript==
// @name        Outlook Logout Redirect
// @version     1.1
// @description Redirect to login page after logout message appears
// @match       *://login.microsoftonline.com/common/oauth2/logout
// @run-at      document-idle
// ==/UserScript==

const id = 'login_workload_logo_text';
const test_phrase = 'signed out of your account';
const redirect = 'https://outlook.office.com';

if (document.getElementById(id).innerText.includes(test_phrase)) {
    window.location.replace(redirect);
}
