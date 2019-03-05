# http://thweeble:3000/marc_accession/new

# Useful for testing:
# doc.css('datafield[tag="490"]').last.add_next_sibling('<datafield tag="490" ind1="0"><subfield code="a">some details</subfield></datafield>')

require 'uri'
require 'net/http'
require 'nokogiri'

$TERRIBLE_DEVELOPMENT_MEMORY_LEAK ||= {}

class Nokogiri::XML::NodeSet
  # Working around a Nokogiri 1.8.1 bug where .slice(0, 1).css() blows up with
  # an NPE when the initial set was empty.
  def first_or_empty
    if self.first
      self.slice(0, 1)
    else
      self
    end
  end
end


# FIXME: Split fetching from mapping?
class YaleMarcMapper

  BIB_URL = 'https://libapp.library.yale.edu/VoySearch/GetBibMarc?bibid=%{BIBID}'

  def self.for_bibid(bibid)
    new(fetch_bibid(bibid))
  end

  def self.for_marc(marcxml)
    new(marcxml)
  end

  attr_reader :doc, :agents

  def initialize(marcxml)
    @doc = Nokogiri::XML(marcxml)

    @agents = extract_agents
  end

  def extract_agents
    # Agents get pulled from several locations in the MARC record, but we give
    # the user a chance to review them prior to adding them to the final
    # accession.

    linked_agents = []

    (doc.css('datafield[tag="100"]') + doc.css('datafield[tag="700"]')).take(1).each do |datafield|
      # Do not import/create agent or agent link
      next if (datafield['ind1'] == '3' or datafield.css('subfield[code="a"]').empty?)

      name_order = datafield['ind1'] == '1' ? 'direct' : 'indirect'

      primary_name, rest_of_name = datafield.css('subfield[code="a"]').text.split(',', 2).map {|s| trim_text(s.strip)}

      linked_agents << {
        :relator => trim_text(datafield.css('subfield[code="e"]').text),
        :role => 'creator',
        :agent_type => 'agent_person',
        :agent => {
          'names' => [
            {
              'jsonmodel_type' => 'name_person',
              'name_order' => name_order,
              'primary_name' => primary_name,
              'rest_of_name' => rest_of_name,
              'number' => trim_text(datafield.css('subfield[code="b"]').text),
              'title' => trim_text(datafield.css('subfield[code="c"]').text),
              'fuller_form' => trim_text(datafield.css('subfield[code="q"]').text),
            }
          ],
          'dates_of_existence' => [string_to_date(trim_text(datafield.css('subfield[code="d"]').text))].compact,
        }
      }
    end

    (doc.css('datafield[tag="110"]') + doc.css('datafield[tag="710"]')).take(1).each do |datafield|
      linked_agents << {
        :relator => trim_text(datafield.css('subfield[code="e"]').text),
        :role => 'creator',
        :agent_type => 'agent_corporate_entity',
        :agent => {
          'names' => [
            {
              'jsonmodel_type' => 'name_corporate_entity',
              'primary_name' => trim_text(datafield.css('subfield[code="a"]').text),
              'subordinate_name_1' => trim_text(datafield.css('subfield[code="b"]').first_or_empty.text),
              'subordinate_name_2' => trim_text(datafield.css('subfield[code="b"]').drop(1).map(&:text).join(' ')),
              'qualifier' => trim_text(datafield.css('subfield').select {|s| "cdg".include?(s['code'])}.map(&:text).join(' ')),
              'number' => trim_text(datafield.css('subfield[code="n"]').text),
            }
          ],
          'dates_of_existence' => [string_to_date(trim_text(datafield.css('subfield[code="d"]').text))].compact,
        }
      }
    end

    (doc.css('datafield[tag="111"]') + doc.css('datafield[tag="711"]')).take(1).each do |datafield|
      linked_agents << {
        :relator => trim_text(datafield.css('subfield[code="j"]').text),
        :role => 'creator',
        :agent_type => 'agent_corporate_entity',
        :agent => {
          'names' => [
            {
              'jsonmodel_type' => 'name_corporate_entity',
              'primary_name' => trim_text(datafield.css('subfield[code="a"]').text),
              'subordinate_name_1' => [datafield.css('subfield[code="e"]').first_or_empty.text, datafield.css('subfield[code="q"]').first_or_empty.text].reject(&:empty?).join(' '),
              'subordinate_name_2' => trim_text((datafield.css('subfield[code="e"]').drop(1).map(&:text) +
                                                 datafield.css('subfield[code="q"]').drop(1).map(&:text))
                                                  .join(' ')),
              'qualifier' => trim_text(datafield.css('subfield').select {|s| "cdg".include?(s['code'])}.map(&:text).join(' ')),
              'number' => trim_text(datafield.css('subfield[code="n"]').text),
            }
          ],
          'dates_of_existence' => [string_to_date(trim_text(datafield.css('subfield[code="d"]').text))].compact,
        }
      }
    end

    ["260", "264"].each do |extra_agent_field|
      doc.css('datafield[tag="%s"]' % [extra_agent_field]).first_or_empty.each do |datafield|
        datafield.css('subfield').select {|s| "bf".include?(s['code'])}.map(&:text).each do |name|
          linked_agents << {
            :role => 'creator',
            :agent_type => 'agent_corporate_entity',
            :agent => {
              'names' => [
                {
                  'jsonmodel_type' => 'name_corporate_entity',
                  'primary_name' => name,
                }
              ],
            }
          }
        end
      end
    end

    linked_agents
  end

  def load_materials_type(doc)
    leader = doc.css('leader').text
    case leader[7]
    when 'a'
      case leader[8]
      when 'm'
        'book'
      when 's'
        'serials'
      else
        nil
      end
    when 'e', 'f'
      'maps'
    when 'g', 'i', 'j'
      'audiovisual materials'
    when 'm'
      'electronic documents'
    when 't'
      'manuscripts'
    when 'k'
      'photographs'
    else
      nil
    end
  end

  def load_isbn_issn(doc)
    # Try the ISBN first
    #
    # "Use first instance of field and subfield only. If multiple 020, import
    # only first 020. If one 020 has subfields a and z, import only subfield a
    # text."
    isbn_or_issn = doc.css('datafield[tag="020"] subfield[code="a"]').map(&:text).first

    if isbn_or_issn.blank?
      # Try the ISSN field
      #
      # "Import only if 020 is not in record. If there is no 020, use first
      # instance of field and subfield only. If multiple 022 import only first
      # 022. If one 022 has subfields a and z, import only subfield a text."
      #
      isbn_or_issn = doc.css('datafield[tag="022"] subfield[code="a"]').map(&:text).first
    end
  end

  # TODO: No luck finding a record with these fields... need a test record
  def load_uniform_title(doc)
    # "Import all subfields listed in order of entry in MARC XML. Concatenate
    # with added space between the content of each subfield.."
    result = trim_text(doc.css('datafield[tag="130"] > subfield').map(&:text).join(' '))

    if result.blank?
      # "Do not import if 130 is present in record"
      result = trim_text(doc.css('datafield[tag="240"] > subfield').map(&:text).join(' '))
    end

    result
  end

  # TODO: Question: we'll make dates for f & g, but should we leave them in the title too?  I'm assuming yes.
  def load_title(doc)
    trim_text(doc.css('datafield[tag="245"] > subfield').map(&:text).join(' '))
  end

  # Best-effort parse of 's' into a date
  def string_to_date(s, extra_fields = {})
    if !s || s.empty?
      return nil
    end

    begin_date, end_date = [nil, nil]

    if s =~ /([0-9]{4}).*-.*([0-9]{4})/
      begin_date, end_date = [$1, $2]
    elsif s =~ /([0-9]{4})/
      begin_date = $1
    end

    {
      'jsonmodel_type' => 'date',
      'begin' => begin_date,
      'end' => end_date,
      'expression' => s,
    }.merge(extra_fields)
  end

  # TODO: Haven't yet found a MARC record containing dates.  Got an example?
  def load_dates(doc)
    result = []

    # 245 contains creation dates
    [["f", "inclusive"], ["g", "bulk"]].each do |code, date_type|
      field = doc.css('datafield[tag="245"] subfield[code="%s"]' % [code]).text

      next if field.empty?

      result << string_to_date(field, 'date_label' => 'creation', 'date_type' => date_type)
    end

    # 260 contains publication dates
    ["e", "c"].each do |code|
      field = doc.css('datafield[tag="260"]').first_or_empty.css('subfield[code="%s"]' % [code]).text

      next if field.empty?

      result << string_to_date(field,
                               'date_type' => 'single',
                               'date_label' => 'publication')
    end

    result
  end

  def load_general_note(doc)
    general_notes = []

    edition = trim_text(doc.css('datafield[tag="250"] subfield').map(&:text).join(' '))

    if !edition.empty?
      edition = "EDITION: #{edition}"
      general_notes << edition
    end

    general_notes.concat(doc.css('datafield[tag="590"]').map {|df| trim_text(df.css('subfield').map(&:text).join(' '))})

    general_notes.reject(&:empty?).map(&:strip).join("\n\n")
  end

  # Remove any leading/trailing punctuation and whitespace
  def trim_text(s)
    "#{s}"
      .gsub(/[ [:punct:]]+$/, '')
      .gsub(/^[ [:punct:]]+/, '')
  end

  def load_place_of_publication(doc)
    [
      trim_text(doc.css('datafield[tag="260"]').first_or_empty.css('subfield').select {|s| "ae".include?(s['code'])}.map(&:text).join(' ')),
      trim_text(doc.css('datafield[tag="264"]').first_or_empty.css('subfield').select {|s| "ae".include?(s['code'])}.map(&:text).join(' ')),
    ].reject(&:empty?).join('; ')
  end

  def load_extents(doc)
    result = []

    doc.css('datafield[tag="300"]').each do |df|
      extent = {
        'container_summary' => trim_text(df.css('subfield[code="a"]').map(&:text).join(' ')),
        'physical_details' => trim_text(df.css('subfield[code="b"]').map(&:text).join(' ')),
        'dimensions' => trim_text(df.css('subfield[code="c"]').map(&:text).join(' ')),
      }

      unless extent.values.all?(&:empty?)
        result << extent
      end
    end

    result
  end


  def load_monographic_series(doc)
    doc.css('datafield[tag="490"][ind1="0"]').map {|df|
      trim_text(df.css('subfield').map(&:text).join(' '))
    }.join("\n\n")
  end


  # TODO: Selecting "bulk" seems to show up as inclusive on the accession form.  Like the JS is doing the wrong thing?
  #   >>> Selecting "Publication" for the date type is broken too.  Same sort of issue.
  def to_accession
    isbn_or_issn = load_isbn_issn(doc)
    uniform_title = load_uniform_title(doc)

    Accession.new(
      :title => load_title(doc),
      :dates => load_dates(doc),
      :general_note => load_general_note(doc),
      :extents => load_extents(doc),
      :user_defined => {
        'jsonmodel_type' => 'user_defined',

        # FIXME: which user defined field do Yale use for 001 MARC?
        'string_1' => doc.css('controlfield[tag="001"]').text,
        'string_2' => isbn_or_issn,
        'string_3' => uniform_title,
        'string_4' => load_place_of_publication(doc),

        'text_1' => load_monographic_series(doc),
        'text_2' => load_materials_type(doc),
      }
    )._always_valid!
  end


  private

  def self.fetch_bibid(bibid)
    if $TERRIBLE_DEVELOPMENT_MEMORY_LEAK.include?(bibid)
      return $TERRIBLE_DEVELOPMENT_MEMORY_LEAK[bibid].clone
    end

    uri = URI.parse(BIB_URL % {BIBID: bibid})

    $stderr.puts("HITTING THE NETWORK")
    response = Net::HTTP.get_response(uri)

    if response.is_a?(Net::HTTPSuccess)
      marcxml = response.body.clone
      marcxml.force_encoding('UTF-8')

      $TERRIBLE_DEVELOPMENT_MEMORY_LEAK[bibid] = marcxml
      marcxml
    else
      raise BibServiceRequestFailure.new(response.code, response.body)
    end
  end


  class BibServiceRequestFailure < StandardError
    def initialize(http_response_code, message)
      super("BibServiceRequestFailure http_status=%s; message=%s",
            http_response_code,
            message)
    end
  end

