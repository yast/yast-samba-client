# encoding: utf-8

# ------------------------------------------------------------------------------
# Copyright (c) 2006-2012 Novell, Inc. All Rights Reserved.
#
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, contact Novell, Inc.
#
# To contact Novell about this file by physical or electronic mail, you may find
# current contact information at www.novell.com.
# ------------------------------------------------------------------------------

# File:	include/samba-client/complex.ycp
# Package:	Configuration of samba-client
# Summary:	Dialogs definitions
# Authors:	Stanislav Visnovsky <visnov@suse.cz>
#
# $Id$
module Yast
  module SambaClientComplexInclude
    def initialize_samba_client_complex(include_target)
      Yast.import "UI"

      textdomain "samba-client"

      Yast.import "PackageSystem"
      Yast.import "Samba"
      Yast.import "Wizard"


      Yast.include include_target, "samba-client/helps.rb"
      Yast.include include_target, "samba-client/routines.rb"
    end

    # Return a modification status
    # @return true if data was modified
    def Modified
      Samba.GetModified
    end

    # Read settings dialog
    # @return `abort if aborted and `next otherwise
    def ReadDialog
      Wizard.RestoreHelp(Ops.get_string(@HELPS, "read", ""))

      # check installed packages
      if !PackageSystem.CheckAndInstallPackagesInteractive(["samba-client"])
        Builtins.y2warning("package samba-client not installed")
        return :abort
      end

      ret = Samba.Read
      ret ? :next : :abort
    end

    # Write settings dialog
    # @return `abort if aborted and `next otherwise
    def WriteDialog
      Wizard.RestoreHelp(Ops.get_string(@HELPS, "write", ""))
      ret = Samba.Write(false)
      ret ? :next : :abort
    end
  end
end
