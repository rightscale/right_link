#
# Copyright (c) 2010-2014 RightScale Inc
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

provides 'cloudstack'
require 'chef/ohai/mixin/cloudstack_metadata'

extend ::Ohai::Mixin::CloudstackMetadata

def looks_like_cloudstack?
  looks_like_cloudstack = hint?('cloudstack')
  ::Ohai::Log.debug("looks_like_cloudstack? == #{looks_like_cloudstack.inspect} ")
  looks_like_cloudstack
end

if looks_like_cloudstack?
  dhcp_ip = dhcp_lease_provider
  metadata = fetch_metadata(dhcp_ip)
  cloudstack Mash.new
  if metadata
    metadata.each { |k,v| cloudstack[k] = v }
  end
  # Note: the cloudstack public_ipv4 is the value of the NAT router (as per cloudstack documentation)
  # and not necessarily the publicly available IP.  cloustack semi-supports floating
  # ips in that the public ip for an instance can be an IP different from the NAT router
  cloudstack['router_ipv4'] = cloudstack.delete('public_ipv4')
  cloudstack.delete('public_hostname')
  cloudstack['dhcp_lease_provider_ip'] = dhcp_ip
end
