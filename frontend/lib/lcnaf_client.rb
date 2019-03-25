require 'net/http'
require 'uri'

class LCNAFClient

  SEARCH_URI_JS_TEMPLATE = 'http://id.loc.gov/search/?q=rdftype:Name&q=${query}&q=cs:http://id.loc.gov/authorities/names'
  RECORD_URI_SPRINTF_TEMPLATE = 'http://id.loc.gov/authorities/names/%s.marcxml.xml'

  MAX_REDIRECTS = 5


  # If `s` looks like a record URL, extract the record identifier from it.  Otherwise, return s.
  def extract_identifier(s)
    if s =~ %r{/names/([a-zA-Z0-9]+)\.html$}
      $1
    else
      s
    end
  end

  # Return a LCNAF record as MARCXML
  def fetch_marcxml(lcnaf_id)
    uri = URI.parse(RECORD_URI_SPRINTF_TEMPLATE % [lcnaf_id])

    MAX_REDIRECTS.times do
      response = Net::HTTP.get_response(uri)

      case response
      when Net::HTTPRedirection then
        uri = URI(response['location'])
      when Net::HTTPSuccess then
        return response.body
      else
        raise ClientError.new("#{response.code} #{response.message}")
      end
    end
  end


  class ClientError < StandardError
  end

end
