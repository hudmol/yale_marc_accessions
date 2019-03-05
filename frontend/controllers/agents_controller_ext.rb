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

      # @agent
      require 'pp';$stderr.puts("\n*** DEBUG #{(Time.now.to_f * 1000).to_i} [agents_controller_ext.rb:13 f431d7]: " + {%Q^@agent^ => @agent}.pretty_inspect + "\n")

      # marc_accession['json']['agents'][Integer(params[:stored_agent_idx])]['agent']
      require 'pp';$stderr.puts("\n*** DEBUG #{(Time.now.to_f * 1000).to_i} [agents_controller_ext.rb:16 e79b13]: " + {%Q^marc_accession['json']['agents'][Integer(params[:stored_agent_idx])]['agent']^ => marc_accession['json']['agents'][Integer(params[:stored_agent_idx])]['agent']}.pretty_inspect + "\n")

      @agent.update(marc_accession['json']['agents'][Integer(params[:stored_agent_idx])]['agent'])

      # @agent
      require 'pp';$stderr.puts("\n*** DEBUG #{(Time.now.to_f * 1000).to_i} [agents_controller_ext.rb:21 4c8dbc]: " + {%Q^@agent^ => @agent}.pretty_inspect + "\n")

      render_aspace_partial :partial => "agents/new"
    else
      new_pre_marc_accession
    end
  end
end
