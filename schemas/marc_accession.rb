{
  :schema => {
    "$schema" => "http://www.archivesspace.org/archivesspace.json",
    "version" => 1,
    "type" => "object",
    "uri" => "/repositories/:repo_id/marc_accessions",
    "properties" => {
      "uuid" => {"type" => "string"},
      "json" => {"type" => "object"},
    },
  },
}
