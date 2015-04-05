json.array!(@visits) do |visit|
  json.extract! visit, :id, :entry_date, :exit_date, :country_id
  json.url visit_url(visit, format: :json)
end
