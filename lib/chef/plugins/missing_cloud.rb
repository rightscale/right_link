#
# Copyright (c) 2010-2011 RightScale Inc
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


# Extends ohai/plugin/cloud with additional clouds
# that RightLink knows about
# Later this code will be contributed into

require_plugin 'cloud'
require_plugin 'cloudstack'
require_plugin 'softlayer'
require_plugin 'vsphere'

require 'chef/ohai/mixin/rightlink'
extend ::Ohai::Mixin::RightLink::CloudUtilities

# ----------------------------------------
#  cloudstack
# ----------------------------------------
#
# Is current cloud cloudstack?
#
# === Return
# true:: If cloudstack Hash is defined
# false:: Otherwise
def on_cloudstack?
  cloudstack != nil
end

# Fill cloud hash with cloudstack values. Cloudstack is a bit different in that
# the local interface can be a public or private ip is using basic networking.
# When using advanced networking, the public_ipv4 passed in the metadata isn't 
# usually going to be the public ip of the interface, so don't use that value. As
# per the Cloudstack documentation its actually the NAT router IP.
def get_cloudstack_values
  cloud[:local_ipv4] = cloudstack['local_ipv4']

  if cloudstack['local_ipv4']
    if private_ipv4?(cloudstack['local_ipv4'])
      cloud[:private_ips] << cloudstack['local_ipv4']
      cloud[:public_ipv4] = nil
    else
      cloud[:public_ips] << cloudstack['local_ipv4']
      # Yes, not a mistake, for basic networking this may be true
      cloud[:public_ipv4] = cloudstack['local_ipv4']
    end
  end

  cloud[:local_hostname] = cloudstack['local_hostname']
  cloud[:provider] = 'cloudstack'
end

# Setup cloudstack cloud data
if on_cloudstack?
  create_objects
  get_cloudstack_values
end

def on_softlayer?
  softlayer != nil
end

def get_softlayer_values
  cloud[:public_ipv4] = softlayer['public_ipv4']
  cloud[:local_ipv4] = softlayer['local_ipv4']
  cloud[:public_ips] << softlayer['public_ipv4'] if softlayer['public_ipv4']
  cloud[:private_ips] << softlayer['local_ipv4'] if softlayer['local_ipv4']
  cloud[:public_hostname] = softlayer['public_fqdn']
  cloud[:provider] = 'softlayer'
end

if on_softlayer?
  create_objects
  get_softlayer_values
end

def on_vsphere?
  vsphere != nil
end

def get_vsphere_values
  cloud[:public_ipv4] = vsphere['public_ipv4']
  cloud[:local_ipv4] = vsphere['local_ipv4']
  cloud[:public_ips].concat(vsphere['public_ips'])  if vsphere['public_ips']
  cloud[:private_ips].concat(vsphere['private_ips'])  if vsphere['public_ips']
  cloud[:provider] = 'vsphere'
end

if on_vsphere?
  create_objects
  get_vsphere_values
end

def on_azure?
  azure != nil
end

if on_azure?
  # We don't do a create_objects call, we're amending the value created by the
  # cloud plugin until its in official ohai
  cloud[:private_ips] |= [azure['private_ip']] if azure['private_ip']
  cloud[:public_ipv4] = azure['public_ip']
  cloud[:local_ipv4] = azure['private_ip']
  cloud[:public_hostname] = azure['public_fqdn']
end
