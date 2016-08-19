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

# File:	include/samba-client/routines.ycp
# Package:	Configuration of samba-client
# Summary:	Miscelanous functions for configuration of samba-client.
# Authors:	Stanislav Visnovsky <visnov@suse.cz>
#
# $Id$
module Yast
  module SambaClientRoutinesInclude
    def initialize_samba_client_routines(include_target)
      Yast.import "UI"

      textdomain "samba-client"

      Yast.import "FileUtils"
      Yast.import "Mode"
      Yast.import "Label"
      Yast.import "Stage"
      Yast.import "Popup"
      Yast.import "Service"
      Yast.import "String"

      Yast.import "Samba"
      Yast.import "SambaConfig"
      Yast.import "SambaNetJoin"
      Yast.import "SambaNmbLookup"
      Yast.import "SambaAD"
      Yast.import "OSRelease"

    end

    # Allow user to type in a user/password pair in a popup.
    #
    # @param [String] message	a text to be displayed above the password text entry
    # @param [String] defaultuser	a pre-filled user name
    # @return [Hash{String => String}]		$["user": string, "password": string] with information
    #			provided by the user or nil on cancel
    def passwordUserPopup(message, defaultuser, domain, what)
      machine_term = Empty()
      default_id = "default_entry"
      # default value of Machine Account
      default_entry = Item(Id(default_id), _("(default)"))
      update_dns = Empty()
      if SambaAD.ADS != "" && what != :leave
        machines = [default_entry]
        machine_term = HBox(
          ReplacePoint(
            Id(:rpcombo),
            Left(
              ComboBox(
                Id(:machines),
                Opt(:hstretch),
                # combo box label
                _("&Machine Account OU"),
                machines
              )
            )
          ),
          VBox(Label(""), PushButton(Id(:acquire), _("O&btain list")))
        )
        update_dns = CheckBox(Id(:update_dns), Opt(:hstretch), _('Update DNS'), true)
      end
      UI.OpenDialog(
        Opt(:decorated),
        HBox(
          HSpacing(0.7),
          VBox(
            HSpacing(25),
            VSpacing(0.2),
            Left(Label(message)),
            # text entry label
            InputField(Id(:user), Opt(:hstretch), _("&Username"), defaultuser),
            Password(Id(:passwd), Opt(:hstretch), Label.Password),
            machine_term,
            update_dns,
            VSpacing(0.2),
            ButtonBox(
              PushButton(Id(:ok), Opt(:default), Label.OKButton),
              PushButton(Id(:cancel), Label.CancelButton)
            ),
            VSpacing(0.2)
          ),
          HSpacing(0.7)
        )
      )

      if SambaAD.ADS != "" && what != :leave
        UI.ChangeWidget(Id(:machines), :Enabled, false)
      end
      UI.SetFocus(Id(:passwd))
      ret = nil
      user = ""
      pass = ""
      while true
        ret = UI.UserInput
        user = Convert.to_string(UI.QueryWidget(Id(:user), :Value))
        pass = Convert.to_string(UI.QueryWidget(Id(:passwd), :Value))

        break if ret == :ok || ret == :cancel
        if ret == :acquire
          if user == "" || pass == ""
            # error popup
            Popup.Error(
              _(
                "User name and password are required\nfor listing the machine accounts."
              )
            )
            next
          end
          machines = SambaAD.GetMachines(domain, user, pass)
          if machines != nil
            items = Builtins.maplist(Builtins.sort(machines)) do |m|
              Item(Id(m), m)
            end
            items = Builtins.prepend(items, default_entry)
            UI.ReplaceWidget(
              Id(:rpcombo),
              Left(
                ComboBox(
                  Id(:machines),
                  Opt(:hstretch),
                  _("&Machine Account"),
                  items
                )
              )
            )
            UI.ChangeWidget(Id(:machines), :Enabled, true)
          end
        end
      end

      result = ret == :ok ? { "user" => user, "password" => pass, "update_dns" => UI.QueryWidget(Id(:update_dns), :Value) } : nil
      if SambaAD.ADS != "" && ret == :ok && what != :leave
        machine = Convert.to_string(UI.QueryWidget(Id(:machines), :Value))
        Ops.set(result, "machine", machine) if machine != default_id
      end
      UI.CloseDialog

      deep_copy(result)
    end

    # If modified, ask for confirmation
    # @return true if abort is confirmed
    def ReallyAbort
      Samba.GetModified || Stage.cont ? Popup.ReallyAbort(true) : true
    end

    # Check, if the workgroup is a domain or a workgroup. Uses caching to avoid long checks of a workgroup members.
    #
    # @param [String] workgroup	the workgroup to be checked
    # @return [Symbol]	type of the workgroup: `joined_domain, `not_joined_domain, `workgroup or `domain if
    # 			it is a domain, but the status is not known
    def CheckWorkgroup(workgroup)
      # for autoyast, skip testing
      return :workgroup if Mode.config

      ret = nil

      # translators: text for busy pop-up
      Popup.ShowFeedback("", _("Verifying workgroup membership..."))

      if SambaNmbLookup.IsDomain(workgroup) || SambaAD.ADS != ""
        # handle domain joining
        res = SambaNetJoin.Test(workgroup)
        # we the host is already in domain, continue
        if res == true
          ret = :joined_domain
        elsif res != nil
          ret = :not_joined_domain
        else
          ret = :domain
        end
      else
        ret = :workgroup
      end
      Popup.ClearFeedback
      Builtins.y2debug("Check workgroup result: %1", ret)
      ret
    end

    # Leave an AD domain
    def LeaveDomain(workgroup)
      # popup to fill in the domain leaving info; %1 is the domain name
      passwd = passwordUserPopup(
        Builtins.sformat(
          _("Enter the username and the password for leaving the domain %1."),
          workgroup
        ),
        "Administrator",
        workgroup,
        :leave
      )

      # cancelled the domain leaving
      return :fail if passwd == nil
      # try to join the domain
      error = SambaNetJoin.Leave(
        workgroup,
        Ops.get(passwd, "user"),
        Ops.get(passwd, "password", "")
      )

      if error != nil
        Popup.Error(error)
        return :fail
      end
      :ok
    end

    def JoinDomain(workgroup)
      cluster_info = ""
      if SambaNetJoin.ClusterPresent(false)
        # additional information for cluster environment
        cluster_info = _(
          "The configuration will be propagated across cluster nodes."
        )
      end

      # popup to fill in the domain joining info; %1 is the domain name
      passwd = passwordUserPopup(
        Ops.add(
          Ops.add(
            Ops.add(
              Builtins.sformat(
                _(
                  "Enter the username and the password for joining the domain %1."
                ),
                workgroup
              ),
              "\n\n"
            ),
            _("To join the domain anonymously, leave the text entries empty.\n")
          ),
          cluster_info
        ),
        "Administrator",
        workgroup,
        :join
      )

      # cancelled the domain joining
      return :fail if passwd == nil
      relname = OSRelease.ReleaseName
      relver = OSRelease.ReleaseVersion
      # try to join the domain
      error = SambaNetJoin.Join(
        workgroup,
        "member",
        Ops.get(passwd, "user"),
        Ops.get(passwd, "password", ""),
        Ops.get(passwd, "machine"),
        relname,
        relver,
        passwd["update_dns"]
      )

      if error != nil
        Popup.Error(error)
        return :fail
      end
      # Translators: Information popup, %1 is the name of the domain
      Popup.Message(
        Builtins.sformat(
          _("Domain %1 joined successfully."),
          Samba.GetWorkgroup
        )
      )
      :ok
    end


    # Allow to join a domain. Uses result of {#CheckWorkgroup} to inform the user about the status.
    #
    # @param [String] workgroup	the workgroup to be joined
    # @param [Symbol] status	domain status returned by CheckWorkgroup
    # @return [Symbol]		`ok on successful join (workgroup is always successful),
    #			`fail on error or user cancel
    #			`nojoin if user don't want to join
    def AskJoinDomain(workgroup, status)
      # for autoyast, skip testing
      return :ok if Mode.config

      return :ok if status == :workgroup || status == :joined_domain

      res = false

      # popup question, the domain status cannot be found out, ask user what to do
      dont_know = _(
        "Cannot automatically determine if this host\nis a member of the domain %1."
      )
      # popup question, first part
      not_member = _("This host is not a member\nof the domain %1.")
      # last part of popup question
      join_q = Ops.add(
        "\n\n",
        Builtins.sformat(_("Join the domain %1?"), workgroup)
      )

      if SambaNetJoin.ClusterPresent(false)
        dont_know = _(
          "Cannot automatically determine if this cluster\nis a member of the domain %1."
        )
        not_member = _("This cluster is not a member\nof the domain %1.")
      end

      # allow to join the domain
      if status == :domain
        # we don't know the domain status
        res = Popup.YesNo(
          Ops.add(Builtins.sformat(dont_know, workgroup), join_q)
        )
      elsif status == :not_joined_domain
        res = Popup.YesNo(
          Ops.add(Builtins.sformat(not_member, workgroup), join_q)
        )
      end

      return :nojoin if !res
      JoinDomain(workgroup)
    end


    # Check if user shares already exist
    # @param path to directory with shares
    def SharesExist(share_dir)
      return false if !FileUtils.Exists(share_dir)
      out = Convert.to_map(
        SCR.Execute(
          path(".target.bash_output"),
          Builtins.sformat("/usr/bin/find %1 -type f | wc -l", share_dir)
        )
      )
      count = Builtins.tointeger(
        String.FirstChunk(Ops.get_string(out, "stdout", "0"), "\n")
      )
      count != nil && Ops.greater_than(count, 0)
    end

    # ask user if existing shares should be removed
    # @return true for removing
    def AskForSharesRemoval
      !Popup.AnyQuestion(
        Popup.NoHeadline,
        # popup question
        _("User shares already exist.  Keep or delete these shares?"),
        # button label
        _("&Keep"),
        # button label
        _("&Delete"),
        :focus_yes
      ) 
      # FIXME details
    end

    # check if services should be stopped: only if there are more sections in
    # smb.conf and if user confirms (bug #143908)
    # @return true if smb+nmb should be stopped
    def AskToStopServices
      return false if Service.Status("nmb") != 0 && Service.Status("smb") != 0

      return true if Ops.less_than(Builtins.size(SambaConfig.GetShares), 1)

      # yes/no popup
      Popup.YesNo(
        _("Other Windows sharing services are available. Stop them as well?")
      )
    end

    # return the term with hosts resolution support check box (fate#300971)
    # @param [Boolean] hosts_resolution current value of hosts resolution in nsswitch.conf
    def HostsResolutionTerm(hosts_resolution)
      # check box label
      Left(
        CheckBox(
          Id(:hosts_resolution),
          _("&Use WINS for Hostname Resolution"),
          hosts_resolution
        )
      )
    end

    # Return help text for hosts resolution term
    def HostsResolutionHelp
      # help text for "Use WINS for Hostname Resolution" check box label
      _(
        "<p>If you want to use Microsoft Windows Internet Name Service (WINS) for name resolution, check <b>Use WINS for Hostname Resolution</b>.</p>"
      )
    end

    # return the term with DHCP support check box
    # @param [Boolean] dhcp_support current value of DHCP support in smb.conf
    def DHCPSupportTerm(dhcp_support)
      # check box label
      Left(
        CheckBox(Id(:dhcp), _("Retrieve WINS server via &DHCP"), dhcp_support)
      )
    end

    # return the help text for DHCP support
    def DHCPSupportHelp
      # help text ("Retrieve WINS server via DHCP" is a checkbox label)
      _(
        "<p>Check <b>Retrieve WINS server via DHCP</b> to use a WINS server provided by DHCP.</p>"
      )
    end

    # return the term with shares settings
    # @param [Hash] settings map with parameters to show in term
    def SharesTerm(settings)
      settings = deep_copy(settings)
      allow = Ops.get_boolean(settings, "allow_share", false)
      group = Ops.get_string(
        settings,
        "group",
        Ops.get_string(settings, "shares_group", "")
      )
      max = Ops.get_integer(settings, "max_shares", 100)
      guest = Ops.get_boolean(settings, "guest_access", false)

      # frame label
      label = true ?
        _("Sharing by Users") :
        # frame label
        _("Sharing")
      VBox(
        VSpacing(0.4),
        # frame label
        Frame(
          label,
          VBox(
            VSpacing(0.4),
            Left(
              CheckBox(
                Id(:share_ch),
                Opt(:notify),
                # checkbox label
                _("&Allow Users to Share Their Directories"),
                allow
              )
            ),
            Builtins.haskey(settings, "guest_access") ?
              Left(
                CheckBox(
                  Id(:guest_ch),
                  Opt(:notify),
                  # checkbox label
                  _("Allow &Guest Access"),
                  guest
                )
              ) :
              VSpacing(0),
            HBox(
              HSpacing(2),
              VBox(
                # texty entry label
                InputField(
                  Id(:group),
                  Opt(:hstretch),
                  _("&Permitted Group"),
                  group
                ),
                # infield label
                IntField(
                  Id(:max_shares),
                  _("&Maximum Number of Shares"),
                  1,
                  99999,
                  max
                )
              )
            ),
            VSpacing(0.2)
          )
        )
      )
    end

    # return the term with shares settings
    # @param [Boolean] allow if shares are allowed
    # @param [String] group name of group owning the shares dir
    # @param [Fixnum] max maximum number of allowed shares
    def GetSharesTerm(allow, group, max)
      Builtins.y2warning("GetSharesTerm is obsolete, use SharesTerm instead")
      SharesTerm(
        { "allow_share" => allow, "shares_group" => group, "max_shares" => max }
      )
    end

    # return the help text for shares
    def SharesHelp
      Ops.add(
        Ops.add(
          # membership dialog help (common part 3/4), %1 is separator (e.g. '\')
          Builtins.sformat(
            _(
              "<p><b>Allow Users to Share Their Directories</b> enables members of the group in <b>Permitted Group</b> to share directories they own with other users. For example, <tt>users</tt> for a local scope or <tt>DOMAIN%1Users</tt> for a domain scope.  The user also must make sure that the file system permissions allow access.</p>"
            ),
            Samba.shares_separator
          ),
          # membership dialog help (common part 3/4)
          _(
            "<p>With <b>Maximum Number of Shares</b>, limit the total amount of shares that may be created.</p>"
          )
        ),
        # membership dialog help common part
        _(
          "<p>To permit access to user shares without authentication, enable <b>Allow Guest Access</b>.</p>"
        )
      )
    end

    # return the help text for PAM Mount table
    def PAMMountHelp
      # help text for PAM Mount table
      _(
        "<p>In the table <b>Mount Server Directories</b>, you can specify server\n" +
          "directories (such as home directory) which should be locally mounted when the\n" +
          "user is logged in. If mounting should be user-specific, specify <b>User\n" +
          "Name</b> for the selected rule. Otherwise, the directory is mounted for each user. For more information, see pam_mount.conf manual page.</p>"
      ) +
        # help text for PAM Mount table: example
        _(
          "<p>For example, you may use <tt>/home/%(DOMAIN_USER)</tt> value for <b>Remote Path</b>, <tt>~/</tt> value for <b>Local Mount Point</b> to mount the home directory, together with a value <tt>user=%(DOMAIN_USER)</tt> as a part of <b>Options</b>.</p>"
        )
    end

    # return help for Kerberos Method
    def KerberosMethodHelp
      # help text for kerberos method option
      _(
        "<p>The value of <b>Kerberos Method</b> defines how kerberos tickets are verified. When <b>Single Sing-on for SSH</b> is used, the default Kerberos Method set by YaST is <tt>secrets and keytab</tt>. See smb.conf manual page for details.</p>"
      )
    end
  end
end
