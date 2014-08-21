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


# Create user and group first, so we have control over uid and gid instead of leaving it to fate
if %x(grep #{node.memsql.owner} /etc/passwd | wc -l).strip.to_i == 0
  group node.memsql.group do
    gid node.memsql.gid
  end

  user node.memsql.owner do
    uid node.memsql.uid
    group node.memsql.group
  end
end

#TODO refactor
filtered = node.memsql.node_scope.enabled ? node.memsql.node_scope.filter : ""

#install client libs
if node.platform_family == 'debian'
  include_recipe 'apt::default'
  execute 'apt-get update'
end
%w(ntp g++ mysql-client libmysqlclient-dev python-dev).each do |pkg|
  package pkg do
    action [:install, :upgrade]
  end
end

remote_file "#{Chef::Config[:file_cache_path]}/memsql-#{node[:memsql][:version]}" do
  source "#{node[:memsql][:url]}/#{node[:memsql][:license]}/memsql-#{node[:memsql][:version]}"
  action :create_if_missing
end

dpkg_package "memsql" do
  source  "#{Chef::Config[:file_cache_path]}/memsql-#{node[:memsql][:version]}"
  action [:install, :upgrade]
end

#start memsql
service "memsql" do
  supports :status => true, :restart => true, :reload => true, :start => true, :stop => true
  action [:enable, :start]
end

#find the master aggregator
master_aggregator = search(:node, "role:memsql_master_aggregator #{filtered}").first || node

#find leaf nodes
leaves = search(:node, "role:memsql_leaf #{filtered}")

#attaches leaf to master aggregator
leaves.each do |node|
  #Todo
  #attach the leaf on the master aggregator
  Chef::Log.info("leaf #{node["name"]} has IP address #{node["ipaddress"]}")
end

template "/var/lib/memsql/memsql.cnf" do
  source "memsql.cnf.erb"
  mode 0600
  owner "memsql"
  group "memsql"
  variables({
                :master_aggregator_ip => node.run_list.roles.include?("memsql_child_aggregator") ? master_aggregator["ipaddress"] : nil,
                :is_master => node.run_list.roles.include?("memsql_master_aggregator") ? true : false,
                :redundancy_level => node.memsql.redundancy_level
            })
end

node[:memsql][:users].each do |user|
  %x(sudo mysql -u root -h #{master_aggregator[:ipaddress]} -e "grant all on *.* to '#{user[:name]}'@'localhost' identified by '#{user[:password]}'; flush privileges;")
end

if node.memsql.ops.enabled
  include_recipe "memsql::collectd"
end
