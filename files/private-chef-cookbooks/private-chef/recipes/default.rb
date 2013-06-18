#
# Author:: Adam Jacob (<adam@opscode.com>)
# Copyright:: Copyright (c) 2012 Opscode, Inc.
#

require 'uuidtools'
require 'openssl'

ENV['PATH'] = "/opt/opscode/bin:/opt/opscode/embedded/bin:#{ENV['PATH']}"

directory "/etc/opscode" do
  owner "root"
  group "root"
  mode "0755"
  action :nothing
end.run_action(:create)

directory "/etc/opscode/logrotate.d" do
  owner "root"
  group "root"
  mode "0755"
  action :nothing
end.run_action(:create)

if File.exists?("/etc/opscode/chef-server.json")
  Chef::Log.warn("Please move to /etc/opscode/private-chef.rb for configuration - /etc/opscode/chef-server.json is deprecated.")
else
  PrivateChef[:node] = node
  if File.exists?("/etc/opscode/private-chef.rb")
    PrivateChef.from_file("/etc/opscode/private-chef.rb")
  end
  node.consume_attributes(PrivateChef.generate_config(node['fqdn']))
end

# the bootstrap_server attribute is set to signify that this node is
# cofigured to be the bootstrap server. If bootstrap#enable is set in
# the OPC config, then we know we should be the bootstrap server.
node.set['private_chef']['bootstrap']['bootstrap_server'] = node['private_chef']['bootstrap']['enable']

if File.exists?("/var/opt/opscode/bootstrapped")
	node.set['private_chef']['bootstrap']['enable'] = false
end

# Create the Chef User
include_recipe "private-chef::users"

sql_migration_phase_1     = node['private_chef']['dark_launch']['sql_migration_phase_1']
dark_launch_couchdb_flags = %w(roles data cookbooks checksums clients environments).map {|k| ["couchdb_#{k}", !sql_migration_phase_1] }.flatten
dark_launch_features_hash = node['private_chef']['dark_launch'].to_hash.merge(Hash[*dark_launch_couchdb_flags])

file "/etc/opscode/dark_launch_features.json" do
  owner node["private_chef"]["user"]["username"]
  group "root"
  mode "0644"
  content Chef::JSONCompat.to_json_pretty(dark_launch_features_hash)
end

webui_key = OpenSSL::PKey::RSA.generate(2048) unless File.exists?('/etc/opscode/webui_pub.pem')

file "/etc/opscode/webui_pub.pem" do
  owner "root"
  group "root"
  mode "0644"
  content webui_key.public_key.to_s unless File.exists?('/etc/opscode/webui_pub.pem')
end

file "/etc/opscode/webui_priv.pem" do
  owner node["private_chef"]["user"]["username"]
  group "root"
  mode "0600"
  content webui_key.to_pem.to_s unless File.exists?('/etc/opscode/webui_pub.pem')
end

worker_key = OpenSSL::PKey::RSA.generate(2048) unless File.exists?('/etc/opscode/worker-public.pem')

file "/etc/opscode/worker-public.pem" do
  owner "root"
  group "root"
  mode "0644"
  content worker_key.public_key.to_s unless File.exists?('/etc/opscode/worker-public.pem')
end

file "/etc/opscode/worker-private.pem" do
  owner node["private_chef"]["user"]["username"]
  group "root"
  mode "0600"
  content worker_key.to_pem.to_s unless File.exists?('/etc/opscode/worker-public.pem')
end

unless File.exists?('/etc/opscode/pivotal.pem')
  cert, key = OmnibusHelper.gen_certificate
end

file "/etc/opscode/pivotal.cert" do
  owner "root"
  group "root"
  mode "0644"
  content cert.to_s unless File.exists?('/etc/opscode/pivotal.pem')
end

file "/etc/opscode/pivotal.pem" do
  owner node["private_chef"]["user"]["username"]
  group "root"
  mode "0600"
  content key.to_pem.to_s unless File.exists?('/etc/opscode/pivotal.pem')
end

directory "/etc/chef" do
  owner "root"
  group node['private_chef']['user']['username']
  mode "0775"
  action :create
end

directory "/var/opt/opscode" do
  owner "root"
  group "root"
  mode "0755"
  recursive true
  action :create
end

# Install our runit instance
include_recipe "runit"

# Configure Services
[
  "drbd",
  "couchdb",
  "varnish",
  "rabbitmq",
  "postgresql",
  "mysql",
  "redis",
  "bifrost",
  "opscode-certificate",
  "opscode-account",
  "opscode-solr",
  "opscode-expander",
  "bookshelf",
  "bootstrap",
  "opscode-org-creator",
  "opscode-erchef",
  "opscode-webui",
  "nagios",
  "nrpe",
  "nginx",
  "varnish",
	"keepalived"
].each do |service|
  if node["private_chef"][service]["enable"]
    include_recipe "private-chef::#{service}"
  else
    include_recipe "private-chef::#{service}_disable"
  end
end

include_recipe "private-chef::orgmapper"
include_recipe "private-chef::oc-chef-pedant"
include_recipe "private-chef::log_cleanup"
include_recipe "private-chef::partybus"

file "/etc/opscode/chef-server-running.json" do
  owner node["private_chef"]["user"]["username"]
  group "root"
  mode "0600"
  content Chef::JSONCompat.to_json_pretty({ "private_chef" => node['private_chef'].to_hash, "run_list" => node.run_list })
end
