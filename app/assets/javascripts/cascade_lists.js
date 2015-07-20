
var App = App || {};

App.Cascade = function(parentEle, childEle, childData, idName, valueName, linkName, filterFunction){
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
  $(this.parentEle).change();
}
App.Cascade.prototype.buildOption = function(value, text) {
  return "<option value=" + value + ">" + text + "</option>"
}
App.Cascade.prototype.loadSelect = function(selectEle, data){
  var options  = ""
  $(data).each(function(index, obj){
    options = options + this.buildOption(obj[this.idName], obj[this.valueName] )
  }.bind(this))
  $(selectEle).html(options)
}
App.Cascade.prototype.defaultFilter = function(obj){
  if (obj[this.linkName] == $(this.parentEle).val())  {
    return true;
  } else {
    return false;
  }
}

