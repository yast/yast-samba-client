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

# File:	include/samba-client/dialogs.ycp
# Package:	Configuration of samba-client
# Summary:	Dialogs definitions
# Authors:	Stanislav Visnovsky <visnov@suse.cz>
#
# $Id$
module Yast
  module SambaClientDialogsInclude
    def initialize_samba_client_dialogs(include_target)
      Yast.import "UI"

      textdomain "samba-client"

      Yast.import "Autologin"
      Yast.import "CWMFirewallInterfaces"
      Yast.import "Directory"
      Yast.import "Label"
      Yast.import "Message"
      Yast.import "Mode"
      Yast.import "Package"
      Yast.import "Popup"
      Yast.import "Samba"
      Yast.import "SambaConfig"
      Yast.import "Stage"
      Yast.import "Wizard"

      Yast.include include_target, "samba-client/helps.rb"
      Yast.include include_target, "samba-client/routines.rb"
    end

    # Popup for editing the mount entry data
    def MountEntryPopup(volume)
      volume = deep_copy(volume)
      # labels of keys which are shown only if they are already present in the
      # volume entry (manualy added to congig file)
      key2label =
        # we do not show "fstype" key, this is limited to cifs...
        {
          # text entry label
          "uid"  => _("U&ID"),
          # text entry label
          "pgrp" => _("&Primary Group Name"),
          # text entry label
          "sgrp" => _("&Secondary Group Name"),
          # text entry label
          "gid"  => _("&GID")
        }

      input_fields = VBox(
        # text entry label
        InputField(Id("server"), Opt(:hstretch), _("&Server Name")),
        # text entry label
        InputField(Id("path"), Opt(:hstretch), _("Remote &Path")),
        # text entry label
        InputField(Id("mountpoint"), Opt(:hstretch), _("&Mount Point")),
        # text entry label
        InputField(Id("options"), Opt(:hstretch), _("O&ptions")),
        # text entry label
        InputField(Id("user"), Opt(:hstretch), _("&User Name"))
      )
      # default keys
      widgets = ["server", "path", "mountpoint", "options", "user"]

      Builtins.foreach(key2label) do |key, label|
        if Builtins.haskey(volume, key)
          input_fields = Builtins.add(
            input_fields,
            InputField(Id(key), Opt(:hstretch), label)
          )
          widgets = Builtins.add(widgets, key)
        end
      end

      UI.OpenDialog(
        Opt(:decorated),
        HBox(
          HSpacing(0.2),
          VBox(
            HSpacing(50),
            VSpacing(0.2),
            input_fields,
            VSpacing(0.2),
            ButtonBox(
              PushButton(Id(:ok), Label.OKButton),
              PushButton(Id(:cancel), Label.CancelButton)
            ),
            VSpacing(0.2)
          ),
          HSpacing(0.2)
        )
      )

      if volume == {}
        # offer this as a default option for new volumes (bnc#433845)
        Ops.set(volume, "options", "user=%(DOMAIN_USER)")
      end
      Builtins.foreach(widgets) do |key|
        UI.ChangeWidget(Id(key), :Value, Ops.get_string(volume, key, ""))
      end

      ret = UI.UserInput
      if ret == :ok
        # saving value to the same map we got as argument =>
        # keys that were not shown (e.g. fstype) are preserved)
        Builtins.foreach(widgets) do |key|
          Ops.set(volume, key, UI.QueryWidget(Id(key), :Value))
        end
      end
      UI.CloseDialog

      # filter out default keys without value (but leave the rest, so they
      # may appear on next editing)
      volume = Builtins.filter(
        Convert.convert(volume, :from => "map", :to => "map <string, string>")
      ) do |k, v|
        v != "" ||
          !Builtins.contains(
            ["server", "path", "mountpoint", "options", "user"],
            k
          )
      end
      # nothing was added, remove the proposal
      if Builtins.size(volume) == 1 &&
          Ops.get_string(volume, "options", "") == "user=%(DOMAIN_USER)"
        volume = {}
      end
      deep_copy(volume)
    end

    # dialog for setting expert settings, like winbind uid/gid keys (F301518)
    def ExpertSettingsDialog(use_winbind, workgroup)
      idmap_default = SambaConfig.GlobalGetStr("idmap config * : range", "10000-20000")
      l = Builtins.splitstring(idmap_default, "-")
      default_min = Builtins.tointeger(Ops.get_string(l, 0, "10000"))
      default_min = 10000 if default_min == nil
      default_max = Builtins.tointeger(Ops.get_string(l, 1, "20000"))
      default_max = 20000 if default_max == nil

      idmap_domain_backend_setting = Builtins.sformat("idmap config %1 : backend", workgroup)
      idmap_domain_backend = SambaConfig.GlobalGetStr(idmap_domain_backend_setting, "rid")
      idmap_domain_setting = Builtins.sformat("idmap config %1 : range", workgroup)
      idmap_domain = SambaConfig.GlobalGetStr(idmap_domain_setting, "20001-99999")
      l = Builtins.splitstring(idmap_domain, "-")
      domain_min = Builtins.tointeger(Ops.get_string(l, 0, "20001"))
      domain_min = 20001 if domain_min == nil
      domain_max = Builtins.tointeger(Ops.get_string(l, 1, "99999"))
      domain_max = 99999 if domain_max == nil
      dhcp_support = Samba.GetDHCP
      kerberos_method = SambaConfig.GlobalGetStr("kerberos method", "")

      # help text, do not translate 'winbind uid', 'winbind gid'
      help_text = Ops.add(
        Ops.add(
          Ops.add(
            Ops.add(
              _(
                "<p>Specify the <b>Range</b> for Samba user and group IDs (<tt>winbind uid</tt> and <tt>winbind gid</tt> values).</p>"
              ),
              HostsResolutionHelp()
            ),
            DHCPSupportHelp()
          ),
          KerberosMethodHelp()
        ),
        PAMMountHelp()
      )

      hosts_resolution = Samba.GetHostsResolution

      mount_items = []
      non_cifs_volumes = []

      # mapping of unique ID's to volume entries
      mount_map = {}
      i = 0

      Builtins.foreach(Samba.GetPAMMountVolumes) do |volume|
        if Ops.get_string(volume, "fstype", "") != "cifs"
          Builtins.y2debug("volume fstype different from cifs, skipping")
          non_cifs_volumes = Builtins.add(non_cifs_volumes, volume)
          next
        end
        Ops.set(mount_map, i, volume)
        i = Ops.add(i, 1)
      end

      build_mount_items = lambda do
        mount_items = Builtins.maplist(mount_map) do |id, volume|
          Item(
            Id(id),
            Ops.get_string(volume, "server", ""),
            Ops.get_string(volume, "path", ""),
            Ops.get_string(volume, "mountpoint", ""),
            Ops.get_string(volume, "user", ""),
            Ops.get_string(volume, "options", "")
          )
        end
        deep_copy(mount_items)
      end
      kerberos_methods = Builtins.maplist(
        [
          "secrets only",
          "system keytab",
          "dedicated keytab",
          "secrets and keytab"
        ]
      ) do |method|
        Item(Id(method), method, method == kerberos_method)
      end
      idmap_domain_backends = Builtins.maplist(
        [
          "tdb",
          "ad",
          "rid",
          "autorid"
        ]
      ) do |method|
        Item(Id(method), method, method == idmap_domain_backend)
      end

      contents = HBox(
        HSpacing(3),
        VBox(
          VSpacing(0.4),
          # frame label
          Frame(
            _("&Default Range"),
            HBox(
              # int field label
              IntField(Id(:default_min), _("&Minimum"), 0, 999999, default_min),
              # int field label
              IntField(Id(:default_max), _("Ma&ximum"), 0, 999999, default_max)
            )
          ),
          VSpacing(0.5),
          # frame label
          Frame(
            _("Domain &Range"),
            VBox(HBox(
              # int field label
              IntField(Id(:domain_min), _("M&inimum"), 0, 999999, domain_min),
              # int field label
              IntField(Id(:domain_max), _("M&aximum"), 0, 999999, domain_max),
              ComboBox(Id(:backend), _("Back&end"), idmap_domain_backends),
            ),
            RichText("If you're unsure of which backend to choose, please <a href=\"https://www.suse.com/support/kb/doc/?id=7007006\">read kb article 7007006</a>. For the tdb, ad, rid, and autorid idmap backend details, see the idmap_tdb(8), idmap_ad(8), idmap_rid(8) and idmap_autorid(8) man pages. Please refer to the smb.conf(5) man page for further options which may need to be manually configured. For other idmap backends, see the idmap_tdb2(8), idmap_ldap(8), idmap_hash(8), idmap_nss(8) and idmap_rfc2307(8) man pages.")
            )
          ),
          VSpacing(0.2),
          # require_groups
          Frame(_("Allowed Group(s)"),
          Left(
            InputField(
              Id("require_grp"),
              Opt(:hstretch),
              _("Group Name(s) or SID(s)"),
              SambaConfig::WinbindGlobalGetStr("require_membership_of", "")
            )
          )
          ),
          VSpacing(0.2),
          # combobox label
          Left(
            ComboBox(
              Id(:kerberos_method),
              _("&Kerberos Method"),
              kerberos_methods
            )
          ),
          # frame label
          Frame(
            _("Windows Internet Name Service"),
            VBox(
              HostsResolutionTerm(hosts_resolution),
              DHCPSupportTerm(dhcp_support)
            )
          ),
          VSpacing(0.4),
          # frame label
          Frame(
            _("Mount Server Directories"),
            VBox(
              VSpacing(0.2),
              Table(
                Id(:table),
                Opt(:notify),
                Header(
                  # table header
                  _("Server Name"),
                  # table header
                  _("Remote Path"),
                  # table header
                  _("Local Mount Point"),
                  # table header
                  _("User Name"),
                  # table header
                  _("Options")
                ),
                build_mount_items.call
              ),
              HBox(
                PushButton(Id(:add), Label.AddButton),
                PushButton(Id(:edit), Label.EditButton),
                PushButton(Id(:delete), Label.DeleteButton),
                HStretch()
              )
            )
          )
        ),
        HSpacing(3)
      )

      Wizard.OpenOKDialog
      # dialog title
      Wizard.SetContents(_("Expert Settings"), contents, help_text, true, true)

      Builtins.foreach([:edit, :delete]) do |s|
        UI.ChangeWidget(
          Id(s),
          :Enabled,
          Ops.greater_than(Builtins.size(mount_items), 0)
        )
      end

      ret = :cancel
      selected = 0
      while true
        ret2 = UI.UserInput
        break if ret2 == :cancel
        if ret2 == :delete || ret2 == :edit || ret2 == :table
          selected = Convert.to_integer(
            UI.QueryWidget(Id(:table), :CurrentItem)
          )
          ret2 = :edit if ret2 == :table
        end
        if ret2 == :delete
          mount_map = Builtins.remove(mount_map, selected)
          UI.ChangeWidget(Id(:table), :Items, build_mount_items.call)
          Builtins.foreach([:edit, :delete]) do |s|
            UI.ChangeWidget(
              Id(s),
              :Enabled,
              Ops.greater_than(Builtins.size(mount_items), 0)
            )
          end
        end
        if ret2 == :add || ret2 == :edit
          volume = ret2 == :edit ? Ops.get(mount_map, selected, {}) : {}
          volume = MountEntryPopup(volume)
          next if volume == {}
          Ops.set(volume, "fstype", "cifs") if ret2 == :add
          id = ret2 == :edit ? selected : Builtins.size(mount_map)
          Ops.set(mount_map, id, volume)
          UI.ChangeWidget(Id(:table), :Items, build_mount_items.call)
          Builtins.foreach([:edit, :delete]) do |s|
            UI.ChangeWidget(
              Id(s),
              :Enabled,
              Ops.greater_than(Builtins.size(mount_items), 0)
            )
          end
        end
        if ret2 == :ok
          default_min = Convert.to_integer(UI.QueryWidget(Id(:default_min), :Value))
          default_max = Convert.to_integer(UI.QueryWidget(Id(:default_max), :Value))
          domain_min = Convert.to_integer(UI.QueryWidget(Id(:domain_min), :Value))
          domain_max = Convert.to_integer(UI.QueryWidget(Id(:domain_max), :Value))
          idmap_domain_backend_new = Convert.to_string(UI.QueryWidget(Id(:backend), :Value))
          if Ops.greater_or_equal(default_min, default_max) ||
              Ops.greater_or_equal(domain_min, domain_max)
            # error popup: min >= max
            Popup.Error(
              _(
                "The minimum value in the range cannot be\nlarger than maximum one.\n"
              )
            )
            next
          end
          idmap_default_new = Builtins.sformat("%1-%2", default_min, default_max)
          idmap_domain_new = Builtins.sformat("%1-%2", domain_min, domain_max)
          if idmap_default_new != idmap_default
            SambaConfig.GlobalSetStr("idmap config * : range", idmap_default_new)
          end
          if idmap_domain_new != idmap_domain && workgroup != ""
            idmap_domain_setting = Builtins.sformat("idmap config %1 : range", workgroup)
            SambaConfig.GlobalSetStr(idmap_domain_setting, idmap_domain_new)
          end
          if idmap_domain_backend_new != idmap_domain_backend && workgroup != ""
            SambaConfig.GlobalSetStr(idmap_domain_backend_setting, idmap_domain_backend_new)
            if idmap_domain_backend_new == "ad"
              idmap_domain_schema_mode = Builtins.sformat("idmap config %1 : schema_mode", workgroup)
              SambaConfig.GlobalSetStr(idmap_domain_schema_mode, "rfc2307")
              idmap_domain_unix_nss_info = Builtins.sformat("idmap config %1 : unix_nss_info", workgroup)
              SambaConfig.GlobalSetStr(idmap_domain_unix_nss_info, "yes")
            end
          end
          Samba.SetDHCP(Convert.to_boolean(UI.QueryWidget(Id(:dhcp), :Value)))
          Samba.SetHostsResolution(
            Convert.to_boolean(UI.QueryWidget(Id(:hosts_resolution), :Value))
          )

          kerberos_method = Convert.to_string(
            UI.QueryWidget(Id(:kerberos_method), :Value)
          )
          SambaConfig.GlobalSetStr(
            "kerberos method",
            kerberos_method == "secrets only" ? nil : kerberos_method
          )

          required_groups = Convert.to_string(
            UI.QueryWidget(Id("require_grp"), :Value)
          )
          #remove leading/trailing spaces from each comma separated entry
          required_groups = required_groups.split(',').map(&:strip).join(',')

          SambaConfig::WinbindGlobalSetStr("require_membership_of",
                                           required_groups);
          updated_volumes = deep_copy(non_cifs_volumes)
          Builtins.foreach(mount_map) do |id, volume|
            updated_volumes = Builtins.add(updated_volumes, volume)
          end
          Samba.SetPAMMountVolumes(updated_volumes)
          break
        end
      end
      UI.CloseDialog
      Convert.to_symbol(ret)
    end

    # Samba memberhip dialog
    # @return dialog result
    def MembershipDialog
      # Samba-client workgroup dialog caption
      caption = _("Windows Domain Membership")
      mkhomedir = Samba.mkhomedir
      allow_share = true
      max_shares = Samba.GetMaxShares
      if max_shares == 0
        max_shares = 100
        allow_share = false
      end
      shares_group = Samba.shares_group
      guest = allow_share && Samba.GetGuessAccess
      status_term = VBox(ReplacePoint(Id(:rpstatus), Empty()))
      pw_data = deep_copy(Samba.password_data)
      left_domain = ""

      # internal function: update the status line
      check_domain_membership = lambda do |domain|
        Samba.SetWorkgroup(domain)

        return if Mode.config

        # busy popup text
        Popup.ShowFeedback("", _("Verifying AD domain membership..."))
        SambaAD.ReadADS(domain)
        if SambaAD.ADS != ""
          domain = SambaAD.GetWorkgroup(domain)
          Samba.SetWorkgroup(domain)
          SambaAD.ReadRealm
        end
        Popup.ClearFeedback

        leave_button = SambaAD.ADS == "" ?
          Empty() :
          # push button label
          PushButton(Id(:leave), _("&Leave"))
        UI.ReplaceWidget(
          Id(:rpstatus),
          Stage.cont || CheckWorkgroup(domain) != :joined_domain ?
            Empty() :
            HBox(
              # status label
              Left(Label(_("Currently a member of this domain"))),
              HStretch(),
              leave_button
            )
        )

        nil
      end

      # winbind enabled on start
      was_winbind = Samba.GetWinbind

      winbind_term = Stage.cont ?
        Empty() :
        VBox(
          VSpacing(0.4),
          Left(
            CheckBox(
              Id(:winbind),
              Opt(:notify),
              # translators: checkbox label to enable winbind
              _("&Use SMB Information for Linux Authentication"),
              Samba.GetWinbind
            )
          )
        )

      mkhomedir_term = VBox(
        Left(
          CheckBox(
            Id(:mkhomedir),
            # checkbox label
            _("&Create Home Directory on Login"),
            mkhomedir
          )
        )
      )

      autoyast_term = Mode.config ?
        VBox(
          VSpacing(),
          # frame label
          Frame(
            _("Join Settings"),
            HBox(
              # text entry label
              InputField(
                Id("user"),
                Opt(:hstretch),
                _("&Username"),
                Ops.get_string(pw_data, "user", "") != nil ?
                  Ops.get_string(pw_data, "user", "") :
                  ""
              ),
              # text entry label
              Password(
                Id("password"),
                Opt(:hstretch),
                _("&Password"),
                Ops.get_string(pw_data, "password", "")
              ),
              # text entry label
              InputField(
                Id("machine"),
                Opt(:hstretch),
                _("Mac&hine Account OU"),
                Ops.get_string(pw_data, "machine", "") != nil ?
                  Ops.get_string(pw_data, "machine", "") :
                  ""
              )
            )
          ),
          VSpacing(),
          # text entry label
          InputField(Id(:ads), Opt(:hstretch), _("Active Directory Server"))
        ) :
        Empty()

      ntp_term = Mode.config ?
        Empty() :
        VBox(
          VSpacing(0.4),
          # button label (run YaST client for NTP)
          Right(PushButton(Id(:ntp), _("N&TP Configuration...")))
        )

      # checkbox label
      text_nscd = _("Disable Name Service Cache")
      # checkbox label
      text_fam = _("Start File Alteration Monitor")

      firewall_widget = CWMFirewallInterfaces.CreateOpenFirewallWidget(
        { "services" => ["samba-server"], "display_details" => true }
      )
      firewall_layout = Ops.get_term(firewall_widget, "custom_widget", VBox())

      #    Wizard::SetContentsButtons( caption, `HVSquash( `VBox(
      Wizard.SetContentsButtons(
        caption,
        HBox(
          HSpacing(3),
          VBox(
            # translators: frame label
            Frame(
              _("Membership"),
              VBox(
                HBox(
                  HSpacing(0.2),
                  InputField(
                    Id(:workgroup),
                    Opt(:hstretch),
                    Stage.cont ?
                      _("&Domain") :
                      # translators: text entry label
                      _("&Domain or Workgroup"),
                    Samba.GetWorkgroupOrRealm
                  )
                ),
                status_term,
                winbind_term,
                HBox(
                  Stage.cont ? Empty() : HSpacing(2),
                  VBox(
                    mkhomedir_term,
                    Left(
                      # checkbox label
                      CheckBox(
                        Id(:caching),
                        _("Off&line Authentication"),
                        Samba.GetWinbindCaching
                      )
                    ),
                    Left(
                      # checkbox label
                      CheckBox(
                        Id(:ssh),
                        Opt(:notify),
                        _("&Single Sign-on for SSH"),
                        Samba.GetSSHSupport
                      )
                    ),
                    VSpacing(0.2)
                  )
                ),
                Left(
                  SambaAD.ADS != "" && !SambaAD.IsDHCPClient(false) ?
                    # checkbox label
                    CheckBox(Id(:adapt_dns), _("Change primary DNS suffix")) :
                    VBox()
                )
              )
            ),
            VSpacing(0.4),
            # button label
            Right(PushButton(Id(:expert), _("&Expert Settings..."))),
            SharesTerm(
              {
                "allow_share"  => allow_share,
                "group"        => shares_group,
                "max_shares"   => max_shares,
                "guest_access" => guest
              }
            ),
            autoyast_term,
            ntp_term
          ),
          HSpacing(3)
        ),
        Ops.add(
          Ops.add(
            Ops.add(
              Stage.cont ?
                Ops.get_string(@HELPS, "MembershipDialog_cont", "") :
                Ops.get_string(@HELPS, "MembershipDialog_nocont", ""),
              Ops.get_string(@HELPS, "MembershipDialog_common", "")
            ),
            SharesHelp()
          ),
          Mode.config ?
            Ops.get_string(@HELPS, "MembershipDialog_config", "") :
            Ops.get_string(@HELPS, "MembershipDialog_NTP", "")
        ),
        Stage.cont ? Label.BackButton : Label.CancelButton,
        Stage.cont ? Label.NextButton : Label.OKButton
      )
      #    CWMFirewallInterfaces::OpenFirewallInit (firewall_widget, "");
      Builtins.foreach([:mkhomedir, :caching, :ssh]) do |t|
        UI.ChangeWidget(Id(t), :Enabled, Samba.GetWinbind || Stage.cont)
      end
      Builtins.foreach([:group, :max_shares, :guest_ch]) do |t|
        UI.ChangeWidget(Id(t), :Enabled, allow_share)
      end

      if !Stage.cont
        Wizard.HideAbortButton
        check_domain_membership.call(Samba.GetWorkgroupOrRealm)
      end

      ret = nil
      while true
        event = UI.WaitForEvent
        ret = Ops.get_symbol(event, "ID")
        #	CWMFirewallInterfaces::OpenFirewallHandle(firewall_widget,"",event);
        use_winbind = Stage.cont ?
          true :
          Convert.to_boolean(UI.QueryWidget(Id(:winbind), :Value))

        if ret == :abort || ret == :cancel || ret == :back && !Stage.cont
          if ReallyAbort()
            break
          else
            next
          end
        elsif ret == :leave
          workgroup = Convert.to_string(UI.QueryWidget(Id(:workgroup), :Value))
          if LeaveDomain(workgroup) == :ok
            left_domain = workgroup
            check_domain_membership.call(workgroup)
            UI.ChangeWidget(Id(:winbind), :Value, false)
            SambaAD.SetADS("")
          end
        elsif ret == :winbind
          UI.ChangeWidget(Id(:mkhomedir), :Enabled, use_winbind)
          UI.ChangeWidget(Id(:caching), :Enabled, use_winbind)
          UI.ChangeWidget(Id(:ssh), :Enabled, use_winbind)
        elsif ret == :share_ch
          Builtins.foreach([:group, :max_shares, :guest_ch]) do |t|
            UI.ChangeWidget(
              Id(t),
              :Enabled,
              Convert.to_boolean(UI.QueryWidget(Id(:share_ch), :Value))
            )
          end
        elsif ret == :expert
          workgroup = Convert.to_string(
            UI.QueryWidget(Id(:workgroup), :Value)
          )
          workgroup = SambaAD.GetWorkgroup(workgroup)
          ExpertSettingsDialog(use_winbind, workgroup)
        elsif ret == :ntp
          if Package.InstallAll(["yast2-ntp-client"])
            workgroup = Convert.to_string(
              UI.QueryWidget(Id(:workgroup), :Value)
            )
            ads = SambaAD.ReadADS(workgroup)
            tmpfile = Ops.add(Directory.vardir, "/ad_ntp_data.ycp")
            ad_data = { "ads" => ads }
            SCR.Write(path(".target.ycp"), tmpfile, ad_data)
            WFM.CallFunction("ntp-client", [])
          end
        elsif ret == :next
          workgroup = Convert.to_string(UI.QueryWidget(Id(:workgroup), :Value))
          if workgroup != Samba.GetWorkgroup &&
              (left_domain == "" || workgroup != left_domain)
            check_domain_membership.call(workgroup)
            workgroup = Samba.GetWorkgroup
          end

          Samba.SetWinbind(use_winbind, workgroup)

          if use_winbind
            packages = ["samba-winbind"]
            if SambaAD.ADS != ""
              packages = Convert.convert(
                Builtins.merge(packages, ["krb5", "krb5-client"]),
                :from => "list",
                :to   => "list <string>"
              )
            end
            if Samba.PAMMountModified &&
                Ops.greater_than(Builtins.size(Samba.GetPAMMountVolumes), 0)
              packages = Builtins.add(packages, "pam_mount")
            end
            if !Package.InstallAll(packages)
              Popup.Error(Message.FailedToInstallPackages)
              ret = :not_next
              UI.ChangeWidget(Id(:winbind), :Value, false)
              next
            end
          end

          # for domain ask to join
          workgroup_type = CheckWorkgroup(workgroup)

          # need to set this before the join
          Samba.SetSSHSupport(
            use_winbind && Convert.to_boolean(UI.QueryWidget(Id(:ssh), :Value))
          )

          if UI.WidgetExists(:adapt_dns)
            SambaNetJoin.SetAdaptDNS(
              Convert.to_boolean(UI.QueryWidget(Id(:adapt_dns), :Value))
            )
          end

          if Mode.config
            Builtins.foreach(["user", "password", "machine"]) do |key|
              val = Convert.to_string(UI.QueryWidget(Id(key), :Value))
              Ops.set(Samba.password_data, key, val) if val != nil && val != ""
            end
            if Convert.to_string(UI.QueryWidget(Id(:ads), :Value)) != ""
              SambaAD.SetADS(
                Convert.to_string(UI.QueryWidget(Id(:ads), :Value))
              )
            end
          else
            if Samba.GetWinbind && workgroup_type == :workgroup
              Popup.Error(
                Ops.add(
                  Ops.add(
                    # 1st part of an error message:
                    # winbind cannot provide user information taken from
                    # a workgroup, must be a domain; %1 is the workgroup name
                    Builtins.sformat(
                      _(
                        "Cannot use the workgroup\n'%1' for Linux authentication."
                      ),
                      workgroup
                    ),
                    "\n\n"
                  ),
                  Stage.cont ?
                    # translators: 2nd part of an error message
                    _("Enter a valid domain.") :
                    # translators: 2nd part of an error message
                    _(
                      "Enter a domain or disable\nusing SMB for Linux authentication."
                    )
                )
              )
              next
            end

            in_domain = nil
            if Stage.cont && workgroup_type != :joined_domain
              # return `ok or `fail
              in_domain = JoinDomain(workgroup)
              Samba.in_domain = in_domain
              next if in_domain == :fail
            end

            if false # we might use it to warn user (#155716)
              # continue/cancel popup
              Popup.ContinueCancel(
                Builtins.sformat(
                  _(
                    "Configuring this system as a client for Active Directory resets the following\n" +
                      "settings in smb.conf to the default values:\n" +
                      "%1"
                  ),
                  Builtins.mergestring(["domain master", "domain logons"], "\n")
                )
              )
            end
            if !Stage.cont &&
                (left_domain == "" || use_winbind || left_domain != workgroup)
              # return `ok, `fail or `nojoin
              in_domain = AskJoinDomain(workgroup, workgroup_type)
              next if in_domain == :fail
              if in_domain != :ok && Samba.GetWinbind
                # 1st part of an error message:
                # winbind cannot provide user information if the host
                # is not in a domain
                Popup.Error(
                  _(
                    "The host must be a member of a domain\nfor Linux authentication using SMB."
                  ) + "\n\n" +
                    # translators: 2nd part of an error message
                    _(
                      "Join a domain or disable use of SMB\nfor Linux authentication."
                    )
                )
                next
              end
            end
            if Samba.GetWinbind
              # used outside this module for autologin function. must be complete sentence.
              Autologin.AskForDisabling(_("Samba is now enabled."))
            end
          end
          if Mode.config ||
              Stage.cont && Samba.in_domain == :ok &&
                Ops.get_string(
                  Samba.network_setup,
                  ["dhcp", "DHCLIENT_SET_HOSTNAME"],
                  "yes"
                ) == "yes"
            # yes/no popup text
            Samba.disable_dhcp_hostname = Popup.YesNo(
              _(
                "In a Microsoft environment,\n" +
                  "hostname changes with DHCP are problematic.\n" +
                  "Disable hostname changes with DHCP?"
              )
            )
          end


          Samba.SetMkHomeDir(
            use_winbind &&
              Convert.to_boolean(UI.QueryWidget(Id(:mkhomedir), :Value))
          )
          Samba.SetWinbindCaching(
            use_winbind &&
              Convert.to_boolean(UI.QueryWidget(Id(:caching), :Value))
          )

          new_share = Convert.to_boolean(UI.QueryWidget(Id(:share_ch), :Value))
          if new_share && !allow_share && SharesExist(Samba.shares_dir)
            Samba.remove_shares = AskForSharesRemoval()
          end
          max = Convert.to_integer(UI.QueryWidget(Id(:max_shares), :Value))
          max = 0 if !new_share
          Samba.SetShares(
            max,
            Convert.to_string(UI.QueryWidget(Id(:group), :Value))
          )
          Samba.SetGuessAccess(
            new_share &&
              Convert.to_boolean(UI.QueryWidget(Id(:guest_ch), :Value))
          )
          if !Stage.cont && !Mode.config && use_winbind && !was_winbind
            # message popup, part 1/2
            Popup.Message(
              _(
                "This change only affects newly created processes and not already\n" +
                  "running services. Restart your services manually or reboot \n" +
                  "the machine to enable it for all services.\n"
              )
            )
          end
          #	    CWMFirewallInterfaces::OpenFirewallStore (firewall_widget,"",event);
          break
        elsif ret == :back
          break
        end
      end

      Wizard.RestoreNextButton
      Wizard.RestoreBackButton
      Convert.to_symbol(ret)
    end
  end
end
