# encoding: utf-8

# test SambaConfig_Global::GetGlobalCfgStr:
module Yast
  class Samba_GlobalClient < Client
    def main
      Yast.import "Testsuite"
      Yast.import "SambaConfig"

      @i = {
        "global"         => {
          "a"   => 1,
          "b" => true,
          "c"=> "string",
        },
        "share" => { "sharekey" => "sharevalue" },
      }

      Testsuite.Dump(@i)

      SambaConfig.Import(@i)
      # test output of normal globals read in
      Testsuite.Dump(SambaConfig.GetGlobalCfgStr())
      j = { "a"   => "2" }
      # test override of a param
      Testsuite.Dump(SambaConfig.GetGlobalCfgStr(j))
      # test override (removal) of a param
      j["a"] = nil
      Testsuite.Dump(SambaConfig.GetGlobalCfgStr(j))

      nil
    end
  end
end

Yast::Samba_GlobalClient.new.main
