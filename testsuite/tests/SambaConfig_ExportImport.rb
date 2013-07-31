# encoding: utf-8

# test SambaConfig::Export:
# should remove modified flags and internal shares from config
module Yast
  class SambaConfigExportImportClient < Client
    def main
      Yast.import "Testsuite"
      Yast.import "SambaConfig"

      @i = {
        "a"         => {
          "Bee Bee"   => "x",
          "_modified" => true,
          "_disabled" => true,
          "_xxx"      => 8,
          "_comment"  => "A"
        },
        "_internal" => { "abc" => "ABC" },
        "removed"   => nil,
        "b"         => { "no" => nil, "Two Two" => 22 }
      }

      Testsuite.Dump(@i)

      Testsuite.Test(lambda { SambaConfig.Import(@i) }, [{}, {}, {}], 0)

      Testsuite.Test(lambda { SambaConfig.Export }, [], 0)

      nil
    end
  end
end

Yast::SambaConfigExportImportClient.new.main
