# Copyright (c) 2010-2019 SUSE
# Licensed under the terms of the MIT license.

require 'jwt'
require 'securerandom'
require 'pathname'

When(/^I save a screenshot as "([^"]+)"$/) do |filename|
  save_screenshot(filename)
end

When(/^I wait for "(\d+)" seconds?$/) do |arg1|
  sleep(arg1.to_i)
end

When(/^I download the SSL certificate$/) do
  cert_path = '/usr/share/rhn/RHN-ORG-TRUSTED-SSL-CERT'
  wget = 'wget --no-check-certificate -O'
  $client.run("#{wget} #{cert_path} http://#{$server.ip}/pub/RHN-ORG-TRUSTED-SSL-CERT", true, 500, 'root')
  $client.run("ls #{cert_path}")
end

When(/^I make the SSL certificate available to zypper$/) do
  cert_path = '/usr/share/rhn/RHN-ORG-TRUSTED-SSL-CERT'
  trust_path = '/etc/pki/trust/anchors'
  $client.run("cd #{trust_path} && ln -sf #{cert_path}")
  $client.run('update-ca-certificates')
end

Then(/^I can see all system information for "([^"]*)"$/) do |host|
  node = get_target(host)
  step %(I should see a "#{node.hostname}" text)
  kernel_version, _code = node.run('uname -r')
  puts 'i should see kernel version: ' + kernel_version
  step %(I should see a "#{kernel_version.strip}" text)
  os_pretty_raw, _code = node.run('grep "PRETTY" /etc/os-release')
  os_pretty = os_pretty_raw.strip.split('=')[1].delete '"'
  # skip this test for centos and ubuntu systems
  puts 'i should see os version: ' + os_pretty if os_pretty.include? 'SUSE Linux'
  step %(I should see a "#{os_pretty}" text) if os_pretty.include? 'SUSE Linux'
end

# events

When(/^I wait until event "([^"]*)" is completed$/) do |event|
  steps %(
    When I wait at most #{DEFAULT_TIMEOUT} seconds until event "#{event}" is completed
  )
end

When(/^I wait at most (\d+) seconds until event "([^"]*)" is completed$/) do |final_timeout, event|
  # The code below is not perfect because there might be other events with the
  # same name in the events history - however, that's the best we have so far.
  steps %(
    When I follow "Events"
    And I follow "Pending"
    And I wait until I do not see "#{event}" text, refreshing the page
    And I follow "History"
    And I wait until I see "System History" text
    And I wait until I see "#{event}" text, refreshing the page
    And I follow first "#{event}"
    And I wait at most #{final_timeout} seconds until the event is completed, refreshing the page
  )
end

When(/^I wait until I see the event "([^"]*)" completed during last minute, refreshing the page$/) do |event|
  repeat_until_timeout(message: "Couldn't find the event #{event}") do
    now = Time.now
    current_minute = now.strftime('%H:%M')
    previous_minute = (now - 60).strftime('%H:%M')
    break if all(:xpath, "//a[contains(text(),'#{event}')]/../..//td[4][contains(text(),'#{current_minute}') or contains(text(),'#{previous_minute}')]/../td[3]/a[1]").any?
    sleep 1
    page.evaluate_script 'window.location.reload()'
  end
end

When(/^I follow the event "([^"]*)" completed during last minute$/) do |event|
  now = Time.now
  current_minute = now.strftime('%H:%M')
  previous_minute = (now - 60).strftime('%H:%M')
  xpath_query = "//a[contains(text(), '#{event}')]/../..//td[4][contains(text(),'#{current_minute}') or contains(text(),'#{previous_minute}')]/../td[3]/a[1]"
  raise unless find(:xpath, xpath_query).click
end

# spacewalk errors steps
Then(/^the up2date logs on client should contain no Traceback error$/) do
  cmd = 'if grep "Traceback" /var/log/up2date ; then exit 1; else exit 0; fi'
  _out, code = $client.run(cmd)
  raise 'error found, check the client up2date logs' if code.nonzero?
end

# salt failures log check
Then(/^the salt event log on server should contain no failures$/) do
  # upload salt event parser log
  file = 'salt_event_parser.py'
  source = File.dirname(__FILE__) + '/../upload_files/' + file
  dest = "/tmp/" + file
  return_code = file_inject($server, source, dest)
  raise 'File injection failed' unless return_code.zero?
  # print failures from salt event log
  output = $server.run("python3 /tmp/#{file}")
  count_failures = output.to_s.scan(/false/).length
  raise "\nFound #{count_failures} failures in salt event log:\n#{output.join.to_s}\n" if count_failures.nonzero?
end

# action chains
When(/^I check radio button "(.*?)"$/) do |arg1|
  raise unless choose(arg1)
end

When(/^I enter as remote command this script in$/) do |multiline|
  find(:xpath, '//textarea[@name="script_body"]').set(multiline)
end

# bare metal
When(/^I check the ram value$/) do
  get_ram_value = "grep MemTotal /proc/meminfo |awk '{print $2}'"
  ram_value, _local, _remote, _code = $client.test_and_store_results_together(get_ram_value, 'root', 600)
  ram_value = ram_value.gsub(/\s+/, '')
  ram_mb = ram_value.to_i / 1024
  step %(I should see a "#{ram_mb}" text)
