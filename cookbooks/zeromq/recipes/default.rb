include_recipe "build-essential"

zeromq_tar_gz = File.join(Chef::Config[:file_cache_path], "/", "zeromq-#{node[:zeromq][:version]}.tar.gz")

remote_file zeromq_tar_gz do
  source "#{node[:zeromq][:url]}/zeromq-#{node[:zeromq][:version]}.tar.gz"
end

package "uuid-dev" do
  action :upgrade
end

bash "install zeromq #{node[:zeromq][:version]}" do
  cwd Chef::Config[:file_cache_path]
  code <<-EOH
    tar -zxf #{zeromq_tar_gz}
    cd zeromq-#{node[:zeromq][:version]} && ./configure && make && make install && ldconfig
  EOH
  not_if { ::FileTest.exists?("/usr/local/lib/libzmq.so") }
end