end


# <?xml version="1.0" encoding="utf-8"?>
# <collection xmlns="http://www.loc.gov/MARC21/slim">
#   <record>
#     <leader>00807cam a2200277 4500</leader>
#     <controlfield tag="001">2002</controlfield>
#     <controlfield tag="005">20110324191328.0</controlfield>
#     <controlfield tag="008">801220s1966 nyuc b 00000 eng u</controlfield>
#     <datafield tag="010" ind1="" ind2="">
#       <subfield code="a">66010776</subfield>
#     </datafield>
#     <datafield tag="035" ind1="" ind2="">
#       <subfield code="a">(OCoLC)ocn687596807</subfield>
#     </datafield>
#     <datafield tag="035" ind1="" ind2="">
#       <subfield code="a">(CStRLIN)CTYG0181105-B</subfield>
#     </datafield>
#     <datafield tag="035" ind1="" ind2="">
#       <subfield code="9">AAA2028YL</subfield>
#     </datafield>
#     <datafield tag="035" ind1="" ind2="">
#       <subfield code="a">2002</subfield>
#     </datafield>
#     <datafield tag="040" ind1="" ind2="">
#       <subfield code="c">OAkU</subfield>
#       <subfield code="d">CtY</subfield>
#     </datafield>
#     <datafield tag="050" ind1="0" ind2="">
#       <subfield code="a">PA26</subfield>
#       <subfield code="b">.C29</subfield>
#     </datafield>
#     <datafield tag="079" ind1="" ind2="">
#       <subfield code="a">ocm00181105</subfield>
#     </datafield>
#     <datafield tag="090" ind1="" ind2="">
#       <subfield code="a">PA26</subfield>
#       <subfield code="b">.C29</subfield>
#     </datafield>
#     <datafield tag="100" ind1="1" ind2="">
#       <subfield code="a">Wallach, Luitpold.</subfield>
#     </datafield>
#     <datafield tag="245" ind1="1" ind2="4">
#       <subfield code="a">The classical tradition;</subfield>
#       <subfield code="b">literary and historical studies in honor of Harry Caplan.</subfield>
#     </datafield>
#     <datafield tag="260" ind1="0" ind2="">
#       <subfield code="a">Ithaca, N.Y.,</subfield>
#       <subfield code="b">Cornell University Press</subfield>
#       <subfield code="c">[1966]</subfield>
#     </datafield>
#     <datafield tag="300" ind1="" ind2="">
#       <subfield code="a">xv, 606 p.</subfield>
#       <subfield code="b">port.</subfield>
#       <subfield code="c">24 cm.</subfield>
#     </datafield>
#     <datafield tag="504" ind1="" ind2="">
#       <subfield code="a">Bibliographical footnotes.</subfield>
#     </datafield>
#     <datafield tag="650" ind1="" ind2="0">
#       <subfield code="a">Classical literature.</subfield>
#     </datafield>
#     <datafield tag="700" ind1="1" ind2="">
#       <subfield code="a">Caplan, Harry,</subfield>
#       <subfield code="d">1896-</subfield>
#     </datafield>
#     <datafield tag="928" ind1="" ind2="">
#       <subfield code="a">AC031297</subfield>
#     </datafield>
#     <datafield tag="948" ind1="" ind2="">
#       <subfield code="a">CCL : Transf. from S.</subfield>
#     </datafield>
#   </record>
# </collection>