end

When(/^I check the MAC address value$/) do
  get_mac_address = 'cat /sys/class/net/eth0/address'
  mac_address, _local, _remote, _code = $client.test_and_store_results_together(get_mac_address, 'root', 600)
  mac_address = mac_address.gsub(/\s+/, '')
  mac_address.downcase!
  step %(I should see a "#{mac_address}" text)
end

Then(/^I should see the CPU frequency of the client$/) do
  get_cpu_freq = "lscpu  | grep 'CPU MHz'" # | awk '{print $4}'"
  cpu_freq, _local, _remote, _code = $client.test_and_store_results_together(get_cpu_freq, 'root', 600)
  get_cpu = cpu_freq.gsub(/\s+/, '')
  cpu = get_cpu.split('.')
  cpu = cpu[0].gsub(/[^\d]/, '')
  step %(I should see a "#{cpu.to_i / 1000} GHz" text)
end

Then(/^I should see the power is "([^"]*)"$/) do |arg1|
  within(:xpath, "//*[@for='powerStatus']/..") do
    10.times do
      break if has_content?(arg1)
      find(:xpath, '//button[@value="Get status"]').click unless has_content?(arg1)
      sleep 3
    end
    raise unless has_content?(arg1)
  end
end

When(/^I select "(.*?)" as the origin channel$/) do |label|
  step %(I select "#{label}" from "original_id")
end

Then(/^I add "([^"]*)" channel$/) do |channel|
  $server.run("echo -e \"admin\nadmin\n\" | mgr-sync add channel #{channel}")
end

# channel steps
When(/^I use spacewalk\-channel to add test-channel-x86_64-child-channel/) do
  child_channel = 'test-channel-x86_64-child-channel'
  step %(I execute spacewalk\-channel and pass "--add -c #{child_channel} -u admin -p admin")
end

When(/^I use spacewalk\-channel to remove test-channel-x86_64-child-channel/) do
  child_channel = 'test-channel-x86_64-child-channel'
  step %(I execute spacewalk\-channel and pass "--remove -c #{child_channel} -u admin -p admin")
end

And(/^I navigate to "([^"]*)" page$/) do |page|
  visit("https://#{$server.full_hostname}/#{page}")
end

# nagios steps

When(/^I perform a nagios check patches for "([^"]*)"$/) do |host|
  system_name = get_system_name(host)
  command = "/usr/lib/nagios/plugins/check_suma_patches #{system_name} > /tmp/nagios.out"
  $server.run(command, false, 600, 'root')
end

When(/^I perform a nagios check last event for "([^"]*)"$/) do |host|
  system_name = get_system_name(host)
  command = "/usr/lib/nagios/plugins/check_suma_lastevent #{system_name} > /tmp/nagios.out"
  $server.run(command, false, 600, 'root')
end

When(/^I perform an invalid nagios check patches$/) do
  command = '/usr/lib/nagios/plugins/check_suma_patches does.not.exist > /tmp/nagios.out'
  $server.run(command, false, 600, 'root')
end

Then(/^I should see CRITICAL: 1 critical patch pending$/) do
  command = 'grep "CRITICAL: 1 critical patch(es) pending" /tmp/nagios.out'
  $server.run(command, true, 600, 'root')
end

Then(/^I should see Completed: OpenSCAP xccdf scanning scheduled by admin/) do
  command = 'grep "Completed: OpenSCAP xccdf scanning scheduled by admin" /tmp/nagios.out'
  $server.run(command, true, 600, 'root')
end

Then(/^I should see an unknown system message$/) do
  command = 'grep -i "^Unknown system:.*does.not.exist" /tmp/nagios.out 2>&1'
  $server.run(command, true, 600, 'root')
end

# systemspage and clobber
Given(/^I am on the Systems page$/) do
  steps %(
    When I am authorized as "admin" with password "admin"
    When I follow the left menu "Systems > Overview"
  )
end

Given(/cobblerd is running/) do
  ct = CobblerTest.new
  raise 'cobblerd is not running' unless ct.running?
end

Then(/create distro "([^"]*)" as user "([^"]*)" with password "([^"]*)"/) do |distro, user, pwd|
  ct = CobblerTest.new
  ct.login(user, pwd)
  raise 'distro ' + distro + ' already exists' if ct.distro_exists(distro)
  ct.distro_create(distro, '/install/SLES11-SP1-x86_64/DVD1/boot/x86_64/loader/linux', 'install/SLES11-SP1-x86_64/DVD1/boot/x86_64/loader/initrd')
end

When(/^I trigger cobbler system record$/) do
  # not for SSH-push traditional client
  space = 'spacecmd -u admin -p admin'
  host = $client.full_hostname
  $server.run("#{space} clear_caches")
  out, _code = $server.run("#{space} system_details #{host}")
  unless out.include? 'ssh-push-tunnel'
    # normal traditional client
    steps %(
      And I follow this "sle-client" link
      And I follow "Provisioning"
      And I click on "Create PXE installation configuration"
      And I click on "Continue"
      And I wait until file "/srv/tftpboot/pxelinux.cfg/01-*" contains "ks=" on server
      )
  end
end

