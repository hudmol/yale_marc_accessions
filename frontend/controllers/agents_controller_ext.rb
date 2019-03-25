class AgentsController < ApplicationController

  # Override #new with a version that prepopulates from a stored MARC accession
  # when requested.
  alias :new_pre_marc_accession :new
  def new
    if params[:stored_accession_uuid]
      # Prevent the template from rendering until we've had a chance to monkey with it.
      params[:inline] = false
      result = new_pre_marc_accession
      marc_accession = JSONModel(:marc_accession).find(nil, :uuid => params[:stored_accession_uuid])

      @agent.update(marc_accession['json']['agents'][Integer(params[:stored_agent_idx])]['agent'])

      render_aspace_partial :partial => "agents/new"
    else
      new_pre_marc_accession
    end
  end
end
