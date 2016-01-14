var app = app || {};

app.goToNationality = function(nationality, anchor){
  var url = "/about/" + nationality
  if (anchor > ""){
    url = url + "#" + anchor
  }
  window.location = url
}
