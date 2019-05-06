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

# File:	modules/Samba.ycp
# Package:	Configuration of samba-client
# Summary:	Data for configuration of samba-client, input and output functions.
# Authors:	Stanislav Visnovsky <visnov@suse.cz>
#
# $Id$
#
# Representation of the configuration of samba-client.
# Input and output routines.
require "yast"
require "y2firewall/firewalld"

module Yast
  class SambaClass < Module
    def main
      textdomain "samba-client"

      Yast.import "Autologin"
      Yast.import "FileUtils"
      Yast.import "NetworkConfig"
      Yast.import "Mode"
      Yast.import "Nsswitch"
      Yast.import "Package"
      Yast.import "Pam"
      Yast.import "Progress"
      Yast.import "Report"
      Yast.import "Service"
      Yast.import "SambaAD"
      Yast.import "SambaConfig"
      Yast.import "SambaWinbind"
      Yast.import "SambaNetJoin"
      Yast.import "SambaNmbLookup"
      Yast.import "String"
      Yast.import "Summary"
      Yast.import "OSRelease"


      # Data was modified?
      @modified = false

      # Are globals already configured (for AutoYaST)
      @globals_configured = false

      # Write only, used during autoinstallation.
      # Don't run services and SuSEconfig, it's all done at one place.
      @write_only = false

      # Should be winbind enabled?
      @winbind_enabled = false

      # If FAM should be started
      @start_fam = true

      # if pam_mkhomedir is set in /etc/pam.d/commond-session
      @mkhomedir = false

      # if it mkhomedir was modified
      @mkhomedir_modified = false

      # if shares config (actually group owner) was modified
      @shares_modified = false

      # map with user name and password (used for autoinstallation only)
      @password_data = {}

      # dir with user shares
      @shares_dir = "/var/lib/samba/usershares"

      # path to config file with DHCP settings
      @dhcp_path = "/etc/samba/dhcp.conf"

      # if existing shares should be removed
      @remove_shares = false

      # if smb + nmb services should be stopped
      @stop_services = false

      @shares_group = "users"

      @shares_separator = "\\"

      # remember if the last join was succesful
      @in_domain = nil

      # if changing hostname by DHCP should be disabled (#169260)
      @disable_dhcp_hostname = false

      # support for SSH single-sign-on (fate #303415)
      @ssh_support = false

      # initial status of single-sign-on suport in ssh_config
      @ssh_was_enabled = false

      # initial status of single-sign-on suport in sshd_config
      @sshd_was_enabled = false

      # if it ssh support was modified
      @ssh_modified = false

      # section in /etc/ssh/ssh_config file for storing single-sign-on settings
      @ssh_section = "*"

      # if hosts are resolved via WINS
      @hosts_resolution = nil

      # host line of nsswitch.conf
      @hosts_db = []

      # original value of hosts_resolution, for detecting changes
      @hosts_resolution_orig = false

      # path to pam_mount.conf.xml
      @pam_mount_path = "/etc/security/pam_mount.conf.xml"

      # the volume data from pam_mount.conf.xml
      @pam_mount_volumes = []

      # original value of pam_mount_volumes, for detecting changes
      @pam_mount_volumes_orig = nil

      # network configuration (to be read from NetworkConfig module)
      @network_setup = NetworkConfig.Export
    end

    def firewalld
      Y2Firewall::Firewalld.instance
    end

    def PAMMountModified
      @pam_mount_volumes_orig == nil && @pam_mount_volumes != [] ||
        @pam_mount_volumes_orig != nil &&
          Builtins.sort(@pam_mount_volumes) !=
            Builtins.sort(@pam_mount_volumes_orig)
    end


    # Data was modified?
    # @return true if modified
    def GetModified
      Builtins.y2debug("modified=%1", @modified)
      @modified || @mkhomedir_modified || @shares_modified ||
        SambaConfig.GetModified || @ssh_modified ||
        PAMMountModified()
    end

    # Read the data from /etc/security/pam_mount.conf.xml regarding
    # mounting user's home directories
    def ReadPAMMount
      if !FileUtils.Exists(@pam_mount_path)
        Builtins.y2warning("%1 does not exist", @pam_mount_path)
        return false
      end
      # initially, parse the whole file and let the agent build data map
      if SCR.Read(path(".pam_mount"), @pam_mount_path) != true
        Builtins.y2warning("reading %1 failed", @pam_mount_path)
        return false
      end

      @pam_mount_volumes = Convert.convert(
        SCR.Read(path(".pam_mount.get"), { "element" => "volume" }),
        :from => "any",
        :to   => "list <map>"
      )
      @pam_mount_volumes = [] if @pam_mount_volumes == nil

      @pam_mount_volumes_orig = deep_copy(@pam_mount_volumes)
      true
    end

    # Return the list of 'volume' entries from pam_mount.conf.xml
    def GetPAMMountVolumes
      deep_copy(@pam_mount_volumes)
    end

    # Set the new list of 'volume' entries
    def SetPAMMountVolumes(new_volumes)
      new_volumes = deep_copy(new_volumes)
      @pam_mount_volumes = deep_copy(new_volumes)

      nil
    end

    # Write the changes to /etc/security/pam_mount.conf.xml
    def WritePAMMount
      if !FileUtils.Exists(@pam_mount_path)
        Builtins.y2warning("%1 does not exist, no writing", @pam_mount_path)
        return false
      end
      if @pam_mount_volumes_orig == nil
        Builtins.y2milestone("%1 not read yet, reading now...", @pam_mount_path)
        if SCR.Read(path(".pam_mount"), @pam_mount_path) != true
          Builtins.y2error("reading %1 failed", @pam_mount_path)
          return false
        end
      end
      if !PAMMountModified()
        Builtins.y2milestone("no changes to pam_mount.conf.xml")
        return true
      end

      SCR.Execute(
        path(".target.bash"),
        Builtins.sformat("cp %1 %1.YaST2save", @pam_mount_path)
      )

      # 1. delete all volume entries with 'cifs' fstype
      SCR.Write(
        path(".pam_mount.delete"),
        { "element" => "volume", "attrmap" => { "fstype" => "cifs" } }
      )

      # 2. save the new set of volume entries
      Builtins.foreach(@pam_mount_volumes) do |volume|
        next if Ops.get_string(volume, "fstype", "") != "cifs"
        # if no volume entry is present, add new
        SCR.Write(
          path(".pam_mount.add"),
          {
            "element" => "volume",
            # ... the keys without values should not end in config file
            "attrmap" => Builtins.filter(
              Convert.convert(
                volume,
                :from => "map",
                :to   => "map <string, string>"
              )
            ) do |k, v|
              v != ""
            end,
            "newline" => true
          }
        )
      end
      SCR.Write(path(".pam_mount"), nil)
      true
    end

    # Read the state of mkhomedir in /etc/pam.d/common-session (bug #143519)
    def ReadMkHomeDir
      @mkhomedir = Pam.Enabled("mkhomedir")
      @mkhomedir
    end

    # Write the new value of pam_mkhomedir to /etc/pam.d/common-session
    # @param boolean new status
    def WriteMkHomeDir(enabled)
      return true if !@mkhomedir_modified
      Pam.Set("mkhomedir", enabled)
    end

    # Set the new value of mkhomedir
    def SetMkHomeDir(new_value)
      if @mkhomedir != new_value
        @mkhomedir_modified = true
        @mkhomedir = new_value
      end
      @mkhomedir
    end

    # get number of max shares from smb.conf; 0 mean shares are not enabled
    def GetMaxShares
      SambaConfig.GlobalGetInteger("usershare max shares", 0)
    end

    # Read /etc/nsswitch.conf and check if WINS is used for hosts resolution
    def GetHostsResolution
      if @hosts_resolution == nil
        @hosts_db = Nsswitch.ReadDb("hosts")
        @hosts_resolution = Builtins.contains(@hosts_db, "wins")
        @hosts_resolution_orig = @hosts_resolution
      end
      @hosts_resolution
    end

    # Set the new value for hosts resolution
    def SetHostsResolution(resolve)
      @hosts_resolution = resolve
      true
    end

    # Write /etc/nsswitch.conf if modified
    def WriteHostsResolution
      if @hosts_resolution != @hosts_resolution_orig
        if @hosts_resolution
          @hosts_db = Builtins.add(@hosts_db, "wins")
        else
          @hosts_db = Builtins.filter(@hosts_db) { |e| e != "wins" }
        end
        Nsswitch.WriteDb("hosts", @hosts_db)
        ret = Nsswitch.Write
        Builtins.y2milestone("/etc/nsswitch.conf written: %1", ret)
        return ret
      end
      true
    end


    # Check if dhcp.conf is included in smb.conf
    def GetDHCP
      include_list = SambaConfig.GlobalGetList("include", [])
      Builtins.contains(include_list, @dhcp_path)
    end

    # Set the support of DHCP (include dhcp.conf in smb.conf)
    # @return if status was changed
    def SetDHCP(new)
      include_list = SambaConfig.GlobalGetList("include", [])
      if new && !Builtins.contains(include_list, @dhcp_path)
        include_list = Convert.convert(
          Builtins.union(include_list, [@dhcp_path]),
          :from => "list",
          :to   => "list <string>"
        )
      elsif !new && Builtins.contains(include_list, @dhcp_path)
        include_list = Builtins.filter(include_list) { |i| i != @dhcp_path }
      else
        return false
      end
      SambaConfig.GlobalSetList("include", include_list)
      true
    end

    # check if shares guest access is allowed
    def GetGuessAccess
      SambaConfig.GlobalGetTruth("usershare allow guests", false)
    end

    # Set the new value for guest access (#144787)
    def SetGuessAccess(guest)
      SambaConfig.GlobalSetTruth("usershare allow guests", guest)
      true
    end

    # Read user shares settings
    def ReadSharesSetting
      @shares_dir = SambaConfig.GlobalGetStr("usershare path", @shares_dir)
      if @shares_dir != nil && FileUtils.Exists(@shares_dir)
        stat = Convert.to_map(SCR.Read(path(".target.stat"), @shares_dir))
        out = Convert.to_map(
          SCR.Execute(
            path(".target.bash_output"),
            Builtins.sformat(
              "getent group %1 | /usr/bin/cut -f 1 -d :",
              Ops.get_integer(stat, "gid", 100)
            )
          )
        )
        @shares_group = String.FirstChunk(
          Ops.get_string(out, "stdout", ""),
          "\n"
        )
      end
      @shares_separator = SambaConfig.GlobalGetStr("winbind separator", "\\")

      nil
    end

    # set the new values for user shares
    # @param [Fixnum] max maximum number of shares (0 is for disabling)
    # @param [String] group permited group
    def SetShares(max, group)
      SambaConfig.GlobalSetStr(
        "usershare max shares",
        Ops.greater_than(max, 0) ? max : nil
      )

      @shares_modified = true if @shares_group != group
      @shares_group = group
      true
    end

    # Get the current status of winbind caching
    def GetWinbindCaching
      cached = SambaConfig.WinbindGlobalGetStr("cached_login", "")
      offline = SambaConfig.GlobalGetStr("winbind offline logon", "")
      cached == "yes" && offline == "yes"
    end

    # Set the new value for winbind caching (see bug #143927)
    def SetWinbindCaching(enable)
      SambaConfig.WinbindGlobalSetStr("cached_login", enable ? "yes" : nil)
      SambaConfig.GlobalSetStr("winbind offline logon", enable ? "yes" : nil)
      enable
    end

    # Read the current status of ssh single-sign-on support (fate #303415)
    def ReadSSHSupport
      ssh = nil
      sshd = false

      if FileUtils.Exists("/etc/ssh/ssh_config") &&
          FileUtils.Exists("/etc/ssh/sshd_config")
        hostname = "*"
        out = Convert.to_map(
          SCR.Execute(path(".target.bash_output"), "LANG=C /bin/hostname")
        )
        if Ops.get(out, "stderr") == ""
          hostname = Builtins.deletechars(
            Ops.get_string(out, "stdout", ""),
            "\n"
          )
        end
        Builtins.foreach(SCR.Dir(path(".etc.ssh.ssh_config.s"))) do |sec|
          next if ssh != nil
          cont = SCR.Dir(Builtins.add(path(".etc.ssh.ssh_config.v"), sec))
          Builtins.y2debug("section %1 contains: %2", sec, cont)
          if (sec == "*" || sec == hostname) &&
              Builtins.contains(cont, "GSSAPIAuthentication") &&
                Builtins.contains(cont, "GSSAPIDelegateCredentials")
            ssh = SCR.Read(
              Builtins.add(
                Builtins.add(path(".etc.ssh.ssh_config.v"), sec),
                "GSSAPIAuthentication"
              )
            ) == "yes" &&
              SCR.Read(
                Builtins.add(
                  Builtins.add(path(".etc.ssh.ssh_config.v"), sec),
                  "GSSAPIDelegateCredentials"
                )
              ) == "yes"
            @ssh_section = sec
          end
        end
        sshd = true
        Builtins.foreach(
          [
            "GSSAPIAuthentication",
            "GSSAPICleanupCredentials",
            "ChallengeResponseAuthentication",
            "UsePAM"
          ]
        ) do |key|
          sshd = sshd &&
            Builtins.contains(
              Convert.to_list(
                SCR.Read(Builtins.add(path(".etc.ssh.sshd_config"), key))
              ),
              "yes"
            )
        end
      end
      @ssh_was_enabled = ssh == true
      @sshd_was_enabled = sshd
      @ssh_support = @ssh_was_enabled && @sshd_was_enabled
      @ssh_support
    end

    # Get the current status of ssh single-sign-on support
    def GetSSHSupport
      @ssh_support
    end

    # Set the new value for sh single-sign-on support
    def SetSSHSupport(enable)
      @ssh_support = enable
      @ssh_modified = enable != (@ssh_was_enabled && @sshd_was_enabled)
      kerberos_method = SambaConfig.GlobalGetStr("kerberos method", "")
      # bnc#673982, use "secrets and keytab" as default (=when not set otherwise)
      if @ssh_support && kerberos_method == ""
        kerberos_method = "secrets and keytab"
        SambaConfig.GlobalSetStr("kerberos method", kerberos_method)
      end
      enable
    end

    # Write the new value for sh single-sign-on support (fate #303415)
    def WriteSSHSupport(enable)
      write = enable ? "yes" : "no"

      # do not write "no" everywhere, there might be some user setting...
      if enable || @ssh_was_enabled
        SCR.Write(
          Builtins.add(
            Builtins.add(path(".etc.ssh.ssh_config.v"), @ssh_section),
            "GSSAPIAuthentication"
          ),
          write
        )
        SCR.Write(
          Builtins.add(
            Builtins.add(path(".etc.ssh.ssh_config.v"), @ssh_section),
            "GSSAPIDelegateCredentials"
          ),
          write
        )
        SCR.Write(path(".etc.ssh.ssh_config"), nil)
        Builtins.y2milestone("/etc/ssh/ssh_config modified")
      end
      if enable || @sshd_was_enabled
        Builtins.foreach(
          [
            "GSSAPIAuthentication",
            "GSSAPICleanupCredentials",
            "ChallengeResponseAuthentication",
            "UsePAM"
          ]
        ) do |key|
          SCR.Write(Builtins.add(path(".etc.ssh.sshd_config"), key), [write])
        end
        SCR.Write(path(".etc.ssh.sshd_config"), nil)
        Builtins.y2milestone("/etc/ssh/sshd_config modified")
      end
      enable
    end

    # Start/Stop and FAM service according to current settings
    # @param [Boolean] write_only do not start/stop services
    # @return success
    def WriteFAM(write_only)
      if @start_fam
        return false if !Package.InstalledAll(["fam", "fam-server"])

        Service.Enable("fam")
        Service.Start("fam") if !write_only
      else
        Service.Disable("fam")
        Service.Stop("fam") if !write_only
      end
      true
    end

    # create the shares directory with correct rights
    def WriteShares
      if !FileUtils.Exists(@shares_dir)
        SCR.Execute(path(".target.mkdir"), @shares_dir)
      elsif @remove_shares
        SCR.Execute(
          path(".target.bash"),
          Builtins.sformat("/bin/rm -f %1/*", @shares_dir)
        )
      end
      if FileUtils.Exists(@shares_dir)
        @shares_group = "users" if @shares_group == ""
        SCR.Execute(
          path(".target.bash"),
          Builtins.sformat(
            "/bin/chmod 1770 %1; /bin/chgrp '%2' %1",
            @shares_dir,
            @shares_group
          )
        )
      end
      true
    end

    # adjust the services for sharing
    def AdjustSharesServices(write_only)
      if Ops.greater_than(GetMaxShares(), 0)
        Builtins.foreach(["nmb", "smb"]) do |service|
          Service.Enable(service)
          if !write_only
            if Service.Status(service) == 0
              Service.Restart(service)
            else
              Service.Start(service)
            end
          end
        end
      elsif @stop_services
        Service.Disable("nmb")
        Service.Disable("smb")
        if !write_only
          Service.Stop("nmb")
          Service.Stop("smb")
        end
      end
      true
    end

    # Tell displaymanager (KDM/GDM) to use special windbind greeter
    # @param [Boolean] enable if  winbind is enabled
    # @return success
    def WriteDisplayManager(enable)
      return false if !FileUtils.Exists("/etc/sysconfig/displaymanager")

      if enable
        if !Package.InstalledAny(["kdebase3-kdm", "kde4-kdm", "gdm", "kdm"])
          return false
        end
        if SCR.Read(
            path(".sysconfig.displaymanager.DISPLAYMANAGER_AD_INTEGRATION")
          ) == "yes"
          return true
        end
      end

      SCR.Write(
        path(".sysconfig.displaymanager.DISPLAYMANAGER_AD_INTEGRATION"),
        enable ? "yes" : "no"
      )
      SCR.Write(path(".sysconfig.displaymanager"), nil)

      dm = Convert.to_string(
        SCR.Read(path(".sysconfig.displaymanager.DISPLAYMANAGER"))
      )

      true
    end

    # Read all samba-client settings
    # @return true on success
    def Read
      # Samba-client read dialog caption
      caption = _("Initializing Samba Client Configuration")

      steps = 2

      # We do not set help text here, because it was set outside
      Progress.New(
        caption,
        " ",
        steps,
        [
          # translators: progress stage 1/2
          _("Read the global Samba settings"),
          # translators: progress stage 2/2
          _("Read the winbind status")
        ],
        [
          # translators: progress step 1/2
          _("Reading the global Samba settings..."),
          # translators: progress step 2/2
          _("Reading the winbind status..."),
          # translators: progress finished
          _("Finished")
        ],
        ""
      )

      # read global settings
      Progress.NextStage

      SambaConfig.Read(false)

      # read winbind status
      Progress.NextStage
      @winbind_enabled = SambaWinbind.IsEnabled

      # start nmbstatus in background
      SambaNmbLookup.Start if !Mode.test

      ReadMkHomeDir()

      ReadSharesSetting()

      GetHostsResolution()

      ReadSSHSupport()

      Autologin.Read

      # read network settings
      # (for bug 169260: do not allow DHCP to change the hostname)
      NetworkConfig.Read
      @network_setup = NetworkConfig.Export

      firewalld.read

      ReadPAMMount()

      # ensure nmbd is restarted if stopped for lookup
      SambaNmbLookup.checkNmbstatus if !Mode.test

      # finished
      Progress.NextStage
      @globals_configured = true
      @modified = false
      true
    end

    # Set a windind status
    #
    # @param group	a new winbind status
    def SetWinbind(status, workgroup)
      if status != @winbind_enabled
        @modified = true
        @winbind_enabled = status
      end
      SambaAD.AdjustSambaConfig(status)
      SambaWinbind.AdjustSambaConfig(status, workgroup)

      nil
    end

    # In cluster environment,
    # synchronize nodes after the configuration has been written
    def SynchronizeCluster
      if FileUtils.Exists("/usr/sbin/csync2")
        # first, force syncing of smb.conf (bnc#802814)
        out = Convert.to_map(
          SCR.Execute(path(".target.bash_output"), "/usr/sbin/csync2 -cr /")
        )
        if Ops.get_integer(out, "exit", 0) != 0
          Builtins.y2error("csync2 -cr failed with %1", out)
          return false
        end
        out = Convert.to_map(
          SCR.Execute(
            path(".target.bash_output"),
            "/usr/sbin/csync2 -f /etc/samba/smb.conf"
          )
        )
        if Ops.get_integer(out, "exit", 0) != 0
          Builtins.y2error("csync2 -f failed with %1", out)
          return false
        end

        # sync the rest
        out = Convert.to_map(
          SCR.Execute(path(".target.bash_output"), "/usr/sbin/csync2 -xv")
        )
        if Ops.get_integer(out, "exit", 0) != 0
          Builtins.y2error("csync2 -x failed with %1", out)
          return false
        end
        return true
      end
      false
    end

    # Write all samba-client settings
    # @return true on success
    def Write(write_only)
      ret = true

      # Samba-client read dialog caption
      caption = _("Saving Samba Client Configuration")

      stages = [
        # translators: write progress stage
        _("Write the settings"),
        !# translators: write progress stage
        @winbind_enabled ?
          _("Disable Samba services") :
          # translators: write progress stage
          _("Enable Samba services")
      ]
      steps = [
        # translators: write progress step
        _("Writing the settings..."),
        !# translators: write progress step
        @winbind_enabled ?
          _("Disabling Samba services...") :
          # translators: write progress step
          _("Enabling Samba services..."),
        # translators: write progress finished
        _("Finished")
      ]

      # rely on ctdb to perform all changes to the samba services for the clustered case
      cluster_present = SambaNetJoin.ClusterPresent(false)

      if SambaAD.ADS != "" && @winbind_enabled
        # write progress stage
        stages = Builtins.add(stages, _("Write Kerberos configuration"))
        # write progress step
        steps = Builtins.add(steps, _("Writing Kerberos configuration..."))
      end

      # bug 169260: do not allow DHCP to change the hostname
      if @winbind_enabled && @disable_dhcp_hostname
        if @network_setup == {}
          NetworkConfig.Read
          @network_setup = NetworkConfig.Export
        end
        Ops.set(@network_setup, ["dhcp", "DHCLIENT_SET_HOSTNAME"], "no")
        NetworkConfig.Import(@network_setup)
        NetworkConfig.Write
      end

      # We do not set help text here, because it was set outside
      Progress.New(caption, " ", Builtins.size(stages), stages, steps, "")

      # write settings
      Progress.NextStage
      # if nothing to write, quit (but show at least the progress bar :-)
      return true if !GetModified()

      if Mode.autoinst
        if SambaAD.ADS != ""
          SambaConfig.GlobalSetStr(
            "workgroup",
            SambaAD.GetWorkgroup(SambaConfig.GlobalGetStr("workgroup", ""))
          )
          SambaAD.ReadRealm
        end
        # join the domain during autoinstallation
        if @password_data != {}
          relname = OSRelease.ReleaseName
          relver = OSRelease.ReleaseVersion
          SambaNetJoin.Join(
            SambaConfig.GlobalGetStr("workgroup", ""),
            "member",
            Ops.get(
              @password_data,
              "user",
              Ops.get(@password_data, "username", "")
            ),
            Ops.get(
              @password_data,
              "password",
              Ops.get(@password_data, "passwd", "")
            ),
            Ops.get(@password_data, "machine"),
            relname,
            relver
          )
        end
      end

      if !SambaConfig.Write(write_only)
        # translators: error message, %1 is filename
        Report.Error(
          Builtins.sformat(
            _("Cannot write settings to %1."),
            "/etc/samba/smb.conf"
          )
        )
        ret = false
      end

      # winbind
      Progress.NextStage
      if @winbind_enabled && !cluster_present
        ret = false if !Package.Installed("samba-winbind") && !Mode.test
        if !SambaWinbind.AdjustService(true)
          # translators: error message, do not change winbind
          Report.Error(_("Cannot start winbind service."))
          ret = false
        end
        if !write_only && !SambaWinbind.StartStopNow(true)
          # translators: error message, do not change winbind
          Report.Error(_("Cannot start winbind daemon."))
          ret = false
        end
      elsif !@winbind_enabled
        if !SambaWinbind.AdjustService(false)
          # translators: error message, do not change winbind
          Report.Error(_("Cannot stop winbind service."))
          ret = false
        end
        if !write_only && !SambaWinbind.StartStopNow(false)
          # translators: error message, do not change winbind
          Report.Error(_("Cannot stop winbind daemon."))
          ret = false
        end
      end
      if !SambaWinbind.AdjustNsswitch(@winbind_enabled, write_only)
        # translators: error message, %1 is filename
        Report.Error(
          Builtins.sformat(
            _("Cannot write settings to %1."),
            "/etc/nsswitch.conf"
          )
        )
        ret = false
      end
      if !SambaWinbind.AdjustPam(@winbind_enabled)
        # translators: error message
        Report.Error(_("Cannot write PAM settings."))
        ret = false
      end

      Progress.NextStage if SambaAD.ADS != "" && @winbind_enabled

      if !SambaAD.AdjustKerberos(@winbind_enabled)
        # translators: error message, %1 is filename
        Report.Error(
          Builtins.sformat(_("Cannot write settings to %1."), "/etc/krb5.conf")
        )
        ret = false
      end

      WriteMkHomeDir(@mkhomedir)

      WriteDisplayManager(@winbind_enabled)

      Autologin.Write(write_only) # see dialog.ycp

      WriteShares()

      AdjustSharesServices(write_only) if !cluster_present

      WriteSSHSupport(@ssh_support)

      WriteHostsResolution()

      write_only ? firewalld.write_only : firewalld.write

      if WritePAMMount() &&
          Ops.greater_than(Builtins.size(@pam_mount_volumes), 0)
        # enable pam_mount for services gdm, xdm, login, sshd (bnc#433845)
        Builtins.foreach(["gdm", "login", "xdm", "sshd"]) do |service|
          out = Convert.to_map(
            SCR.Execute(
              path(".target.bash_output"),
              Builtins.sformat("pam-config --service %1 -a --mount", service)
            )
          )
          if Ops.get_string(out, "stderr", "") != ""
            Builtins.y2warning("pam-config failed for service %1", service)
          end
        end
      end

      if cluster_present
        SynchronizeCluster()
        SambaNetJoin.CleanupCTDB
      end

      # finished
      Progress.NextStage
      @modified = false

      ret
    end

    # Get all samba-client settings from the first parameter
    # (For use by autoinstallation.)
    # @param [Hash] settings The YCP structure to be imported.
    # @return [Boolean] True on success
    def Import(settings)
      settings = deep_copy(settings)
      @globals_configured = false
      globals = Ops.get_map(settings, "global", {})
      sections = []

      Builtins.foreach(
        Convert.convert(settings, :from => "map", :to => "map <string, any>")
      ) do |key, value|
        # handle special keys separately
        if key == "shares_group"
          @shares_group = Ops.get_string(
            settings,
            "shares_group",
            @shares_group
          )
        elsif key == "active_directory"
          SambaAD.SetADS(
            Ops.get_string(settings, ["active_directory", "kdc"], "")
          )
        elsif key == "join"
          @password_data = Ops.get_map(settings, "join", {})
        elsif key == "mkhomedir"
          SetMkHomeDir(Ops.get_boolean(settings, "mkhomedir", @mkhomedir))
        elsif key == "disable_dhcp_hostname"
          @disable_dhcp_hostname = Ops.get_boolean(
            settings,
            "disable_dhcp_hostname",
            @disable_dhcp_hostname
          )
        elsif key != "winbind" && Ops.is_map?(value)
          # form a section to import SambaConfig
          sections = Builtins.add(
            sections,
            { "name" => key, "parameters" => value }
          )
        end
      end

      # call this _after_ evaluation if AD is used
      winbind = Ops.get_boolean(
        settings,
        "winbind",
        Ops.get_boolean(settings, ["global", "winbind"], false)
      )
      @workgroup = Ops.get_string(settings, ["global", "workgroup"], "")
      SetWinbind(winbind, @workgroup) if winbind != nil

      SambaConfig.Import(sections) if sections != []

      # explicitely adapt some variables based on 'globals' section
      if globals != {}
        if Builtins.haskey(globals, "usershare_max_shares") ||
            Builtins.haskey(settings, "shares_group")
          SetShares(
            Builtins.tointeger(
              Ops.get_string(globals, "usershare_max_shares", "0")
            ),
            Ops.get_string(settings, "shares_group", @shares_group)
          )
        end
        @globals_configured = true
      end
      @modified = true

      true
    end

    # Dump the samba-client settings to a single map
    # (For use by autoinstallation.)
    # @return [Hash] Dumped settings (later acceptable by Import ())
    def Export
      return {} if !@globals_configured
      ret = { "winbind" => @winbind_enabled }
      Ops.set(ret, "mkhomedir", @mkhomedir) if @mkhomedir_modified

      if @shares_modified && @shares_group != ""
        Ops.set(ret, "shares_group", @shares_group)
      end

      if @disable_dhcp_hostname
        Ops.set(ret, "disable_dhcp_hostname", @disable_dhcp_hostname)
      end

      Builtins.foreach(
        Convert.convert(SambaConfig.Export, :from => "any", :to => "list <map>")
      ) do |sect|
        name = Ops.get_string(sect, "name", "")
        Ops.set(ret, name, Ops.get_map(sect, "parameters", {}))
      end

      if SambaAD.ADS != ""
        Ops.set(ret, "active_directory", { "kdc" => SambaAD.ADS })
      end
      # export user & password to "join" map
      joinmap = {}
      Builtins.foreach(@password_data) do |key, val|
        Ops.set(joinmap, key, val) if val != nil && val != ""
      end
      Ops.set(ret, "join", joinmap) if joinmap != {}
      @modified = false
      deep_copy(ret)
    end

    # Create a textual summary and a list of unconfigured options
    # @return summary of the current configuration
    def Summary
      summary = ""
      nc = Summary.NotConfigured
      workgroup = SambaConfig.GlobalGetStr("workgroup", "")

      # summary header
      summary = Summary.AddHeader(summary, _("Global Configuration"))

      if @globals_configured
        summary = Summary.AddLine(
          summary,
          Builtins.sformat(
            # autoyast summary item: configured workgroup
            _("Workgroup or Domain: %1"),
            workgroup
          )
        )

        if @mkhomedir
          summary = Summary.AddLine(
            summary,
            # autoyast summary item
            _("Create Home Directory on Login")
          )
        end
        if GetWinbindCaching()
          summary = Summary.AddLine(
            summary,
            # autoyast summary item
            _("Offline Authentication Enabled")
          )
        end
        if Ops.greater_than(GetMaxShares(), 0)
          summary = Summary.AddLine(
            summary,
            Builtins.sformat(
              # autoyast summary item
              _("Maximum Number of Shares: %1"),
              GetMaxShares()
            )
          )
        end
      else
        summary = Summary.AddLine(summary, nc)
      end
      summary
    end

    # Create shorter textual summary and a list of unconfigured options
    # @return summary of the current configuration
    def ShortSummary
      summary = ""
      workgroup = SambaConfig.GlobalGetStr("workgroup", "")

      if @globals_configured
        # summary item: configured workgroup
        summary = Ops.add(
          Builtins.sformat(
            _("<p><b>Workgroup or Domain</b>: %1</p>"),
            workgroup
          ),
          # summary item: authentication using winbind
          Builtins.sformat(
            _("<p><b>Authentication with SMB</b>: %1</p>"),
            # translators: winbind status in summary
            @winbind_enabled ?
              _("Yes") :
              # translators: winbind status in summary
              _("No")
          )
        )
      else
        summary = Summary.NotConfigured
      end
      summary
    end


    # Set a host workgroup
    #
    # @param [String] group	a new workgroup
    def SetWorkgroup(group)
      SambaConfig.GlobalSetStr("workgroup", group)

      nil
    end

    # Get a host workgroup
    #
    # @return [String]	a new workgroup
    def GetWorkgroup
      SambaConfig.GlobalGetStr("workgroup", "")
    end

    def GetWorkgroupOrRealm
      workgroup = SambaConfig.GlobalGetStr("workgroup", "")
      if Builtins.toupper(SambaConfig.GlobalGetStr("security", "")) == "ADS"
        return SambaConfig.GlobalGetStr("realm", workgroup)
      end
      workgroup
    end


    # Get a winbind status
    #
    # @return [Boolean]d	a winbind status
    def GetWinbind
      @winbind_enabled
    end

    # Return required packages for auto-installation
    # @return [Hash] of packages to be installed and to be removed
    def AutoPackages
      to_install = ["samba-client", "samba-winbind", "pam_mount"]
      if SambaAD.ADS != ""
        to_install = Convert.convert(
          Builtins.union(to_install, ["krb5", "krb5-client"]),
          :from => "list",
          :to   => "list <string>"
        )
      end
      { "install" => to_install, "remove" => [] }
    end

    # update the information if FAM should be started
    # @return current fam status
    def SetStartFAM(fam)
      if fam != @start_fam
        @start_fam = fam
        @modified = true
      end
      @start_fam
    end

    publish :variable => :modified, :type => "boolean"
    publish :variable => :globals_configured, :type => "boolean"
    publish :variable => :write_only, :type => "boolean"
    publish :variable => :winbind_enabled, :type => "boolean"
    publish :variable => :start_fam, :type => "boolean"
    publish :variable => :mkhomedir, :type => "boolean"
    publish :variable => :password_data, :type => "map <string, string>"
    publish :variable => :shares_dir, :type => "string"
    publish :variable => :remove_shares, :type => "boolean"
    publish :variable => :stop_services, :type => "boolean"
    publish :variable => :shares_group, :type => "string"
    publish :variable => :shares_separator, :type => "string"
    publish :variable => :in_domain, :type => "symbol"
    publish :variable => :disable_dhcp_hostname, :type => "boolean"
    publish :variable => :ssh_support, :type => "boolean"
    publish :variable => :network_setup, :type => "map"
    publish :function => :PAMMountModified, :type => "boolean ()"
    publish :function => :GetModified, :type => "boolean ()"
    publish :function => :ReadPAMMount, :type => "boolean ()"
    publish :function => :GetPAMMountVolumes, :type => "list <map> ()"
    publish :function => :SetPAMMountVolumes, :type => "void (list <map>)"
    publish :function => :WritePAMMount, :type => "boolean ()"
    publish :function => :ReadMkHomeDir, :type => "boolean ()"
    publish :function => :WriteMkHomeDir, :type => "boolean (boolean)"
    publish :function => :SetMkHomeDir, :type => "boolean (boolean)"
    publish :function => :GetMaxShares, :type => "integer ()"
    publish :function => :GetHostsResolution, :type => "boolean ()"
    publish :function => :SetHostsResolution, :type => "boolean (boolean)"
    publish :function => :WriteHostsResolution, :type => "boolean ()"
    publish :function => :GetDHCP, :type => "boolean ()"
    publish :function => :SetDHCP, :type => "boolean (boolean)"
    publish :function => :GetGuessAccess, :type => "boolean ()"
    publish :function => :SetGuessAccess, :type => "boolean (boolean)"
    publish :function => :ReadSharesSetting, :type => "boolean ()"
    publish :function => :SetShares, :type => "boolean (integer, string)"
    publish :function => :GetWinbindCaching, :type => "boolean ()"
    publish :function => :SetWinbindCaching, :type => "boolean (boolean)"
    publish :function => :ReadSSHSupport, :type => "boolean ()"
    publish :function => :GetSSHSupport, :type => "boolean ()"
    publish :function => :SetSSHSupport, :type => "boolean (boolean)"
    publish :function => :WriteSSHSupport, :type => "boolean (boolean)"
    publish :function => :WriteShares, :type => "boolean ()"
    publish :function => :AdjustSharesServices, :type => "boolean (boolean)"
    publish :function => :Read, :type => "boolean ()"
    publish :function => :SetWinbind, :type => "void (boolean)"
    publish :function => :SynchronizeCluster, :type => "boolean ()"
    publish :function => :Write, :type => "boolean (boolean)"
    publish :function => :Import, :type => "boolean (map)"
    publish :function => :Export, :type => "map ()"
    publish :function => :Summary, :type => "string ()"
    publish :function => :ShortSummary, :type => "string ()"
    publish :function => :SetWorkgroup, :type => "void (string)"
    publish :function => :GetWorkgroup, :type => "string ()"
    publish :function => :GetWorkgroupOrRealm, :type => "string ()"
    publish :function => :GetWinbind, :type => "boolean ()"
    publish :function => :AutoPackages, :type => "map ()"
    publish :function => :SetStartFAM, :type => "boolean (boolean)"
  end

  Samba = SambaClass.new
  Samba.main
end
