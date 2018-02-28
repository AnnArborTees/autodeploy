require 'spec_helper'
require_relative '../../lib/git'

RSpec.describe Git do
  before do
    allow(Open3).to receive(:popen2)
      .with('git', 'log', '-n', '1')
      .and_return [StringIO.new, OutputStub.git_log_n1, nil]

    allow(Open3).to receive(:popen2)
      .with('git', 'show', 'HEAD')
      .and_return [StringIO.new, OutputStub.git_show, nil]
  end

  describe '#commit_hash' do
    it "returns the commit hash" do
      expect(Git.commit_hash).to eq "cabc994a5cf74f85f86b33a3149a8cf48464aadc"
    end
  end

  describe '#commit_author' do
    it "returns the author" do
      expect(Git.commit_author).to eq "NinjaButtersAATC <stefan@annarbortees.com>"
    end
  end

  describe '#commit_message' do
    it "returns the commit message" do
      expect(Git.commit_message).to eq "(HOTFIX) Fixed how dates were being sent to production."
    end
  end
end
