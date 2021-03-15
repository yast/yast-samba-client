# Copyright (c) [2021] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.

require "yast"

module Yast
  class SambaNetUtilsClass < Module
    def main
      textdomain "samba-client"

      Yast.import "Lan"
      Yast.import "String"
    end

    # Checks if any interface is configured to use DHCP.
    #
    # @return [Boolean] true when an interface uses DHCP config
    def IsDHCPClient
      Yast::Lan.ReadWithCacheNoGUI
      config = Yast::Lan.yast_config
      return false unless config&.connections
      config.connections.any?(&:dhcp?)
    end

    # Checks if all IP addresses are configured for CTDB (/etc/ctdb/nodes).
    #
    # Note: This is not a perfect solution, but as we cannot find out if IP is statically assigned
    # by DHCP server, we have at least a hint that current addresses seem to be configured
    # correctly. See bnc#811008.
    #
    # @return [Boolean] true when all IP addresses are configured for CTDB
    def IsIPValidForCTDB
      return true unless IsDHCPClient()
      Builtins.y2milestone(
        "DHCP client found: checking if IP addresses are configured for CTDB traffic..."
      )

      Yast::Lan.ReadWithCacheNoGUI
      config = Yast::Lan.yast_config
      return true unless config&.connections

      # Collect the first IP address of each interface that is configured by DHCP.
      iface_names = config.connections.select(&:dhcp?).map(&:interface)
      used_ips = iface_names.each_with_object([]) do |iface, res|
        cmd = "LANG=C /usr/sbin/ip addr show dev #{iface.shellescape} scope global | " \
          "grep --max-count=1 'inet\\(6\\)\\?' | " \
          "sed 's/^[ \\t]\\+inet\\(6\\)\\?[ \\t]\\+\\([^\\/]\\+\\)\\/.*$/\\2/'"
        out = Convert.to_map(SCR.Execute(path(".target.bash_output"), cmd))
        if Ops.get_integer(out, "exit", 0) != 0
          Builtins.y2error("Cannot get IP information for '%1': %2", iface, out)
          next
        end
        res.concat(String.NewlineItems(Ops.get_string(out, "stdout", "")))
      end

      # Obtain CTDB private addresses from /etc/ctdb/nodes.
      out = SCR.Read(path(".target.string"), "/etc/ctdb/nodes") || ""
      nodes = String.NewlineItems(out)

      cluster_ip = true
      used_ips.each do |address|
        if !nodes.include? address
          Builtins.y2warning("IP address #{address} is not configured for CTDB")
          cluster_ip = false
        end
      end
      cluster_ip
    end

    publish :function => :IsDHCPClient, :type => "boolean ()"
    publish :function => :IsIPValidForCTDB, :type => "boolean ()"
  end

  SambaNetUtils = SambaNetUtilsClass.new
  SambaNetUtils.main
end
