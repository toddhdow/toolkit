#encoding: utf-8

require_relative "../mapping"
require_relative "../helpers"

require 'json'
require 'csv'

include Kenna::Helpers
include Kenna::Mapping::External

$basedir = "/opt/toolkit"
$assets = []
$vuln_defs = []

SCAN_SOURCE="Expanse"

def create_asset(ip_address, hostname=nil)

  # if we already have it, skip
  return unless $assets.select{|a| a[:ip_address] == ip_address }.empty?

  asset = {
    ip_address: ip_address,
    tags: [],
    priority: 10,
    vulns: []
  }

  # if we have a hostname, add it
  asset[:hostname] = hostname if hostname

  $assets << asset
end

def create_asset_vuln(ip_address, port, vuln_id, first_seen, last_seen)

  # grab the asset
  asset = $assets.select{|a| a[:ip_address] == ip_address}.first

  asset[:vulns] << {
    scanner_identifier: "#{vuln_id}",
    scanner_type: SCAN_SOURCE,
    created_at: first_seen,
    port: port.to_i,
    last_seen_at: last_seen,
    status: "open"
  }

end

# verify we have a valid file
#hheaders = [] 
headers = [] 

CSV.parse(read_input_file("#{ARGV[0]}"), encoding: "UTF-8", row_sep: :auto, col_sep: ",").each_with_index do |row,index|
  # skip first
  if index == 0
    headers = row.to_a
    next 
  end
  
  # create the asset
  hostname = get_value_by_header(row, headers,"firstObservation_hostname").gsub("*.","")
  ip_address = get_value_by_header(row, headers,"ip")
  port = get_value_by_header(row, headers,"port")
  create_asset ip_address, hostname

  first = get_value_by_header(row, headers,"firstObservation_scanned")
  last = get_value_by_header(row, headers,"lastObservation_scanned")
  if first
    first_seen = Date.strptime("#{first}", "%Y-%m-%d")
  else
    first_seen = Date.today
  end

  if last
    last_seen = Date.strptime("#{last}", "%Y-%m-%d")
  else
    last_seen = Date.today
  end

  serial = get_value_by_header(row, headers,"certificate_serialNumber")
  issuer = get_value_by_header(row, headers,"certificate_issuer")
  alternative_names = get_value_by_header(row, headers,"certificate_subjectAlternativeNames")
  provider = get_value_by_header(row, headers,"provider")
  key_length = get_value_by_header(row, headers,"certificate_publicKeyBits") 
  algorithm = get_value_by_header(row, headers,"certificate_publicKeyAlgorithm")
  
  vuln_id = "certificate_short_key_#{serial}"
  description = "Detected certificate with short key \n"
  description << "Serial: #{serial}\n"
  description << "Public Key Length: #{key_length}\n"
  description << "Signature Algorithm: #{algorithm}\n"
  description << "Issuer: #{issuer}\n"
  description << "Subject Alt Names: #{alternative_names}\n"

  recommendation = "Verify and if required, re-issue certificate or remove system" # TODO?

  mapped_vuln = get_canonical_vuln_details(SCAN_SOURCE, "#{vuln_id}", description, recommendation)

  create_asset_vuln ip_address, port, vuln_id, first_seen, last_seen
  create_vuln_def mapped_vuln[:name], vuln_id, mapped_vuln[:description], mapped_vuln[:recommendation], mapped_vuln[:cwe]

end

kdi_output = generate_kdi_file
puts JSON.pretty_generate kdi_output