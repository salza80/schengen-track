
$(document).on("ready page:load", function() {
  $("#Continent").change(function(){ 
    load_countries();
    });

});

function load_countries(continent_id) {
  var country_list
  country_list = country.filter(filter_by_selected_continent);
  options  = ""
  $(country_list).each(function(){
    options = options + build_option(this.id, this.name)
  })
   $("#visit_country_id").html(options)

}

function filter_by_selected_continent(obj){

  if (obj.continent_id == $("#Continent").val())  {
    return true;
  } else {
    
    return false;
  }
}

function build_option(value, text) {
  return "<option value=" + value + ">" + text + "</option>"
}

