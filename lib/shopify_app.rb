require_relative 'app'
require 'open3'

class ShopifyApp < App
  def setup_commands
    [
      %w(yarn install)
    ]
  end

  def run_tests!(run)
    ENV['CI'] = 'true'
    %w(npm test -- -u)
    success = run.record('yarn', 'test')
    ENV.delete 'CI'

    success
  end

  def deploy_commands
    [
      %w(yarn build),
      "scp -r #{directory}/build/* ubuntu@52.5.26.219:~/ReactApps/aatc-ssa-shopify"
    ]
  end
end
