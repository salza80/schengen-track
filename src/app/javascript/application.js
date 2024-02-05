// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails

// Entry point for the build script in your package.json

import 'bootstrap';

window.App = window.App || {};
window.App.goToNationality = function(nationality, anchor){
  var url = "/about/" + nationality
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

window.App.Cascade = function(parentEle, childEle, childData, idName, valueName, linkName, filterFunction){
    this.parentEle = parentEle;
    this.childEle = childEle;
    this.childData = childData;
    this.idName = idName;
    this.valueName = valueName;
    this.linkName = linkName
    this.filter = filterFunction;
    if (this.filter==undefined){ this.filter = this.defaultFilter.bind(this)};
    $(this.parentEle).change(function(){
    var filteredData = ""
    filteredData = this.childData.filter(this.filter);
    this.loadSelect(this.childEle, filteredData);
    }.bind(this))
    // $(this.parentEle).change();
}
window.App.Cascade.prototype.buildOption = function(value, text) {
    return "<option value=" + value + ">" + text + "</option>"
}
window.App.Cascade.prototype.loadSelect = function(selectEle, data){
    var options  = ""
    $(data).each(function(index, obj){
    options = options + this.buildOption(obj[this.idName], obj[this.valueName] )
    }.bind(this))
    $(selectEle).html(options)
}
window.App.Cascade.prototype.defaultFilter = function(obj){
    if (obj[this.linkName] == $(this.parentEle).val())  {
    return true;
    } else {
    return false;
    }
}

$(document).on('page:change', function() {
  if (typeof ga !== "undefined" && ga !== null) {
    ga('send', {
    'hitType': 'pageview',
    'page': window.location.pathname
    });
  }
});


