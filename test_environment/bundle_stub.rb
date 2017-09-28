#
# This provides the framework used in the mock_bundle*.rb files
#

require 'mysql2'

def stub_rspec(&block)
  @rspec_block = block
end

def stub_cap(&block)
  @cap_block = block
end

def verify(&block)
  @verify_block = block

  case ARGV[1]
  when 'rspec'
    @rspec_block.call
  when 'cap'
    @cap_block.call

  else
    if ARGV[0] == 'verify'
      def fail_verification(msg)
        puts "\033[0;41mVERIFICATION FAILED\033[0m"
        puts ARGV[1]
        puts "--------------------------------------------------------------"
        puts msg
        exit 1
      end

      def expect(substring)
        unless ARGV[1].include?(substring)
          fail_verification "Expected to contain \"#{substring}\", but didn't."
        end
      end

      def reject(substring)
        if ARGV[1].include?(substring)
          fail_verification "Expected to NOT contain \"#{substring}\", but did."
        end
      end

      @verify_block.call
      puts "\033[44mAutodeploy verification complete!\033[0m"

    else
      puts "\033[0;31m*** Bundle called with args: #{ARGV}\033[0m"
    end
  end
end

