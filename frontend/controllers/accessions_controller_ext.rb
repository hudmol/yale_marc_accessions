class AccessionsController < ApplicationController

  # Override #new with a version that prepopulates from a stored MARC accession
  # when requested.
  alias :new_pre_marc_accession :new
  def new
    result = new_pre_marc_accession

    if params[:marc_accession]
      marc_accession = JSONModel(:marc_accession).find(nil, :uuid => params[:marc_accession])

      @accession = JSONModel(:accession).new
      @accession.update(marc_accession.json['accession'])
    end

    result
  end
end
