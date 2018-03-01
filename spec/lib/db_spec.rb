require 'spec_helper'
require_relative '../../lib/db'

RSpec.describe Db do
  subject { Class.new(Db).new }

  describe '#own_ip_address' do
    before do
      allow(subject).to receive(:read_config).and_return('subnets' => ['10.0.', '10.1.', '10.2.'])
      allow(Socket).to receive(:ip_address_list)
        .and_return([
          double('IPv4 Address', ipv4_private?: true, getnameinfo: ['10.10.0.5']),
          double('IPv6 Address', ipv4_private?: false, getnameinfo: ['FE80:CD00:0000:0CDE:1257:0000:211E:729C']),
          double('IPv4 Address', ipv4_private?: true, getnameinfo: ['10.1.0.244'])
        ])
    end

    it 'return an ip address based on the allowed ones in the config' do
      expect(subject.own_ip_address).to eq '10.1.0.244'
    end
  end
end
