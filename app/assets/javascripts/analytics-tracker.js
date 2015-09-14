$(document).on('page:change', function() {
 if (typeof ga !== "undefined" && ga !== null) {
    ga('send', {
     'hitType': 'pageview',
     'page': window.location.pathname
    });
 }
});
