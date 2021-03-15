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

    publish :function => :IsDHCPClient, :type => "boolean ()"
  end

  SambaNetUtils = SambaNetUtilsClass.new
  SambaNetUtils.main
end
