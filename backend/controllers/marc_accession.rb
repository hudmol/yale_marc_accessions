class ArchivesSpaceService < Sinatra::Base

  Endpoint.get('/repositories/:repo_id/marc_accessions')
    .description("Fetch a saved MARC accession")
    .params(["repo_id", :repo_id],
            ["uuid", String, "The ID of the saved MARC accession"])
    .permissions([:update_accession_record])
    .returns([200, "(JSON record)"]) \
  do
    row = MARCAccessionRecord[:uuid => params[:uuid]]

    raise NotFoundException.new if row.nil?

    json_response(JSONModel(:marc_accession).from_hash(:uuid => row[:uuid],
                                                       :json => ASUtils.json_parse(row[:json])).to_hash,
                  200)
  end

  Endpoint.post('/repositories/:repo_id/marc_accessions')
    .description("Save a work in progress MARC accession")
    .params(["repo_id", :repo_id],
            ["marc_accession", JSONModel(:marc_accession), "A JSON record to save", :body => true])
    .permissions([:update_accession_record])
    .returns([200, "{'uuid': 'someuuid'}"]) \
  do
    uuid = SecureRandom.hex

    # Expire old records.  FIXME: AppConfig this?
    expiration = Time.now - (14 * 24 * 60 * 60)
    MARCAccessionRecord.where { create_time < expiration }.delete

    MARCAccessionRecord.create(:uuid => uuid,
                               :json => params[:marc_accession].json.to_json,
                               :create_time => Time.now)

    json_response({'uuid' => uuid}, 200)
  end

  Endpoint.post('/repositories/:repo_id/marc_accessions/:uuid')
    .description("Save a work in progress MARC accession")
    .params(["repo_id", :repo_id],
            ["uuid", String, "The MARC Accession record to update"],
            ["marc_accession", JSONModel(:marc_accession), "A JSON record to save", :body => true])
    .permissions([:update_accession_record])
    .returns([200, "{'uuid': 'someuuid'}"]) \
  do
    marc_accession = MARCAccessionRecord[:uuid => params[:uuid]] or raise NotFoundException.new
    marc_accession.json = params[:marc_accession].json.to_json
    marc_accession.save

    json_response({'uuid' => params[:uuid]}, 200)
  end

  Endpoint.post('/repositories/:repo_id/marc_accessions_similar_agents')
    .description("Given a set of agents, return any that are close enough for a match")
    .params(["repo_id", :repo_id],
            ["agents", String, "A JSON array of agents", :body => true])
    .permissions([])
    .returns([200, "[{'ref': '/agent/uri', 'display_string': 'agent name']"]) \
  do
    agents = ASUtils.json_parse(params[:agents])

    result = agents.map {|agent|
      begin
        if agent['agent_type'] == 'agent_person'
          # Match on primary and rest of name
          matched = NamePerson.filter(:primary_name => agent['agent']['names'][0]['primary_name'],
                                      :rest_of_name => agent['agent']['names'][0]['rest_of_name'])
                      .first

          if matched
            {
              'ref' => AgentPerson[matched[:agent_person_id]].uri,
              'display_string' => matched.sort_name
            }
          end
        elsif agent['agent_type'] == 'agent_corporate_entity'
          # Match on primary name only
          matched = NameCorporateEntity.filter(:primary_name => agent['agent']['names'][0]['primary_name'])
                      .first

          if matched
            obj = AgentCorporateEntity[matched[:agent_corporate_entity_id]]
            {
              'ref' => obj.uri,
              'display_string' => matched.sort_name
              }
          end

        else
          nil
        end
      rescue
        Log.error("Unexpected error while attempting to match agent")
        Log.exception($!)

        nil
      end
    }

    json_response(result, 200)
  end

end
