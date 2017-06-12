require_relative "test_helper"

class DummyClass < Yast::Client
  def initialize
    Yast.include self, "ntp-client/misc.rb"
  end
end

describe "Yast::NtpClientMiscInclude" do
  subject { DummyClass.new }

  describe "string2opts" do
    let(:options) { "time1 0.0 time2 0.0 for_test refid GPS stratum 12 not_in_list" }
    let(:with_params) { ["time1", "time2", "stratum", "refid", "flag1", "flag2", "flag3"] }
    let(:without_params) { ["for_test"] }

    context "given a string of options, a list of options with params and other without params" do
      it "returns a hash of parsed and unkown options" do
        expect(subject.string2opts(options, with_params, without_params)).to eql(
          "parsed"  => {
            "time1" => "0.0", "time2" => "0.0", "for_test" => true,
              "refid" => "GPS", "stratum" => "12"
          },
          "unknown" => "not_in_list"
        )
      end
    end
  end

end
