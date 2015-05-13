json.array!(@country) do |c|
  json.extract! c, :id, :name, :continent_id
  json.url visit_new_url(visit, format: :json)
end
