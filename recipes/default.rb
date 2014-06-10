#
# Cookbook Name:: memsql
# Recipe:: default
#
# Copyright 2014, Chris Molle
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#        node.run_list.roles.include?('base')

package "libmysqlclient-dev" do
  action :install
end

remote_file "#{Chef::Config[:file_cache_path]}/memsql-#{node[:memsql][:version]}" do
  source "#{node[:memsql][:url]}/#{node[:memsql][:license]}/memsql-#{node[:memsql][:version]}"
  action :create_if_missing
end

dpkg_package node[:memsql][:version] do
  source  "#{Chef::Config[:file_cache_path]}/memsql-#{node[:memsql][:version]}"
  action :install
end

service "memsql" do
  supports :status => true, :restart => true, :reload => true, :start => true, :stop => true
  action [ :enable, :start ]
end


master_aggregator = search(:node, "role:memsql_master_aggregator").first


child_aggregators = search(:node, "role:memsql_child_aggregator")
child_aggregators.each do |node|
  Chef::Log.info("leaf #{node["name"]} has IP address #{node["ipaddress"]}")
end

leaves = search(:node, "role:memsql_leaf")
leaves.each do |node|
  Chef::Log.info("leaf #{node["name"]} has IP address #{node["ipaddress"]}")
end


template "/var/lib/memsql.cnf" do
  source "memsql.cnf"
  mode 0600
  owner "memsql"
  group "memsql"
  variables({
               :master_aggregator_ip => node.run_list.roles.include?("child_aggregator") ? master_aggregator["ipaddress"] : nil,
               :is_master => node.run_list.roles.include?("master_aggregator") ? true : false
            })
end
