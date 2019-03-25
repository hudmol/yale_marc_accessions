ArchivesSpace::Application.routes.draw do
  scope AppConfig[:frontend_proxy_prefix] do
    match 'marc_accessions/new' => 'marc_accessions#new', :via => [:get]
    match 'marc_accessions/review_agents' => 'marc_accessions#review_agents', :via => [:get]
    match 'marc_accessions/create' => 'marc_accessions#create', :via => [:post]
    match 'marc_accessions/lcnaf_import' => 'marc_accessions#lcnaf_import', :via => [:post]
  end
end
