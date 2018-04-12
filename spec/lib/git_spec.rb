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

    allow(Open3).to receive(:popen2)
      .with('git', 'branch', '-a')
      .and_return [StringIO.new, OutputStub.git_branch_a, nil]

    allow(Open3).to receive(:popen2e)
      .with('git', 'checkout', 'story-2222-stefan')
      .and_return [StringIO.new, OutputStub.git_checkout, nil]

    allow(Open3).to receive(:popen2e)
      .with('git', 'checkout', '3bfcd53e18606c6b933ed94221428b4206039431')
      .and_return [StringIO.new, OutputStub.git_checkout_commit, nil]
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

  describe '#branches' do
    subject { Git.branches }

    it "returns all remote branches" do
      expect(subject).to include 'email-on-failure'
      expect(subject).to include 'master'
      expect(subject).to include 'multi-rspec'
      expect(subject).to include 'random-failures-workaround'
      expect(subject).to include 'rework'
    end
  end

  describe '#branch' do
    context 'when HEAD is on a normal branch' do
      before do
        allow(Open3).to receive(:popen2)
          .with('git', 'status')
          .and_return [StringIO.new, OutputStub.git_status, nil]
      end

      it "returns the current branch" do
        expect(Git.branch).to eq 'master'
      end
    end

    context 'when HEAD is detached' do
      before do
        allow(Open3).to receive(:popen2)
          .with('git', 'status')
          .and_return [StringIO.new, OutputStub.git_status_detached, nil]
      end

      it "returns the current commit" do
        expect(Git.branch).to eq 'cabc994a5cf74f85f86b33a3149a8cf48464aadc'
      end
    end
  end

  describe '#checkout' do
    it "checks out the given branch" do
      expect(Git.checkout('story-2222-stefan')).to be_truthy
    end

    it "can checkout a specific commit" do
      expect(Git.checkout('3bfcd53e18606c6b933ed94221428b4206039431')).to be_truthy
    end
  end
end
