var App = App || {};
App.goToNationality = function(nationality, anchor, locale){
  var url = locale && locale > "" ? "/" + locale + "/about/" : "/about/";
  url += nationality.replace(/ /g, "_");
  if (anchor > ""){
    url = url + "#" + anchor
  }
  window.location = url
}

$(window).on('load', function() {
  setTimeout(function() {
    $('.alert-dismissible').fadeOut();
  }, 3000);
});

// Some calculator controls stop click propagation, which prevents Bootstrap's
// document handler from closing an open person switcher. Capture outside clicks
// before page-specific handlers run so the switcher behaves consistently.
document.addEventListener('click', function(event) {
  var openSwitcher = document.querySelector('.person-switcher.show');
  if (!openSwitcher || openSwitcher.contains(event.target)) return;

  var toggle = openSwitcher.querySelector('[data-toggle="dropdown"]');
  if (toggle && window.jQuery && jQuery.fn.dropdown) {
    jQuery(toggle).dropdown('toggle');
  }
}, true);


