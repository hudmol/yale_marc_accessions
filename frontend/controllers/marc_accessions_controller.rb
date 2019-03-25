# coding: utf-8
class MarcAccessionsController < ApplicationController

  set_access_control "update_accession_record" => [:new, :create, :review_agents],
                     "update_agent_record" => [:lcnaf_import]


  before_action :marc_accessions_reload_mapper_for_dev

  def review_agents
    # Grab our MARCXML
    marc = YaleMarcMapper.fetch_bibid(params[:bibid])

    mapper = YaleMarcMapper.for_marc(marc)

    save_response = JSONModel(:marc_accession)
                      .from_hash(:json => {
                                   'accession' => mapper.to_accession.to_hash(:trusted),
                                   'agents' => mapper.agents,
                                 })
                      .save({}, true)

    @stored_accession_uuid = save_response['uuid']
    @agents = mapper.agents

    if @agents.empty?
      # We can redirect straight to the final step
      redirect_to(:controller => :accessions,
                  :action => :new,
                  :marc_accession => @stored_accession_uuid)
    end

    # Otherwise, look for agents that have already been created
    post_uri = URI("#{JSONModel::HTTP.backend_url}/repositories/#{session[:repo_id]}/marc_accessions_similar_agents")
    matched_agents = [nil] * @agents.length

    begin
      matched_agents = ASUtils.json_parse(JSONModel::HTTP.post_json(post_uri, ASUtils.to_json(@agents)).body)
    rescue
      Rails.logger.warn("Failed to find similar agents: #{$!}")
    end

    (0...@agents.length).each do |idx|
      @agents[idx][:matched_existing_agent] = matched_agents[idx]
    end
  end

  def create
    marc_accession = JSONModel(:marc_accession).find(nil, :uuid => params[:stored_accession_uuid])

    roles = (params['linked_agents'] || {}).fetch('role')
    relators = (params['linked_agents'] || {}).fetch('relator')
    agents = (params['linked_agents'] || {}).fetch('agent')

    accession = marc_accession.json['accession']
    accession['linked_agents'] ||= []
    agents.zip(relators, roles).each do |agent, relator, role|
      accession['linked_agents'] << {
        'ref' => agent['ref'],
        'role' => role,
        'relator' => relator,
        '_resolved' => ASUtils.json_parse(agent['_resolved']),
      }
    end

    save_response = JSONModel(:marc_accession)
                      .from_hash(:json => {
                                   'accession' => accession,
                                 })
                      .save({}, true)

    redirect_to(:controller => :accessions,
                :action => :new,
                :marc_accession => save_response['uuid'])
  end


  def marc_accessions_reload_mapper_for_dev
    if Rails.env.development?
      load '/mnt/ssd/archivesspace-dev/archivesspace/plugins/yale_marc_accession/frontend/lib/yale_marc_mapper.rb'
    end
  end

  def lcnaf_import
    params.require([:lcnaf_id, :stored_accession_uuid, :agent_idx])

    lcnaf = LCNAFClient.new

    lcnaf_id = lcnaf.extract_identifier(params[:lcnaf_id])

    marc = lcnaf.fetch_marcxml(lcnaf_id)
    mapper = YaleMarcMapper.for_marc(marc)

    marc_accession = JSONModel(:marc_accession).find(nil, :uuid => params[:stored_accession_uuid])

    if mapper.agents.empty?
      raise "NO_AGENT_FOUND"
    else
      marc_accession.json['agents'][Integer(params[:agent_idx])]['agent'].merge!(mapper.agents[0][:agent])
    end

    # This record type doesn't have a proper ID, so the usual #save method
    # doesn't work.  Just send a POST to the right URL.
    JSONModel::HTTP.post_json(JSONModel(:marc_accession).my_url(params[:stored_accession_uuid], {}),
                              marc_accession.to_json)
  end

end