Given(/distro "([^"]*)" exists/) do |distro|
  ct = CobblerTest.new
  raise 'distro ' + distro + ' does not exist' unless ct.distro_exists(distro)
end

Then(/create profile "([^"]*)" as user "([^"]*)" with password "([^"]*)"/) do |arg1, arg2, arg3|
  ct = CobblerTest.new
  ct.login(arg2, arg3)
  raise 'profile ' + arg1 + ' already exists' if ct.profile_exists(arg1)
  ct.profile_create('testprofile', 'testdistro', '/install/empty.xml')
end

When(/^I remove kickstart profiles and distros$/) do
  host = $server.full_hostname
  @cli = XMLRPC::Client.new2('http://' + host + '/rpc/api')
  @sid = @cli.call('auth.login', 'admin', 'admin')
  # -------------------------------
  # cleanup kickstart profiles and distros
  distro_name = 'fedora_kickstart_distro'
  @cli.call('kickstart.tree.delete_tree_and_profiles', @sid, distro_name)
  @cli.call('auth.logout', @sid)
  # -------------------------------
  # remove not from suma managed profile
  $server.run('cobbler profile remove --name "testprofile"')
  # remove not from suma managed distro
  $server.run('cobbler distro remove --name "testdistro"')
end

When(/^I attach the file "(.*)" to "(.*)"$/) do |path, field|
  canonical_path = Pathname.new(File.join(File.dirname(__FILE__), '/../upload_files/', path)).cleanpath
  attach_file(field, canonical_path)
end

When(/I view system with id "([^"]*)"/) do |arg1|
  visit Capybara.app_host + '/rhn/systems/details/Overview.do?sid=' + arg1
end

# weak dependencies steps
When(/^I refresh the metadata for "([^"]*)"$/) do |host|
  case host
  when 'sle-client'
    $client.run('rhn_check -vvv', true, 500, 'root')
    client_refresh_metadata
  when 'sle-minion'
    $minion.run_until_ok('zypper --non-interactive refresh -s')
  else
    raise 'Invalid target.'
  end
end

Then(/^channel "([^"]*)" should be enabled on "([^"]*)"$/) do |channel, host|
  node = get_target(host)
  node.run("zypper lr -E | grep '#{channel}'")
end

Then(/^channel "([^"]*)" should not be enabled on "([^"]*)"$/) do |channel, host|
  node = get_target(host)
  _out, code = node.run("zypper lr -E | grep '#{channel}'", false)
  raise "'#{channel}' was not expected but was found." if code.to_i.zero?
end

Then(/^"(\d+)" channels should be enabled on "([^"]*)"$/) do |count, host|
  node = get_target(host)
  _out, code = node.run("zypper lr -E | tail -n +5 | wc -l")
  raise "Expected #{count} channels enabled but found #{_out}." unless count.to_i == _out.to_i
end

Then(/^"(\d+)" channels with prefix "([^"]*)" should be enabled on "([^"]*)"$/) do |count, prefix, host|
  node = get_target(host)
  _out, code = node.run("zypper lr -E | tail -n +5 | grep '#{prefix}' | wc -l")
  raise "Expected #{count} channels enabled but found #{_out}." unless count.to_i == _out.to_i
end

Then(/^I should have '([^']*)' in the metadata for "([^"]*)"$/) do |text, host|
  raise 'Invalid target.' unless host == 'sle-client'
  target = $client
  arch, _code = target.run('uname -m')
  arch.chomp!
  cmd = "zgrep '#{text}' #{client_raw_repodata_dir("test-channel-#{arch}")}/primary.xml.gz"
  target.run(cmd, true, 500, 'root')
end

Then(/^I should not have '([^']*)' in the metadata for "([^"]*)"$/) do |text, host|
  raise 'Invalid target.' unless host == 'sle-client'
  target = $client
  arch, _code = target.run('uname -m')
  arch.chomp!
  cmd = "zgrep '#{text}' #{client_raw_repodata_dir("test-channel-#{arch}")}/primary.xml.gz"
  target.run(cmd, true, 500, 'root')
end

Then(/^"([^"]*)" should exist in the metadata for "([^"]*)"$/) do |file, host|
  raise 'Invalid target.' unless host == 'sle-client'
  node = $client
  arch, _code = node.run('uname -m')
  arch.chomp!
  raise unless file_exists?(node, "#{client_raw_repodata_dir("test-channel-#{arch}")}/#{file}")
end

Then(/^I should have '([^']*)' in the patch metadata$/) do |text|
  arch, _code = $client.run('uname -m')
  arch.chomp!
  cmd = "zgrep '#{text}' #{client_raw_repodata_dir("test-channel-#{arch}")}/updateinfo.xml.gz"
  $client.run(cmd, true, 500, 'root')
end

# package steps
Then(/^I should see package "([^"]*)"$/) do |package|
  raise unless all(:xpath, "//div[@class=\"table-responsive\"]/table/tbody/tr/td/a[contains(.,'#{package}')]").any?
end

Given(/^I am on the manage software channels page$/) do
  step %(I am authorized as "testing" with password "testing")
  visit("https://#{$server.full_hostname}/rhn/channels/manage/Manage.do")
end

