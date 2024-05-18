var App = App || {};
App.goToNationality = function(nationality, anchor, locale){
  var url = locale && local > "" ? "/" + local + "/about/" : "/about/";
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



