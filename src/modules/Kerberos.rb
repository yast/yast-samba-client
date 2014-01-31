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

# File:	modules/Kerberos.ycp
# Package:	Configuration of kerberos-client
# Summary:	Data for configuration of kerberos-client, i/o functions.
# Authors:	Jiri Suchomel <jsuchome@suse.cz>
#
# $Id$
#
# Representation of the configuration of kerberos-client.
# Input and output routines.
require "yast"

module Yast
  class KerberosClass < Module
    def main

      textdomain "kerberos"

      Yast.import "FileUtils"
      Yast.import "Hostname"
      Yast.import "Label"
      Yast.import "Mode"
      Yast.import "Package"
      Yast.import "Pam"
      Yast.import "Progress"
      Yast.import "Report"
      Yast.import "Service"
      Yast.import "Stage"
      Yast.import "Summary"

      # Required packages for this module to operate
      @required_packages = ["pam_krb5", "krb5", "krb5-client"]

      @write_only = false

      # if pam_krb5 module is used for login
      @use_pam_krb = false

      # if pam_unix is in /etc/pam.d/login
      @pam_unix_present = false

      # default realm and domain name
      @default_realm = ""
      @default_domain = ""

      @dns_default_realm = ""
      @dns_kdc = ""

      # adress of KDC (key distribution centre) server for default realm
      @kdc = ""
      @admin_server = ""

      # used for pkinit-nss (feature 302132)
      @trusted_servers = ""

      @clockskew = "300"

      @pam_modified = false
      @ssh_modified = false
      @modified = false

      # advanced krb5.conf settings (pam section)
      @ticket_lifetime = "1d"
      @renew_lifetime = "1d"
      @forwardable = "true"
      @proxiable = "false"
      # obsolete, do not use
      @retain_after_close = "false"
      @ssh_support = false
      @minimum_uid = "1"

      # deprecated at this scope: now present in ExpertSettings map
      @use_shmem = "sshd"
      @mappings = ""

      # --krb5-ignore_unknown_principals for pam-config
      @ignore_unknown = true

      # section in /etc/ssh/ssh_config file for storing krb support
      @ssh_section = "*"

      # packages to install (openssh etc.)
      @packages = []

      # if DNS can be used for retrieving configuration data
      @dns_available = false

      # if DNS is used for retrieving configuration data
      @dns_used = false

      # if sssd is configured, do not use pam_krb5
      @sssd = false

      #   map with the settings configurable in the expert tabs
      @ExpertSettings = {}

      # backup of original ExpertSettings
      @OrigExpertSettings = {}
    end

    # Data was modified?
    # @return true if modified
    def Modified
      Builtins.y2debug("modified=%1", @modified)
      @modified || @pam_modified || @ssh_modified
    end


    # Get all the Kerberos configuration from a map.
    # @param [Hash] settings imported map
    # @return	success
    def Import(settings)
      settings = deep_copy(settings)
      @use_pam_krb = Ops.get_boolean(
        settings,
        ["pam_login", "use_kerberos"],
        false
      )
      client = Ops.get_map(settings, "kerberos_client", {})

      @default_domain = Ops.get_string(client, "default_domain", "")
      @default_realm = Ops.get_string(client, "default_realm", "")
      @kdc = Ops.get_string(client, "kdc_server", "")
      @clockskew = Ops.get_string(client, "clockskew", @clockskew)
      @ssh_support = Ops.get_boolean(client, "ssh_support", false)
      @ignore_unknown = Ops.get_boolean(
        client,
        "ignore_unknown",
        @ignore_unknown
      )
      @ticket_lifetime = Ops.get_string(client, "ticket_lifetime", "1d")
      @renew_lifetime = Ops.get_string(client, "renew_lifetime", "1d")
      @minimum_uid = Ops.get_string(client, "minimum_uid", @minimum_uid)
      @forwardable = Ops.get_boolean(client, "forwardable", true) ? "true" : "false"
      @proxiable = Ops.get_boolean(client, "proxiable", false) ? "true" : "false"
      @use_shmem = Ops.get_string(client, "use_shmem", @use_shmem)
      @mappings = Ops.get_string(client, "mappings", "")
      @trusted_servers = Ops.get_string(client, "trusted_servers", "")
      @ExpertSettings = Ops.get_map(client, "ExpertSettings", {})
      if !Builtins.haskey(@ExpertSettings, "use_shmem") &&
          Builtins.haskey(client, "use_shmem")
        Ops.set(@ExpertSettings, "use_shmem", @use_shmem)
      end

      @sssd = Ops.get_boolean(settings, ["pam_login", "sssd"], @sssd)
      @pam_modified = true
      @modified = true
      @ssh_modified = true
      true
    end


    # Dump the Kerberos settings to a map, for autoinstallation use.
    # @return [Hash] with settings
    def Export
      export_map = {
        "pam_login"       => { "use_kerberos" => @use_pam_krb, "sssd" => @sssd },
        "kerberos_client" => {
          "default_domain"  => @default_domain,
          "default_realm"   => @default_realm,
          "kdc_server"      => @kdc,
          "clockskew"       => @clockskew,
          "ssh_support"     => @ssh_support,
          "ignore_unknown"  => @ignore_unknown,
          "ticket_lifetime" => @ticket_lifetime,
          "renew_lifetime"  => @renew_lifetime,
          "minimum_uid"     => @minimum_uid,
          "forwardable"     => @forwardable == "true",
          "proxiable"       => @proxiable == "true",
          "ExpertSettings"  => @ExpertSettings
        }
      }
      if @mappings != ""
        Ops.set(export_map, ["kerberos_client", "mappings"], @mappings)
      end
      if @trusted_servers != ""
        Ops.set(
          export_map,
          ["kerberos_client", "trusted_servers"],
          @trusted_servers
        )
      end
      deep_copy(export_map)
    end

    # Reads the item values from the /etc/krb5.conf via ini agent
    # If the item doesn't exist, returns the default value
    # @param [Yast::Path] path_to_value path for agent (.etc.krb5_conf)
    # @param [String] def_value default value for the key (path)
    # @return [Array] string the values for given key
    def ReadKrb5ConfValues(path_to_value, def_value)
      value = Convert.convert(
        SCR.Read(path_to_value),
        :from => "any",
        :to   => "list <string>"
      )
      value = [def_value] if value == nil
      deep_copy(value)
    end

    # Reads the item value from the /etc/krb5.conf via ini agent
    # If the item doesn't exist, returns the default value
    # @param [Yast::Path] path_to_value path for agent (.etc.krb5_conf)
    # @param [String] def_value default value for the key (path)
    # @return [String] the value
    def ReadKrb5ConfValue(path_to_value, def_value)
      vals = ReadKrb5ConfValues(path_to_value, def_value)
      Ops.get_string(vals, 0, def_value)
    end

    # Deprecated variant to ReadKrb5ConfValue
    # @deprecated
    def ReadFile(path_to_value, def_value)
      Builtins.y2warning(
        "This function is deprecated, use ReadKrb5ConfValue instead."
      )
      ReadKrb5ConfValue(path_to_value, def_value)
    end

    # Write list of values for given key to /etc/krb5.conf
    # Do not write anything for empty and nil values
    # @param [Yast::Path] path_to_value path for agent (.etc.krb5_conf)
    # @param value
    # @return false when nothing was written, success of write otherwise
    def WriteKrb5ConfValues(path_to_value, values)
      values = deep_copy(values)
      return SCR.Write(path_to_value, nil) if values == nil || values == []
      SCR.Write(path_to_value, values)
    end

    # Write (possible) multiple values of given key to /etc/krb5.conf
    # @param [String] values values separated by spaces
    def WriteKrb5ConfValuesAsString(path_to_value, values)
      WriteKrb5ConfValues(
        path_to_value,
        Builtins.filter(Builtins.splitstring(values, " \t")) { |val| val != "" }
      )
    end
    # Write the item value to /etc/krb5.conf
    # Do not write anything for empty and nil values
    # @param [Yast::Path] path_to_value path for agent (.etc.krb5_conf)
    # @param [String] value
    # @return false when nothing was written, success of write otherwise
    def WriteKrb5ConfValue(path_to_value, value)
      return SCR.Write(path_to_value, nil) if value == nil || value == ""
      WriteKrb5ConfValues(path_to_value, [value])
    end

    # Deprecated variant to WriteKrb5ConfValue
    # @deprecated
    def WriteFile(path_to_value, value)
      Builtins.y2warning(
        "This function is deprecated, use WriteKrb5ConfValue instead."
      )
      WriteKrb5ConfValue(path_to_value, value)
    end

    # Read given value from /etc/sssd/sssd.conf
    # @param [String] default_value default, if not found in the file
    def ReadSSSDValue(key, default_value)
      ret = default_value
      val = Convert.to_string(
        SCR.Read(
          Builtins.add(
            Builtins.add(path(".etc.sssd_conf.v"), "domain/default"),
            key
          )
        )
      )
      ret = val if val != nil
      ret
    end

    # Reads Kerberos settings from the SCR
    # @return success
    def Read
      pam_query = Pam.Query("krb5")
      @use_pam_krb = Ops.greater_than(Builtins.size(pam_query), 0)
      if @use_pam_krb # if krb is not enabled, ignore_unknown is true by default
        @ignore_unknown = Builtins.contains(
          Ops.get_list(pam_query, "account", []),
          "ignore_unknown_principals"
        )
      end

      # now read the settings from /etc/krb5.conf
      if FileUtils.Exists("/etc/krb5.conf")
        Builtins.y2debug(
          "krb5.conf sections: %1",
          SCR.Dir(path(".etc.krb5_conf.s"))
        )

        @default_realm = ReadKrb5ConfValue(
          path(".etc.krb5_conf.v.libdefaults.default_realm"),
          ""
        )

        @clockskew = ReadKrb5ConfValue(
          path(".etc.krb5_conf.v.libdefaults.clockskew"),
          "300"
        )

        if Ops.greater_than(Builtins.size(@default_realm), 0)
          realm = Builtins.add(path(".etc.krb5_conf.v"), @default_realm)
          @kdc = Builtins.mergestring(
            ReadKrb5ConfValues(Builtins.add(realm, "kdc"), ""),
            " "
          )
          @admin_server = Builtins.mergestring(
            ReadKrb5ConfValues(Builtins.add(realm, "admin_server"), ""),
            " "
          )
          @default_domain = ReadKrb5ConfValue(
            Builtins.add(realm, "default_domain"),
            ""
          )
        end
        @admin_server = "" if @admin_server == @kdc # we could replace it in Write in this case...

        pam_p = path(".etc.krb5_conf.v.pam")
        @ticket_lifetime = ReadKrb5ConfValue(
          Builtins.add(pam_p, "ticket_lifetime"),
          "1d"
        )
        @renew_lifetime = ReadKrb5ConfValue(
          Builtins.add(pam_p, "renew_lifetime"),
          "1d"
        )
        @forwardable = ReadKrb5ConfValue(
          Builtins.add(pam_p, "forwardable"),
          "true"
        )
        @proxiable = ReadKrb5ConfValue(
          Builtins.add(pam_p, "proxiable"),
          "false"
        )
        @minimum_uid = ReadKrb5ConfValue(
          Builtins.add(pam_p, "minimum_uid"),
          "1"
        )

        Builtins.foreach(
          [
            "keytab",
            "ccache_dir",
            "ccname_template",
            "mappings",
            "existing_ticket",
            "external",
            "validate",
            "use_shmem",
            "addressless",
            "debug",
            "debug_sensitive",
            "initial_prompt",
            "subsequent_prompt",
            "banner"
          ]
        ) do |key|
          val = ReadKrb5ConfValue(Builtins.add(pam_p, key), nil)
          Ops.set(@ExpertSettings, key, val) if val != nil
        end
        if !Builtins.haskey(@ExpertSettings, "use_shmem")
          Ops.set(@ExpertSettings, "use_shmem", "sshd")
        end
        @use_shmem = Ops.get_string(@ExpertSettings, "use_shmem", "sshd")
        if !Builtins.haskey(@ExpertSettings, "external")
          Ops.set(@ExpertSettings, "external", "sshd")
        end

        @OrigExpertSettings = deep_copy(@ExpertSettings)

        @trusted_servers = ReadKrb5ConfValue(
          path(".etc.krb5_conf.v.pkinit.trusted_servers"),
          ""
        )
      else
        SCR.Execute(
          path(".target.bash"),
          Builtins.sformat("/usr/bin/touch /etc/krb5.conf")
        )
      end

      # propose some good values, if there are install defaults
      if @default_domain == ""
        @default_domain = Hostname.CurrentDomain
        # workaround for bug#393951
        if @default_domain == "" && Stage.cont
          out = Convert.to_map(
            SCR.Execute(path(".target.bash_output"), "domainname")
          )
          if Ops.get_integer(out, "exit", 0) == 0
            @default_domain = Builtins.deletechars(
              Ops.get_string(out, "stdout", ""),
              "\n"
            )
          end
        end
      end

      # now, check DNS status (Fate 301812)
      if FileUtils.Exists("/usr/bin/dig") && @default_domain != "" && !Mode.test
        out = Convert.to_map(
          SCR.Execute(
            path(".target.bash_output"),
            Builtins.sformat("dig TXT _kerberos.%1 +short", @default_domain)
          )
        )
        @dns_default_realm = Builtins.deletechars(
          Ops.get_string(out, "stdout", ""),
          "\n\""
        )
        if @dns_default_realm != ""
          out = Convert.to_map(
            SCR.Execute(
              path(".target.bash_output"),
              Builtins.sformat(
                "dig SRV _kerberos._udp.%1 +short",
                @default_domain
              )
            )
          )
          split = Builtins.splitstring(
            Ops.get(
              Builtins.splitstring(Ops.get_string(out, "stdout", ""), "\n"),
              0,
              ""
            ),
            " "
          )
          @dns_kdc = Ops.get_string(split, 3, "")
          if @dns_kdc != "" &&
              Builtins.substring(
                @dns_kdc,
                Ops.subtract(Builtins.size(@dns_kdc), 1),
                1
              ) == "."
            @dns_kdc = Builtins.substring(
              @dns_kdc,
              0,
              Ops.subtract(Builtins.size(@dns_kdc), 1)
            )
          end
          @dns_available = true if @dns_kdc != ""
          # empty domain_realm section and no kdc entry defined and
          # values via DNS are available -> DNS is used
          if @kdc == "" &&
              (!Builtins.contains(
                SCR.Dir(path(".etc.krb5_conf.s")),
                "domain_realm"
              ) ||
                SCR.Dir(path(".etc.krb5_conf.v.domain_realm")) == [])
            @dns_used = true
            @kdc = @dns_kdc
            @default_realm = @dns_default_realm
            Builtins.y2milestone(
              "kdc by DNS %1, default_domain: %2",
              @dns_kdc,
              @dns_default_realm
            )
            Builtins.y2milestone("DNS is used for Kerberos data")
          end
        end
      end

      if (@default_realm == "" || @default_realm == "MY.REALM" ||
          @default_realm == "EXAMPLE.COM") &&
          @default_domain != ""
        @default_realm = Builtins.toupper(@default_domain)
      end
      if (@kdc == "" || @kdc == "MY.COMPUTER" || @kdc == "kerberos.example.com") &&
          FileUtils.Exists("/usr/bin/ypwhich")
        out = Convert.to_map(
          SCR.Execute(path(".target.bash_output"), "/usr/bin/ypwhich")
        )
        @kdc = Builtins.deletechars(Ops.get_string(out, "stdout", ""), "\n")
      end
      if (@kdc == "" || @kdc == "MY.COMPUTER" || @kdc == "kerberos.example.com") &&
          FileUtils.Exists("/usr/bin/host")
        proposed = Ops.add("kdc.", Hostname.CurrentDomain)
        m = Convert.to_map(
          SCR.Execute(
            path(".target.bash_output"),
            Builtins.sformat(
              "LANG=C /usr/bin/host %1 | /bin/grep address",
              proposed
            )
          )
        )
        @kdc = proposed if Ops.get_integer(m, "exit", 1) == 0
        Builtins.y2milestone("no kdc defined, proposing: %1", @kdc)
      end

      # read ssh support
      Builtins.y2debug(
        "ssh_config sections: %1",
        SCR.Dir(path(".etc.ssh.ssh_config.s"))
      )
      hostname = Hostname.CurrentHostname

      @ssh_support = nil
      Builtins.foreach(SCR.Dir(path(".etc.ssh.ssh_config.s"))) do |sec|
        # according to ssh man page, first value is taken:
        next if @ssh_support != nil
        cont = SCR.Dir(Builtins.add(path(".etc.ssh.ssh_config.v"), sec))
        Builtins.y2debug("section %1 contains: %2", sec, cont)
        if (sec == "*" || sec == hostname) &&
            Builtins.contains(cont, "GSSAPIAuthentication") &&
              Builtins.contains(cont, "GSSAPIDelegateCredentials")
          @ssh_support = SCR.Read(
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
      @ssh_support = false if @ssh_support == nil

      @sssd = Pam.Enabled("sss")

      if @sssd && FileUtils.Exists("/etc/sssd/sssd.conf")
        # read kerberos settings from sssd.conf (if available)
        @default_realm = ReadSSSDValue("krb5_realm", @default_realm)
        @kdc = ReadSSSDValue("krb5_server", @kdc)
        Ops.set(
          @ExpertSettings,
          "ccache_dir",
          ReadSSSDValue(
            "krb5_ccachedir",
            Ops.get_string(@ExpertSettings, "ccache_dir", "")
          )
        )
        Ops.set(
          @ExpertSettings,
          "ccname_template",
          ReadSSSDValue(
            "krb5_ccname_template",
            Ops.get_string(@ExpertSettings, "ccname_template", "")
          )
        )
        Ops.set(
          @ExpertSettings,
          "keytab",
          ReadSSSDValue(
            "krb5_keytab",
            Ops.get_string(@ExpertSettings, "keytab", "")
          )
        )
        @renew_lifetime = ReadSSSDValue(
          "krb5_renewable_lifetime",
          @renew_lifetime
        )
        @ticket_lifetime = ReadSSSDValue("krb5_lifetime", @ticket_lifetime)
        Ops.set(
          @ExpertSettings,
          "validate",
          Builtins.tolower(
            ReadSSSDValue(
              "krb5_validate",
              Ops.get_string(@ExpertSettings, "validate", "")
            )
          )
        )
      end
      true
    end

    # Write Kerberos related settings to sssd.conf
    def WriteSSSD
      Builtins.y2milestone("updating sssd.conf with new kerberos values")

      domain = Builtins.add(path(".etc.sssd_conf.v"), "domain/default")

      SCR.Write(Builtins.add(domain, "auth_provider"), "krb5")
      SCR.Write(Builtins.add(domain, "chpass_provider"), "krb5")
      SCR.Write(Builtins.add(domain, "krb5_realm"), @default_realm)
      # divide by commas: krb5_server = kdcserver1, kdcserver2 (bnc#729174)
      SCR.Write(Builtins.add(domain, "krb5_server"), @kdc.gsub(/\s+/, ","))

      # write expert settings (bnc#778513)
      SCR.Write(
        Builtins.add(domain, "krb5_ccachedir"),
        Ops.get_string(@ExpertSettings, "ccache_dir", "") == "" ?
          nil :
          Ops.get_string(@ExpertSettings, "ccache_dir", "")
      )
      SCR.Write(
        Builtins.add(domain, "krb5_ccname_template"),
        Ops.get_string(@ExpertSettings, "ccname_template", "") == "" ?
          nil :
          Ops.get_string(@ExpertSettings, "ccname_template", "")
      )
      SCR.Write(
        Builtins.add(domain, "krb5_validate"),
        Ops.get_string(@ExpertSettings, "validate", "") == "true" ? "True" : "False"
      )
      SCR.Write(
        Builtins.add(domain, "krb5_keytab"),
        Ops.get_string(@ExpertSettings, "keytab", "") == "" ?
          nil :
          Ops.get_string(@ExpertSettings, "keytab", "")
      )
      SCR.Write(
        Builtins.add(domain, "krb5_renewable_lifetime"),
        @renew_lifetime
      )
      SCR.Write(Builtins.add(domain, "krb5_lifetime"), @ticket_lifetime)

      ret = SCR.Write(path(".etc.sssd_conf"), nil)
      Builtins.y2error("error writing sssd.conf file") if !ret
      ret
    end

    # Saves Kerberos configuration.
    # (No parameters because it is too short to abort)
    # @return true on success
    def Write
      pam_installed = false
      ret = true

      # dialog caption
      caption = _("Saving Kerberos Client Configuration")

      no_stages = 3
      stages = [
        # progress stage label
        _("Write PAM settings"),
        # progress stage label
        _("Write Kerberos client settings"),
        # progress stage label
        _("Write OpenSSH settings")
      ]
      steps = [
        # progress step label
        _("Writing PAM settings..."),
        # progress step label
        _("Writing Kerberos client settings..."),
        # progress step label
        _("Writing OpenSSH settings..."),
        # final progress step label
        _("Finished")
      ]
      if @packages != []
        # progress stage label
        stages = Builtins.prepend(stages, _("Install required packages"))
        # progress step label
        steps = Builtins.prepend(steps, _("Installing required packages..."))
        no_stages = Ops.add(no_stages, 1)
      end

      Progress.New(caption, " ", no_stages, stages, steps, "")

      if @packages != []
        Builtins.y2debug("packages to install: %1", @packages)
        Progress.NextStage
        to_install = []
        # check if packages are avialable...
        Builtins.foreach(@packages) do |p|
          if Package.Available(p) == true
            to_install = Builtins.add(to_install, p)
          end
        end
        Package.DoInstallAndRemove(to_install, [])

        @packages = []
      end

      Progress.NextStage

      # -- pam settings
      if @pam_modified || @write_only
        # whem sssd is configured, do not use pam_krb5 and update sssd.conf
        # fate#308902
        if @sssd
          Builtins.y2milestone("not using pam_krb5 because sssd is configured")
          Pam.Remove("krb5")
        elsif @use_pam_krb
          Pam.Add("krb5")
          # If ldap is configured we need to change it to ldap-account_only
          Pam.Add("ldap-account_only") if Pam.Enabled("ldap")
          if @ignore_unknown
            Pam.Add("krb5-ignore_unknown_principals")
          else
            Pam.Remove("krb5-ignore_unknown_principals")
          end
        else
          # if ldap-account_only is used we need to change it to ldap
          Pam.Add("ldap") if Pam.Enabled("ldap-account_only")
          Pam.Remove("krb5")
        end
      end

      # -- write to /etc/krb5.conf
      Progress.NextStage

      if @modified && !@dns_used
        # change the default realm name
        WriteKrb5ConfValue(
          path(".etc.krb5_conf.v.libdefaults.default_realm"),
          @default_realm
        )

        # write the mapping domain-realm
        if @default_domain != ""
          domain = @default_domain
          if Builtins.findfirstof(domain, ".") != 0
            domain = Ops.add(".", domain)
          end
          WriteKrb5ConfValue(
            Builtins.add(path(".etc.krb5_conf.v.domain_realm"), domain),
            @default_realm
          )
        end

        WriteKrb5ConfValue(
          path(".etc.krb5_conf.v.libdefaults.clockskew"),
          @clockskew
        )

        if Builtins.contains(SCR.Dir(path(".etc.krb5_conf.s")), @default_realm)
          # update the default realm settings
          WriteKrb5ConfValuesAsString(
            Builtins.add(
              Builtins.add(path(".etc.krb5_conf.v"), @default_realm),
              "kdc"
            ),
            @kdc
          )
          if @default_domain != "" && @default_domain != nil
            WriteKrb5ConfValue(
              Builtins.add(
                Builtins.add(path(".etc.krb5_conf.v"), @default_realm),
                "default_domain"
              ),
              @default_domain
            )
          end
          if @admin_server == ""
            # save only when the entry was mising or same as KDC
            WriteKrb5ConfValuesAsString(
              Builtins.add(
                Builtins.add(path(".etc.krb5_conf.v"), @default_realm),
                "admin_server"
              ),
              @kdc
            )
          end
        elsif @default_realm != ""
          # specify the type of this subsection
          SCR.Write(
            Builtins.add(path(".etc.krb5_conf.st.realms"), @default_realm),
            [1]
          )
          # write the settings of the new default realm
          WriteKrb5ConfValuesAsString(
            Builtins.add(
              Builtins.add(path(".etc.krb5_conf.v.realms"), @default_realm),
              "kdc"
            ),
            @kdc
          )
          if @default_domain != "" && @default_domain != nil
            WriteKrb5ConfValue(
              Builtins.add(
                Builtins.add(path(".etc.krb5_conf.v.realms"), @default_realm),
                "default_domain"
              ),
              @default_domain
            )
          end
          if @admin_server == ""
            WriteKrb5ConfValuesAsString(
              Builtins.add(
                Builtins.add(path(".etc.krb5_conf.v.realms"), @default_realm),
                "admin_server"
              ),
              @kdc
            )
          end
        end
      end
      if @modified
        WriteSSSD() if @sssd

        #     3. Yes, if the user chooses DNS you need to remove the domain_realm
        #     section (so that the domain->realm mapping can be read through DNS)
        #     and at least the complete sub-section describing the realm
        #     (maybe even the whole [realms]-section).
        if @dns_used
          Builtins.y2milestone(
            "DNS set to use: removing domain info from krb5.conf"
          )
          WriteKrb5ConfValue(path(".etc.krb5_conf.s.domain_realm"), nil)
          WriteKrb5ConfValue(
            Builtins.add(path(".etc.krb5_conf.s"), @default_realm),
            nil
          )
          # write the default realm name
          WriteKrb5ConfValue(
            path(".etc.krb5_conf.v.libdefaults.default_realm"),
            @default_realm
          )
        end

        # write advanced settings
        pam_sect = path(".etc.krb5_conf.v.pam")
        if !Builtins.contains(SCR.Dir(path(".etc.krb5_conf.s")), "pam")
          # specify the type of new subsection
          SCR.Write(path(".etc.krb5_conf.st.appdefaults.pam"), [1])
          pam_sect = path(".etc.krb5_conf.v.appdefaults.pam")
        end

        WriteKrb5ConfValue(
          Builtins.add(pam_sect, "ticket_lifetime"),
          @ticket_lifetime
        )
        WriteKrb5ConfValue(
          Builtins.add(pam_sect, "renew_lifetime"),
          @renew_lifetime
        )
        WriteKrb5ConfValue(Builtins.add(pam_sect, "forwardable"), @forwardable)
        WriteKrb5ConfValue(Builtins.add(pam_sect, "proxiable"), @proxiable)
        WriteKrb5ConfValue(Builtins.add(pam_sect, "minimum_uid"), @minimum_uid)

        Builtins.foreach(@ExpertSettings) do |key, value|
          pth = Builtins.add(pam_sect, key)
          if Ops.is_boolean?(value)
            WriteKrb5ConfValue(pth, value == true ? "true" : "false")
            next
          end
          # rest is string
          if value != ""
            WriteKrb5ConfValue(pth, Convert.to_string(value))
          # removin
          elsif Ops.get_string(@OrigExpertSettings, key, "") != ""
            WriteKrb5ConfValue(pth, nil)
          end
        end

        if @trusted_servers != "" &&
            Package.Installed("krb5-plugin-preauth-pkinit-nss")
          pkinit_sect = path(".etc.krb5_conf.v.pkinit")
          if !Builtins.contains(SCR.Dir(path(".etc.krb5_conf.s")), "pkinit")
            SCR.Write(path(".etc.krb5_conf.st.appdefaults.pkinit"), [1])
            pkinit_sect = path(".etc.krb5_conf.v.appdefaults.pkinit")
          end
          WriteKrb5ConfValue(
            Builtins.add(pkinit_sect, "trusted_servers"),
            @trusted_servers
          )
          if FileUtils.Exists("/etc/pam_pkcs11/pam_pkcs11.conf")
            SCR.Write(
              Builtins.add(
                Builtins.add(
                  path(".etc.pam_pkcs11_conf.v.pam_pkcs11"),
                  "mapper ms"
                ),
                "domainname"
              ),
              @default_realm
            )
            SCR.Write(
              Builtins.add(
                Builtins.add(
                  path(".etc.pam_pkcs11_conf.v.pam_pkcs11"),
                  "mapper ms"
                ),
                "domainnickname"
              ),
              @default_domain
            )
            SCR.Write(path(".etc.pam_pkcs11_conf"), nil)
          end
        end

        # write the changes now
        SCR.Write(path(".etc.krb5_conf"), nil)

        # unmount agent; otherwise it won't be available to read new created
        # sections (it will treat DEFAULT_REALM as a subsection of [realms])
        SCR.UnmountAgent(path(".etc.krb5_conf"))
      end

      # -- write openssh settings
      Progress.NextStage

      if @ssh_modified
        write = @ssh_support ? "yes" : "no"
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

      # final stage
      Progress.NextStage

      ret
    end

    # Create a textual summary
    # @return summary of the current configuration
    def Summary
      summary = ""
      nc = Summary.NotConfigured
      # summary header
      summary = Summary.AddHeader(summary, _("PAM Login"))

      # summary item
      summary = Summary.AddLine(
        summary,
        @use_pam_krb ?
          _("Use Kerberos") :
          # summary item
          _("Do Not Use Kerberos")
      )

      # summary header
      summary = Summary.AddHeader(summary, _("Default Realm"))
      summary = Summary.AddLine(
        summary,
        @default_realm != "" ? @default_realm : nc
      )

      # summary header
      summary = Summary.AddHeader(summary, _("Default Domain"))
      summary = Summary.AddLine(
        summary,
        @default_domain != "" ? @default_domain : nc
      )

      # summary header
      summary = Summary.AddHeader(summary, _("KDC Server Address"))
      summary = Summary.AddLine(summary, @kdc != "" ? @kdc : nc)

      # summary header
      summary = Summary.AddHeader(summary, _("Clock Skew"))
      summary = Summary.AddLine(summary, @clockskew != "" ? @clockskew : nc)

      [summary, []]
    end

    # Create a short textual summary
    # @return summary of the current configuration
    def ShortSummary
      summary = ""
      nc = Summary.NotConfigured
      # summary text, %1 is value
      summary = Ops.add(
        Ops.add(
          Ops.add(
            Builtins.sformat(
              _("<b>KDC Server</b>: %1<br>"),
              @kdc != "" ? @kdc : nc
            ),
            # summary text, %1 is value
            Builtins.sformat(
              _("<b>Default Domain</b>: %1<br>"),
              @default_domain != "" ? @default_domain : nc
            )
          ),
          # summary text, %1 is value
          Builtins.sformat(
            _("<b>Default Realm</b>: %1<br>"),
            @default_realm != "" ? @default_realm : nc
          )
        ),
        # summary text (yes/no follows)
        Builtins.sformat(
          _("<b>Kerberos Authentication Enabled</b>: %1"),
          @use_pam_krb ?
            # summary value
            _("Yes") :
            # summary value
            _("No")
        )
      )
      if @dns_used
        # summary line
        summary = Ops.add(
          Ops.add(summary, "<br>"),
          _("Configuration Acquired via DNS")
        )
      end

      summary
    end

    # Return the list of packages for kerberos configuration
    def RequiredPackages
      pkgs = deep_copy(@required_packages)
      # do not install pam_krb5 if sssd is configured
      pkgs = Builtins.filter(pkgs) { |p| p != "pam_krb5" } if @sssd
      deep_copy(pkgs)
    end


    # Return required packages for auto-installation
    # @return [Hash] of packages to be installed and to be removed
    def AutoPackages
      { "install" => RequiredPackages(), "remove" => [] }
    end

    # Validation function for time-related values
    def ValidateTimeEntries(key, val)
      if !Builtins.regexpmatch(val, "^([0-9]+)[dmh]$") &&
          !Builtins.regexpmatch(val, "^([0-9]+)$")
        if key == "clockskew"
          # error popup (wrong format of entered value)
          Report.Error(_("Clock skew is invalid.\nTry again.\n"))
        else
          # error popup (wrong format of entered value)
          Report.Error(_("Lifetime is invalid.\nTry again."))
        end
        return false
      end
      true
    end

    publish :variable => :required_packages, :type => "list <string>"
    publish :variable => :write_only, :type => "boolean"
    publish :variable => :use_pam_krb, :type => "boolean"
    publish :variable => :pam_unix_present, :type => "boolean", :private => true
    publish :variable => :default_realm, :type => "string"
    publish :variable => :default_domain, :type => "string"
    publish :variable => :dns_default_realm, :type => "string"
    publish :variable => :dns_kdc, :type => "string"
    publish :variable => :kdc, :type => "string"
    publish :variable => :admin_server, :type => "string", :private => true
    publish :variable => :trusted_servers, :type => "string"
    publish :variable => :clockskew, :type => "string"
    publish :variable => :pam_modified, :type => "boolean"
    publish :variable => :ssh_modified, :type => "boolean"
    publish :variable => :modified, :type => "boolean"
    publish :variable => :ticket_lifetime, :type => "string"
    publish :variable => :renew_lifetime, :type => "string"
    publish :variable => :forwardable, :type => "string"
    publish :variable => :proxiable, :type => "string"
    publish :variable => :retain_after_close, :type => "string"
    publish :variable => :ssh_support, :type => "boolean"
    publish :variable => :minimum_uid, :type => "string"
    publish :variable => :use_shmem, :type => "string"
    publish :variable => :mappings, :type => "string"
    publish :variable => :ignore_unknown, :type => "boolean"
    publish :variable => :ssh_section, :type => "string", :private => true
    publish :variable => :packages, :type => "list <string>"
    publish :variable => :dns_available, :type => "boolean"
    publish :variable => :dns_used, :type => "boolean"
    publish :variable => :sssd, :type => "boolean"
    publish :variable => :ExpertSettings, :type => "map <string, any>"
    publish :variable => :OrigExpertSettings, :type => "map <string, any>", :private => true
    publish :function => :Modified, :type => "boolean ()"
    publish :function => :Import, :type => "boolean (map)"
    publish :function => :Export, :type => "map ()"
    publish :function => :ReadKrb5ConfValues, :type => "list <string> (path, string)"
    publish :function => :ReadKrb5ConfValue, :type => "string (path, string)"
    publish :function => :ReadFile, :type => "string (path, string)"
    publish :function => :WriteKrb5ConfValues, :type => "boolean (path, list <string>)"
    publish :function => :WriteKrb5ConfValuesAsString, :type => "boolean (path, string)"
    publish :function => :WriteKrb5ConfValue, :type => "boolean (path, string)"
    publish :function => :WriteFile, :type => "boolean (path, string)"
    publish :function => :ReadSSSDValue, :type => "string (string, string)", :private => true
    publish :function => :Read, :type => "boolean ()"
    publish :function => :WriteSSSD, :type => "boolean ()", :private => true
    publish :function => :Write, :type => "boolean ()"
    publish :function => :Summary, :type => "list ()"
    publish :function => :ShortSummary, :type => "string ()"
    publish :function => :RequiredPackages, :type => "list <string> ()"
    publish :function => :AutoPackages, :type => "map ()"
    publish :function => :ValidateTimeEntries, :type => "boolean (string, string)"
  end

  Kerberos = KerberosClass.new
  Kerberos.main
end