Given(/^metadata generation finished for "([^"]*)"$/) do |channel|
  $server.run_until_ok("ls /var/cache/rhn/repodata/#{channel}/updateinfo.xml.gz")
end

When(/^I push package "([^"]*)" into "([^"]*)" channel$/) do |arg1, arg2|
  srvurl = "http://#{ENV['SERVER']}/APP"
  command = "rhnpush --server=#{srvurl} -u admin -p admin --nosig -c #{arg2} #{arg1} "
  $server.run(command, true, 500, 'root')
  $server.run('ls -lR /var/spacewalk/packages', true, 500, 'root')
end

Then(/^I should see package "([^"]*)" in channel "([^"]*)"$/) do |pkg, channel|
  steps %(
    When I follow the left menu "Software > Channel List > All"
    And I follow "#{channel}"
    And I follow "Packages"
    Then I should see package "#{pkg}"
    )
end

# setup wizard

When(/^I make the credentials primary$/) do
  raise unless find('i.fa-star-o').click
end

When(/^I delete the primary credentials$/) do
  raise unless find('i.fa-trash-o', match: :first).click
  step 'I click on "Delete"'
end

When(/^I view the primary subscription list$/) do
  raise unless find('i.fa-th-list', match: :first).click
end

When(/^I view the primary subscription list for SCC user$/) do
  within(:xpath, "//h3[contains(text(), 'SCC user')]/../..") do
    raise unless find('i.fa-th-list', match: :first).click
  end
end

And(/^I select "(.*?)" in the dropdown list of the architecture filter$/) do |architecture|
  # let the the select2js box filter open the hidden options
  raise unless find(:xpath, "//div[@id='s2id_product-arch-filter']/ul/li/input").click
  # select the desired option
  raise unless find(:xpath, "//div[@id='select2-drop']/ul/li/div[contains(text(), '#{architecture}')]").click
end

When(/^I select "([^\"]*)" as a product$/) do |product|
  # click on the checkbox to select the product
  xpath = "//span[contains(text(), '#{product}')]/ancestor::div[contains(@class, 'product-details-wrapper')]/div/input[@type='checkbox']"
  raise unless find(:xpath, xpath).set(true)
end

And(/^I open the sub-list of the product "(.*?)"$/) do |product|
  xpath = "//span[contains(text(), '#{product}')]/ancestor::div[contains(@class, 'product-details-wrapper')]/div/i[contains(@class, 'fa-angle-right')]"
  # within(:xpath, xpath) do
  #   raise unless find('i.fa-angle-down').click
  # end
  raise unless find(:xpath, xpath).click
end

When(/^I select the addon "(.*?)"$/) do |addon|
  # click on the checkbox of the sublist to select the addon product
  xpath = "//span[contains(text(), '#{addon}')]/ancestor::div[contains(@class, 'product-details-wrapper')]/div/input[@type='checkbox']"
  raise unless find(:xpath, xpath).set(true)
end

And(/^I should see that the "(.*?)" product is "(.*?)"$/) do |product, recommended|
  xpath = "//span[text()[normalize-space(.) = '#{product}'] and ./span/text() = '#{recommended}']"
  raise unless find(:xpath, xpath)
end

Then(/^I should see the "(.*?)" selected$/) do |product|
  xpath = "//span[contains(text(), '#{product}')]/ancestor::div[contains(@class, 'product-details-wrapper')]"
  product_identifier = find(:xpath, xpath)['data-identifier']
  raise unless has_checked_field?('checkbox-for-' + product_identifier)
end

And(/^I wait until I see "(.*?)" product has been added$/) do |product|
  repeat_until_timeout(message: "Couldn't find the installed product #{product} in the list") do
    xpath = "//span[contains(text(), '#{product}')]/ancestor::div[contains(@class, 'product-details-wrapper')]"
    product_wrapper = find(:xpath, xpath)
    break if product_wrapper[:class].include?('product-installed')
    sleep 1
  end
end

When(/^I click the Add Product button$/) do
  raise unless find('button#addProducts').click
end

Then(/^the SLE12 products should be added$/) do
  output = sshcmd('echo -e "admin\nadmin\n" | mgr-sync list channels', ignore_err: true)
  sle_module = '[I] SLE-Module-Legacy12-Updates for x86_64 Legacy Module 12 x86_64 [sle-module-legacy12-updates-x86_64-sp2]'
  raise unless output[:stdout].include? '[I] SLES12-SP2-Pool for x86_64 SUSE Linux Enterprise Server 12 SP2 x86_64 [sles12-sp2-pool-x86_64]'
  raise unless output[:stdout].include? sle_module
end

Then(/^the SLE15 products should be added$/) do
  output = sshcmd('echo -e "admin\nadmin\n" | mgr-sync list channels', ignore_err: true)
  raise unless output[:stdout].include? '[I] SLE-Product-SLES15-Pool for x86_64 SUSE Linux Enterprise Server 15 x86_64 [sle-product-sles15-pool-x86_64]'
  raise unless output[:stdout].include? '[I] SLE-Module-Basesystem15-Updates for x86_64 Basesystem Module 15 x86_64 [sle-module-basesystem15-updates-x86_64]'
  raise unless output[:stdout].include? '[I] SLE-Module-Server-Applications15-Pool for x86_64 Server Applications Module 15 x86_64 [sle-module-server-applications15-pool-x86_64]'
end

When(/^I click the channel list of product "(.*?)"$/) do |product|
  xpath = "//span[contains(text(), '#{product}')]/ancestor::div[contains(@class, 'product-details-wrapper')]/div/a[contains(@class, 'showChannels')]"
  raise unless find(:xpath, xpath).click
end

Then(/^I see verification succeeded/) do
  10.times do
    begin
      break if find('i.text-success')
    rescue Capybara::ElementNotFound
      sleep 3
    end
  end
  find('i.text-success')
end

When(/^I enter the address of the HTTP proxy as "([^"]*)"/) do |hostname|
  step %(I enter "#{$server_http_proxy}" as "#{hostname}")
