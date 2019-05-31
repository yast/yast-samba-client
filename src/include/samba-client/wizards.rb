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

# File:	include/samba-client/wizards.ycp
# Package:	Configuration of samba-client
# Summary:	Wizards definitions
# Authors:	Stanislav Visnovsky <visnov@suse.cz>
#
# $Id$
module Yast
  module SambaClientWizardsInclude
    def initialize_samba_client_wizards(include_target)
      Yast.import "UI"

      textdomain "samba-client"

      Yast.import "Wizard"
      Yast.import "Label"
      Yast.import "Samba"
      Yast.import "Sequencer"

      Yast.include include_target, "samba-client/complex.rb"
      Yast.include include_target, "samba-client/dialogs.rb"
    end

    # Whole configuration of samba-client
    # @return sequence result
    def SambaClientSequence
      aliases = {
        "read"  => [lambda { ReadDialog() }, true],
        "main"  => lambda { MembershipDialog() },
        "write" => [lambda { WriteDialog() }, true]
      }

      sequence = {
        "ws_start" => "read",
        "read"     => { :abort => :abort, :next => "main" },
        "main"     => { :abort => :abort, :next => "write", :back => :back },
        "write"    => { :abort => :abort, :next => :next }
      }

      Wizard.CreateDialog
      Wizard.SetDesktopTitleAndIcon("org.openSUSE.YaST.SambaClient")

      ret = Sequencer.Run(aliases, sequence)

      UI.CloseDialog
      Convert.to_symbol(ret)
    end

    # Whole configuration of samba-client but without reading and writing.
    # For use with autoinstallation.
    # @return sequence result
    def SambaClientAutoSequence
      # translators: initialization dialog caption
      caption = _("Samba Client Configuration")
      # translators: initialization dialog contents
      contents = Label(_("Initializing..."))

      Wizard.CreateDialog
      Wizard.SetContentsButtons(
        caption,
        contents,
        "",
        Label.BackButton,
        Label.NextButton
      )

      ret = MembershipDialog()

      UI.CloseDialog
      Samba.globals_configured = true if ret != :abort

      Convert.to_symbol(ret)
    end
  end
end
