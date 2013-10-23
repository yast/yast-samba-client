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

# File:	clients/samba-client.ycp
# Package:	Configuration of samba-client
# Summary:	Main file
# Authors:	Stanislav Visnovsky <visnov@suse.cz>
#
# $Id$
#
# Main file for samba-client configuration. Uses all other files.
module Yast
  class SambaClientClient < Client
    def main
      Yast.import "UI"

      #**
      # <h3>Configuration of the samba-client</h3>

      textdomain "samba-client"

      Yast.import "CommandLine"
      Yast.import "Popup"
      Yast.import "Report"

      Yast.import "Samba"
      Yast.import "SambaAD"
      Yast.import "SambaNetJoin"

      # The main ()
      Builtins.y2milestone("----------------------------------------")
      Builtins.y2milestone("Samba-client module started")

      Yast.include self, "samba-client/wizards.rb"

      # main ui function
      @ret = nil

      # the command line description map
      @cmdline = {
        "id"         => "samba-client",
        # translators: command line help text for Samba client module
        "help"       => _(
          "Samba client configuration module.\nSee Samba documentation for details."
        ),
        "guihandler" => fun_ref(method(:SambaClientSequence), "symbol ()"),
        "initialize" => fun_ref(Samba.method(:Read), "boolean ()"),
        "finish"     => fun_ref(method(:SambaWrite), "boolean ()"),
        "actions"    => {
          "winbind"        => {
            "handler" => fun_ref(
              method(:WinbindEnableHandler),
              "boolean (map <string, string>)"
            ),
            # translators: command line help text for winbind action
            "help"    => _(
              "Enable or disable the Winbind services (winbindd)"
            )
          },
          "isdomainmember" => {
            "handler" => fun_ref(
              method(:DomainMemberHandler),
              "boolean (map <string, any>)"
            ),
            # translators: command line help text for isdomainmember action
            "help"    => _(
              "Check if this machine is a member of a domain"
            )
          },
          "joindomain"     => {
            "handler" => fun_ref(
              method(:JoinDomainHandler),
              "boolean (map <string, any>)"
            ),
            # translators: command line help text for joindomain action
            "help"    => _(
              "Join this machine to a domain"
            )
          },
          "configure"      => {
            "handler" => fun_ref(
              method(:ChangeConfiguration),
              "boolean (map <string, any>)"
            ),
            # translators: command line help text for configure action
            "help"    => _(
              "Change the global settings of Samba"
            )
          }
        },
        "options"    => {
          "enable"    => {
            # translators: command line help text for winbind enable option
            "help" => _(
              "Enable the service"
            )
          },
          "disable"   => {
            # translators: command line help text for winbind disable option
            "help" => _(
              "Disable the service"
            )
          },
          "domain"    => {
            # translators: command line help text for domain to be checked/joined
            "help" => _(
              "The name of a domain to join"
            ),
            "type" => "string"
          },
          "user"      => {
            # translators: command line help text for joindomain user option
            "help" => _(
              "The user used for joining the domain. If omitted, YaST will\ntry to join the domain without specifying user and password.\n"
            ),
            "type" => "string"
          },
          "password"  => {
            # translators: command line help text for joindomain password option
            "help" => _(
              "The password used for the user when joining the domain"
            ),
            "type" => "string"
          },
          "machine"   => {
            # command line help text for machine optioa
            "help" => _(
              "The machine account"
            ),
            "type" => "string"
          },
          "workgroup" => {
            # translators: command line help text for the workgroup name option
            "help" => _(
              "The name of a workgroup"
            ),
            "type" => "string"
          }
        },
        "mappings"   => {
          "winbind"        => ["enable", "disable"],
          "isdomainmember" => ["domain"],
          "joindomain"     => ["domain", "user", "password", "machine"],
          "configure"      => ["workgroup"]
        }
      }

      @ret = CommandLine.Run(@cmdline)

      Builtins.y2debug("ret=%1", @ret)

      # Finish
      Builtins.y2milestone("Samba-client module finished")
      Builtins.y2milestone("----------------------------------------")

      deep_copy(@ret) 

      # EOF
    end

    # Enable or disable winbind service (high-level)
    #
    # @param [Hash{String => String}] options  a list of parameters passed as args
    # @return [Boolean] true on success
    def WinbindEnableHandler(options)
      options = deep_copy(options)
      # check the "command" to be present exactly once
      command = CommandLine.UniqueOption(options, ["enable", "disable"])
      return false if command == nil

      # read AD settings, so the write command does not fallback to non-AD default
      domain    = Samba.GetWorkgroupOrRealm
      SambaAD.ReadADS(domain)
      Samba.SetWorkgroup(domain)
      SambaAD.ReadRealm

      Samba.SetWinbind(command == "enable")
    end

    # Check domain membership.
    #
    # @param [Hash{String => Object}] options  a list of parameters passed as args
    # @return [Boolean] true on success
    def DomainMemberHandler(options)
      options = deep_copy(options)
      domain = Ops.get_string(options, "domain")

      # validate the options
      if domain == nil
        # user must provide the domain name to be tested
        # error message for isdomainmember command line action
        Report.Error(Builtins.sformat(_("Enter the name of a domain.")))
        return false
      end

      SambaAD.ReadADS(domain)
      if SambaAD.ADS != ""
        domain = SambaAD.GetWorkgroup(domain)
        SambaAD.ReadRealm
      end

      result = SambaNetJoin.Test(domain)
      if result == nil
        # translators: error message for isdomainmember command line action
        Report.Error(_("Cannot test domain membership."))
        return false
      end

      if result
        # translators: result message for isdomainmember command line action
        CommandLine.Print(
          Builtins.sformat(_("This machine is a member of %1."), domain)
        )
      else
        # translators: result message for isdomainmember command line action
        CommandLine.Print(
          Builtins.sformat(_("This machine is not a member of %1."), domain)
        )
      end

      true
    end

    # Join a domain.
    #
    # @param [Hash{String => Object}] options  a list of parameters passed as args
    # @return [Boolean] true on success
    def JoinDomainHandler(options)
      options = deep_copy(options)
      domain = Ops.get_string(options, "domain")

      # validate the options
      if domain == nil
        # must provide the domain name to be joined
        # error message for joindomain command line action
        Report.Error(Builtins.sformat(_("Enter the name of a domain.")))
        return false
      end

      SambaAD.ReadADS(domain)
      if SambaAD.ADS != ""
        domain = SambaAD.GetWorkgroup(domain)
        SambaAD.ReadRealm
      end

      result = SambaNetJoin.Join(
        domain,
        "member",
        Ops.get_string(options, "user"),
        Ops.get_string(options, "password", ""),
        Ops.get_string(options, "machine")
      )
      if result == nil
        # translators: result message for joindomain command line action
        CommandLine.Print(
          Builtins.sformat(_("Domain %1 joined successfully."), domain)
        )
        return true
      else
        Report.Error(result)
        return false
      end
    end

    # Change workgroup name.
    #
    # @param [Hash{String => Object}] options  a list of parameters passed as args
    # @return [Boolean] true on success
    def ChangeConfiguration(options)
      options = deep_copy(options)
      value = Ops.get_string(options, "workgroup")
      Samba.SetWorkgroup(value) if value != nil

      true
    end

    # command line handler for writing
    def SambaWrite
      Samba.Write(true)
    end
  end
end

Yast::SambaClientClient.new.main