end

# configuration management steps

Then(/^I should see a table line with "([^"]*)", "([^"]*)", "([^"]*)"$/) do |arg1, arg2, arg3|
  within(:xpath, "//div[@class=\"table-responsive\"]/table/tbody/tr[.//td[contains(.,'#{arg1}')]]") do
    raise unless find_link(arg2)
    raise unless find_link(arg3)
  end
end

Then(/^I should see a table line with "([^"]*)", "([^"]*)"$/) do |arg1, arg2|
  within(:xpath, "//div[@class=\"table-responsive\"]/table/tbody/tr[.//td[contains(.,'#{arg1}')]]") do
    raise unless find_link(arg2)
  end
end

Then(/^a table line should contain system "([^"]*)", "([^"]*)"$/) do |host, text|
  system_name = get_system_name(host)
  within(:xpath, "//div[@class=\"table-responsive\"]/table/tbody/tr[.//td[contains(.,'#{system_name}')]]") do
    raise unless find_all(:xpath, "//td[contains(., '#{text}')]")
  end
end

# generic file management steps

When(/^I destroy "([^"]*)" directory on server$/) do |directory|
  $server.run("rm -rf #{directory}")
end

When(/^I destroy "([^"]*)" directory on "([^"]*)"$/) do |directory, host|
  node = get_target(host)
  node.run("rm -rf #{directory}")
end

When(/^I remove "([^"]*)" from "([^"]*)"$/) do |filename, host|
  node = get_target(host)
  file_delete(node, filename)
end

Then(/^file "([^"]*)" should exist on server$/) do |filename|
  $server.run("test -f #{filename}")
end

Then(/^file "([^"]*)" should exist on "([^"]*)"$/) do |filename, host|
  node = get_target(host)
  node.run("test -f #{filename}", true)
end

Then(/^file "([^"]*)" should not exist on server$/) do |filename|
  $server.run("test ! -f #{filename}")
end

When(/^I store "([^"]*)" into file "([^"]*)" on "([^"]*)"$/) do |content, filename, host|
  node = get_target(host)
  node.run("echo \"#{content}\" > #{filename}", true, 600, 'root')
end

When(/^I set the activation key "([^"]*)" in the bootstrap script on the server$/) do |key|
  $server.run("sed -i '/^ACTIVATION_KEYS=/c\\ACTIVATION_KEYS=#{key}' /srv/www/htdocs/pub/bootstrap/bootstrap.sh")
  output, code = $server.run('cat /srv/www/htdocs/pub/bootstrap/bootstrap.sh')
  assert(output.include?(key))
end

Then(/^file "([^"]*)" should contain "([^"]*)" on "([^"]*)"$/) do |filename, content, host|
  node = get_target(host)
  node.run("test -f #{filename}")
  node.run("grep \"#{content}\" #{filename}")
end

Then(/^I remove server hostname from hosts file on "([^"]*)"$/) do |host|
  node = get_target(host)
  node.run("sed -i \'s/#{$server.full_hostname}//\' /etc/hosts")
end

Then(/^the image "([^"]*)" should exist on "([^"]*)"$/) do |image, host|
  node = get_target(host)
  images, _code = node.run("ls /srv/saltboot/image/")
  raise "Image #{image} does not exist on #{host}" unless images.include? image
end

# Repository steps

When(/^I enable SUSE Manager tools repository on "([^"]*)"$/) do |host|
  node = get_target(host)
  out, _code = node.run('zypper lr | grep SLE-Manager-Tools | cut -d"|" -f2')
  # This enables tools development repository too if it exists
  node.run("zypper mr --enable #{out.gsub(/\s/, ' ')}")
end

When(/^I enable repositories before installing Docker$/) do
  # Distribution Pool and Update
  os_version, os_family = get_os_version($minion)
  if os_family =~ /^opensuse/
    repos = "openSUSE-Leap-#{os_version}-Pool openSUSE-Leap-#{os_version}-Update"
    puts $minion.run("zypper mr --enable #{repos}")
  elsif os_version =~ /^15/
    repos, _code = $minion.run('zypper lr | grep SLE-Module-Basesystem | cut -d"|" -f2')
    puts $minion.run("zypper mr --enable #{repos.gsub(/\s/, ' ')}")
  else
    arch, _code = $minion.run('uname -m')
    repos = "SLE-#{os_version}-#{arch.strip}-Pool SLE-#{os_version}-#{arch.strip}-Update"
    puts $minion.run("zypper mr --enable #{repos}")
  end

  # Tools
  repos, _code = $minion.run('zypper lr | grep SLE-Manager-Tools | cut -d"|" -f2')
  puts $minion.run("zypper mr --enable #{repos.gsub(/\s/, ' ')}")

  # Container repositories
  # They don't exist for SLES11 systems, only for SLES12 and upper systems
  unless os_version =~ /^11/
    repos, _code = $minion.run('zypper lr | grep SLE-Manager-Tools | cut -d"|" -f2')
    $minion.run("zypper mr --enable #{repos.gsub(/\s/, ' ')}")
    repos, _code = $minion.run('zypper lr | grep SLE-Module-Containers | cut -d"|" -f2')
    $minion.run("zypper mr --enable #{repos.gsub(/\s/, ' ')}")
  end

  $minion.run('zypper -n --gpg-auto-import-keys ref')
end

When(/^I disable repositories after installing Docker$/) do
  # Distribution Pool and Update
  os_version, os_family = get_os_version($minion)
  if os_family =~ /^opensuse/
    repos = "openSUSE-Leap-#{os_version}-Pool openSUSE-Leap-#{os_version}-Update"
    puts $minion.run("zypper mr --disable #{repos}")
  elsif os_version =~ /^15/
    repos, _code = $minion.run('zypper lr | grep SLE-Module-Basesystem | cut -d"|" -f2')
    puts $minion.run("zypper mr --disable #{repos.gsub(/\s/, ' ')}")
  else
    arch, _code = $minion.run('uname -m')
    repos = "SLE-#{os_version}-#{arch.strip}-Pool SLE-#{os_version}-#{arch.strip}-Update"
    puts $minion.run("zypper mr --disable #{repos}")
  end

  # Tools
  repos, _code = $minion.run('zypper lr | grep SLE-Manager-Tools | cut -d"|" -f2')
  puts $minion.run("zypper mr --disable #{repos.gsub(/\s/, ' ')}")

  # Container repositories
  # They don't exist for SLES11 systems, only for SLES12 and upper systems
  unless os_version =~ /^11/
    repos, _code = $minion.run('zypper lr | grep SLE-Manager-Tools | cut -d"|" -f2')
    $minion.run("zypper mr --disable #{repos.gsub(/\s/, ' ')}")
    repos, _code = $minion.run('zypper lr | grep SLE-Module-Containers | cut -d"|" -f2')
    $minion.run("zypper mr --disable #{repos.gsub(/\s/, ' ')}")
  end

  $minion.run('zypper -n --gpg-auto-import-keys ref')
end

When(/^I enable repositories before installing branch server$/) do
  # Distribution Pool and Update
  os_version, os_family = get_os_version($proxy)
  if os_family =~ /^opensuse/
    repos = "openSUSE-Leap-#{os_version}-Pool openSUSE-Leap-#{os_version}-Update"
    puts $proxy.run("zypper mr --enable #{repos}")
  elsif os_version =~ /^15/
    repos, _code = $proxy.run('zypper lr | grep -E "SLE-Module-Basesystem|SLE-Module-Server-Applications" | cut -d"|" -f2')
    puts $proxy.run("zypper mr --enable #{repos.gsub(/\s/, ' ')}")
  else
    arch, _code = $proxy.run('uname -m')
    repos = "SLE-#{os_version}-#{arch.strip}-Pool SLE-#{os_version}-#{arch.strip}-Update"
    puts $proxy.run("zypper mr --enable #{repos}")
  end
end

When(/^I disable repositories after installing branch server$/) do
  # Distribution Pool and Update
  os_version, os_family = get_os_version($proxy)
  if os_family =~ /^opensuse/
    repos = "openSUSE-Leap-#{os_version}-Pool openSUSE-Leap-#{os_version}-Update"
    puts $proxy.run("zypper mr --disable #{repos}")
  elsif os_version =~ /^15/
    repos, _code = $proxy.run('zypper lr | grep -E "SLE-Module-Basesystem|SLE-Module-Server-Applications" | cut -d"|" -f2')
    puts $proxy.run("zypper mr --disable #{repos.gsub(/\s/, ' ')}")
  else
    arch, _code = $proxy.run('uname -m')
    repos = "SLE-#{os_version}-#{arch.strip}-Pool SLE-#{os_version}-#{arch.strip}-Update"
    puts $proxy.run("zypper mr --disable #{repos}")
  end
end

# Register client
Given(/^I update the profile of this client$/) do
  $client.run('rhn-profile-sync', true, 500, 'root')
end

When(/^I register using "([^"]*)" key$/) do |key|
  command = "rhnreg_ks --force --serverUrl=#{registration_url} --activationkey=#{key}"
  $client.run(command, true, 500, 'root')
end

Then(/^I should see "([^"]*)" in spacewalk$/) do |host|
  steps %(
    Given I am on the Systems page
    Then I should see "#{host}" as link
    )
end

Then(/^I should see "([^"]*)" as link$/) do |host|
  system_name = get_system_name(host)
  step %(I should see a "#{system_name}" link)
end

Then(/^config-actions are enabled$/) do
  unless file_exists?($client, '/etc/sysconfig/rhn/allowed-actions/configfiles/all')
    raise 'config actions are disabled: /etc/sysconfig/rhn/allowed-actions/configfiles/all does not exist on client'
  end
end

Then(/^remote-commands are enabled$/) do
  unless file_exists?($client, '/etc/sysconfig/rhn/allowed-actions/script/run')
    raise 'remote commands are disabled: /etc/sysconfig/rhn/allowed-actions/script/run does not exist'
  end
end

When(/^I remember when I scheduled an action$/) do
  moment = "schedule_action"
  val = DateTime.now
  if defined?($moments)
    $moments[moment] = val
  else
    $moments = {moment => val}
  end
end

Then(/^I should see "([^"]*)" at least (\d+) minutes after I scheduled an action$/) do |text, minutes|
  # TODO is there a better way then page.all ?
  elements = page.all('div', text: text)
  raise if elements.nil?
  match = elements[0].text.match(/#{text}\s*(\d+\/\d+\/\d+ \d+:\d+:\d+ (AM|PM)+ [^\s]+)/)
  raise "No element found matching text '#{text}'" if match.nil?
  text_time = DateTime.strptime("#{match.captures[0]}", '%m/%d/%C %H:%M:%S %p %Z')
  raise "Time the action was scheduled not found in memory" unless defined?($moments) and $moments["schedule_action"]
  initial = $moments["schedule_action"]
  after = initial + Rational(1, 1440) * minutes.to_i
  raise "#{text_time.to_s} is not #{minutes} minutes later than '#{initial.to_s}'" unless (text_time + Rational(1, 1440)) >= after
end

# Valid claims:
#   - org
#   - onlyChannels
def token(secret, claims = {})
  payload = {}
  payload.merge!(claims)
  puts secret
  JWT.encode payload, [secret].pack('H*').bytes.to_a.pack('c*'), 'HS256'
end

def server_secret
  rhnconf = sshcmd('cat /etc/rhn/rhn.conf')[:stdout]
  data = /server.secret_key\s*=\s*(\h+)$/.match(rhnconf)
  data[1].strip
end

Given(/^I have a valid token for organization "([^"]*)"$/) do |org|
  @token = token(server_secret, org: org.to_i)
end

Given(/^I have an invalid token for organization "([^"]*)"$/) do |org|
  @token = token(SecureRandom.hex(64), org: org.to_i)
end

Given(/^I have an expired valid token for organization "([^"]*)"$/) do |org|
  yesterday = Time.now.to_i - 86_400
  @token = token(server_secret, org: org.to_i, exp: yesterday)
end

Given(/^I have a valid token expiring tomorrow for organization "([^"]*)"$/) do |org|
  tomorrow = Time.now.to_i + 86_400
  @token = token(server_secret, org: org.to_i, exp: tomorrow)
end

Given(/^I have a not yet usable valid token for organization "([^"]*)"$/) do |org|
  tomorrow = Time.now.to_i + 86_400
  @token = token(server_secret, org: org.to_i, nbf: tomorrow)
end

Given(/^I have a valid token for organization "(.*?)" and channel "(.*?)"$/) do |org, channel|
  @token = token(server_secret, org: org, onlyChannels: [channel])
end

And(/^I should see the toggler "([^"]*)"$/) do |target_status|
  case target_status
  when 'enabled'
    xpath = "//i[contains(@class, 'fa-toggle-on')]"
    raise unless find(:xpath, xpath)
  when 'disabled'
    xpath = "//i[contains(@class, 'fa-toggle-off')]"
    raise unless find(:xpath, xpath)
  else
    raise 'Invalid target status.'
  end
end

And(/^I click on the "([^"]*)" toggler$/) do |target_status|
  case target_status
  when 'enabled'
    xpath = "//i[contains(@class, 'fa-toggle-on')]"
    raise unless find(:xpath, xpath).click
  when 'disabled'
    xpath = "//i[contains(@class, 'fa-toggle-off')]"
    raise unless find(:xpath, xpath).click
  else
    raise 'Invalid target status.'
  end
end

And(/^I should see the child channel "([^"]*)" "([^"]*)"$/) do |target_channel, target_status|
  step %(I should see a "#{target_channel}" text)

  xpath = "//label[contains(text(), '#{target_channel}')]"
  channel_checkbox_id = find(:xpath, xpath)['for']

  case target_status
  when 'selected'
    raise unless has_checked_field?(channel_checkbox_id)
  when 'unselected'
    raise if has_checked_field?(channel_checkbox_id)
  else
    raise 'Invalid target status.'
  end
end

And(/^I should see the child channel "([^"]*)" "([^"]*)" and "([^"]*)"$/) do |target_channel, target_status, is_disabled|
  step %(I should see a "#{target_channel}" text)

  xpath = "//label[contains(text(), '#{target_channel}')]"
  channel_checkbox_id = find(:xpath, xpath)['for']

  "disabled".eql?(is_disabled) || raise('Invalid disabled flag value')

  case target_status
  when 'selected'
    raise unless has_checked_field?(channel_checkbox_id, disabled: true)
  when 'unselected'
    raise if has_checked_field?(channel_checkbox_id, disabled: true)
  else
    raise 'Invalid target status.'
  end
end

And(/^I select the child channel "([^"]*)"$/) do |target_channel|
  step %(I should see a "#{target_channel}" text)

  xpath = "//label[contains(text(), '#{target_channel}')]"
  channel_checkbox_id = find(:xpath, xpath)['for']

  raise if has_checked_field?(channel_checkbox_id)
  find(:xpath, "//input[@id='#{channel_checkbox_id}']").click
end

And(/^I should see "([^"]*)" "([^"]*)" for the "([^"]*)" channel$/) do |target_radio, target_status, target_channel|
  xpath = "//a[contains(text(), '#{target_channel}')]"
  channel_id = find(:xpath, xpath)['href'].split('?')[1].split('=')[1]

  case target_radio
  when 'No change'
    xpath = "//input[@type='radio' and @name='ch_action_#{channel_id}' and @value='NO_CHANGE']"
  when 'Subscribe'
    xpath = "//input[@type='radio' and @name='ch_action_#{channel_id}' and @value='SUBSCRIBE']"
  when 'Unsubscribe'
    xpath = "//input[@type='radio' and @name='ch_action_#{channel_id}' and @value='UNSUBSCRIBE']"
  end

  case target_status
  when 'selected'
    raise if find(:xpath, xpath)['checked'].nil?
  when 'unselected'
    raise unless find(:xpath, xpath)['checked'].nil?
  end
end

And(/^the notification badge and the table should count the same amount of messages$/) do
  table_notifications_count = count_table_items

  badge_xpath = "//i[contains(@class, 'fa-bell')]/following-sibling::*[text()='#{table_notifications_count}']"

  if table_notifications_count == '0'
    puts "All notification-messages are read, I expect no notification badge"
    raise if all(:xpath, badge_xpath).any?
  else
    puts "Unread notification-messages count = " + table_notifications_count
    raise unless find(:xpath, badge_xpath)
  end
end

And(/^I wait until radio button "([^"]*)" is checked, refreshing the page$/) do |arg1|
  repeat_until_timeout(message: "Couldn't find checked radio button #{arg1}") do
    break if has_checked_field?(arg1)
    sleep 1
    page.evaluate_script 'window.location.reload()'
  end
end

Then(/^I check the first notification message$/) do
  if count_table_items == '0'
    puts "There are no notification messages, nothing to do then"
  else
    within(:xpath, '//section') do
      row = first(:xpath, "//div[@class=\"table-responsive\"]/table/tbody/tr[.//td]")
      row.first(:xpath, './/input[@type="checkbox"]').set(true)
    end
  end
end

And(/^I delete it via the "([^"]*)" button$/) do |target_button|
  if count_table_items != '0'
    xpath_for_delete_button = "//button[contains(text(), '#{target_button}')]"
    raise unless find(:xpath, xpath_for_delete_button).click

    step %(I wait until I see "1 message deleted successfully." text)
  end
end

And(/^I mark as read it via the "([^"]*)" button$/) do |target_button|
  if count_table_items != '0'
    xpath_for_read_button = "//button[contains(text(), '#{target_button}')]"
    raise unless find(:xpath, xpath_for_read_button).click

    step %(I wait until I see "1 message read status updated successfully." text)
  end
end

And(/^I remove package "([^"]*)" from highstate$/) do |package|
  steps %(
    When I follow "States" in the content area
    And I follow "Packages" in the content area
    Then I should see a "Package States" text
  )
  event_table_xpath = "//div[@class='table-responsive']/table/tbody"
  rows = find(:xpath, event_table_xpath)
  rows.all('tr').each do |tr|
    next unless tr.text.include?(package)
    puts tr.text
    tr.find("##{package}-pkg-state").select('Removed')
    next if page.has_css?('#save[disabled]')
    steps %(
      Then I click on "Save"
      And I click on "Apply"
    )
  end
end

And(/^I check for failed events on history event page$/) do
  steps %(
    When I follow "Events" in the content area
    And I follow "History" in the content area
    Then I should see a "System History" text
  )
  failings = ""
  event_table_xpath = "//div[@class='table-responsive']/table/tbody"
  rows = find(:xpath, event_table_xpath)
  rows.all('tr').each do |tr|
    if tr.has_css?('.fa.fa-times-circle-o.fa-1-5x.text-danger')
      failings << "#{tr.text}\n"
    end
  end
  count_failures = failings.length
  raise "\nFailures in event history found:\n\n#{failings}" if count_failures.nonzero?
end

When(/^I wait until all events in history are completed$/) do
  steps %(
    When I follow "Events" in the content area
    And I follow "History" in the content area
    Then I should see a "System History" text
  )
  events_icons = "//div[@class='table-responsive']/table/tbody/tr/td[2]/i"
  repeat_until_timeout(message: 'Not all events in history were completed') do
    pickedup = false
    events = all(:xpath, events_icons)
    events.each do |ev|
      if ev[:class].include?('fa-exchange')
        pickedup = true
        break
      end
    end
    break unless pickedup
    sleep 1
  end
end

And(/I should see a list item with text "([^"]*)" and bullet with "([^"]*)" icon/) do |text, class_name|
  item_xpath = "//ul/li[text()='#{text}']/i[contains(@class, 'text-#{class_name}')]"
  find(:xpath, item_xpath)
end
